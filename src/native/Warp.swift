// The main window's background, as swonmac.com's hero: near-black (paper in light mode), the
// jump point near the top right (a red glow, rings, a crosshair, still stars), and the warp,
// stars streaming out of the jump point towards the viewer. It runs behind the whole window and
// fades out towards the bottom, where the content is.
//
// The warp is a port of the site's src/components/hero/Warp.astro: the same depth model, speed
// curve (near-still, a punch at the jump, then cruise), trail and tints. It is stateless, every
// frame a function of the warp's own clock, and drawn in one Canvas in a few batched strokes.
//
// 0.1.4 shows it still (Tuning.animated off): one frame at cruise, drawn at the display's full
// resolution, again only when the window's size or appearance changes, so the window draws
// nothing while it is open. Animated, a frame costs about the same whatever it draws (the
// window is composited again), which is why it is off until a cheaper way is measured
// (docs/warp-video-loop.md). Animated, measured with scripts/ui-snapshot.sh:
//   - 24 frames a second, at half the display's resolution (Tuning: what a frame costs is
//     mostly the window composited again, so fewer frames is what counts),
//   - paused while the window is not the key window or not visible (occluded, minimized),
//   - stopped while the SWTOR launcher or the game runs (MainView: quiet), so it never takes
//     GPU or CPU time from the game,
//   - gliding to a stop 30 s after the last input, until the next (Tuning.idleStop),
//   - still, one frame after the jump, with Reduce Motion.
// The clock stops while paused, so the stars carry on where they were.

import AppKit
import SwiftUI

struct WindowBackground: View {
  // SWTOR runs: no animation at all
  let quiet: Bool
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      let jump = WindowBackground.jumpPoint(in: size)
      let dark = scheme == .dark
      ZStack {
        Brand.bg
        JumpPoint(jump: jump, dark: dark)
        Warp(jump: jump, dark: dark, quiet: quiet)
      }
    }
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }

  // near the top right, as on the site; never left of the window's middle
  static func jumpPoint(in size: CGSize) -> CGPoint {
    CGPoint(x: max(size.width * 0.6, size.width - 180), y: 96)
  }
}

// The still part: glow, rings, crosshair, stars. Drawn again only when the size changes.
private struct JumpPoint: View {
  let jump: CGPoint
  let dark: Bool

  private static let stars: [(x: Double, y: Double, r: Double, a: Double)] = {
    var rng = SeededRandom(0x5717_0E0F_2026)
    return (0..<110).map { _ in (rng.next(), rng.next(), 0.4 + 0.9 * rng.next() * rng.next(), 0.25 + 0.55 * rng.next()) }
  }()

  var body: some View {
    Canvas { g, size in
      let red = Brand.red(dark: dark), ink = Brand.ink(dark: dark), line = Brand.ring(dark: dark)
      // the glow
      let glow = CGRect(x: jump.x - 420, y: jump.y - 420, width: 840, height: 840)
      g.fill(Path(ellipseIn: glow), with: .radialGradient(
        Gradient(colors: [red.opacity(dark ? 0.13 : 0.08), red.opacity(0)]),
        center: jump, startRadius: 0, endRadius: 420))
      // rings and crosshair
      var rings = Path()
      for r in [44.0, 100, 170, 260, 380, 520] {
        rings.addEllipse(in: CGRect(x: jump.x - r, y: jump.y - r, width: 2 * r, height: 2 * r))
      }
      g.stroke(rings, with: .color(line.opacity(0.8)), lineWidth: 1)
      var cross = Path()
      cross.move(to: CGPoint(x: 0, y: jump.y))
      cross.addLine(to: CGPoint(x: size.width, y: jump.y))
      cross.move(to: CGPoint(x: jump.x, y: 0))
      cross.addLine(to: CGPoint(x: jump.x, y: size.height))
      g.stroke(cross, with: .color(line.opacity(0.5)), lineWidth: 1)
      // stars
      for s in JumpPoint.stars {
        let rect = CGRect(x: s.x * size.width, y: s.y * size.height, width: s.r * 2, height: s.r * 2)
        g.fill(Path(ellipseIn: rect), with: .color(ink.opacity(s.a * (dark ? 1 : 0.6))))
      }
    }
  }
}

