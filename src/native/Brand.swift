// The look of swonmac.com in SwiftUI: its colour tokens for dark and light (the values of
// sw-on-mac/src/styles/global.css), its two typefaces (Unbounded for the wordmark, JetBrains
// Mono for labels; Resources/Fonts, registered through ATSApplicationFontsPath, both SIL OFL
// 1.1), and the small pieces built from them: section labels, chips, status pips, panels and
// the primary action. Everything else stays the system's: running text, controls, sheets.
//
// Design decisions with a default (Jan can change them here):
//   accent        SWTOR red for the one big action, progress and the active step; controls
//                 in Settings keep the user's own accent colour
//   surfaces      the site's near-black and paper in the main window; Settings stays system
//   primaryLabel  the big action in mono caps, as the site's download button
//   corners       panels 8 pt, buttons 6 pt, chips 4 pt

import AppKit
import SwiftUI

enum Brand {
  // MARK: Colours (dark, light; Increase Contrast steps the hairlines up)

  static let bg = dynamic(0x05060A, 0xF3F1EC)
  static let bgRaised = dynamic(0x0B0D14, 0xFFFFFF)
  static let surface = dynamic(0x10131C, 0xE9E6DF)
  static let border = dynamic(0x1D2230, 0xD3CFC5, contrast: (0x3A435A, 0x9C978B))
  static let borderStrong = dynamic(0x2C3345, 0xB5B0A4, contrast: (0x4A5470, 0x8C877C))
  static let fg = dynamic(0xEEF1F6, 0x0B0D14)
  static let fg2 = dynamic(0x9AA3B5, 0x4A4F5C)
  // (light: a touch darker than the site's #6A6F79, which is 4.47:1 on paper)
  static let fg3 = dynamic(0x7B8496, 0x62676F)
  static let accent = dynamic(0xFF3D2E, 0xD42A1C)
  static let accentSoft = dynamic(0xFF3D2E, 0xD42A1C, alpha: (0.12, 0.08))
  // (light: darker than the site's #B86E00, 3.5:1 on paper, for text: 4.9:1 on paper, 5.5:1
  // on white; darker again with Increase Contrast)
  static let warning = dynamic(0xFFB020, 0x9A5900, contrast: (0xFFC24D, 0x8A4F00))
  static let warningSoft = dynamic(0xFFB020, 0xB86E00, alpha: (0.10, 0.08))
  static let onAccent = dynamic(0x05060A, 0xFFFFFF)
  static let good = Color(nsColor: .systemGreen)
  static let bad = Color(nsColor: .systemRed)

  // RGB colours of the warp, which draws in a Canvas without the environment's appearance
  static func ink(dark: Bool) -> Color { dark ? Color(hex: 0xEEF1F6) : Color(hex: 0x0B0D14) }
  static func red(dark: Bool) -> Color { dark ? Color(hex: 0xFF3D2E) : Color(hex: 0xD42A1C) }
  static func ring(dark: Bool) -> Color { dark ? Color(hex: 0x2C3345) : Color(hex: 0xB5B0A4) }

  private static func dynamic(_ dark: UInt32, _ light: UInt32, alpha: (Double, Double) = (1, 1),
                              contrast: (UInt32, UInt32)? = nil) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
      let match = appearance.bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua,
                                              .accessibilityHighContrastAqua])
      let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
      let high = match == .accessibilityHighContrastDarkAqua || match == .accessibilityHighContrastAqua
      let hex = high && contrast != nil ? (isDark ? contrast!.0 : contrast!.1) : (isDark ? dark : light)
      return NSColor(hex: hex, alpha: isDark ? alpha.0 : alpha.1)
    })
  }
}

extension NSColor {
  convenience init(hex: UInt32, alpha: Double = 1) {
    self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
              blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
  }
}

extension Color {
  init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }
}

// MARK: - Type

extension Font {
  // Unbounded: the wordmark only
  static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
    .custom("Unbounded", size: size, relativeTo: style).weight(weight)
  }

  // JetBrains Mono: labels, chips, versions, the big action
  static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold, relativeTo style: Font.TextStyle = .caption) -> Font {
    .custom("JetBrains Mono", size: size, relativeTo: style).weight(weight)
  }
}

// MARK: - Pieces

