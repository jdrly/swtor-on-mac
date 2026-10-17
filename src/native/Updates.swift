// App updates with Sparkle 2 (Contents/Frameworks/Sparkle.framework), as in SWGL on Mac: the
// same feed and signing setup (SUFeedURL, SUPublicEDKey in Info.plist; the feed is built by
// scripts/release.sh) and the same update window, the app's own in SwiftUI (Liquid Glass)
// instead of Sparkle's.
//
// Sparkle keeps its settings in the app's defaults (cz.jandrly.swtoronmac). Info.plist turns
// automatic checks on without Sparkle's permission prompt and leaves installing to the user;
// the Settings window switches automatic checks.
//
// The game never runs from inside the app (the wrapper, engine and prefix live outside it),
// so an update may replace the app while the game runs. Only an install or uninstall in
// progress holds it: "Install and Relaunch" then waits for it to finish.
//
// Also: the Wine wrapper looks at the same feed once a day when the game starts and leaves
// <app dir>/update-available when it finds a newer version (src/wine-wrapper.sh); the window
// then starts a check (Installer.refresh).
//
// For testing, `defaults write cz.jandrly.swtoronmac SWTORUpdateFeedURL <url>` replaces the
// feed (Sparkle accepts http only on 127.0.0.1/localhost); scripts/test-update.sh does that.
//
// Development builds (compiled with SWTOR_DEV, SWTORChannel dev in Info.plist, version X.Y.Z-dev.N; build.sh) never
// check automatically, whatever the setting says; Check for Updates… still works. Their
// CFBundleVersion sorts between the previous release and X.Y.Z (0.0.6-dev.1 is 0.0.5.1001),
// so the feed's 0.0.5 is never offered and the public 0.0.6 is.

import AppKit
import Sparkle
import SwiftUI

@MainActor
final class Updates: NSObject, SPUUpdaterDelegate {
  static let appBundleID = "cz.jandrly.swtoronmac"
  static let feedOverrideKey = "SWTORUpdateFeedURL"
  // build.sh compiles development builds with SWTOR_DEV (and writes SWTORChannel dev into
  // Info.plist for som.sh); release binaries contain none of the dev-only UI.
  #if SWTOR_DEV
  static let isDevBuild = true
  #else
  static let isDevBuild = false
  #endif

  private(set) var updater: SPUUpdater?
  private var userDriver: UserDriver?
  private var heldInstall: (() -> Void)?
  // true while an install or uninstall runs: an update waits for it
  var isBusy: () -> Bool = { false }
  // a sheet is open on the main window (it would keep the app from quitting), and closing it
  var sheetOpen: () -> Bool = { false }
  var closeSheets: () -> Void = {}

  // Starts Sparkle; without it (not the app bundle, Sparkle failed), no updates.
  func start() {
    let app = Bundle.main
    guard app.bundleIdentifier == Updates.appBundleID else {
      NSLog("SWTOR on Mac: not running as %@; no update checks", Updates.appBundleID)
      return
    }
    let driver = UserDriver(host: app)
    let updater = SPUUpdater(hostBundle: app, applicationBundle: app, userDriver: driver, delegate: self)
    do {
      try updater.start()
    } catch {
      NSLog("SWTOR on Mac: Sparkle did not start: %@", error.localizedDescription)
      return
    }
    userDriver = driver
    self.updater = updater
    // Sparkle keeps the setting in the defaults, which a release build may have turned on
    if Updates.isDevBuild { updater.automaticallyChecksForUpdates = false }
    NSLog("SWTOR on Mac: update checks %@, feed %@",
          updater.automaticallyChecksForUpdates ? "automatic" : "manual", updater.feedURL?.absoluteString ?? "-")
  }

  var available: Bool { updater != nil }

  func checkForUpdates() { updater?.checkForUpdates() }

  var automaticChecks: Bool {
    get { updater?.automaticallyChecksForUpdates ?? true }
    set { if !Updates.isDevBuild { updater?.automaticallyChecksForUpdates = newValue } }
  }

