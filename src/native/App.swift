// SWTOR on Mac: the app's only window (SwiftUI). Shows the notice and the state of this Mac,
// and runs Resources/som.sh (status, install, uninstall), which does the actual work and
// streams its progress back as "@" lines (see the header of src/som.sh).
//
// Built against the macOS 27 SDK, so the standard controls and Liquid Glass styles used here
// take the macOS 27 design; runs on macOS 26 too (same APIs, 26 look).
//
// SWTOR_ON_MAC_ROOT and SWTOR_ON_MAC_DRY_RUN in the app's environment are passed on to
// som.sh, so the window can be tried against a sandbox:
//   SWTOR_ON_MAC_ROOT=/tmp/som-sandbox "SWTOR on Mac.app/Contents/MacOS/SWTORonMac"

import AppKit
import SwiftUI

// MARK: - Model

@MainActor @Observable
final class Installer {
  enum Operation: String { case install, uninstall }
  enum Phase: Equatable {
    case idle
    case working(Operation)
    case succeeded(String)
    case failed(String)
  }
  struct Progress: Equatable { var label: String; var done: Int64; var total: Int64 }

  var status: [String: String] = [:]
  var phase: Phase = .idle
  var step = ""
  var progress: Progress?
  var log: [String] = []
  var warnings: [String] = []
  var understood = false
  var showLog = false
  let credits: [String: String]

  private var process: Process?
  private let script = Bundle.main.resourceURL!.appendingPathComponent("som.sh")

  init() {
    credits = Installer.readProperties(Bundle.main.resourceURL!.appendingPathComponent("app.properties"))
  }

  // MARK: Derived state

  var isBusy: Bool { if case .working = phase { true } else { false } }
  var officialPresent: Bool { status["official_app"] == "yes" && status["official_wine"] == "yes" }
  var rosetta: Bool { status["rosetta"] == "yes" }
  var installed: Bool { status["installed"] == "yes" }
  var running: Bool { status["running"] == "yes" }
  var wrapper: String { status["wrapper"] ?? "" }
  // a wrapper (or its leftovers) that is not ours: install/uninstall ask before going ahead
  var otherWrapper: Bool { wrapper == "personal" || wrapper == "foreign" || (wrapper == "replaced" && !installed) }
  var appleSilicon: Bool { status["arch"].map { $0 == "arm64" } ?? true }
  var loaded: Bool { !status.isEmpty }

  var canInstall: Bool {
    loaded && !isBusy && officialPresent && rosetta && appleSilicon && !running && (installed || understood)
  }
  var canUninstall: Bool {
    loaded && !isBusy && !running && (installed || wrapper == "ours" || wrapper == "replaced")
  }

  // MARK: Actions

  func refresh() {
    guard !isBusy else { return }
    Task {
      var values: [String: String] = [:]
      let output = await Installer.capture(script: script, arguments: ["status"])
      for line in output.split(separator: "\n") {
        guard let eq = line.firstIndex(of: "=") else { continue }
        values[String(line[..<eq])] = String(line[line.index(after: eq)...])
      }
      status = values
    }
  }

