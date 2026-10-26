// The app icon: an Icon Composer document (src/AppIcon.icon) that macOS 26 and later draws as a
// Liquid Glass icon (glass rim, specular highlights, shadow; Default, Dark, Tinted and Clear).
// The design: a blue and a red blade crossed at the centre, the window's "SWTOR / ON MAC" wordmark
// across them (Unbounded, as Brand.swift's Wordmark), over the main window's jump point
// (Warp.swift): a red glow, sonar rings, a crosshair and warp streaks. Original artwork: no Star
// Wars or SWTOR logo. The layers carry no tile, rim or
// shadow: the system draws those, and icon.json holds the background gradient and each group's
// glass settings (fine-tune them in Xcode's Icon Composer).
//
//   swift src/make-icon.swift layers src/AppIcon.icon
//       writes the layers into Assets/ (icon.json is left as it is)
//   swift src/make-icon.swift preview src/AppIcon.icon <sheet.png> [other.icns]
//       renders a review sheet with Icon Composer's ictool: the six appearances, and every size on
//       light and on dark, optionally next to another app's .icns
//
// build.sh compiles the document with actool into Assets.car and a fallback AppIcon.icns.
import AppKit
import CoreImage
import CoreText

let args = CommandLine.arguments
guard args.count >= 3, (args[1] == "layers" && args.count == 3) || (args[1] == "preview" && (4...5).contains(args.count)) else {
  FileHandle.standardError.write("usage: make-icon.swift layers <AppIcon.icon> | preview <AppIcon.icon> <sheet.png> [other.icns]\n".data(using: .utf8)!)
  exit(1)
}
let doc = URL(fileURLWithPath: args[2])

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let ci = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB])
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}
func hex(_ c: CGColor) -> String {
  let v = c.components!.prefix(3).map { Int(($0 * 255).rounded()) }
  return String(format: "#%02X%02X%02X", v[0], v[1], v[2])
}
func f(_ x: CGFloat) -> String { String(format: "%.2f", x) }

// Canvas: 1024 units, the whole icon shape, y up (flipped once for SVG).
struct Saber {
  var pommel: CGPoint
  var angle: CGFloat
  var bloom: CGColor
  var edge: CGColor
  var hilt: CGFloat
  var blade: CGFloat
  func at(_ d: CGFloat) -> CGPoint { CGPoint(x: pommel.x + cos(angle) * d, y: pommel.y + sin(angle) * d) }
}
let k: CGFloat = 1.35  // scale of the blades' and hilts' widths and lengths (the old 824-unit grid)
let blue = (bloom: rgb(0.10, 0.50, 1.0), edge: rgb(0.247, 0.663, 1.0))
let red = (bloom: rgb(1.0, 0.10, 0.06), edge: rgb(1.0, 0.231, 0.188))
// The blades cross at the centre at 45 degrees, blue from the lower left, red from the lower
// right, the hilts kept clear of the shape's corners.
let reach: CGFloat = 470  // pommel to centre
let sabers = [
  Saber(pommel: CGPoint(x: 512 - reach * cos(.pi / 4), y: 512 - reach * sin(.pi / 4)), angle: .pi / 4,
        bloom: blue.bloom, edge: blue.edge, hilt: 196 * k, blade: 480 * k),
  Saber(pommel: CGPoint(x: 512 + reach * cos(.pi / 4), y: 512 - reach * sin(.pi / 4)), angle: 3 * .pi / 4,
        bloom: red.bloom, edge: red.edge, hilt: 196 * k, blade: 480 * k),
]
func crossing() -> CGPoint {
  let p = sabers[0].pommel, r = CGVector(dx: cos(sabers[0].angle), dy: sin(sabers[0].angle))
  let q = sabers[1].pommel, s = CGVector(dx: cos(sabers[1].angle), dy: sin(sabers[1].angle))
  let d = r.dx * s.dy - r.dy * s.dx
  return sabers[0].at(((q.x - p.x) * s.dy - (q.y - p.y) * s.dx) / d)
}

