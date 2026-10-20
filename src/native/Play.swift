// The Play button, the window's primary action once SWTOR on Mac is installed: opens the
// official SWTOR app (its launcher then starts the game on SWTOR on Mac's engine), or brings
// the launcher, or the game, to the front if it already runs.
//
// The official app is where som.sh status finds it (official_app_path: /Applications, or the
// sandbox's under SWTOR_ON_MAC_ROOT); outside a sandbox, if it is not there, wherever Launch
// Services knows it by its bundle id (com.solidstatenetworks.host, the launcher's: Solid State
// Networks' launcher host, so the name must match too). In a sandbox it is never anything
// outside the sandbox, and a running SWTOR outside it is not brought to the front.
//
//   SWTORonMac --play-target   prints what the button would do and exits (no window, nothing
//                              is opened): "launch <path>", "show launcher|game" or
//                              "unavailable <reason>"
//   SWTORonMac --is-game BUNDLE_ID PATH PID   "game" or "not game": whether an app with that
//                              bundle id ("-": none), executable path and process counts as the
//                              game (isGame), for tests

import AppKit
import os

enum PlayAction: Equatable {
  case launch(URL)
  // the launcher or the game runs: bring it to the front (game: the game does)
  case show(game: Bool)
  case unavailable(String)
}

extension Installer {
  // Settings: "Quit SWTOR on Mac after launching" (off by default)
  static let quitAfterLaunchKey = "quitAfterLaunch"

  // What the button does right now.
  var playAction: PlayAction {
    Installer.playAction(status: status, working: isBusy, launcher: runningLauncher, game: runningGame)
  }

  nonisolated static func playAction(status: [String: String], working: Bool, launcher: Bool, game: Bool) -> PlayAction {
    if working { return .unavailable("Wait until SWTOR on Mac has finished.") }
    guard !status.isEmpty else { return .unavailable("Checking this Mac…") }
    guard let url = officialAppURL(status) else {
      return .unavailable("The official SWTOR app was not found. Install it from swtor.com.")
    }
    guard status["installed"] == "yes" else { return .unavailable("Install SWTOR on Mac first.") }
    switch status["wrapper"] {
    case "ours": break
    case "replaced": return .unavailable("A launcher update removed the hook. Repair it first.")
    default: return .unavailable("The launcher hook is not active. Reinstall SWTOR on Mac first.")
    }
    let busy = status["busy"] ?? ""
    if game { return .show(game: true) }
    if launcher || busy == "launcher" || busy == "game" { return .show(game: busy == "game") }
    return .launch(url)
  }

  // The sandbox's root (SWTOR_ON_MAC_ROOT; som.sh reports its real path), or nil.
  nonisolated static func sandboxRoot(_ status: [String: String]) -> String? {
    if let root = status["root"], !root.isEmpty, root != "/" { return root }
    let env = ProcessInfo.processInfo.environment["SWTOR_ON_MAC_ROOT"] ?? ""
    return env.isEmpty ? nil : env
  }