struct Warp: View {
  let jump: CGPoint
  let dark: Bool
  let quiet: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.controlActiveState) private var activeState
  @State private var visible = true
  // the warp's clock: time since the window opened, less the time it was paused
  @State private var start = Date.now
  @State private var pausedSince: Date? = nil
  @State private var pausedTotal: TimeInterval = 0
  // idleStop: the last input, and whether the warp has glided to a stop since
  @State private var lastInput = Date.now
  @State private var idle = false
  @State private var inputMonitor: Any?

  #if SWTOR_SNAPSHOT
  // the UI snapshot tool (scripts/ui-snapshot.swift) measures it on a virtual display, where
  // windows count as occluded
  nonisolated(unsafe) static var forceRunning = false
  nonisolated(unsafe) static var frames = 0
  // a still at this time, for screenshots
  nonisolated(unsafe) static var fixedTime: Double?
  // an empty canvas on the same clock: what the frames cost without the stars
  nonisolated(unsafe) static var skipDrawing = false
  // variants to measure against each other
  nonisolated(unsafe) static var tuning = Tuning.chosen
  #else
  static let tuning = Tuning.chosen
  #endif

  // How the warp is rendered. Not for players: the animation is off in 0.1.4.
  // Measured against each other with scripts/ui-snapshot.sh sweep
  // (2026-10-21, the app's own GPU time, a 960 x 680 window): 30 fps at full resolution 2.0 %,
  // 24 fps at half resolution 1.6 %; the warp's resolution or size alone, or Core Graphics
  // instead of Metal, changed little.
  struct Tuning {
    // animated, or the still frame at `stillTime` (cruise, past the jump)
    var animated = false
    var stillTime = 6.0
    var fps = 24.0
    // Metal (drawingGroup) or Core Graphics
    var metal = true
    // the warp's own resolution, as a fraction of the display's (the streaks are soft anyway)
    var resolution = 0.5
    // the part of the window it covers, from the top (the rest fades out to almost nothing)
    var height = 1.0
    // Seconds without input (in the app: mouse, keys, scrolling; or the window coming to the
    // front) after which the warp glides to a stop in `glide` seconds, and stays still until the
    // next input; nil: it runs as long as the window is in front. Each frame costs about the
    // same whatever it draws (findcost: an empty canvas 1.6 % of the 1.7 %), so a window left
    // open costs nothing only if it stops. A video loop instead: docs/warp-video-loop.md.
    var idleStop: TimeInterval? = 30
    var glide: TimeInterval = 2
    static let chosen = Tuning()
  }

  private var running: Bool {
    #if SWTOR_SNAPSHOT
    if Warp.forceRunning { return !quiet }
    #endif
    return !reduceMotion && !quiet && visible && activeState == .key && !idle
  }

  @ViewBuilder var body: some View {
    if Warp.tuning.animated { animatedBody } else { still }
  }

  // One frame, at the display's resolution (Core Graphics, no Metal layer): drawn when the
  // window opens and when its size or appearance changes, never on a clock.
  private var still: some View {
    Canvas { g, size in
      #if SWTOR_SNAPSHOT
      Warp.frames += 1
      #endif
      WarpField.draw(in: &g, size: size, jump: jump, time: Warp.tuning.stillTime, dark: dark)
    }
  }

  private var animatedBody: some View {
    let tune = Warp.tuning
    return GeometryReader { geometry in
      let full = geometry.size
      let s = tune.resolution
      TimelineView(.animation(minimumInterval: 1.0 / tune.fps, paused: !running)) { context in
        let t = frameTime(context.date)
        let canvas = Canvas(rendersAsynchronously: true) { g, _ in
          #if SWTOR_SNAPSHOT
          Warp.frames += 1
          if Warp.skipDrawing { return }
          #endif
          g.scaleBy(x: s, y: s)
          WarpField.draw(in: &g, size: full, jump: jump, time: t, dark: dark)
        }
        .frame(width: full.width * s, height: full.height * tune.height * s)
        Group {
          if tune.metal { canvas.drawingGroup() } else { canvas }
        }
        .scaleEffect(1 / s, anchor: .topLeading)
        .frame(width: full.width, height: full.height, alignment: .topLeading)
      }
    }
    .background(OcclusionReader(visible: $visible))
    // idleStop: any input in the app, or the window coming to the front, starts it again
    .onAppear {
      guard tune.idleStop != nil, inputMonitor == nil else { return }
      inputMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { event in
        input()
        return event
      }
    }
    .onDisappear {
      if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
      inputMonitor = nil
    }
    .onChange(of: activeState) { _, state in if state == .key { input() } }
    // (one wait per input, not a poll: a newer input cancels it)
    .task(id: lastInput) {
      guard let stop = tune.idleStop else { return }
      try? await Task.sleep(for: .seconds(stop + tune.glide))
      if !Task.isCancelled { idle = true }
    }
    .onChange(of: running, initial: true) { _, now in
      if now, let since = pausedSince {
        pausedTotal += Date.now.timeIntervalSince(since)
        pausedSince = nil
      } else if !now, pausedSince == nil {
        pausedSince = .now
      }
    }
  }

  // An input (idleStop). At most once a second, so mouse movement doesn't update the view all
  // the time. Coming back from a stop, the clock leaves out what the glide didn't travel, so
  // the stars carry on where they stopped.
  private func input() {
    let now = Date.now
    if idle {
      pausedTotal += Warp.tuning.glide / 2
      idle = false
      lastInput = now
    } else if now.timeIntervalSince(lastInput) > 1 {
      lastInput = now
    }
  }

  // still with Reduce Motion: a frame just after the jump; idleStop: slowing down evenly to a
  // stop over the glide
  private func frameTime(_ date: Date) -> Double {
    #if SWTOR_SNAPSHOT
    if let fixed = Warp.fixedTime { return fixed }
    #endif
    if reduceMotion { return 2.6 }
    let tune = Warp.tuning
    guard let stop = tune.idleStop else { return time(at: date) }
    let glideStart = lastInput.addingTimeInterval(stop)
    guard date > glideStart else { return time(at: date) }
    let u = min(date.timeIntervalSince(glideStart), tune.glide)
    return time(at: glideStart) + u - u * u / (2 * tune.glide)
  }

  private func time(at date: Date) -> Double {
    // (while paused, no later than the pause)
    (pausedSince.map { min($0, date) } ?? date).timeIntervalSince(start) - pausedTotal
  }
}