func svg(_ body: String, defs: String = "") -> String {
  """
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\
  <defs>\(defs)</defs><g transform="matrix(1 0 0 -1 0 1024)">\(body)</g></svg>

  """
}

// --- space: the app window's jump point (Warp.swift) as the background: red glow, sonar rings, crosshair,
// warp streaks (ink, red, cyan) streaming out of the centre, still stars
let spaceSVG: String = {
  var b = "<circle cx=\"512\" cy=\"512\" r=\"470\" fill=\"url(#jump)\"/>"
  for r in [62.0, 140, 238, 360, 500, 660] as [CGFloat] {
    b += "<circle cx=\"512\" cy=\"512\" r=\"\(f(r))\" fill=\"none\" stroke=\"#2C3345\" stroke-opacity=\"0.85\" stroke-width=\"3\"/>"
  }
  b += "<path d=\"M0 512 L1024 512 M512 0 L512 1024\" stroke=\"#2C3345\" stroke-opacity=\"0.6\" stroke-width=\"3\"/>"
  var sd: UInt64 = 0x5717_0E0F_2026
  func rn() -> CGFloat { sd = sd &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(sd >> 33) / CGFloat(1 << 31) }
  let tints = ["#EEF1F6", "#FF3D2E", "#2FD5FF"]
  for _ in 0..<64 {
    let ang = rn() * 2 * .pi, r0 = 110 + rn() * 420, len = (18 + rn() * 70) * (0.4 + r0 / 530)
    let t = rn() < 0.7 ? 0 : (rn() < 0.5 ? 1 : 2), op = 0.25 + rn() * 0.55, w = 2 + rn() * 2.5
    let a = CGPoint(x: 512 + cos(ang) * r0, y: 512 + sin(ang) * r0)
    let m = CGPoint(x: 512 + cos(ang) * (r0 + len / 2), y: 512 + sin(ang) * (r0 + len / 2))
    let e = CGPoint(x: 512 + cos(ang) * (r0 + len), y: 512 + sin(ang) * (r0 + len))
    b += "<path d=\"M\(f(a.x)) \(f(a.y)) L\(f(m.x)) \(f(m.y))\" stroke=\"\(tints[t])\" stroke-opacity=\"\(f(op * 0.3))\" stroke-width=\"\(f(w))\" stroke-linecap=\"round\"/>"
    b += "<path d=\"M\(f(m.x)) \(f(m.y)) L\(f(e.x)) \(f(e.y))\" stroke=\"\(tints[t])\" stroke-opacity=\"\(f(op))\" stroke-width=\"\(f(w))\" stroke-linecap=\"round\"/>"
  }
  for _ in 0..<70 {
    let x = 40 + rn() * 944, y = 40 + rn() * 944, r = 1.2 + rn() * rn() * 3
    b += "<circle cx=\"\(f(x))\" cy=\"\(f(y))\" r=\"\(f(r))\" fill=\"#EEF1F6\" fill-opacity=\"\(f(0.25 + rn() * 0.55))\"/>"
  }
  let defs = "<radialGradient id=\"jump\" gradientUnits=\"userSpaceOnUse\" cx=\"512\" cy=\"512\" r=\"470\">" +
    "<stop offset=\"0\" stop-color=\"#FF3D2E\" stop-opacity=\"0.22\"/><stop offset=\"1\" stop-color=\"#FF3D2E\" stop-opacity=\"0\"/></radialGradient>"
  return svg(b, defs: defs)
}()

// --- blades: coloured rim, a paler band, a white-hot core
func bladeLine(_ s: Saber, width: CGFloat, color: String, opacity: CGFloat = 1) -> String {
  let from = s.at(s.hilt + width / 2 - 6 * k), to = s.at(s.hilt + s.blade)
  return "<line x1=\"\(f(from.x))\" y1=\"\(f(from.y))\" x2=\"\(f(to.x))\" y2=\"\(f(to.y))\" stroke=\"\(color)\" " +
    "stroke-width=\"\(f(width))\" stroke-linecap=\"round\" stroke-opacity=\"\(f(opacity))\"/>"
}
func pale(_ c: CGColor) -> String {
  let v = c.components!
  return hex(rgb(v[0] + (1 - v[0]) * 0.4, v[1] + (1 - v[1]) * 0.4, v[2] + (1 - v[2]) * 0.4))
}
let bladesSVG = svg(sabers.map { s in bladeLine(s, width: 17 * k, color: "#FFFFFF") }.joined())

