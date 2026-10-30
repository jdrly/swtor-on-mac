// Off-screen screenshots and a cost measurement of SWTOR on Mac's windows, for reviews and the
// redesign's proof. Compiled with the app's sources (-D SWTOR_SNAPSHOT, which drops the app's
// own entry point) by scripts/ui-snapshot.sh, which runs it under tools/vd/with-vd.sh: every
// window is put on that temporary virtual display before it is shown, never on the main one,
// and the program refuses to run without it. It never activates (an accessory app), so it takes
// no focus, and it captures with cacheDisplay, not a screen capture (no permission prompt).
// The installer state is made up here; nothing runs som.sh but Settings' fake one.
//
//   ui-snapshot shots <out dir>                       PNGs of the windows in their states
//   ui-snapshot still <png>                           the main window alone (WARP: a variant)
//   ui-snapshot measure <state> <seconds>             CPU (and GPU) time of this process
//       states: animating (the warp runs as in a key, visible window), paused (as when the
//       window is not in front: on the virtual display windows count as occluded), game (the
//       warp asked to run, but SWTOR runs), closed (no window)
//   ui-snapshot bench <frames>                        the warp's drawing alone, off-screen
//   ui-snapshot alertkeys                             which button Esc and Return press in the Logs collected alert

import AppKit
import SwiftUI

@main
struct UISnapshot {
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let args = Array(CommandLine.arguments.dropFirst())
    MainActor.assumeIsolated {
      Task { @MainActor in
        switch args.first {
        case "shots" where args.count == 2: await shots(URL(fileURLWithPath: args[1]))
        case "still" where args.count == 2: await still(URL(fileURLWithPath: args[1]))
        case "measure" where args.count == 3: await measure(args[1], seconds: Double(args[2]) ?? 30)
        case "bench" where args.count == 2: bench(frames: Int(args[1]) ?? 300)
        case "alertkeys": await alertKeys()
        default:
          print("usage: ui-snapshot shots <dir> | measure <animating|paused|game|closed> <seconds> | bench <frames> | alertkeys")
          exit(2)
        }
        exit(0)
      }
    }
    app.run()
  }
}

// MARK: - The virtual display

@MainActor
func virtualScreen() -> NSScreen {
  let parts = (ProcessInfo.processInfo.environment["VD_BOUNDS"] ?? "").split(separator: " ").compactMap { Double($0) }
  guard parts.count == 4 else { fail("no VD_BOUNDS: run me through tools/vd/with-vd.sh") }
  let want = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
  for screen in NSScreen.screens {
    guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
    if CGDisplayBounds(id) == want, CGDisplayIsMain(id) == 0 { return screen }
  }
  fail("the virtual display \(want) is not among NSScreen.screens")
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write("ui-snapshot: \(message)\n".data(using: .utf8)!)
  exit(5)
}

// A window on the virtual display, placed before it is ever shown.
@MainActor
func window<V: View>(_ view: V, size: CGSize, dark: Bool, key: Bool = true) -> NSWindow {
  let screen = virtualScreen()
  let host = NSHostingView(rootView: view.environment(\.controlActiveState, key ? .key : .inactive))
  let win = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                     styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                     backing: .buffered, defer: true)
  win.titlebarAppearsTransparent = true
  win.titleVisibility = .hidden
  win.isReleasedWhenClosed = false
  win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
  win.contentView = host
  win.setFrame(CGRect(x: screen.frame.minX + 60, y: screen.frame.maxY - 60 - size.height,
                      width: size.width, height: size.height), display: false)
  let main = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID).map { CGDisplayIsMain($0) != 0 } ?? false }
  guard screen.frame.contains(win.frame), !(main?.frame.intersects(win.frame) ?? true) else {
    fail("the window \(win.frame) would not be on the virtual display alone")
  }
  win.orderFrontRegardless()
  return win
}