// "// THIS MAC" on the left, an optional HUD count on the right. VoiceOver reads the title
// alone, as a header.
struct SectionLabel<Trailing: View>: View {
  let title: String
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(alignment: .center) {
      Text("// " + title)
        .font(.mono(10.5))
        .tracking(1.8)
        .textCase(.uppercase)
        .foregroundStyle(Brand.fg2)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 8)
      trailing
    }
  }
}

extension SectionLabel where Trailing == EmptyView {
  init(_ title: String) { self.init(title: title) { EmptyView() } }
}

// A count or note at the right of a section label ("6 CHECKS · ALL GOOD"); decoration, which
// VoiceOver skips.
struct HUDNote: View {
  let text: String
  var body: some View {
    Text(text)
      .font(.mono(10, .medium))
      .tracking(1.6)
      .textCase(.uppercase)
      .foregroundStyle(Brand.fg3)
      .lineLimit(1)
      .accessibilityHidden(true)
  }
}

// A small square, the site's list marker; here the colour of a state.
struct StatusPip: View {
  let color: Color
  var body: some View {
    Rectangle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
  }
}

// A mono caps tag in a hairline frame: a pip or a symbol, then the text.
struct Chip: View {
  let text: String
  var symbol: String?
  var pip: Color?
  var tint: Color = Brand.fg
  var fill: Color = .clear
  var stroke: Color = Brand.borderStrong

  var body: some View {
    HStack(spacing: 7) {
      if let pip { StatusPip(color: pip) }
      if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
      Text(text)
        .font(.mono(10))
        .tracking(1.4)
        .textCase(.uppercase)
        .lineLimit(1)
    }
    .foregroundStyle(tint)
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(fill, in: .rect(cornerRadius: 4))
    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(stroke, lineWidth: 1))
    .fixedSize()
  }
}

// A raised panel with a hairline border.
extension View {
  func brandPanel(cornerRadius: CGFloat = 8, padding: CGFloat? = nil) -> some View {
    self
      .padding(padding ?? 0)
      // (opaque: the glass buttons on it then have a still backdrop while the warp runs behind)
      .background(Brand.bgRaised, in: .rect(cornerRadius: cornerRadius))
      .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Brand.border, lineWidth: 1))
  }
}

// The one big action: filled with the accent, mono caps. Disabled: a hairline frame.
struct BrandPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    Face(configuration: configuration)
  }

  struct Face: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
      configuration.label
        .font(.mono(15, .bold, relativeTo: .title3))
        .tracking(2)
        .textCase(.uppercase)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(isEnabled ? Brand.onAccent : Brand.fg3)
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(.horizontal, 16)
        .background(isEnabled ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(Brand.surface),
                    in: .rect(cornerRadius: 6))
        .overlay {
          if !isEnabled { RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.borderStrong, lineWidth: 1) }
        }
        .brightness(isEnabled ? (configuration.isPressed ? -0.08 : hovered ? 0.06 : 0) : 0)
        .scaleEffect(configuration.isPressed ? 0.985 : 1)
        .animation(.snappy(duration: 0.15), value: configuration.isPressed)
        .onHover { hovered = $0 }
        .contentShape(.rect(cornerRadius: 6))
    }
  }
}

extension ButtonStyle where Self == BrandPrimaryButtonStyle {
  static var brandPrimary: BrandPrimaryButtonStyle { BrandPrimaryButtonStyle() }
}

// "SWTOR" heavy, "ON MAC" light and tracked in the accent behind a rule, as the site's #swtor
// section title. VoiceOver reads "SWTOR on Mac".
struct Wordmark: View {
  var size: CGFloat = 60

  var body: some View {
    VStack(alignment: .leading, spacing: size * 0.1) {
      Text("SWTOR")
        .font(.display(size))
        .tracking(-size * 0.04)
        .foregroundStyle(Brand.fg)
      HStack(spacing: size * 0.2) {
        Rectangle().fill(Brand.accent).frame(width: size * 0.66, height: max(2, size * 0.05))
        Text("ON MAC")
          .font(.display(size / 3, .light, relativeTo: .title2))
          .tracking(size * 0.117)
          .foregroundStyle(Brand.accent)
      }
      .padding(.leading, size * 0.05)
    }
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("SWTOR on Mac")
    .accessibilityAddTraits(.isHeader)
  }
}
