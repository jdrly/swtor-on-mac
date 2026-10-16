// Renders the placeholder app icon: a glowing blade over a starfield on a deep-space squircle
// (no Star Wars or SWTOR artwork). Usage: swift make-icon.swift <out.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
  FileHandle.standardError.write("usage: make-icon.swift <out.iconset>\n".data(using: .utf8)!)
  exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// Fixed star positions, so every size (and every build) shows the same icon
var seed: UInt64 = 0x5357_544F_5221
func rnd() -> CGFloat {
  seed = seed &* 6364136223846793005 &+ 1442695040888963407
  return CGFloat(seed >> 33) / CGFloat(1 << 31)
}
let stars = (0..<110).map { _ in (x: rnd(), y: rnd(), r: 0.4 + rnd() * 1.2, a: 0.25 + rnd() * 0.6) }

func render(_ px: Int) -> Data {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let s = CGFloat(px)
  // Apple's icon grid: 824/1024 body, 185.4/1024 corner radius.
  let inset = s * 100 / 1024
  let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
  let path = NSBezierPath(roundedRect: body, xRadius: s * 185.4 / 1024, yRadius: s * 185.4 / 1024)
  NSGradient(colors: [NSColor(red: 0.10, green: 0.12, blue: 0.24, alpha: 1),
                      NSColor(red: 0.01, green: 0.02, blue: 0.05, alpha: 1)])!
    .draw(in: path, relativeCenterPosition: NSPoint(x: 0, y: 0.4))
  path.addClip()
  for st in stars {
    let r = st.r * s / 512
    let p = NSPoint(x: body.minX + st.x * body.width, y: body.minY + st.y * body.height)
    NSColor(white: 1, alpha: st.a).setFill()
    NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)).fill()
  }
  // the blade: a soft glow, then a white core, diagonal from lower left to upper right
  let a = NSPoint(x: body.minX + body.width * 0.24, y: body.minY + body.height * 0.22)
  let b = NSPoint(x: body.minX + body.width * 0.80, y: body.minY + body.height * 0.78)
  for (width, color) in [(0.16, NSColor(red: 0.30, green: 0.62, blue: 1.0, alpha: 0.18)),
                         (0.09, NSColor(red: 0.35, green: 0.70, blue: 1.0, alpha: 0.45)),
                         (0.035, NSColor(white: 1, alpha: 0.95))] {
    let line = NSBezierPath()
    line.move(to: a)
    line.line(to: b)
    line.lineWidth = body.width * width
    line.lineCapStyle = .round
    color.setStroke()
    line.stroke()
  }
  // hilt
  let hilt = NSBezierPath()
  let dx = (b.x - a.x), dy = (b.y - a.y), len = (dx * dx + dy * dy).squareRoot()
  let ux = dx / len, uy = dy / len
  hilt.move(to: a)
  hilt.line(to: NSPoint(x: a.x - ux * body.width * 0.16, y: a.y - uy * body.width * 0.16))
  hilt.lineWidth = body.width * 0.06
  hilt.lineCapStyle = .butt
  NSColor(white: 0.72, alpha: 1).setStroke()
  hilt.stroke()
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
  try render(base).write(to: outDir.appendingPathComponent("icon_\(base)x\(base).png"))
  try render(base * 2).write(to: outDir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