  func start(_ operation: Operation, force: Bool = false) {
    guard !isBusy else { return }
    phase = .working(operation)
    step = operation == .install ? "Starting…" : "Removing…"
    progress = nil
    log = []
    warnings = []

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path, operation.rawValue]
    var env = ProcessInfo.processInfo.environment
    if force { env["SWTOR_ON_MAC_FORCE"] = "1" }
    process.environment = env
    process.standardInput = FileHandle.nullDevice
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    let reader = LineReader { [weak self] line in
      Task { @MainActor in self?.handle(line) }
    }
    pipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
        reader.finish()
      } else {
        reader.feed(data)
      }
    }
    process.terminationHandler = { [weak self] p in
      let status = p.terminationStatus
      // let the reader drain what is left before the result is shown
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        MainActor.assumeIsolated { self?.finished(status) }
      }
    }
    do {
      try process.run()
      self.process = process
    } catch {
      phase = .failed("Could not start the installer: \(error.localizedDescription)")
    }
  }

  func cancel() {
    process?.terminate()
  }

  private var lastError: String?
  private var doneMessage: String?

  private func handle(_ line: String) {
    if line.hasPrefix("@step ") {
      step = String(line.dropFirst(6))
      progress = nil
      log.append("▸ " + step)
    } else if line.hasPrefix("@progress ") {
      let parts = line.split(separator: " ")
      if parts.count >= 4, let done = Int64(parts[parts.count - 2]), let total = Int64(parts[parts.count - 1]) {
        let label = parts[1..<(parts.count - 2)].joined(separator: " ")
        progress = Progress(label: label, done: done, total: total)
      }
    } else if line.hasPrefix("@warn ") {
      let text = String(line.dropFirst(6))
      warnings.append(text)
      log.append("⚠︎ " + text)
    } else if line.hasPrefix("@error ") {
      lastError = String(line.dropFirst(7))
      log.append("✕ " + lastError!)
    } else if line.hasPrefix("@done ") {
      doneMessage = String(line.dropFirst(6))
    } else {
      log.append(line)
    }
  }

  private func finished(_ status: Int32) {
    process = nil
    progress = nil
    if status == 0 {
      phase = .succeeded(doneMessage ?? "Done.")
    } else {
      phase = .failed(lastError ?? "Something went wrong (status \(status)). Details are in the log.")
      showLog = true
    }
    lastError = nil
    doneMessage = nil
    refresh()
  }

  // MARK: Helpers

  private static func capture(script: URL, arguments: [String]) async -> String {
    await withCheckedContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/bash")
      process.arguments = [script.path] + arguments
      process.standardInput = FileHandle.nullDevice
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
      } catch {
        continuation.resume(returning: "")
        return
      }
      DispatchQueue.global().async {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        continuation.resume(returning: String(decoding: data, as: UTF8.self))
      }
    }
  }

  // Resources/app.properties (written by build.sh): version, author, github, repo.
  private static func readProperties(_ url: URL) -> [String: String] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
    var values: [String: String] = [:]
    for line in text.split(separator: "\n") {
      guard let eq = line.firstIndex(of: "=") else { continue }
      values[String(line[..<eq])] = String(line[line.index(after: eq)...])
    }
    return values
  }
}

// Splits a byte stream into lines (the pipe hands over arbitrary chunks).
final class LineReader: @unchecked Sendable {
  private var buffer = Data()
  private let lock = NSLock()
  private let emit: (String) -> Void

  init(emit: @escaping (String) -> Void) { self.emit = emit }

  func feed(_ data: Data) {
    lock.lock()
    buffer.append(data)
    var lines: [String] = []
    while let nl = buffer.firstIndex(of: 0x0A) {
      lines.append(String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self))
      buffer.removeSubrange(buffer.startIndex...nl)
    }
    lock.unlock()
    lines.forEach(emit)
  }

  func finish() {
    lock.lock()
    let rest = buffer.isEmpty ? nil : String(decoding: buffer, as: UTF8.self)
    buffer.removeAll()
    lock.unlock()
    if let rest { emit(rest) }
  }
}

// MARK: - Views

struct MainView: View {
  @Bindable var installer: Installer
  @State private var confirmUninstall = false
  @State private var confirmReplace: Installer.Operation?