// The site's warp, stateless: star i's depth is a function of the distance travelled.
enum WarpField {
  // Tuning, as on the site. Depth z runs from 1 (far plane, at the jump point) to NEAR (at the
  // viewer); a star at depth z is drawn SCALE / z of its offset away from the jump point.
  static let scale = 0.18
  static let near = 0.01
  static let cruise = 0.15  // depth units per second
  static let jumpTime = 1.3  // seconds from near-still to cruise
  static let trail = 0.3  // streak length, in seconds of travel
  static let maxStars = 360
  static let pxPerStar = 4500.0  // area per star (points²; the site has 3600)
  static let margin = 60.0
  static let reach = 700.0  // how far below the jump point stars are spread

  // per star: its phase along the depth, tint (0 ink, 1 red, 2 cyan), opacity, width
  private static let stars: [(phase: Double, tint: Int, opacity: Double, width: Double)] = {
    var rng = SeededRandom(0x5754_4F52_5741)
    return (0..<maxStars).map { _ in
      let t = rng.next()
      return (rng.next(), t < 0.08 ? 1 : t < 0.18 ? 2 : 0, 0.35 + rng.next() * 0.65, rng.next() < 0.15 ? 1.5 : 1)
    }
  }()

  // Speed over time: near-still, a punch through ~2x cruise at the jump, then cruise.
  static func speed(_ t: Double) -> Double {
    if t > 2.4 { return cruise }
    let p = min(t / jumpTime, 1)
    let ease = p * p * (3 - 2 * p)
    let d = (t - 1.0) / 0.32
    return cruise * (0.03 + 0.97 * ease + 1.1 * exp(-d * d))
  }

  // Distance travelled after t seconds: the integral of speed (a table for the jump, then cruise).
  private static let step = 1.0 / 240
  private static let travelTable: [Double] = {
    var table = [0.0], sum = 0.0, t = 0.0
    while t < 2.4 {
      sum += speed(t + step / 2) * step
      t += step
      table.append(sum)
    }
    return table
  }()

  static func travel(_ t: Double) -> Double {
    guard t > 0 else { return 0 }
    let i = t / step
    if Int(i) >= travelTable.count - 1 {
      return travelTable[travelTable.count - 1] + (t - Double(travelTable.count - 1) * step) * cruise
    }
    let lo = Int(i), f = i - Double(lo)
    return travelTable[lo] * (1 - f) + travelTable[lo + 1] * f
  }

  // Calm under the content: full strength around the hero, faint at the bottom (in the stars'
  // opacity: a mask on the layer would cost an off-screen pass every frame).
  static func calm(_ y: Double) -> Double {
    if y < 0.32 { return 1 }
    if y < 0.7 { return 1 - (y - 0.32) / 0.38 * 0.72 }
    return max(0.12, 0.28 - (y - 0.7) / 0.3 * 0.16)
  }