// --- hilts: cap, ribbed grip, body with an activator, flared emitter (gradients across the hilt)
let metalLight: [(CGFloat, CGColor)] = [(0, rgb(0.28, 0.29, 0.31)), (0.55, rgb(0.82, 0.84, 0.87)), (0.68, rgb(0.98, 0.98, 0.99)), (0.80, rgb(0.66, 0.68, 0.71)), (1, rgb(0.22, 0.23, 0.25))]
let metalDark: [(CGFloat, CGColor)] = [(0, rgb(0.06, 0.06, 0.07)), (0.62, rgb(0.30, 0.31, 0.33)), (0.72, rgb(0.20, 0.21, 0.22)), (1, rgb(0.05, 0.05, 0.06))]
func grad(_ id: String, _ stops: [(CGFloat, CGColor)]) -> String {
  "<linearGradient id=\"\(id)\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">" +
    stops.map { "<stop offset=\"\(f($0.0))\" stop-color=\"\(hex($0.1))\"/>" }.joined() + "</linearGradient>"
}
let hiltDefs = grad("ml", metalLight) + grad("md", metalDark)
func hilt(_ s: Saber) -> String {
  func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ g: String, _ rad: CGFloat = 3) -> String {
    "<rect x=\"\(f(x))\" y=\"\(f(y))\" width=\"\(f(w))\" height=\"\(f(h))\" rx=\"\(f(rad))\" fill=\"url(#\(g))\"/>"
  }
  var b = "<g transform=\"translate(\(f(s.pommel.x)) \(f(s.pommel.y))) rotate(\(f(s.angle * 180 / .pi))) scale(\(f(k)))\">"
  b += r(0, -23, 24, 46, "ml", 8) + r(22, -19, 98, 38, "md", 0)
  for i in 0..<6 { b += r(30 + CGFloat(i) * 15, -20.5, 6, 41, "ml", 2) }
  b += r(118, -21, 50, 42, "ml", 2)
  b += "<rect x=\"132\" y=\"13\" width=\"18\" height=\"8\" fill=\"#141417\"/>"
  b += "<rect x=\"136\" y=\"15\" width=\"10\" height=\"4\" fill=\"\(hex(s.edge))\"/>"
  b += "<path d=\"M166 -22 L196 -27 L196 27 L166 22 Z\" fill=\"url(#ml)\"/>"
  b += "<rect x=\"166\" y=\"-22\" width=\"3\" height=\"44\" fill=\"#0D0D0F\" fill-opacity=\"0.8\"/>"
  return b + "</g>"
}
let hiltsSVG = svg(sabers.map(hilt).joined(), defs: hiltDefs)