@MainActor
func settle(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

// backdrop: the window's background colour under it, rounded, for an alert, whose glass
// cacheDisplay doesn't draw
@MainActor
func capture(_ win: NSWindow, to url: URL, backdrop: Bool = false) {
  let view = win.contentView!.superview ?? win.contentView!
  guard var rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fail("no bitmap for \(url.lastPathComponent)") }
  view.cacheDisplay(in: view.bounds, to: rep)
  if backdrop, let out = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    win.effectiveAppearance.performAsCurrentDrawingAppearance { NSColor.windowBackgroundColor.setFill() }
    NSBezierPath(roundedRect: view.bounds, xRadius: 26, yRadius: 26).fill()
    rep.draw(in: view.bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
    rep = out
  }
  try! rep.representation(using: .png, properties: [:])!.write(to: url)
  print("wrote \(url.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}

// MARK: - States

@MainActor
func installer(_ state: String) -> Installer {
  let i = Installer()
  i.understood = true
  var st = ["official_app": "yes", "official_wine": "yes", "rosetta": "yes", "arch": "arm64", "installed": "yes",
            "installed_version": "0.1.3", "wrapper": "ours", "d9mt": "2a1bc00",
            "engine": "cx-26.3.0-8", "installed_engine": "cx-26.3.0-8", "busy": "none",
            "official_app_path": "/Applications/Star Wars - The Old Republic.app"]
  switch state {
  case "fresh":
    st["installed"] = "no"; st["wrapper"] = "stock"; st["installed_version"] = nil
  case "installing":
    st["installed"] = "no"; st["wrapper"] = "stock"; st["installed_version"] = nil
    i.operation = .install
    i.phase = .working(.install)
    i.stepIndex = 0
    i.progress = .init(label: "Wine engine", done: 142_000_000, total: 235_000_000)
  case "done":
    i.operation = .install
    i.phase = .succeeded(.install, "SWTOR on Mac 0.1.3 is installed. Press Play SWTOR to start the game.")
    i.stepIndex = 3
  case "attention":
    st["wrapper"] = "replaced"
  case "game":
    i.runningGame = true; st["busy"] = "game"
  default: break
  }
  i.status = st
  return i
}

// MARK: - Shots

// WARP="fps=24 metal=1 res=0.5 height=0.7": a variant of the warp's rendering (Warp.Tuning)
func applyVariant() {
  for pair in (ProcessInfo.processInfo.environment["WARP"] ?? "").split(separator: " ") {
    let kv = pair.split(separator: "=")
    guard kv.count == 2, let v = Double(kv[1]) else { continue }
    switch kv[0] {
    case "fps": Warp.tuning.fps = v
    case "metal": Warp.tuning.metal = v != 0
    case "res": Warp.tuning.resolution = v
    case "height": Warp.tuning.height = v
    case "anim": Warp.tuning.animated = v != 0
    case "idle": Warp.tuning.idleStop = v > 0 ? v : nil
    default: break
    }
  }
}

@MainActor
func shots(_ dir: URL) async {
  try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  Warp.fixedTime = 6.0
  applyVariant()
  let settings = GameSettings()
  settings.reload()
  let main: [(String, String, Bool, CGSize)] = [
    ("main-installed-dark", "installed", true, CGSize(width: 960, height: 680)),
    ("main-installed-light", "installed", false, CGSize(width: 960, height: 680)),
    ("main-fresh-dark", "fresh", true, CGSize(width: 960, height: 680)),
    ("main-installing-dark", "installing", true, CGSize(width: 960, height: 680)),
    ("main-installing-light", "installing", false, CGSize(width: 960, height: 680)),
    ("main-done-dark", "done", true, CGSize(width: 960, height: 680)),
    ("main-attention-light", "attention", false, CGSize(width: 960, height: 680)),
    ("main-narrow-dark", "installed", true, CGSize(width: 520, height: 760)),
  ]
  for (name, state, dark, size) in main {
    let win = window(MainView(installer: installer(state), settings: settings), size: size, dark: dark)
    await settle(1.5)
    capture(win, to: dir.appendingPathComponent(name + ".png"))
    win.close()
  }
  UserDefaults.standard.set("game", forKey: SettingsView.selectedPaneKey)
  for dark in [true, false] {
    let win = window(SettingsView(settings: settings), size: CGSize(width: 760, height: 520), dark: dark)
    await settle(1.5)
    capture(win, to: dir.appendingPathComponent("settings-game-\(dark ? "dark" : "light").png"))
    win.close()
  }
  for dark in [true, false] {
    let alert = logsAlert(dark: dark)
    await settle(1.0)
    capture(alert.window, to: dir.appendingPathComponent("logs-collected-\(dark ? "dark" : "light").png"), backdrop: true)
    alert.window.close()
  }
}

// Collect Logs…' alert, laid out and shown on the virtual display (not runModal, which centers
// it on the main display)
@MainActor
func logsAlert(dark: Bool) -> NSAlert {
  let alert = LogCollector.alert(zip: NSHomeDirectory() + "/Desktop/SWTOR-on-Mac-logs-2026-10-30-1313.zip", problem: nil)
  alert.window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
  alert.layout()
  let screen = virtualScreen(), win = alert.window
  // in the middle: an alert grows by about 72 pt on each side while it pops in
  win.setFrameOrigin(CGPoint(x: screen.frame.midX - win.frame.width / 2, y: screen.frame.midY - win.frame.height / 2))
  let main = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID).map { CGDisplayIsMain($0) != 0 } ?? false }
  guard screen.frame.insetBy(dx: 200, dy: 200).contains(win.frame), !(main?.frame.intersects(win.frame.insetBy(dx: -200, dy: -200)) ?? true) else {
    fail("the alert \(win.frame) would not be on the virtual display alone")
  }
  win.orderFrontRegardless()
  return alert
}