  static func draw(in g: inout GraphicsContext, size: CGSize, jump: CGPoint, time t: Double, dark: Bool) {
    let w = size.width, h = size.height, vx = jump.x, vy = jump.y
    guard w > 0, h > 0 else { return }
    let fieldH = min(h, vy + reach)
    let count = max(60, min(maxStars, Int((w * fieldH / pxPerStar).rounded())))
    let far = max(vx, w - vx, vy, fieldH - vy) + margin
    let minR = far * near * 1.3 / scale
    let span = 1 - near
    let travelled = travel(t)
    let tail = max(speed(t) * trail, 0.004)
    let alphaMul = dark ? 1.0 : 0.7
    let colors = [Brand.ink(dark: dark), Brand.red(dark: dark), Color(hex: dark ? 0x2FD5FF : 0x0A8DB8)]

    // Batched: one path per tint, opacity step (tenths) and width step (half points).
    let alphaSteps = 10, widthSteps = 8
    var paths = [Path](repeating: Path(), count: 3 * (alphaSteps + 1) * widthSteps)
    func add(_ tint: Int, _ alpha: Double, _ width: Double, _ a: CGPoint, _ b: CGPoint) {
      let ai = min(alphaSteps, Int((alpha * Double(alphaSteps)).rounded()))
      guard ai > 0 else { return }
      let wi = min(widthSteps - 1, max(0, Int((width * 2).rounded()) - 1))
      let k = (tint * (alphaSteps + 1) + ai) * widthSteps + wi
      paths[k].move(to: a)
      paths[k].addLine(to: b)
    }

    for i in 0..<count {
      let s = stars[i]
      let u = s.phase * span + travelled
      let cycle = (u / span).rounded(.down)
      let z = 1 - (u - cycle * span)
      // where this star (in this cycle) flies: a point of the screen as seen at depth SCALE
      var rng = SeededRandom(UInt64(i) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(cycle) &* 0xBF58_476D_1CE4_E5B9 &+ 1)
      var x = 0.0, y = 0.0
      repeat {
        x = -vx - margin + rng.next() * (w + 2 * margin)
        y = -vy - margin + rng.next() * (fieldH + 2 * margin)
      } while x * x + y * y < minR * minR
      let k = scale / z
      let hx = vx + x * k, hy = vy + y * k
      if hx < -margin || hx > w + margin || hy < -margin || hy > h + margin { continue }
      let f = 1 - z  // nearness, 0 far .. 1 here
      let a = s.opacity * alphaMul * min(1, f * 1.6) * calm(hy / h)
      if a < 0.02 { continue }
      let tz = z + tail, kt = scale / tz
      let tx = vx + x * kt, ty = vy + y * kt
      let mid = CGPoint(x: (tx + hx) / 2, y: (ty + hy) / 2)
      let width = s.width * (0.45 + 1.9 * f * f * f)
      // faint tail half, bright head half: a cheap fade without per-star gradients
      add(s.tint, a * 0.3, width, CGPoint(x: tx, y: ty), mid)
      add(s.tint, a, width, mid, CGPoint(x: hx, y: hy))
    }

    for (k, path) in paths.enumerated() where !path.isEmpty {
      let wi = k % widthSteps, ai = (k / widthSteps) % (alphaSteps + 1), tint = k / (widthSteps * (alphaSteps + 1))
      g.stroke(path, with: .color(colors[tint].opacity(Double(ai) / Double(alphaSteps))),
               style: StrokeStyle(lineWidth: Double(wi + 1) / 2, lineCap: .butt))
    }
  }
}

// SplitMix64: the same stars on every frame and every Mac.
struct SeededRandom {
  private var state: UInt64
  init(_ seed: UInt64) { state = seed }
  mutating func next() -> Double {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z ^= z >> 31
    return Double(z >> 11) / Double(1 << 53)
  }
}

// Whether the window is visible at all (not occluded by other windows, not minimized, not on
// another Space): the warp pauses otherwise.
private struct OcclusionReader: NSViewRepresentable {
  @Binding var visible: Bool

  func makeNSView(context: Context) -> NSView {
    let view = ObservingView()
    view.onChange = { visible in DispatchQueue.main.async { if self.visible != visible { self.visible = visible } } }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}

  final class ObservingView: NSView {
    var onChange: ((Bool) -> Void)?
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let observer { NotificationCenter.default.removeObserver(observer) }
      observer = nil
      guard let window else { return }
      observer = NotificationCenter.default.addObserver(
        forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, let window = self.window else { return }
          self.onChange?(window.occlusionState.contains(.visible))
        }
      }
      onChange?(window.occlusionState.contains(.visible))
    }
  }
}
