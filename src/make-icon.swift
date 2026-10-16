// Renders the app icon: a blue and a red blade crossed over a starfield on a deep-space squircle,
// with an "SWTOR" wordmark set in the system font (original artwork: no Star Wars or SWTOR logo).
// Like SWGL on Mac it is a plain .icns (CFBundleIconFile), drawn on Apple's macOS icon grid.
//
//   swift src/make-icon.swift <out.iconset>                          the iconset for iconutil
//   swift src/make-icon.swift <out.iconset> <preview.png> [other.icns]  also a preview sheet
//                                             (light and dark, every size, next to other.icns)
//
// Small sizes get their own layout: no "ON MAC" below 256 px, no wordmark at 32 px and less.
import AppKit
import CoreImage
import CoreText

let args = CommandLine.arguments
guard (2...4).contains(args.count) else {
  FileHandle.standardError.write("usage: make-icon.swift <out.iconset> [<preview.png> [<other.icns>]]\n".data(using: .utf8)!)
  exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let ci = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB])

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}
func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
  CGGradient(colorsSpace: sRGB, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}
func bitmap(_ px: Int) -> CGContext {
  CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// Apple's continuous-corner rounded rect (the squircle of the icon grid), corner radius r.
func squircle(_ rc: CGRect, _ r: CGFloat) -> CGPath {
  let p = CGMutablePath()
  // each corner: c = corner point, a = back along the incoming edge, b = along the outgoing edge
  let corners: [(CGPoint, CGVector, CGVector)] = [
    (CGPoint(x: rc.maxX, y: rc.maxY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)),
    (CGPoint(x: rc.maxX, y: rc.minY), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0)),
    (CGPoint(x: rc.minX, y: rc.minY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)),
    (CGPoint(x: rc.minX, y: rc.maxY), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0)),
  ]
  for (i, (c, a, b)) in corners.enumerated() {
    func pt(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
      CGPoint(x: c.x + (a.dx * u + b.dx * v) * r, y: c.y + (a.dy * u + b.dy * v) * r)
    }
    if i == 0 { p.move(to: pt(1.52866483, 0)) } else { p.addLine(to: pt(1.52866483, 0)) }
    p.addCurve(to: pt(0.63149399, 0.07491100), control1: pt(1.08849323, 0), control2: pt(0.86840689, 0))
    p.addCurve(to: pt(0.07491100, 0.63149399), control1: pt(0.37282392, 0.16905899), control2: pt(0.16905899, 0.37282392))
    p.addCurve(to: pt(0, 1.52866483), control1: pt(0, 0.86840689), control2: pt(0, 1.08849323))
  }
  p.closeSubpath()
  return p
}

// Outline of a string set in the system font, glyph by glyph.
func textPath(_ s: String, size: CGFloat, weight: NSFont.Weight, width: NSFont.Width, kern: CGFloat) -> CGPath {
  let font = NSFont.systemFont(ofSize: size, weight: weight, width: width)
  let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .kern: kern]))
  let path = CGMutablePath()
  for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
    let n = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
    CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
    for i in 0..<n {
      if let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
        path.addPath(g, transform: CGAffineTransform(translationX: pos[i].x, y: pos[i].y))
      }
    }
  }
  return path
}
// The path scaled to `w` units wide, centred on (cx, cy) by its outline (not its advance).
func fitted(_ path: CGPath, width w: CGFloat, cx: CGFloat, cy: CGFloat) -> CGPath {
  let bb = path.boundingBoxOfPath, k = w / bb.width
  var t = CGAffineTransform(translationX: cx - bb.midX * k, y: cy - bb.midY * k).scaledBy(x: k, y: k)
  return path.copy(using: &t)!
}

// Fixed star positions, so every size (and every build) shows the same sky.
var seed: UInt64 = 0x5357_544F_5221
func rnd() -> CGFloat {
  seed = seed &* 6364136223846793005 &+ 1442695040888963407
  return CGFloat(seed >> 33) / CGFloat(1 << 31)
}
let stars = (0..<85).map { _ in (x: 100 + rnd() * 824, y: 100 + rnd() * 824, r: 0.9 + rnd() * rnd() * 2.6, a: 0.2 + rnd() * 0.6) }