// Which button Esc presses in the alert's modal session, without LogCollector's monitor
// (AppKit's own behaviour) and with it; a key that presses nothing times out. Return is only
// checked as Close's key equivalent: a button takes it only in the key window, and this
// accessory app is never active, so its alert never is.
@MainActor
func alertKeys() async {
  for monitor in [false, true] {
    let alert = logsAlert(dark: false)
    await settle(0.5)
    let win = alert.window
    let escape = monitor ? LogCollector.closeOnEscape(alert) : nil
    let screen = virtualScreen()
    // run loop timers, not GCD: this runs in a main-queue job, and the modal loop below
    // doesn't drain the main queue meanwhile
    var running = true
    let key = Timer(timeInterval: 0.5, repeats: false) { _ in
      MainActor.assumeIsolated {
        guard screen.frame.insetBy(dx: 100, dy: 100).contains(win.frame) else { fail("the alert moved off the virtual display: \(win.frame)") }
        NSApp.postEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber, context: nil,
          characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!, atStart: false)
      }
    }
    let timeout = Timer(timeInterval: 4, repeats: false) { _ in MainActor.assumeIsolated { if running { NSApp.abortModal() } } }
    for t in [key, timeout] { RunLoop.main.add(t, forMode: .common) }
    let response = NSApp.runModal(for: win)
    running = false
    timeout.invalidate()
    if let escape { NSEvent.removeMonitor(escape) }
    let pressed = response == .alertFirstButtonReturn ? "Close" : response == .alertSecondButtonReturn ? "Show in Finder"
      : response == .abort ? "nothing (timed out)" : "\(response.rawValue)"
    print("Esc\(monitor ? "" : ", AppKit alone"): \(pressed)")
    win.close()
    await settle(0.5)
  }
  let alert = LogCollector.alert(zip: "/Desktop/x.zip", problem: nil)
  print("Return: \(alert.buttons.first { $0.keyEquivalent == "\r" }?.title ?? "no button")")
}

// The installed main window in dark, for comparing the warp's variants.
@MainActor
func still(_ url: URL) async {
  Warp.fixedTime = 6.0
  applyVariant()
  let win = window(MainView(installer: installer("installed"), settings: GameSettings()), size: CGSize(width: 960, height: 680), dark: true)
  await settle(1.5)
  capture(win, to: url)
  win.close()
}

// MARK: - Cost

// CPU time (user + system) and GPU time of this process, in seconds; instructions and cycles
// (which, unlike time, don't depend on whether it ran on efficiency or performance cores)
func usage() -> (cpu: Double, gpu: Double, instructions: Double, cycles: Double) {
  var ri = rusage_info_v4()
  let ok = withUnsafeMutablePointer(to: &ri) {
    $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
  } == 0
  var ru = rusage()
  getrusage(RUSAGE_SELF, &ru)
  let cpu = Double(ru.ru_utime.tv_sec + ru.ru_stime.tv_sec) + Double(ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) / 1e6
  var info = task_power_info_v2()
  var count = mach_msg_type_number_t(MemoryLayout<task_power_info_v2>.size / MemoryLayout<natural_t>.size)
  let kr = withUnsafeMutablePointer(to: &info) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO_V2), $0, &count) }
  }
  // (task_info's GPU figure stays 0 on Apple silicon: the GPU driver's own count, from ioreg)
  let gpu = kr == KERN_SUCCESS ? max(Double(info.gpu_energy.task_gpu_utilisation) / 1e9, gpuTime()) : gpuTime()
  return (cpu, gpu, ok ? Double(ri.ri_instructions) : .nan, ok ? Double(ri.ri_cycles) : .nan)
}

// A process's accumulated GPU time in seconds, as the GPU driver counts it (ioreg's
// AGXDeviceUserClient AppUsage): ours by default. SwiftUI's layers (drawingGroup too) are
// rendered by WindowServer, so the warp's GPU time shows up there, not here.
func gpuTime(_ owner: String = "\"pid \(getpid()), ") -> Double {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
  p.arguments = ["-r", "-c", "AGXDeviceUserClient", "-l"]
  let pipe = Pipe()
  p.standardOutput = pipe
  p.standardError = FileHandle.nullDevice
  guard (try? p.run()) != nil else { return .nan }
  let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  p.waitUntilExit()
  // one entry per user client ("+-o"); its AppUsage comes before its IOUserClientCreator
  var ns = 0.0
  for entry in text.components(separatedBy: "+-o ") where entry.contains(owner) {
    for part in entry.components(separatedBy: "\"accumulatedGPUTime\"=").dropFirst() {
      ns += Double(part.prefix { $0.isNumber }) ?? 0
    }
  }
  return ns / 1e9
}