  var body: some View {
    VStack(spacing: 0) {
      Header(installer: installer)
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 4)

      ScrollViewReader { proxy in
        Form {
          NoticeSection(installer: installer)
          StatusSection(installer: installer)
          if installer.phase != .idle {
            ProgressSection(installer: installer)
              .id("progress")
          }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // bring the progress into view when an install or uninstall starts or ends
        .onChange(of: installer.phase) { _, _ in
          withAnimation(.smooth) { proxy.scrollTo("progress", anchor: .bottom) }
        }
      }

      ActionBar(installer: installer, uninstall: askUninstall, install: askInstall)
        .padding(.horizontal, 28)
        .padding(.bottom, 18)

      Footer(credits: installer.credits)
    }
    .frame(width: 600)
    .frame(minHeight: 620, idealHeight: 840)
    .animation(.smooth, value: installer.phase)
    .animation(.smooth, value: installer.status)
    .alert("Uninstall SWTOR on Mac?", isPresented: $confirmUninstall) {
      Button("Uninstall", role: .destructive) { uninstall() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The official SWTOR app goes back to how Broadsword ships it. SWTOR on Mac's Wine engine "
           + "and prefix are deleted, including the game settings stored in that prefix (graphics "
           + "options, UI layouts and key bindings saved on this Mac). Your characters and the game "
           + "itself are not affected. Logs are kept.")
    }
    .alert(replaceTitle, isPresented: Binding(get: { confirmReplace != nil }, set: { if !$0 { confirmReplace = nil } })) {
      Button(confirmReplace == .install ? "Replace It" : "Restore Stock Wine", role: .destructive) {
        if let op = confirmReplace { installer.start(op, force: true) }
        confirmReplace = nil
      }
      Button("Cancel", role: .cancel) { confirmReplace = nil }
    } message: {
      Text(replaceMessage)
    }
  }

  private var replaceTitle: String {
    installer.wrapper == "personal" ? "The developer setup is installed" : "A different Wine wrapper is installed"
  }

  private var replaceMessage: String {
    let what = installer.wrapper == "personal"
      ? "Broadsword's Wine folder has the developer setup from swtor-mac-proper installed (it reads ~/.config/swtor-mac/env)."
      : "Broadsword's Wine folder has a Wine wrapper installed that is not SWTOR on Mac's."
    let action = confirmReplace == .install
      ? "Installing replaces it with SWTOR on Mac's wrapper."
      : "Uninstalling removes it and restores Broadsword's own Wine."
    return "\(what) \(action) A copy of it is kept in ~/Library/Application Support/SWTOR on Mac/backup."
  }

  private func askInstall() {
    if installer.otherWrapper { confirmReplace = .install } else { installer.start(.install) }
  }

  private func askUninstall() { confirmUninstall = true }

  private func uninstall() {
    if installer.otherWrapper { confirmReplace = .uninstall } else { installer.start(.uninstall) }
  }
}

struct Header: View {
  let installer: Installer

  var body: some View {
    HStack(spacing: 16) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 72, height: 72)
      VStack(alignment: .leading, spacing: 4) {
        Text("SWTOR on Mac")
          .font(.largeTitle.weight(.semibold))
        Text("Runs the official SWTOR Mac app on a faster graphics layer: Direct3D 9 straight to "
             + "Metal with d9mt, on a newer Wine.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
  }
}

// Broadsword's position on third-party tools, and where support for this app comes from.
struct NoticeSection: View {
  @Bindable var installer: Installer

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 8) {
        Text("SWTOR on Mac is an unofficial community project, not made, endorsed or supported by "
             + "Broadsword Games, Electronic Arts, Lucasfilm or Disney. Broadsword doesn't support "
             + "third-party modifications, so you use it at your own risk.")
        Text("It doesn't modify the game's files. It only changes the graphics layer the official "
             + "Mac app already uses (Wine, plus d9mt for Direct3D 9 on Metal), and Uninstall puts "
             + "that back the way Broadsword ships it.")
        Text("For help, contact Pharaphobia on Discord or open a GitHub issue. Please don't send "
             + "logs or bug reports about SWTOR on Mac to Broadsword or SWTOR customer support.")
        Text("Star Wars: The Old Republic and SWTOR are trademarks of their respective owners.")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      .fixedSize(horizontal: false, vertical: true)
      .foregroundStyle(.secondary)
      if !installer.installed {
        Toggle("I understand, and I use SWTOR on Mac at my own risk", isOn: $installer.understood)
          .toggleStyle(.checkbox)
          .disabled(installer.isBusy)
      }
    } header: {
      Label("Unofficial community project", systemImage: "exclamationmark.shield.fill")
        .foregroundStyle(.orange)
    }
  }
}