struct Saber {
  var pommel: CGPoint
  var angle: CGFloat  // radians, from the pommel towards the tip
  var bloom: CGColor  // outer glow
  var edge: CGColor   // the blade's coloured rim
  var hilt: CGFloat = 196
  var blade: CGFloat = 520
  func at(_ d: CGFloat) -> CGPoint { CGPoint(x: pommel.x + cos(angle) * d, y: pommel.y + sin(angle) * d) }
}

// Everything is drawn in 1024-unit icon-grid coordinates (y up); `k` maps them to pixels.
func render(_ px: Int) -> CGImage {
  let k = CGFloat(px) / 1024
  let wordmark = px >= 64, subline = px >= 256, tiny = px <= 32
  let ctx = bitmap(px)
  ctx.scaleBy(x: k, y: k)
  ctx.interpolationQuality = .high

  // An offscreen layer in the same coordinates, blurred by `sigma` units, drawn back additively.
  func light(sigma: CGFloat, alpha: CGFloat = 1, _ draw: (CGContext) -> Void) {
    let l = bitmap(px)
    l.scaleBy(x: k, y: k)
    draw(l)
    var img = CIImage(cgImage: l.makeImage()!)
    let extent = img.extent
    if sigma * k > 0.3 {
      img = img.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma * k)).cropped(to: extent)
    }
    if alpha < 1 {
      img = img.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: alpha, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: alpha, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: alpha, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
    }
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    ctx.draw(ci.createCGImage(img, from: extent)!, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    ctx.restoreGState()
  }

  // Tile: Apple's grid, an 824-unit body with continuous corners and a soft drop shadow.
  let body = CGRect(x: 100, y: 100, width: 824, height: 824)
  let tile = squircle(body, 185.4)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 22 * k, color: rgb(0, 0, 0, 0.45))
  ctx.addPath(tile)
  ctx.setFillColor(rgb(0.02, 0.03, 0.08))
  ctx.fillPath()
  ctx.restoreGState()
  ctx.addPath(tile)
  ctx.clip()
  // deep space: navy at the top falling to black, a faint teal haze low left (as in the window's header)
  ctx.drawRadialGradient(gradient([(0, rgb(0.10, 0.15, 0.32)), (0.55, rgb(0.03, 0.06, 0.15)), (1, rgb(0.004, 0.008, 0.025))]),
                         startCenter: CGPoint(x: 512, y: 860), startRadius: 0,
                         endCenter: CGPoint(x: 512, y: 860), endRadius: 900, options: .drawsAfterEndLocation)
  ctx.drawRadialGradient(gradient([(0, rgb(0.05, 0.24, 0.32, 0.35)), (1, rgb(0.05, 0.24, 0.32, 0))]),
                         startCenter: CGPoint(x: 230, y: 200), startRadius: 0,
                         endCenter: CGPoint(x: 230, y: 200), endRadius: 520, options: [])
  if !tiny {
    for st in stars {
      ctx.setFillColor(rgb(0.85, 0.92, 1, st.a))
      ctx.fillEllipse(in: CGRect(x: st.x - st.r, y: st.y - st.r, width: 2 * st.r, height: 2 * st.r))
    }
  }

  // The sabers: blue (hilt lower left) and red (hilt lower right), crossing above the wordmark.
  let blue = (bloom: rgb(0.10, 0.50, 1.0), edge: rgb(0.247, 0.663, 1.0))
  let red = (bloom: rgb(1.0, 0.10, 0.06), edge: rgb(1.0, 0.231, 0.188))
  var sabers: [Saber]
  if tiny {
    let a = CGFloat.pi / 4
    sabers = [Saber(pommel: CGPoint(x: 212, y: 212), angle: a, bloom: blue.bloom, edge: blue.edge, hilt: 190, blade: 480),
              Saber(pommel: CGPoint(x: 812, y: 212), angle: .pi - a, bloom: red.bloom, edge: red.edge, hilt: 190, blade: 480)]
  } else {
    let a = 0.84 as CGFloat  // ~48 degrees
    sabers = [Saber(pommel: CGPoint(x: 186, y: 166), angle: a, bloom: blue.bloom, edge: blue.edge, blade: 560),
              Saber(pommel: CGPoint(x: 838, y: 166), angle: .pi - a, bloom: red.bloom, edge: red.edge, blade: 560)]
  }
  let bw: CGFloat = tiny ? 1.9 : (px <= 64 ? 1.3 : 1)  // thicker blades when small

  for s in sabers { drawHilt(ctx, s, simple: px <= 64, scale: tiny ? 2.4 : (px <= 64 ? 1.4 : 1), k: k) }

  func bladeLine(_ c: CGContext, _ s: Saber, width: CGFloat, color: CGColor) {
    let from = s.at(s.hilt + width / 2 - 6), to = s.at(s.hilt + s.blade)
    c.setLineCap(.round)
    c.setLineWidth(width)
    c.setStrokeColor(color)
    c.move(to: from)
    c.addLine(to: to)
    c.strokePath()
  }
  // bloom: wide and faint, then tighter and brighter
  light(sigma: 80, alpha: 0.8) { c in for s in sabers { bladeLine(c, s, width: 70 * bw, color: s.bloom) } }
  light(sigma: 26, alpha: 1) { c in for s in sabers { bladeLine(c, s, width: 50 * bw, color: s.bloom) } }
  light(sigma: 10, alpha: 0.9) { c in for s in sabers { bladeLine(c, s, width: 44 * bw, color: s.bloom) } }
  // the blade: coloured rim, a paler inner band, a white-hot core
  light(sigma: 4) { c in for s in sabers { bladeLine(c, s, width: 40 * bw, color: s.edge) } }
  light(sigma: 2.5, alpha: 0.8) { c in
    for s in sabers { bladeLine(c, s, width: 26 * bw, color: s.edge.blended(with: rgb(1, 1, 1), 0.35)) }
  }
  ctx.saveGState()
  for s in sabers { bladeLine(ctx, s, width: 14 * bw, color: rgb(1, 1, 1)) }
  ctx.restoreGState()
  // a white flare where the blades meet
  if let x = crossing(sabers[0], sabers[1]) {
    let r: CGFloat = tiny ? 70 : 95
    light(sigma: 0, alpha: 1) { c in
      c.drawRadialGradient(gradient([(0, rgb(1, 1, 1, 0.85)), (0.25, rgb(0.85, 0.75, 1, 0.35)), (1, rgb(0.6, 0.4, 1, 0))]),
                           startCenter: x, startRadius: 0, endCenter: x, endRadius: r, options: [])
    }
  }

  if wordmark {
    let markWidth: CGFloat = subline ? 664 : 740
    let cy: CGFloat = subline ? 404 : 330
    let mark = fitted(textPath("SWTOR", size: 200, weight: .black, width: .expanded, kern: -2),
                      width: markWidth, cx: 512, cy: cy)
    let bb = mark.boundingBoxOfPath
    // separation from the blades, then a cool glow, then brushed silver
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * k), blur: 26 * k, color: rgb(0, 0, 0, 0.95))
    ctx.addPath(mark)
    ctx.setFillColor(rgb(0.02, 0.03, 0.07))
    ctx.fillPath()
    ctx.restoreGState()
    light(sigma: 16, alpha: 0.45) { c in
      c.addPath(mark)
      c.setFillColor(rgb(0.70, 0.82, 1))
      c.fillPath()
    }
    ctx.saveGState()
    ctx.addPath(mark)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0.70, 0.73, 0.79)), (0.44, rgb(0.80, 0.83, 0.88)),
                                     (0.47, rgb(0.93, 0.95, 0.98)), (1, rgb(1, 1, 1))]),
                           start: CGPoint(x: 0, y: bb.minY), end: CGPoint(x: 0, y: bb.maxY), options: [])
    ctx.restoreGState()
    // a hairline on the top edges, catching the light
    ctx.saveGState()
    ctx.addPath(mark)
    ctx.setLineWidth(2.5)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.translateBy(x: 0, y: -2)
    ctx.addPath(mark)
    ctx.setFillColor(rgb(0.25, 0.30, 0.40, 0.6))
    ctx.fillPath()
    ctx.restoreGState()

    if subline {
      let sub = fitted(textPath("ON MAC", size: 100, weight: .bold, width: .expanded, kern: 34),
                       width: 250, cx: 512, cy: bb.minY - 66)
      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: 0, height: -3 * k), blur: 12 * k, color: rgb(0, 0, 0, 0.9))
      ctx.addPath(sub)
      ctx.setFillColor(rgb(0.86, 0.89, 0.94))
      ctx.fillPath()
      ctx.restoreGState()
    }
  }

  // depth: a fine light rim along the top of the tile, fading out halfway down
  ctx.saveGState()
  ctx.addPath(squircle(body.insetBy(dx: 1.5, dy: 1.5), 184))
  ctx.setLineWidth(3)
  ctx.replacePathWithStrokedPath()
  ctx.clip()
  ctx.drawLinearGradient(gradient([(0, rgb(1, 1, 1, 0)), (0.55, rgb(1, 1, 1, 0.04)), (1, rgb(1, 1, 1, 0.22))]),
                         start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
  ctx.restoreGState()
  return ctx.makeImage()!
}

