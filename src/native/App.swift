// SWTOR on Mac: the app's main window (SwiftUI). Shows the notice and the state of this Mac,
// and runs Resources/som.sh (status, install, uninstall), which does the actual work and
// streams its progress back as "@" lines (see the header of src/som.sh).
// Also here: the app menu (About, Check for Updates…, Settings…, Collect Logs…, Quit), with
// Settings.swift (the Settings window) and Updates.swift (Sparkle).
//
// The window is resizable in both directions. Wide (the default), it has two columns: the
// notice on the left; this Mac's state, the progress and the buttons on the right; the only
// scrolling part is the install log. Narrow, it is one column that scrolls as a whole (the log
// then shows its last lines without a scroll area of its own). Buttons and footer stay put.
//
// Built against the macOS 27 SDK, so the standard controls and Liquid Glass styles used here
// take the macOS 27 design; runs on macOS 26 too (same APIs, 26 look).
//
// SWTOR_ON_MAC_ROOT and SWTOR_ON_MAC_DRY_RUN in the app's environment are passed on to
// som.sh (and collect-logs.sh), so the window can be tried against a sandbox:
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
    case succeeded(Operation, String)
    case failed(Operation, String)
  }
  // The timeline of an operation: som.sh announces each step with "@phase <n>"
  struct Step: Identifiable, Equatable {
    let id: Int
    let title: String
    let detail: String
    let symbol: String
  }
  static let installSteps = [
    Step(id: 1, title: "Download the Wine engine",
         detail: "CrossOver 24.0.7 and its libraries (about 270 MB)", symbol: "arrow.down"),
    Step(id: 2, title: "Prepare the game files",
         detail: "A Wine prefix of SWTOR on Mac's own, with your game settings", symbol: "folder.fill"),
    Step(id: 3, title: "Install the d9mt graphics driver",
         detail: "The game's Direct3D 9, straight to Metal", symbol: "cpu.fill"),
    Step(id: 4, title: "Hook into the SWTOR launcher",
         detail: "Plus Game Mode, and a repair after launcher updates", symbol: "link"),
  ]
  static let uninstallSteps = [
    Step(id: 1, title: "Restore the launcher's own Wine",
         detail: "Broadsword's files go back where they were", symbol: "arrow.uturn.backward"),
    Step(id: 2, title: "Copy your game settings back",
         detail: "With a backup of the official app's previous ones", symbol: "folder.fill"),
    Step(id: 3, title: "Remove SWTOR on Mac's files",
         detail: "Engine, prefix and settings; the logs stay", symbol: "trash.fill"),
  ]
  struct Progress: Equatable { var label: String; var done: Int64; var total: Int64 }

  var status: [String: String] = [:]
  var phase: Phase = .idle
  var step = ""
  var progress: Progress?
  var log: [String] = []
  var warnings: [String] = []
  // the notice was read and accepted (kept across launches)
  var understood = UserDefaults.standard.bool(forKey: "acceptedNotice") {
    didSet { UserDefaults.standard.set(understood, forKey: "acceptedNotice") }
  }
  var showLog = false
  // a sheet or alert is open on the main window (it keeps the app from quitting), and a
  // request to close them
  var sheetOpen = false
  var closeSheets = 0
  // the operation shown in the step list, and how far it got
  var operation: Operation = .install
  var stepIndex: Int?
  let credits: [String: String]
  // an install or uninstall has ended (a held app update may go ahead)
  var onIdle: (() -> Void)?
  // the wrapper's daily check found a newer version (status update_available)
  var onUpdateAvailable: ((String) -> Void)?

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
  // What runs (som.sh status "busy"): launcher (the SWTOR launcher), game, wine (Broadsword's
  // Wine), session (a Wine session of SWTOR on Mac's engine), leftovers (only leftover
  // processes of its engine, no wineserver: install and uninstall end them first), none
  var busy: String { status["busy"] ?? (running ? "launcher" : "none") }
  var busyDetail: String { status["busy_detail"] ?? "" }
  var leftovers: Bool { busy == "leftovers" }
  // ending them (End Leftover Wine Processes)
  var endingLeftovers = false
  // the launcher or the game runs (NSWorkspace; the Play button brings it to the front), and
  // the Play button is opening the official app (Play.swift)
  var runningLauncher = false
  var runningGame = false
  var launching = false
  var launchID = 0
  var wrapper: String { status["wrapper"] ?? "" }
  // a wrapper (or its leftovers) that is not ours: install/uninstall ask before going ahead
  var otherWrapper: Bool { wrapper == "personal" || wrapper == "foreign" || (wrapper == "replaced" && !installed) }
  var appleSilicon: Bool { status["arch"].map { $0 == "arm64" } ?? true }
  var loaded: Bool { !status.isEmpty }
  var appVersion: String { credits["version"] ?? "?" }
  // installed by an older (or newer) version of the app: Reinstall brings it in line
  var installedOtherVersion: Bool {
    installed && (status["installed_version"] ?? appVersion) != appVersion
  }

  var steps: [Step] { operation == .install ? Installer.installSteps : Installer.uninstallSteps }

  // 0...1 across the steps, a download counting by its bytes
  var fraction: Double {
    guard let i = stepIndex else { return 0 }
    var part = 0.0
    if let p = progress, p.total > 0 { part = min(1, Double(p.done) / Double(p.total)) }
    return min(1, (Double(i) + part) / Double(steps.count))
  }

  // (a running launcher, game or Wine session does not disable them: clicking says why it
  // can't go ahead, see blockedReason)
  var canInstall: Bool {
    loaded && !isBusy && officialPresent && rosetta && appleSilicon && (installed || understood)
  }
  var canUninstall: Bool {
    loaded && !isBusy && (installed || wrapper == "ours" || wrapper == "replaced")
  }

  // Why install/uninstall can't go ahead right now, or nil. Leftover Wine processes don't
  // stop them (som.sh ends those first and logs it).
  var blockedReason: String? {
    let names = busyDetail.isEmpty ? "" : " (\(busyDetail))"
    switch busy {
    case "launcher": return "The SWTOR launcher is running. Quit it first."
    case "game": return "The game is running\(names). Quit it first."
    case "wine": return "Broadsword's Wine is still running\(names). Quit the SWTOR launcher and the game first."
    case "session":
      return "SWTOR on Mac's Wine is still running\(names). It ends by itself a few seconds after the "
        + "launcher and the game have quit; try again then."
    default: return nil
    }
  }

  // MARK: Actions

  // then: runs once the new status is in
  func refresh(then: (() -> Void)? = nil) {
    guard !isBusy else { then?(); return }
    Task {
      let values = Installer.parseStatus(await Installer.capture(script: script, arguments: ["status"]))
      status = values
      let running = Installer.runningSWTOR(values)
      runningLauncher = running.launcher != nil
      runningGame = running.game != nil
      if launching && (runningLauncher || runningGame) { launchEnded(nil, error: nil) }
      if let version = values["update_available"], !version.isEmpty, let dir = values["app_dir"] {
        // once: the file goes, the app's own updater takes it from here
        try? FileManager.default.removeItem(atPath: dir + "/update-available")
        if Installer.isNewer(version, than: appVersion) { onUpdateAvailable?(version) }
      }
      then?()
    }
  }

  // End Leftover Wine Processes: som.sh ends them if nothing else of SWTOR runs. Returns its
  // error, if any.
  func endLeftovers(then: @escaping (String?) -> Void) {
    guard !isBusy, !endingLeftovers else { return }
    endingLeftovers = true
    let script = script
    Task {
      let output = await Installer.capture(script: script, arguments: ["end-leftovers"])
      endingLeftovers = false
      let error = output.contains("@done ") ? nil
        : output.split(separator: "\n").first { $0.hasPrefix("@error ") }.map { String($0.dropFirst(7)) }
          ?? "The leftover Wine processes could not be ended."
      refresh { then(error) }
    }
  }

  // MARK: Re-checking (event-driven, no polling)

  // the official launcher's bundle, and the game's Game Mode bundle (src/som.sh)
  nonisolated static let launcherBundleID = "com.solidstatenetworks.host"
  nonisolated static let gameBundleID = "cz.jandrly.swtoronmac.game"
  // a SWTOR app quit (the settings window re-reads too)
  var onSWTORQuit: (() -> Void)?
  private var activeObserver: NSObjectProtocol?
  private var appsObserver: NSKeyValueObservation?
  private var recheck: DispatchWorkItem?

  // Re-check when the user comes back to the app, and when the launcher or the game starts or
  // quits: NSWorkspace's runningApplications (KVO; its didTerminate notification leaves out
  // LSUIElement apps, and the game runs from the Game Mode bundle, which is one).
  func observe() {
    guard activeObserver == nil else { return }
    activeObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    let swtorPids = PidSet()
    appsObserver = NSWorkspace.shared.observe(\.runningApplications, options: [.initial, .old, .new]) { [weak self] _, change in
      var started = false
      for app in change.newValue ?? [] where Installer.isSWTOR(app) {
        swtorPids.insert(app.processIdentifier)
        started = true
      }
      let quit = (change.oldValue ?? []).contains { swtorPids.remove($0.processIdentifier) || Installer.isSWTOR($0) }
      guard quit || started else { return }
      DispatchQueue.main.async { MainActor.assumeIsolated { if quit { self?.swtorQuit() } else { self?.refresh() } } }
    }
  }

  nonisolated static func isSWTOR(_ app: NSRunningApplication?) -> Bool {
    guard let app else { return false }
    if let id = app.bundleIdentifier, id == launcherBundleID || id == gameBundleID { return true }
    let path = app.executableURL?.path ?? ""
    return path.hasSuffix("/swtor.exe") || path.hasSuffix("/Star Wars - The Old Republic Launcher")
  }

  private func swtorQuit() {
    refresh()
    onSWTORQuit?()
    // After the launcher quits, its Wine session ends and hold-launcher clears what is left of
    // it within about 12 s: one more look then.
    recheck?.cancel()
    let work = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        self?.refresh()
        self?.onSWTORQuit?()
      }
    }
    recheck = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
  }

  func start(_ operation: Operation, force: Bool = false) {
    guard !isBusy else { return }
    phase = .working(operation)
    self.operation = operation
    stepIndex = nil
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
        MainActor.assumeIsolated { self?.finished(operation, status) }
      }
    }
    do {
      try process.run()
      self.process = process
    } catch {
      phase = .failed(operation, "Could not start the installer: \(error.localizedDescription)")
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
    } else if line.hasPrefix("@phase ") {
      if let n = Int(line.dropFirst(7)), n >= 1, n <= steps.count { stepIndex = n - 1; progress = nil }
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

  private func finished(_ operation: Operation, _ status: Int32) {
    process = nil
    progress = nil
    if status == 0 {
      phase = .succeeded(operation, doneMessage ?? "Done.")
    } else {
      phase = .failed(operation, lastError ?? "Something went wrong (status \(status)). Details are in the log.")
    }
    lastError = nil
    doneMessage = nil
    refresh()
    onIdle?()
  }

  // MARK: Helpers

  // dotted version numbers: a > b
  // Dotted numbers; a prerelease (0.0.6-dev.1) is older than its release (0.0.6).
  static func isNewer(_ a: String, than b: String) -> Bool {
    let ca = a.split(separator: "-", maxSplits: 1), cb = b.split(separator: "-", maxSplits: 1)
    let x = (ca.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
    let y = (cb.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(x.count, y.count) {
      let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
      if p != q { return p > q }
    }
    return cb.count > 1 && ca.count == 1
  }

  static func capture(script: URL, arguments: [String]) async -> String {
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

  // som.sh status: KEY=VALUE lines
  nonisolated static func parseStatus(_ output: String) -> [String: String] {
    var values: [String: String] = [:]
    for line in output.split(separator: "\n") {
      guard let eq = line.firstIndex(of: "=") else { continue }
      values[String(line[..<eq])] = String(line[line.index(after: eq)...])
    }
    return values
  }

  // Resources/app.properties (written by build.sh): version, author, github, repo, feed.
  static func readProperties(_ url: URL) -> [String: String] {
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

// The pids of SWTOR's apps seen running (KVO calls back on any thread)
final class PidSet: @unchecked Sendable {
  private var pids = Set<pid_t>()
  private let lock = NSLock()
  func insert(_ pid: pid_t) { lock.lock(); pids.insert(pid); lock.unlock() }
  // true if it was there
  func remove(_ pid: pid_t) -> Bool { lock.lock(); defer { lock.unlock() }; return pids.remove(pid) != nil }
}

// MARK: - App menu actions

@MainActor
enum AppActions {
  // The standard About panel with the credits and component versions.
  static func showAbout(credits: [String: String]) {
    let centered = NSMutableParagraphStyle()
    centered.alignment = .center
    let body: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
      .foregroundColor: NSColor.labelColor, .paragraphStyle: centered]
    let text = NSMutableAttributedString(string:
      "Runs the official SWTOR Mac app on d9mt (Direct3D 9 on Metal)\n"
      + "Developed by \(credits["author"] ?? "Jan Drlý")\n\n"
      + "Unofficial: not made, endorsed or supported by Broadsword Games, EA, Lucasfilm or Disney.\n"
      + "For help: Pharaphobia on Discord or a GitHub issue.\n", attributes: body)
    for key in ["repo", "github"] {
      guard let url = credits[key], !url.isEmpty, let link = URL(string: url) else { continue }
      var attributes = body
      attributes[.link] = link
      text.append(NSAttributedString(string: "\n", attributes: body))
      text.append(NSAttributedString(string: url.replacingOccurrences(of: "https://", with: ""), attributes: attributes))
    }
    if Updates.isDevBuild {
      var dev = body
      dev[.font] = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
      dev[.foregroundColor] = NSColor.systemPurple
      text.insert(NSAttributedString(string: "Development build: for testing, not a release. "
        + "Debug Logging is on by default; no automatic update checks.\n\n", attributes: dev), at: 0)
    }
    var small = body
    small[.font] = NSFont.systemFont(ofSize: NSFont.labelFontSize - 1)
    small[.foregroundColor] = NSColor.secondaryLabelColor
    text.append(NSAttributedString(string: "\n\n" + componentVersions(), attributes: small))
    NSApp.activate()
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationName: "SWTOR on Mac",
      .applicationVersion: (credits["version"] ?? "?") + (Updates.isDevBuild ? " (development build)" : ""),
      .version: "",
      .credits: text,
    ])
  }

  // "d9mt 7975e2e · Wine WS12WineCX24.0.7_7" from Resources/VERSIONS.
  static func componentVersions() -> String {
    let url = Bundle.main.resourceURL!.appendingPathComponent("VERSIONS")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
    var parts: [String] = []
    for line in text.split(separator: "\n") {
      let f = line.split(separator: " ")
      guard f.count >= 2 else { continue }
      if f[0] == "d9mt" { parts.append("d9mt \(f[1])") }
      if f[0] == "engine" { parts.append("Wine \(f[1])") }
      if f[0] == "sparkle" { parts.append("Sparkle \(f[1])") }
    }
    return parts.joined(separator: " · ")
  }
}

// Collect Logs…: Resources/collect-logs.sh zips the logs for a bug report (a few seconds: off
// the main thread) and prints the zip's path; then say where it is and show it in Finder.
@MainActor @Observable
final class LogCollector {
  var busy = false

  func collect() {
    guard !busy else { return }
    busy = true
    let script = Bundle.main.resourceURL!.appendingPathComponent("collect-logs.sh")
    DispatchQueue.global(qos: .userInitiated).async {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/bash")
      process.arguments = [script.path]
      process.standardInput = FileHandle.nullDevice
      let output = Pipe(), errors = Pipe()
      process.standardOutput = output
      process.standardError = errors
      var zip: String?, problem: String?
      do {
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
          .components(separatedBy: "\n").last ?? ""
        if process.terminationStatus == 0, !path.isEmpty, FileManager.default.fileExists(atPath: path) {
          zip = path
        } else {
          problem = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
      } catch {
        problem = error.localizedDescription
      }
      DispatchQueue.main.async { [zip, problem] in
        MainActor.assumeIsolated { self.finished(zip: zip, problem: problem) }
      }
    }
  }

  private func finished(zip: String?, problem: String?) {
    busy = false
    let alert = NSAlert()
    if let zip {
      let folder = FileManager.default.displayName(atPath: (zip as NSString).deletingLastPathComponent)
      alert.messageText = "Logs collected"
      alert.informativeText = "\((zip as NSString).lastPathComponent) is in your \(folder) folder. Send it with a "
        + "short description of the problem to Pharaphobia on Discord or attach it to a GitHub issue, "
        + "not to Broadsword or SWTOR customer support. It contains no account names or passwords."
      alert.addButton(withTitle: "Show in Finder")
    } else {
      alert.alertStyle = .warning
      alert.messageText = "Could not collect the logs"
      alert.informativeText = "\(problem?.isEmpty == false ? problem! : "collect-logs.sh failed.")\n\n"
        + "The logs are in ~/Library/Logs/SWTOR on Mac."
    }
    NSApp.activate()
    alert.runModal()
    if let zip { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: zip)]) }
  }
}