// --- wordmark: "SWTOR" heavy, a red rule and "ON MAC" in Unbounded, as the window's wordmark
// (Brand.swift), a little heavier and larger below so it reads at icon size
func unboundedPath(_ s: String, weight: CGFloat, size: CGFloat = 200, kern: CGFloat = -8) -> CGPath {
  // the app's own copy of Unbounded (src/fonts, SIL OFL 1.1); the SVG carries the outlines
  let url = doc.deletingLastPathComponent().appendingPathComponent("fonts/Unbounded-Variable.ttf") as CFURL
  let desc = (CTFontManagerCreateFontDescriptorsFromURL(url) as! [CTFontDescriptor])[0]
  let wght = 0x77676874 as NSNumber
  let d2 = CTFontDescriptorCreateCopyWithAttributes(desc, [kCTFontVariationAttribute: [wght: weight]] as CFDictionary)
  let font = CTFontCreateWithFontDescriptor(d2, size, nil)
  let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .kern: kern]))
  let path = CGMutablePath()
  for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let n = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
    CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
    let rf = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
    for i in 0..<n { if let g = CTFontCreatePathForGlyph(rf, glyphs[i], nil) { path.addPath(g, transform: CGAffineTransform(translationX: pos[i].x, y: pos[i].y)) } }
  }
  return path
}
func pathD(_ p: CGPath) -> String {
  var out = ""
  p.applyWithBlock { e in
    let pt = e.pointee.points
    switch e.pointee.type {
    case .moveToPoint: out += "M\(f(pt[0].x)) \(f(pt[0].y))"
    case .addLineToPoint: out += "L\(f(pt[0].x)) \(f(pt[0].y))"
    case .addQuadCurveToPoint: out += "Q\(f(pt[0].x)) \(f(pt[0].y)) \(f(pt[1].x)) \(f(pt[1].y))"
    case .addCurveToPoint: out += "C\(f(pt[0].x)) \(f(pt[0].y)) \(f(pt[1].x)) \(f(pt[1].y)) \(f(pt[2].x)) \(f(pt[2].y))"
    case .closeSubpath: out += "Z"
    @unknown default: break
    }
  }
  return out
}
let wordSVG: String = {
  // as Brand.swift's Wordmark at size 200: "SWTOR" heavy, tracking -0.04; under it, 0.1 apart, a
  // red rule (0.66 x 0.05) and "ON MAC" light at a third of the size, tracking 0.117, 0.2 apart
  let S: CGFloat = 200
  let mark = unboundedPath("SWTOR", weight: 800, size: S, kern: -S * 0.04)
  var sub = unboundedPath("ON MAC", weight: 560, size: S / 2.6, kern: S * 0.10)
  let mb = mark.boundingBoxOfPath, sb0 = sub.boundingBoxOfPath
  let ruleW = S * 0.66, ruleH = S * 0.05, gap = S * 0.2
  let lineW = ruleW + gap + sb0.width
  let lineY = mb.minY - S * 0.1 - sb0.height  // bottom of the second line
  var ts = CGAffineTransform(translationX: mb.midX - lineW / 2 + ruleW + gap - sb0.minX, y: lineY - sb0.minY)
  sub = sub.copy(using: &ts)!
  let rule = CGRect(x: mb.midX - lineW / 2, y: lineY + sb0.height / 2 - ruleH / 2, width: ruleW, height: ruleH)
  // the block, scaled so "SWTOR" is 700 wide, centred on the crossing
  let top = mb.maxY, bottom = lineY
  let sc: CGFloat = 700 / mb.width
  var t = CGAffineTransform(translationX: 512 - mb.midX * sc, y: 512 - (top + bottom) / 2 * sc).scaledBy(x: sc, y: sc)
  let m = mark.copy(using: &t)!, sp = sub.copy(using: &t)!, r = rule.applying(t)
  return svg("<path d=\"\(pathD(m))\" fill=\"#EEF1F6\"/>" +
             "<rect x=\"\(f(r.minX))\" y=\"\(f(r.minY))\" width=\"\(f(r.width))\" height=\"\(f(r.height))\" fill=\"#FF3D2E\"/>" +
             "<path d=\"\(pathD(sp))\" fill=\"#FF3D2E\"/>")
}()