  // An install or uninstall has finished: a held update goes ahead.
  func installerIdle() {
    guard let install = heldInstall else { return }
    heldInstall = nil
    NSLog("SWTOR on Mac: the installer has finished; installing the update")
    install()
  }

  // MARK: SPUUpdaterDelegate

  func feedURLString(for updater: SPUUpdater) -> String? {
    let feed = UserDefaults.standard.string(forKey: Updates.feedOverrideKey)
    return (feed?.isEmpty ?? true) ? nil : feed
  }

  func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
               untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
    if !isBusy() {
      guard sheetOpen() else { return false }
      // close it first, then let Sparkle quit and relaunch the app
      closeSheets()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { installHandler() }
      return true
    }
    NSLog("SWTOR on Mac: holding the update to %@ until the installer has finished", item.displayVersionString)
    heldInstall = installHandler
    userDriver?.window.showHeld()
    return true
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
    NSLog("SWTOR on Mac: update aborted: %@", error.localizedDescription)
  }
}

// MARK: - User driver

// Sparkle's user driver, shown in the app's own SwiftUI window (UpdateWindow below, which
// knows nothing about Sparkle). Unlike Sparkle's standard driver, "later" for an update that is
// ready to install cancels it without skipping the version.
@MainActor
final class UserDriver: NSObject, SPUUserDriver {
  let window: UpdateWindow
  private let host: Bundle

  init(host: Bundle) {
    self.host = host
    let version = host.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    window = UpdateWindow(currentVersion: version, icon: NSApp.applicationIconImage)
    super.init()
  }

  private static func choice(_ value: Int) -> SPUUserUpdateChoice {
    value == 0 ? .install : value == 2 ? .skip : .dismiss
  }

  // Skip cancels a prepared install, but also marks the version as skipped: put the skipped
  // versions back once Sparkle has handled the reply.
  private func cancelPreparedInstall(_ reply: @escaping (SPUUserUpdateChoice) -> Void) {
    let defaults = UserDefaults.standard
    let keys = ["SUSkippedVersion", "SUSkippedMajorVersion", "SUSkippedMajorSubreleaseVersion"]
    let before = keys.map { defaults.object(forKey: $0) }
    reply(.skip)
    DispatchQueue.main.async {
      for (key, value) in zip(keys, before) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
      }
    }
  }

  func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
    // Info.plist settles automatic checks (on), so Sparkle doesn't ask; answer like that if it does.
    reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
  }

  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
    window.showChecking(cancel: cancellation)
  }

  func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                       reply: @escaping (SPUUserUpdateChoice) -> Void) {
    let ready = state.stage == .installing
    window.showFound(version: appcastItem.displayVersionString, notes: appcastItem.itemDescription ?? "",
                     notesFormat: appcastItem.itemDescriptionFormat ?? "html", readyToInstall: ready) { [weak self] choice in
      if ready && choice == 1 {
        self?.cancelPreparedInstall(reply)
      } else {
        reply(UserDriver.choice(choice))
      }
    }
  }

  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
    let text = String(decoding: downloadData.data, as: UTF8.self)
    let type = downloadData.mimeType ?? ""
    let format = type.contains("html") ? "html"
      : type.contains("markdown") || downloadData.url.pathExtension == "md" ? "markdown" : "plain"
    window.showNotes(text, format: format)
  }

  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
    window.showNotes("The release notes could not be loaded.", format: "plain")
  }

  func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
    let version = host.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    window.showUpToDate("SWTOR on Mac \(version) is the latest version.", acknowledge: acknowledgement)
  }

  func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
    window.showError(error.localizedDescription, acknowledge: acknowledgement)
  }

  func showDownloadInitiated(cancellation: @escaping () -> Void) {
    window.showDownloading(cancel: cancellation)
  }

  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
    window.setExpectedLength(expectedContentLength)
  }

  func showDownloadDidReceiveData(ofLength length: UInt64) {
    window.addReceived(length)
  }

  func showDownloadDidStartExtractingUpdate() {
    window.showExtracting(0)
  }

  func showExtractionReceivedProgress(_ progress: Double) {
    window.showExtracting(progress)
  }

  func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
    window.showReadyToInstall { [weak self] choice in
      if choice == 1 { self?.cancelPreparedInstall(reply) } else { reply(UserDriver.choice(choice)) }
    }
  }

  func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                            retryTerminatingApplication: @escaping () -> Void) {
    window.showInstalling()
  }

  func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
    window.close()
    acknowledgement()
  }

  func showUpdateInFocus() {
    window.bringToFront()
  }

  func dismissUpdateInstallation() {
    window.close()
  }
}