  // The official app: som.sh's official_app_path, else (outside a sandbox) Launch Services'.
  nonisolated static func officialAppURL(_ status: [String: String]) -> URL? {
    let root = sandboxRoot(status)
    if status["official_app"] == "yes", let path = status["official_app_path"], !path.isEmpty {
      let url = URL(fileURLWithPath: path)
      if let root, !inside(url.path, root) { return nil }
      return url
    }
    guard root == nil else { return nil }
    let named = { (url: URL) in url.lastPathComponent.localizedCaseInsensitiveContains("Old Republic") }
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: launcherBundleID), named(url) {
      return url
    }
    return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: launcherBundleID).first(where: named)
  }

  // path is in folder (both as given, or both standardized: /private/tmp is /tmp)
  nonisolated static func inside(_ path: String, _ folder: String) -> Bool {
    let std = { (p: String) in (p as NSString).standardizingPath }
    return path.hasPrefix(folder + "/") || std(path).hasPrefix(std(folder) + "/")
  }

  // The launcher and the game, if they run (in a sandbox: only the sandbox's). An app whose
  // process is gone does not count: macOS keeps a quit launcher listed (and in the Dock) while
  // processes it started still run (Broadsword's mac_wine, the game's Wine session).
  nonisolated static func runningSWTOR(_ status: [String: String]) -> (launcher: NSRunningApplication?, game: NSRunningApplication?) {
    let root = sandboxRoot(status)
    let apps = NSWorkspace.shared.runningApplications.filter { app in
      guard !app.isTerminated, isSWTOR(app), processAlive(app.processIdentifier) else { return false }
      guard let root else { return true }
      return inSandbox(app, root)
    }
    return (apps.first { !isGame($0) }, apps.first(where: { isGame($0) }))
  }

  // The game: its Game Mode bundle, or a swtor.exe program. Launch Services knows the game by
  // the path CrossOver starts it from, winetemp-<...>/wine: a link to the Game Mode copy of the
  // engine's loader (.../SWTOR.app/Contents/MacOS/swtor.exe), with no bundle id. Wine rewrites
  // the process's argv[0] to the game's path (.../retailclient/swtor.exe), with Game Mode off too.
  nonisolated static func isGame(_ app: NSRunningApplication) -> Bool {
    isGame(bundleID: app.bundleIdentifier, executable: app.executableURL?.path, pid: app.processIdentifier)
  }

  nonisolated static func isGame(bundleID: String?, executable: String?, pid: pid_t) -> Bool {
    if bundleID == gameBundleID { return true }
    guard let path = executable, !path.isEmpty else { return false }
    if isSwtorExe(resolved(path)) { return true }
    return path.contains("/winetemp-") && isSwtorExe(argv0(pid) ?? "")
  }

  // (a Unix or a Windows path)
  nonisolated static func isSwtorExe(_ path: String) -> Bool {
    path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last?.lowercased() == "swtor.exe"
  }

  // the file a path ends up at, links resolved
  nonisolated static func resolved(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
  }

  // the process's argv[0] as ps shows it (KERN_PROCARGS2: argc, the executable path, then argv)
  nonisolated static func argv0(_ pid: pid_t) -> String? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard pid > 0, sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
    var buf = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
    var i = MemoryLayout<Int32>.size
    while i < size, buf[i] != 0 { i += 1 }
    while i < size, buf[i] == 0 { i += 1 }
    let start = i
    while i < size, buf[i] != 0 { i += 1 }
    return i > start ? String(decoding: buf[start..<i], as: UTF8.self) : nil
  }

  // in the sandbox: its bundle or executable there (links resolved)
  nonisolated static func inSandbox(_ app: NSRunningApplication, _ root: String) -> Bool {
    let paths = [app.bundleURL?.path, app.executableURL?.path, app.executableURL.map { resolved($0.path) }]
    return paths.contains { $0.map { inside($0, root) } == true }
  }

  // The game's window comes up behind the app that is active (macOS 14+'s cooperative
  // activation: an app only gets activated if the active one yields to it). After starting the
  // game the launcher deactivates itself, and macOS activates the app that was active before
  // it, often this one (Play): the game's own request to come forward is then turned down, and
  // its window stays behind ours. So while a game that has just started waits for the
  // activation, this app, whenever it is active, yields to it and activates it once it shows
  // its window (a regular app). Once per game start, for 2 minutes at most (no fighting the
  // user later); a game already running when the app starts is left alone.
  func gameStarted(_ game: NSRunningApplication) {
    if let root = Installer.sandboxRoot(status), !Installer.inSandbox(game, root) { return }
    guard startingGame?.processIdentifier != game.processIdentifier else { return }
    startingGame = game
    startingGameSince = .now
    startingGamePolicy = game.observe(\.activationPolicy, options: [.initial, .new]) { [weak self] _, _ in
      DispatchQueue.main.async { MainActor.assumeIsolated { self?.handOffToGame() } }
    }
  }

  func handOffToGame() {
    guard let game = startingGame else { return }
    if game.isTerminated || game.isActive || Date.now.timeIntervalSince(startingGameSince) > 120 {
      endGameHandOff()
      return
    }
    guard NSApp.isActive else { return }
    NSApp.yieldActivation(to: game)
    // (without a window yet it is not a regular app: then it can activate itself when it shows
    // one, as we have yielded)
    guard game.activationPolicy == .regular else { return }
    // (NSLog's text is <private> in the unified log; this one is readable for t2-collect.sh)
    Logger(subsystem: "cz.jandrly.swtoronmac", category: "play")
      .notice("handing the activation to the game (pid \(game.processIdentifier, privacy: .public))")
    game.activate()
  }

  func gameActivated(_ pid: pid_t) {
    if pid != 0, pid == startingGame?.processIdentifier { endGameHandOff() }
  }

  private func endGameHandOff() {
    startingGame = nil
    startingGamePolicy = nil
  }

  nonisolated static func processAlive(_ pid: pid_t) -> Bool {
    pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
  }

  // The button. then: an error to show, if any.
  func play(then: @escaping (String?) -> Void) {
    switch playAction {
    case .unavailable(let reason): then(reason)
    case .show: showSWTOR(then: then)
    case .launch(let url): launch(url, then: then)
    }
  }

  private func launch(_ url: URL, then: @escaping (String?) -> Void) {
    guard !launching else { return }
    launching = true
    launchID += 1
    let id = launchID
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    // in a sandbox, never hand over to a running copy of the real app (same bundle id)
    if Installer.sandboxRoot(status) != nil { configuration.createsNewApplicationInstance = true }
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
      let message = error.map { "\(url.lastPathComponent) could not be opened: \($0.localizedDescription)" }
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self.launchEnded(id, error: message, then: then) }
      }
    }
    // Launch Services answers once the app has checked in; the launcher showing up as running
    // ends the wait too (refresh), and so does this, without quitting
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
      MainActor.assumeIsolated { self.launchEnded(id, error: nil, quit: false) }
    }
  }

  // The launch is over: opened, failed, the launcher seen running (id nil) or timed out. With
  // "Quit SWTOR on Mac after launching", quit once it has opened.
  func launchEnded(_ id: Int?, error: String?, quit: Bool = true, then: ((String?) -> Void)? = nil) {
    guard launching, id == nil || id == launchID else { return }
    launching = false
    then?(error)
    refresh()
    if error == nil, quit, UserDefaults.standard.bool(forKey: Installer.quitAfterLaunchKey) {
      NSApp.terminate(nil)
    }
  }

  // The game if it runs (the launcher waits behind it), else the launcher; neither found (it
  // has just quit): open the official app, which also brings a running one to the front.
  private func showSWTOR(then: @escaping (String?) -> Void) {
    let running = Installer.runningSWTOR(status)
    guard let app = running.game ?? running.launcher else {
      if let url = Installer.officialAppURL(status) { launch(url, then: then) } else { refresh() }
      return
    }
    app.unhide()
    NSApp.yieldActivation(to: app)
    app.activate()
    then(nil)
  }

  // SWTORonMac --play-target
  nonisolated static func printPlayTarget() {
    let script = Bundle.main.resourceURL!.appendingPathComponent("som.sh")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path, "status"]
    process.standardInput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let pipe = Pipe()
    process.standardOutput = pipe
    var output = ""
    if (try? process.run()) != nil {
      output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      process.waitUntilExit()
    }
    let status = parseStatus(output)
    let running = runningSWTOR(status)
    switch playAction(status: status, working: false, launcher: running.launcher != nil, game: running.game != nil) {
    case .launch(let url): print("launch \(url.path)")
    case .show(let game): print("show \(game ? "game" : "launcher")")
    case .unavailable(let reason): print("unavailable \(reason)")
    }
  }
}