// --- glow: the blades' bloom and the flare where they cross, blurred for real (PNG)
func glowPNG() -> Data {
  let px = 1024
  func layer(sigma: CGFloat, alpha: CGFloat, _ draw: (CGContext) -> Void) -> CIImage {
    let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(c)
    var img = CIImage(cgImage: c.makeImage()!)
    let ext = img.extent
    if sigma > 0 { img = img.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: ext) }
    return img.applyingFilter("CIColorMatrix", parameters: [
      "inputRVector": CIVector(x: alpha, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: alpha, z: 0, w: 0),
      "inputBVector": CIVector(x: 0, y: 0, z: alpha, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
  }
  func strokes(_ c: CGContext, width: CGFloat, color: (Saber) -> CGColor = { $0.bloom }) {
    for s in sabers {
      let from = s.at(s.hilt + width / 2 - 6 * k), to = s.at(s.hilt + s.blade)
      c.setLineCap(.round); c.setLineWidth(width); c.setStrokeColor(color(s))
      c.move(to: from); c.addLine(to: to); c.strokePath()
    }
  }
  var out = layer(sigma: 80 * k, alpha: 0.75) { strokes($0, width: 70 * k) }
  for (sg, al, w) in [(26.0, 0.95, 50.0), (10.0, 0.9, 44.0)] as [(CGFloat, CGFloat, CGFloat)] {
    out = layer(sigma: sg * k, alpha: al) { strokes($0, width: w * k) }.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: out])
  }
  // the blade itself: the coloured rim, then a paler inner band (the white core is an SVG layer)
  out = layer(sigma: 4 * k, alpha: 1) { strokes($0, width: 40 * k, color: { $0.edge }) }
    .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: out])
  out = layer(sigma: 2.5 * k, alpha: 0.8) { c in
    strokes(c, width: 26 * k, color: { s in let v = s.edge.components!; return rgb(v[0] + (1 - v[0]) * 0.35, v[1] + (1 - v[1]) * 0.35, v[2] + (1 - v[2]) * 0.35) })
  }.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: out])
  let x = crossing()
  let flare = layer(sigma: 0, alpha: 1) { c in
    let g = CGGradient(colorsSpace: sRGB, colors: [rgb(0.85, 0.80, 1, 0.35), rgb(0.70, 0.55, 1, 0.18), rgb(0.6, 0.4, 1, 0)] as CFArray,
                       locations: [0, 0.25, 1])!
    c.drawRadialGradient(g, startCenter: x, startRadius: 0, endCenter: x, endRadius: 95 * k, options: [])
  }
  out = flare.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: out])
  let cg = ci.createCGImage(out, from: CGRect(x: 0, y: 0, width: px, height: px))!
  return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
}

if args[1] == "layers" {
  let assets = doc.appendingPathComponent("Assets")
  try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
  try spaceSVG.write(to: assets.appendingPathComponent("space.svg"), atomically: true, encoding: .utf8)
  try glowPNG().write(to: assets.appendingPathComponent("glow.png"))
  try bladesSVG.write(to: assets.appendingPathComponent("blades.svg"), atomically: true, encoding: .utf8)
  try hiltsSVG.write(to: assets.appendingPathComponent("hilts.svg"), atomically: true, encoding: .utf8)
  try wordSVG.write(to: assets.appendingPathComponent("wordmark.svg"), atomically: true, encoding: .utf8)
  print("layers written to \(assets.path)")
  exit(0)
}

// --- preview: Icon Composer's own renders, so the sheet shows what the system will draw
let ictool = ProcessInfo.processInfo.environment["ICTOOL"]
  ?? "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("make-icon-\(getpid())")
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }
// ictool draws the shape edge to edge; an app icon puts it on Apple's grid (824 of 1024 units),
// so for the size rows the shape is rendered at 824/1024 and centred, like a .icns.
func render(_ rendition: String, _ px: Int, grid: Bool) -> CGImage {
  let body = grid ? max(1, Int((Double(px) * 824 / 1024).rounded())) : px
  let out = tmp.appendingPathComponent("\(rendition)-\(px)-\(grid).png")
  let p = Process()
  p.executableURL = URL(fileURLWithPath: ictool)
  p.arguments = [doc.path, "--export-image", "--output-file", out.path, "--platform", "macOS", "--rendition", rendition,
                 "--width", "\(body)", "--height", "\(body)", "--scale", "1"]
  p.standardOutput = FileHandle.nullDevice
  try! p.run()
  p.waitUntilExit()
  guard p.terminationStatus == 0, let img = NSBitmapImageRep(data: try! Data(contentsOf: out))?.cgImage else {
    FileHandle.standardError.write("ictool failed for \(rendition) at \(px) px\n".data(using: .utf8)!)
    exit(1)
  }
  let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let o = CGFloat(px - body) / 2
  c.draw(img, in: CGRect(x: o, y: o, width: CGFloat(body), height: CGFloat(body)))
  return c.makeImage()!
}
let renditions = ["Default", "Dark", "TintedLight", "TintedDark", "ClearLight", "ClearDark"]
let sizes = [1024, 256, 128, 64, 32, 16]
let shown = { (px: Int) -> CGFloat in px == 1024 ? 512 : CGFloat(px) }
var groups: [(String, light: [Int: CGImage], dark: [Int: CGImage])] = [
  (doc.lastPathComponent, Dictionary(uniqueKeysWithValues: sizes.map { ($0, render("Default", $0, grid: true)) }),
   Dictionary(uniqueKeysWithValues: sizes.map { ($0, render("Dark", $0, grid: true)) })),
]
if args.count == 5, let other = NSImage(contentsOfFile: args[4]) {
  var imgs: [Int: CGImage] = [:]
  for px in sizes {
    var rect = CGRect(x: 0, y: 0, width: px, height: px)
    let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    if let cg = other.cgImage(forProposedRect: &rect, context: nil, hints: nil) { c.draw(cg, in: rect) }
    imgs[px] = c.makeImage()
  }
  let app = URL(fileURLWithPath: args[4]).pathComponents.last { $0.hasSuffix(".app") }
  groups.append((app.map { String($0.dropLast(4)) } ?? URL(fileURLWithPath: args[4]).lastPathComponent, imgs, imgs))
}
let looks = renditions.map { ($0, render($0, 512, grid: false)) }