@MainActor
func measure(_ state: String, seconds: Double) async {
  var win: NSWindow?
  if state != "closed" {
    // idle: not forced, a key, visible window and no input, so idleStop stops it (WARP="idle=5")
    // still: the window as 0.1.4 ships it, in front, no input: it should draw once, then nothing
    Warp.forceRunning = state == "animating" || state == "game" || state == "empty"
    // (the measurements of the animation turn it on; WARP="anim=0" leaves it off)
    Warp.tuning.animated = Warp.forceRunning || state == "idle"
    applyVariant()
    Warp.skipDrawing = state == "empty"
    // MEASURE_STATE: the installer state behind it (fresh: no glass buttons in the window)
    let i = installer(state == "game" ? "game" : ProcessInfo.processInfo.environment["MEASURE_STATE"] ?? "installed")
    // paused: as a window that is not in front (another app's window is key)
    win = window(MainView(installer: i, settings: GameSettings()), size: CGSize(width: 960, height: 680), dark: true,
                 key: state != "paused")
  }
  await settle(4)  // past the jump and the first layout
  let f0 = Warp.frames, u0 = usage(), w0 = gpuTime(", WindowServer\""), t0 = Date.now
  await settle(seconds)
  let u1 = usage(), w1 = gpuTime(", WindowServer\""), dt = Date.now.timeIntervalSince(t0), frames = Warp.frames - f0
  print(String(format: "measure %@: %.1f s, CPU %.3f s (%.2f %% of one core), %.0f M instructions/s, %.0f M cycles/s, GPU %.3f s, warp frames %d (%.1f/s), visible %@",
               state, dt, u1.cpu - u0.cpu, (u1.cpu - u0.cpu) / dt * 100, (u1.instructions - u0.instructions) / dt / 1e6,
               (u1.cycles - u0.cycles) / dt / 1e6, u1.gpu - u0.gpu, frames, Double(frames) / dt,
               win.map { $0.occlusionState.contains(.visible) ? "yes" : "no (occluded)" } ?? "-"))
  print(String(format: "  variant %@: fps %.0f, %@, resolution %.2f, height %.2f", ProcessInfo.processInfo.environment["WARP"] ?? "chosen",
               Warp.tuning.fps, Warp.tuning.metal ? "Metal" : "Core Graphics", Warp.tuning.resolution, Warp.tuning.height))
  print(String(format: "  WindowServer GPU %.3f s (%.2f %% of the GPU's time, everything it composites on all displays)",
               w1 - w0, (w1 - w0) / dt * 100))
  win?.close()
}

// The warp drawn into an off-screen 960 x 680 point canvas at 2x, frame after frame.
@MainActor
func bench(frames: Int) {
  for dark in [true, false] {
    var times: [Double] = []
    for n in 0..<frames {
      let t = 3.0 + Double(n) / 30
      let view = Canvas { g, size in
        WarpField.draw(in: &g, size: size, jump: WindowBackground.jumpPoint(in: size), time: t, dark: dark)
      }
      .frame(width: 960, height: 680)
      .background(Color(hex: dark ? 0x05060A : 0xF3F1EC))
      let renderer = ImageRenderer(content: view)
      // BENCH_SCALE=1: the warp at half the Retina resolution (Warp.Tuning.resolution 0.5)
      renderer.scale = Double(ProcessInfo.processInfo.environment["BENCH_SCALE"] ?? "") ?? 2
      let start = DispatchTime.now().uptimeNanoseconds
      let image = renderer.cgImage
      times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
      // the last frame, to see that it was drawn
      if n == frames - 1, let image, let out = ProcessInfo.processInfo.environment["BENCH_PNG"] {
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
          .write(to: URL(fileURLWithPath: out.replacingOccurrences(of: ".png", with: "-\(dark ? "dark" : "light").png")))
      }
    }
    times.sort()
    print(String(format: "bench %@: %d frames at 1920x1360 px, median %.2f ms, p95 %.2f ms per frame (at 30 fps: %.1f %% of one core)",
                 dark ? "dark" : "light", frames, times[frames / 2], times[frames * 95 / 100], times[frames / 2] * 30 / 10))
  }
}