extension CGColor {
  func blended(with o: CGColor, _ t: CGFloat) -> CGColor {
    let a = components!, b = o.components!
    return rgb(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, 1)
  }
}

func crossing(_ a: Saber, _ b: Saber) -> CGPoint? {
  let p = a.pommel, r = CGVector(dx: cos(a.angle), dy: sin(a.angle))
  let q = b.pommel, s = CGVector(dx: cos(b.angle), dy: sin(b.angle))
  let d = r.dx * s.dy - r.dy * s.dx
  guard abs(d) > 1e-6 else { return nil }
  let t = ((q.x - p.x) * s.dy - (q.y - p.y) * s.dx) / d
  return a.at(t)
}

// A machined hilt along +x from the pommel: cap, ribbed grip, body with an activator, flared emitter.
func drawHilt(_ ctx: CGContext, _ s: Saber, simple: Bool, scale: CGFloat, k: CGFloat) {
  ctx.saveGState()
  ctx.translateBy(x: s.pommel.x, y: s.pommel.y)
  ctx.rotate(by: s.angle)
  let L = s.hilt
  func metal(_ rect: CGRect, dark: Bool = false, radius: CGFloat = 3) {
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    let stops: [(CGFloat, CGColor)] = dark
      ? [(0, rgb(0.06, 0.06, 0.07)), (0.62, rgb(0.30, 0.31, 0.33)), (0.72, rgb(0.20, 0.21, 0.22)), (1, rgb(0.05, 0.05, 0.06))]
      : [(0, rgb(0.28, 0.29, 0.31)), (0.55, rgb(0.82, 0.84, 0.87)), (0.68, rgb(0.98, 0.98, 0.99)), (0.80, rgb(0.66, 0.68, 0.71)), (1, rgb(0.22, 0.23, 0.25))]
    ctx.drawLinearGradient(gradient(stops), start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
    ctx.restoreGState()
  }
  // shadow under the hilt for depth
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -6 * k), blur: 14 * k, color: rgb(0, 0, 0, 0.7))
  ctx.setFillColor(rgb(0.1, 0.1, 0.12))
  ctx.fill(CGRect(x: 2, y: -21 * scale, width: L - 4, height: 42 * scale))
  ctx.restoreGState()
  if simple {
    metal(CGRect(x: 0, y: -22 * scale, width: L * 0.16, height: 44 * scale), radius: 6)
    metal(CGRect(x: L * 0.16, y: -19 * scale, width: L * 0.46, height: 38 * scale), dark: true, radius: 0)
    metal(CGRect(x: L * 0.62, y: -22 * scale, width: L * 0.38, height: 44 * scale), radius: 4)
  } else {
    metal(CGRect(x: 0, y: -23, width: 24, height: 46), radius: 8)                 // pommel
    metal(CGRect(x: 22, y: -19, width: 98, height: 38), dark: true, radius: 0)   // grip
    for i in 0..<6 { metal(CGRect(x: 30 + CGFloat(i) * 15, y: -20.5, width: 6, height: 41), radius: 2) }
    metal(CGRect(x: 118, y: -21, width: 50, height: 42), radius: 2)              // body
    ctx.setFillColor(rgb(0.08, 0.08, 0.09))                                      // activator
    ctx.fill(CGRect(x: 132, y: 13, width: 18, height: 8))
    ctx.setFillColor(s.edge)
    ctx.fill(CGRect(x: 136, y: 15, width: 10, height: 4))
    // emitter: flares out towards the blade
    ctx.saveGState()
    let shroud = CGMutablePath()
    shroud.move(to: CGPoint(x: 166, y: -22))
    shroud.addLine(to: CGPoint(x: L, y: -27))
    shroud.addLine(to: CGPoint(x: L, y: 27))
    shroud.addLine(to: CGPoint(x: 166, y: 22))
    shroud.closeSubpath()
    ctx.addPath(shroud)
    ctx.clip()
    metal(CGRect(x: 166, y: -27, width: L - 166, height: 54), radius: 0)
    ctx.restoreGState()
    ctx.setFillColor(rgb(0.05, 0.05, 0.06, 0.8))                                 // seam
    ctx.fill(CGRect(x: 166, y: -22, width: 3, height: 44))
  }
  ctx.restoreGState()
}