let gap: CGFloat = 36, margin: CGFloat = 48, labelH: CGFloat = 70, rowH: CGFloat = 512 + labelH + 40, lookW: CGFloat = 300
let groupW = sizes.map(shown).reduce(0, +) + gap * CGFloat(sizes.count - 1)
let W = max(margin * 2 + groupW * CGFloat(groups.count) + 90 * CGFloat(groups.count - 1),
            margin * 2 + (lookW + gap) * CGFloat(renditions.count) - gap)
let looksH = lookW + labelH + 40
let H = margin * 2 + looksH + rowH * 2
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
let c = NSGraphicsContext.current!.cgContext
c.interpolationQuality = .high
let labelFont = NSFont.systemFont(ofSize: 26, weight: .semibold)
let sizeFont = NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .regular)
// the six appearances, on a mid grey (Tinted and Clear take their colour from the wallpaper)
c.setFillColor(rgb(0.45, 0.46, 0.48))
c.fill(CGRect(x: 0, y: H - margin - looksH, width: W, height: looksH + margin))
for (i, (name, img)) in looks.enumerated() {
  let x = margin + CGFloat(i) * (lookW + gap), y = H - margin - looksH + 30
  c.draw(img, in: CGRect(x: x, y: y, width: lookW, height: lookW))
  (name as NSString).draw(at: NSPoint(x: x, y: y + lookW + 10), withAttributes: [.font: labelFont, .foregroundColor: NSColor.white])
}
// every size at 1:1 (1024 at half size): Default on light, Dark on dark
for (row, dark) in [false, true].enumerated() {
  let y0 = H - margin - looksH - rowH * CGFloat(row + 1)
  c.setFillColor(dark ? rgb(0.12, 0.12, 0.13) : rgb(0.93, 0.93, 0.94))
  c.fill(CGRect(x: 0, y: row == 0 ? y0 : 0, width: W, height: row == 0 ? rowH : y0 + rowH))
  let ink = dark ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.25, alpha: 1)
  var x = margin
  for g in groups {
    (g.0 as NSString).draw(at: NSPoint(x: x, y: y0 + rowH - 44), withAttributes: [.font: labelFont, .foregroundColor: ink])
    for px in sizes {
      let d = shown(px)
      c.draw((dark ? g.dark : g.light)[px]!, in: CGRect(x: x, y: y0 + 40 + (512 - d) / 2, width: d, height: d))
      ("\(px)" as NSString).draw(at: NSPoint(x: x, y: y0 + 4), withAttributes: [.font: sizeFont, .foregroundColor: ink.withAlphaComponent(0.7)])
      x += d + gap
    }
    x += 90 - gap
  }
}
NSGraphicsContext.restoreGraphicsState()
try sheet.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
print("preview written to \(args[3])")