struct StatusSection: View {
  let installer: Installer
  private var installed: Bool { installer.installed }

  var body: some View {
    Section("This Mac") {
      if !installer.loaded {
        HStack { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
      } else {
        row("Official SWTOR app", ok: installer.officialPresent,
            detail: installer.officialPresent ? "Installed" : "Not found")
        if !installer.officialPresent {
          VStack(alignment: .leading, spacing: 6) {
            Text("Install SWTOR from the official website first and start it once, so it sets up "
                 + "the game. SWTOR on Mac never downloads the launcher or the game.")
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Link("Get SWTOR at swtor.com", destination: URL(string: "https://www.swtor.com")!)
              .pointerStyle(.link)
          }
        }
        if !installer.appleSilicon {
          row("Apple Silicon", ok: false, detail: "Required")
        }
        row("Rosetta", ok: installer.rosetta, detail: installer.rosetta ? "Installed" : "Not installed")
        row("SWTOR on Mac", ok: installer.installed,
            detail: installer.installed ? "Version \(installer.status["installed_version"] ?? "?")" : "Not installed",
            neutral: !installer.installed)
        wrapperRow
        if installer.running {
          Label("Quit the SWTOR launcher and the game to install or uninstall.", systemImage: "pause.circle.fill")
            .foregroundStyle(.orange)
        }
      }
    }
  }

  @ViewBuilder private var wrapperRow: some View {
    switch installer.wrapper {
    case "personal":
      row("Wine wrapper", ok: false, detail: "Developer setup (swtor-mac-proper)", warning: true)
      Text("A different setup is hooked into Broadsword's Wine folder. SWTOR on Mac leaves it alone "
           + "and asks before replacing it.")
        .font(.callout).foregroundStyle(.secondary)
    case "foreign":
      row("Wine wrapper", ok: false, detail: "Not SWTOR on Mac's", warning: true)
      Text("Something else is hooked into Broadsword's Wine folder. SWTOR on Mac leaves it alone and "
           + "asks before replacing it.")
        .font(.callout).foregroundStyle(.secondary)
    case "replaced" where !installed:
      row("Wine wrapper", ok: false, detail: "Leftovers of another setup", warning: true)
      Text("Broadsword's Wine folder has a bin-real folder SWTOR on Mac did not make. SWTOR on Mac "
           + "asks before taking it over.")
        .font(.callout).foregroundStyle(.secondary)
    case "replaced":
      row("Wine wrapper", ok: false, detail: "Removed by a launcher update", warning: true)
      Text("The official launcher updated its Wine and dropped SWTOR on Mac's hook. Reinstall to put it back.")
        .font(.callout).foregroundStyle(.secondary)
    case "ours":
      row("Wine wrapper", ok: true, detail: "SWTOR on Mac")
    case "stock":
      row("Wine wrapper", ok: true, detail: "Broadsword's own", neutral: true)
    default:
      EmptyView()
    }
  }

  private func row(_ title: String, ok: Bool, detail: String, neutral: Bool = false, warning: Bool = false) -> some View {
    LabeledContent(title) {
      HStack(spacing: 6) {
        Text(detail).foregroundStyle(.secondary)
        Image(systemName: neutral ? "circle.dashed" : ok ? "checkmark.circle.fill"
              : warning ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
          .foregroundStyle(neutral ? Color.secondary : ok ? Color.green : warning ? Color.orange : Color.red)
      }
    }
  }
}

struct ProgressSection: View {
  @Bindable var installer: Installer

  var body: some View {
    Section {
      switch installer.phase {
      case .working(let op):
        VStack(alignment: .leading, spacing: 8) {
          if let p = installer.progress, p.total > 0 {
            ProgressView(value: Double(min(p.done, p.total)), total: Double(p.total))
            Text("Downloading \(p.label): \(mb(p.done)) of \(mb(p.total))")
          } else {
            ProgressView().progressViewStyle(.linear)
            Text(installer.step)
          }
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel(op == .install ? "Installing" : "Uninstalling")
      case .succeeded(let message):
        Label(message, systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .fixedSize(horizontal: false, vertical: true)
        ForEach(installer.warnings, id: \.self) { w in
          Label(w, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }
      case .failed(let message):
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      case .idle:
        EmptyView()
      }
      DisclosureGroup("Details", isExpanded: $installer.showLog) {
        LogView(lines: installer.log)
      }
    } header: {
      Text(installer.phase == .working(.uninstall) ? "Uninstalling" : "Progress")
    } footer: {
      if let dir = installer.status["log_dir"] {
        Text("Full log: \((dir as NSString).abbreviatingWithTildeInPath)/install.log")
          .font(.caption).foregroundStyle(.tertiary)
      }
    }
  }

  private func mb(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

struct LogView: View {
  let lines: [String]

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
            Text(line).id(i)
          }
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(height: 150)
      .onChange(of: lines.count) { _, n in
        if n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) }
      }
    }
  }
}

struct ActionBar: View {
  let installer: Installer
  let uninstall: () -> Void
  let install: () -> Void

  var body: some View {
    GlassEffectContainer(spacing: 12) {
      HStack(spacing: 12) {
        if installer.isBusy {
          Spacer()
          // An install rolls back when cancelled; an uninstall is quick and runs to the end.
          if installer.phase == .working(.install) {
            Button("Cancel") { installer.cancel() }
              .buttonStyle(.glass)
              .keyboardShortcut(.cancelAction)
          }
        } else {
          if installer.canUninstall {
            Button("Uninstall…", role: .destructive, action: uninstall)
              .buttonStyle(.glass)
          }
          Spacer()
          Button(installer.installed ? "Reinstall" : "Install", action: install)
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!installer.canInstall)
        }
      }
      .controlSize(.large)
      .pointerStyle(.link)
    }
  }
}

struct Footer: View {
  let credits: [String: String]