// MARK: - Update window

@MainActor @Observable
final class UpdateModel {
  enum Phase: Equatable {
    case checking
    case found
    case downloading(received: UInt64, expected: UInt64)
    case extracting(Double)
    case ready
    case installing
    case held
    case upToDate(String)
    case failed(String)
  }

  struct Update: Equatable {
    var version: String
    var notes: String
    var notesFormat: String  // "markdown", "html" or "plain"
    var readyToInstall: Bool
  }

  let currentVersion: String
  let icon: NSImage
  var phase: Phase = .checking
  var update: Update?

  // The pending Sparkle reply or acknowledgement for the buttons on screen.
  var onInstall: (() -> Void)?
  var onLater: (() -> Void)?
  var onSkip: (() -> Void)?
  var onCancel: (() -> Void)?
  var onAcknowledge: (() -> Void)?

  init(currentVersion: String, icon: NSImage) {
    self.currentVersion = currentVersion
    self.icon = icon
  }

  func clearActions() {
    onInstall = nil; onLater = nil; onSkip = nil; onCancel = nil; onAcknowledge = nil
  }
}

@MainActor
final class UpdateWindow: NSObject, NSWindowDelegate {
  private let model: UpdateModel
  private var window: NSWindow?

  init(currentVersion: String, icon: NSImage) {
    model = UpdateModel(currentVersion: currentVersion, icon: icon)
    super.init()
  }

  // Sparkle's choices as plain values: install 0, later 1, skip 2.
  func showChecking(cancel: @escaping () -> Void) {
    model.clearActions()
    model.update = nil
    model.onCancel = cancel
    show(.checking)
  }

  func showFound(version: String, notes: String, notesFormat: String, readyToInstall: Bool,
                 reply: @escaping (Int) -> Void) {
    model.clearActions()
    model.update = .init(version: version, notes: notes, notesFormat: notesFormat, readyToInstall: readyToInstall)
    var replied = false
    let once: (Int) -> Void = { choice in
      guard !replied else { return }
      replied = true
      reply(choice)
    }
    model.onInstall = { once(0) }
    model.onLater = { once(1) }
    model.onSkip = { once(2) }
    show(.found)
  }

  func showNotes(_ notes: String, format: String) {
    model.update?.notes = notes
    model.update?.notesFormat = format
  }

  func showDownloading(cancel: @escaping () -> Void) {
    model.clearActions()
    model.onCancel = cancel
    show(.downloading(received: 0, expected: 0))
  }

  func setExpectedLength(_ expected: UInt64) {
    if case .downloading(let received, _) = model.phase { model.phase = .downloading(received: received, expected: expected) }
  }

  func addReceived(_ length: UInt64) {
    if case .downloading(let received, let expected) = model.phase {
      model.phase = .downloading(received: received + length, expected: expected)
    }
  }

  func showExtracting(_ progress: Double) {
    model.clearActions()
    show(.extracting(progress))
  }

  func showReadyToInstall(reply: @escaping (Int) -> Void) {
    model.clearActions()
    var replied = false
    model.onInstall = { if !replied { replied = true; reply(0) } }
    model.onLater = { if !replied { replied = true; reply(1) } }
    show(.ready)
  }

  // Install was chosen while an install or uninstall runs (Updates holds it until it ends).
  func showHeld() {
    model.clearActions()
    model.onAcknowledge = { [weak self] in self?.close() }
    show(.held)
  }