func png(_ img: CGImage) -> Data { NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])! }

var rendered: [Int: CGImage] = [:]
for px in [16, 32, 64, 128, 256, 512, 1024] { rendered[px] = render(px) }
for base in [16, 32, 128, 256, 512] {
  try png(rendered[base]!).write(to: outDir.appendingPathComponent("icon_\(base)x\(base).png"))
  try png(rendered[base * 2]!).write(to: outDir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

// Preview sheet: every size at 1:1 (1024 shown at half size), on light and on dark, optionally
// beside another app's .icns for comparison.
if args.count >= 3 {
  let sizes = [1024, 256, 128, 64, 32, 16]
  let shown = { (px: Int) -> CGFloat in px == 1024 ? 512 : CGFloat(px) }
  var groups: [(String, [Int: CGImage])] = [("SWTOR on Mac", rendered)]
  if args.count == 4, let other = NSImage(contentsOfFile: args[3]) {
    var imgs: [Int: CGImage] = [:]
    for px in sizes {
      var rect = CGRect(x: 0, y: 0, width: px, height: px)
      let best = other.bestRepresentation(for: rect, context: nil, hints: nil)
      let c = bitmap(px)
      c.interpolationQuality = .high
      if let rep = best as? NSBitmapImageRep, rep.pixelsWide == px, let cg = rep.cgImage {
        c.draw(cg, in: rect)
      } else if let cg = other.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
        c.draw(cg, in: CGRect(x: 0, y: 0, width: px, height: px))
      }
      imgs[px] = c.makeImage()
    }
    let app = URL(fileURLWithPath: args[3]).pathComponents.last { $0.hasSuffix(".app") }
    groups.append((app.map { String($0.dropLast(4)) } ?? URL(fileURLWithPath: args[3]).lastPathComponent, imgs))
  }
  let gap: CGFloat = 36, margin: CGFloat = 48, labelH: CGFloat = 70, rowH: CGFloat = 512 + labelH + 40
  let groupW = sizes.map(shown).reduce(0, +) + gap * CGFloat(sizes.count - 1)
  let W = margin * 2 + groupW * CGFloat(groups.count) + 90 * CGFloat(groups.count - 1)
  let H = margin * 2 + rowH * 2
  let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
  let c = NSGraphicsContext.current!.cgContext
  c.interpolationQuality = .high
  for (row, dark) in [false, true].enumerated() {
    let y0 = H - margin - rowH * CGFloat(row + 1)
    c.setFillColor(dark ? rgb(0.12, 0.12, 0.13) : rgb(0.93, 0.93, 0.94))
    c.fill(CGRect(x: 0, y: row == 0 ? H / 2 : 0, width: W, height: H / 2))
    let ink = dark ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.25, alpha: 1)
    var x = margin
    for (name, imgs) in groups {
      (name as NSString).draw(at: NSPoint(x: x, y: y0 + rowH - 44),
                              withAttributes: [.font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: ink])
      for px in sizes {
        let d = shown(px)
        c.draw(imgs[px]!, in: CGRect(x: x, y: y0 + 40 + (512 - d) / 2, width: d, height: d))
        ("\(px)" as NSString).draw(at: NSPoint(x: x, y: y0 + 4),
                                   withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .regular),
                                                    .foregroundColor: ink.withAlphaComponent(0.7)])
        x += d + gap
      }
      x += 90 - gap
    }
  }
  NSGraphicsContext.restoreGraphicsState()
  try sheet.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
}