  var body: some View {
    VStack(spacing: 4) {
      Text("Unofficial. Not made, endorsed or supported by Broadsword Games, EA, Lucasfilm or Disney.")
      HStack(spacing: 6) {
        Text("Developed by \(credits["author"] ?? "Jan Drlý")")
        if let link {
          Text("·")
          Link(link.absoluteString.replacingOccurrences(of: "https://", with: ""), destination: link)
            .foregroundStyle(.link)
            .pointerStyle(.link)
        }
      }
    }
    .font(.caption)
    .foregroundStyle(.tertiary)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(.bar)
    .overlay(alignment: .top) { Divider() }
  }

  private var link: URL? {
    let repo = credits["repo"] ?? "", github = credits["github"] ?? ""
    return URL(string: repo.isEmpty ? github : repo).flatMap { $0.host == nil ? nil : $0 }
  }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
  var installer: Installer?

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  // Not while installing or uninstalling: the script finishes or rolls back first.
  @MainActor func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let installer, installer.isBusy else { return .terminateNow }
    let alert = NSAlert()
    alert.messageText = "SWTOR on Mac is still working"
    alert.informativeText = "Wait until it has finished, or press Cancel in the window first."
    alert.runModal()
    return .terminateCancel
  }
}

@main
struct SWTORonMacApp: App {
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate
  private let installer = Installer()

  var body: some Scene {
    Window("SWTOR on Mac", id: "main") {
      MainView(installer: installer)
        .onAppear {
          delegate.installer = installer
          installer.refresh()
          NSApp.activate()
        }
        // Re-check when the user comes back (e.g. after quitting the launcher): no polling.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
          installer.refresh()
        }
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultSize(width: 600, height: 840)
    .defaultLaunchBehavior(.presented)
    .restorationBehavior(.disabled)
    .commands { CommandGroup(replacing: .newItem) {} }
  }
}