  func showInstalling() {
    model.clearActions()
    show(.installing)
  }

  func showUpToDate(_ message: String, acknowledge: @escaping () -> Void) {
    model.clearActions()
    model.onAcknowledge = { [weak self] in acknowledge(); self?.close() }
    show(.upToDate(message))
  }

  func showError(_ message: String, acknowledge: @escaping () -> Void) {
    model.clearActions()
    model.onAcknowledge = { [weak self] in acknowledge(); self?.close() }
    show(.failed(message))
  }

  func bringToFront() {
    guard let window else { return }
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }

  func close() {
    model.clearActions()
    window?.delegate = nil
    window?.close()
    window = nil
  }

  private func show(_ phase: UpdateModel.Phase) {
    withAnimation(.smooth) { model.phase = phase }
    if window == nil {
      let hosting = NSHostingController(rootView: UpdateView(model: model))
      hosting.sizingOptions = [.preferredContentSize]
      let window = NSWindow(contentViewController: hosting)
      window.styleMask = [.titled, .closable, .fullSizeContentView]
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.title = "Software Update"
      window.isReleasedWhenClosed = false
      window.delegate = self
      // Center at the content's real size; centred while still empty, the window would grow
      // from there and end up low on the screen.
      hosting.view.layoutSubtreeIfNeeded()
      window.setContentSize(hosting.view.fittingSize)
      window.center()
      self.window = window
    }
    bringToFront()
  }

  // The close button: whatever stands for "not now" in the current state.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    let action = model.onCancel ?? model.onLater ?? model.onAcknowledge
    model.clearActions()
    window = nil
    action?()
    return true
  }
}

struct UpdateView: View {
  let model: UpdateModel

  var body: some View {
    VStack(spacing: 18) {
      UpdateHeader(model: model)
      if let update = model.update, model.phase != .checking {
        NotesCard(update: update)
      }
      UpdateStatusCard(phase: model.phase)
      UpdateButtons(model: model)
    }
    .padding(.horizontal, 32)
    .padding(.top, 30)
    .padding(.bottom, 24)
    .frame(width: 540)
    .animation(.smooth, value: model.phase)
  }
}

private struct UpdateHeader: View {
  let model: UpdateModel

  var body: some View {
    HStack(spacing: 16) {
      Image(nsImage: model.icon)
        .resizable()
        .frame(width: 64, height: 64)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.title2.weight(.semibold))
        if let subtitle {
          Text(subtitle)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
    }
  }

  private var title: String {
    switch model.phase {
    case .checking: "Checking for updates…"
    case .upToDate: "You're up to date"
    case .failed: "Couldn't update SWTOR on Mac"
    default: "A new version of SWTOR on Mac is available"
    }
  }

  private var subtitle: String? {
    switch model.phase {
    case .checking: nil
    case .upToDate(let message), .failed(let message): message
    default: model.update.map { "Version \($0.version). You have \(model.currentVersion)." }
    }
  }
}

private struct NotesCard: View {
  let update: UpdateModel.Update

  var body: some View {
    ScrollView {
      ReleaseNotes(text: update.notes, format: update.notesFormat)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
    }
    .frame(height: 220)
    .glassEffect(.regular, in: .rect(cornerRadius: 18))
  }
}

// The notes as release.sh embeds them (Markdown from release-notes/<version>.md): headings,
// bullet lists and paragraphs with inline formatting and links. HTML and plain text too.
private struct ReleaseNotes: View {
  let text: String
  let format: String