struct AppCommands: Commands {
  let installer: Installer
  let updates: Updates
  let settings: GameSettings
  let logs: LogCollector
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("About SWTOR on Mac") { AppActions.showAbout(credits: installer.credits) }
      Button("Check for Updates…") { updates.checkForUpdates() }
        .disabled(!updates.available)
    }
    CommandGroup(replacing: .appSettings) {
      // only with SWTOR on Mac installed: the settings live in its folder
      Button("Settings…") {
        settings.reload()
        openWindow(id: "settings")
      }
      .keyboardShortcut(",")
      .disabled(!installer.installed)
      Button("Collect Logs…") { logs.collect() }
        .disabled(logs.busy)
    }
    CommandGroup(replacing: .newItem) {}
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
  private let updates = Updates()
  private let settings = GameSettings()
  private let logs = LogCollector()

  init() {
    // what the Play button would do, for tests (Play.swift)
    if CommandLine.arguments.contains("--play-target") {
      Installer.printPlayTarget()
      exit(0)
    }
  }

  var body: some Scene {
    Window("SWTOR on Mac", id: "main") {
      MainView(installer: installer, settings: settings)
        .onAppear {
          delegate.installer = installer
          settings.updates = updates
          if !updates.available {
            updates.isBusy = { [installer] in installer.isBusy }
            updates.sheetOpen = { [installer] in installer.sheetOpen }
            updates.closeSheets = { [installer] in installer.closeSheets += 1 }
            installer.onIdle = { [updates] in updates.installerIdle() }
            installer.onUpdateAvailable = { [updates] _ in updates.checkForUpdates() }
            updates.start()
          }
          installer.onSWTORQuit = { [settings] in settings.reload() }
          installer.observe()
          installer.refresh()
          settings.reload()
          // (not for the UI test script, which drives the window in the background)
          switch ProcessInfo.processInfo.environment["SWTOR_ON_MAC_UI_TEST"] {
          case nil: NSApp.activate()
          case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
          default: break
          }
        }
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentMinSize)
    .defaultSize(width: 960, height: 680)
    .defaultLaunchBehavior(.presented)
    .restorationBehavior(.disabled)
    .commands { AppCommands(installer: installer, updates: updates, settings: settings, logs: logs) }

    // A window, not a Settings scene: that one's menu item could not be disabled while SWTOR on
    // Mac is not installed (and with our own item, the menu showed two).
    Window("SWTOR on Mac Settings", id: "settings") {
      SettingsView(settings: settings)
    }
    .windowResizability(.contentMinSize)
    .defaultSize(width: 760, height: 520)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
  }
}