  var body: some View {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      Text("No release notes for this version.").foregroundStyle(.secondary)
    } else if format == "html" {
      Text(html)
    } else if format == "markdown" {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
          switch block {
          case .heading(let level, let text):
            Text(inline(text))
              .font(level <= 2 ? .headline : .subheadline.weight(.semibold))
              .padding(.top, 4)
          case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text("•").foregroundStyle(.secondary)
              Text(inline(text))
            }
          case .paragraph(let text):
            Text(inline(text))
          }
        }
      }
      .textSelection(.enabled)
    } else {
      Text(text).textSelection(.enabled)
    }
  }

  private enum Block { case heading(Int, String), bullet(String), paragraph(String) }

  private var blocks: [Block] {
    var blocks: [Block] = []
    var paragraph: [String] = []
    func flush() {
      if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
      paragraph = []
    }
    for raw in text.components(separatedBy: .newlines) {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.isEmpty {
        flush()
      } else if line.hasPrefix("#") {
        flush()
        let level = line.prefix { $0 == "#" }.count
        blocks.append(.heading(level, line.dropFirst(level).trimmingCharacters(in: .whitespaces)))
      } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
        flush()
        blocks.append(.bullet(String(line.dropFirst(2))))
      } else if raw.hasPrefix("  "), case .bullet(let previous)? = blocks.last, paragraph.isEmpty {
        blocks[blocks.count - 1] = .bullet(previous + " " + line)  // a wrapped list item
      } else {
        paragraph.append(line)
      }
    }
    flush()
    return blocks
  }

  private func inline(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(text)
  }

  private var html: AttributedString {
    guard let data = text.data(using: .utf8),
          let string = try? NSAttributedString(data: data, options: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
    else { return AttributedString(text) }
    return AttributedString(string.string)
  }
}

private struct UpdateStatusCard: View {
  let phase: UpdateModel.Phase

  var body: some View {
    Group {
      switch phase {
      case .checking:
        card { ProgressView().progressViewStyle(.linear) }
      case .downloading(let received, let expected):
        card {
          if expected > 0 {
            ProgressView(value: Double(received), total: Double(max(expected, received)))
            Text("Downloading the update… \(bytes(received)) of \(bytes(expected))")
          } else {
            ProgressView().progressViewStyle(.linear)
            Text("Downloading the update…")
          }
        }
      case .extracting(let progress):
        card {
          ProgressView(value: progress)
          Text("Preparing the update…")
        }
      case .ready:
        card { Label("The update is ready to install.", systemImage: "checkmark.circle.fill") }
      case .installing:
        card {
          ProgressView().progressViewStyle(.linear)
          Text("Installing the update. SWTOR on Mac will open again in a moment.")
        }
      case .held:
        card {
          Label("The update will be installed when SWTOR on Mac has finished installing or "
                + "uninstalling. It then opens again by itself.", systemImage: "hourglass")
            .multilineTextAlignment(.leading)
        }
      case .found, .upToDate, .failed:
        EmptyView()
      }
    }
    .transition(.blurReplace)
  }

  private func card(@ViewBuilder _ content: () -> some View) -> some View {
    VStack(spacing: 10) { content() }
      .font(.callout)
      .foregroundStyle(.secondary)
      .padding(16)
      .frame(maxWidth: .infinity)
      .glassEffect(.regular, in: .rect(cornerRadius: 18))
  }

  private func bytes(_ count: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
  }
}

private struct UpdateButtons: View {
  let model: UpdateModel

  var body: some View {
    GlassEffectContainer(spacing: 12) {
      HStack(spacing: 12) {
        if let skip = model.onSkip {
          Button("Skip This Version", action: skip)
            .buttonStyle(.glass)
        }
        Spacer(minLength: 0)
        if let cancel = model.onCancel {
          Button("Cancel", action: cancel)
            .buttonStyle(.glass)
            .keyboardShortcut(.cancelAction)
        }
        if let later = model.onLater {
          Button("Remind Me Later", action: later)
            .buttonStyle(.glass)
            .keyboardShortcut(.cancelAction)
        }
        if let install = model.onInstall {
          Button(model.phase == .ready || model.update?.readyToInstall == true
                 ? "Install and Relaunch" : "Install Update", action: install)
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        }
        if let acknowledge = model.onAcknowledge {
          Button("OK", action: acknowledge)
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        }
      }
      .controlSize(.large)
      .pointerStyle(.link)
    }
  }
}
