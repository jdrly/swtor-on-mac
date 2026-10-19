// The main window (SwiftUI, macOS 27 design): a hero with an animated deep-space background,
// status tiles in glass, and the install panel with one big action (Install; once installed,
// Play SWTOR) and a timeline of the steps (src/som.sh announces them with "@phase <n>"). The
// notice must be accepted, in a sheet, before anything can be installed; afterwards a badge in
// the hero shows it again.
//
// Resizable both ways: two columns when wide (nothing scrolls), one column when narrow (that
// column is the only scroll area). The install log is a sheet (Show Log).

import AppKit
import SwiftUI

// Lightsaber blue for actions; the hero's gold is only decoration.
let accent = Color(red: 0.20, green: 0.50, blue: 0.98)
let heroGold = Color(red: 0.86, green: 0.66, blue: 0.26)

// Shown once the install is done: d9mt compiles shaders and pipelines the first time it sees
// them and caches them.
let firstRunNote = "The first minutes of play (and each new area or effect seen for the first time) may "
  + "stutter while shaders are compiled and cached; it gets smooth after that. After an update of "
  + "SWTOR on Mac the cache is rebuilt once."

struct MainView: View {
  @Bindable var installer: Installer
  let settings: GameSettings
  @Environment(\.openWindow) private var openWindow
  @State private var confirmUninstall = false
  @State private var confirmReplace: Installer.Operation?
  @State private var showNotice = false
  @State private var showLogSheet = false
  // why an action can't go ahead (an alert, so a click is never a silent no-op)
  @State private var blocked: Blocked?

  struct Blocked: Identifiable {
    let id = UUID()
    let title: String
    let message: String
  }

  // narrower than this: one column
  static let wideWidth: CGFloat = 820

  var body: some View {
    GeometryReader { geometry in
      let wide = geometry.size.width >= MainView.wideWidth
      VStack(spacing: 0) {
        if wide {
          Hero(installer: installer, showNotice: $showNotice)
          HStack(alignment: .top, spacing: 24) {
            // the highlights only if there is room for them
            ViewThatFits(in: .vertical) {
              VStack(alignment: .leading, spacing: 18) {
                StatusTiles(installer: installer)
                Highlights()
              }
              StatusTiles(installer: installer)
            }
            .frame(minWidth: 340, maxWidth: .infinity, alignment: .top)
            ActionPanel(installer: installer, actions: actions)
              .frame(minWidth: 380, maxWidth: 460)
          }
          .padding(.horizontal, 24)
          .padding(.vertical, 20)
          .frame(maxHeight: .infinity, alignment: .top)
        } else {
          ScrollView {
            VStack(spacing: 0) {
              Hero(installer: installer, showNotice: $showNotice)
              VStack(alignment: .leading, spacing: 18) {
                ActionPanel(installer: installer, actions: actions)
                StatusTiles(installer: installer)
                Highlights()
              }
              .padding(20)
            }
          }
          .scrollBounceBehavior(.basedOnSize)
          .ignoresSafeArea(edges: .top)
        }
        Footer(credits: installer.credits)
      }
      .ignoresSafeArea(edges: .top)
    }
    .frame(minWidth: 520, minHeight: 640)
    .tint(accent)
    .animation(.smooth, value: installer.phase)
    .animation(.smooth, value: installer.status)
    // The notice comes first: nothing can be installed before it is accepted.
    .sheet(isPresented: $showNotice) {
      NoticeSheet(installer: installer, isPresented: $showNotice)
    }
    .sheet(isPresented: $showLogSheet) {
      LogSheet(installer: installer)
    }
    // sheets keep the app from quitting: close them when asked to (an app update)
    .onChange(of: installer.closeSheets) { _, _ in
      showNotice = false
      showLogSheet = false
      confirmUninstall = false
      confirmReplace = nil
      blocked = nil
    }
    .onChange(of: showNotice || showLogSheet || confirmUninstall || confirmReplace != nil || blocked != nil) { _, open in
      installer.sheetOpen = open
    }
    .onChange(of: installer.loaded) { _, loaded in
      if loaded && !installer.installed && !installer.understood { showNotice = true }
    }
    .alert("Uninstall SWTOR on Mac?", isPresented: $confirmUninstall) {
      Button("Uninstall", role: .destructive) { uninstall() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The official SWTOR app goes back to how Broadsword ships it, and SWTOR on Mac's Wine "
           + "engine and prefix are deleted. Your game settings (graphics options, UI layouts and "
           + "key bindings) are copied back to the official app first, with a backup of its "
           + "previous ones. Your characters and the game itself are not affected. Logs are kept.")
    }
    .alert(blocked?.title ?? "", isPresented: Binding(get: { blocked != nil }, set: { if !$0 { blocked = nil } }),
           presenting: blocked) { _ in
      Button("OK", role: .cancel) { blocked = nil }
    } message: { b in
      Text(b.message)
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

  private var actions: PanelActions {
    PanelActions(play: play, install: askInstall, uninstall: askUninstall,
                 review: { showNotice = true }, showLog: { showLogSheet = true },
                 settings: { settings.reload(); openWindow(id: "settings") },
                 endLeftovers: endLeftovers)
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

  // Install and Uninstall look again first (the launcher or the game may just have quit), and
  // say why they can't go ahead if something still runs.
  private func askInstall() {
    guard installer.understood || installer.installed else { showNotice = true; return }
    installer.refresh {
      guard !installer.isBusy else { return }
      if let reason = installer.blockedReason {
        blocked = Blocked(title: installer.installed ? "Can't reinstall now" : "Can't install now", message: reason)
      } else if installer.otherWrapper {
        confirmReplace = .install
      } else {
        installer.start(.install)
      }
    }
  }

  private func askUninstall() {
    installer.refresh {
      guard !installer.isBusy else { return }
      if let reason = installer.blockedReason {
        blocked = Blocked(title: "Can't uninstall now", message: reason)
      } else {
        confirmUninstall = true
      }
    }
  }

  private func play() {
    installer.play { error in
      if let error { blocked = Blocked(title: "Can't open SWTOR", message: error) }
    }
  }

  private func endLeftovers() {
    installer.endLeftovers { error in
      if let error { blocked = Blocked(title: "Could not end the leftover Wine processes", message: error) }
    }
  }

  private func uninstall() {
    if installer.otherWrapper { confirmReplace = .uninstall } else { installer.start(.uninstall) }
  }
}

struct PanelActions {
  let play: () -> Void
  let install: () -> Void
  let uninstall: () -> Void
  let review: () -> Void
  let showLog: () -> Void
  let settings: () -> Void
  let endLeftovers: () -> Void
}

// MARK: - Hero

struct Hero: View {
  let installer: Installer
  @Binding var showNotice: Bool
  @State private var showBadge = false
  // the window's own appearance (the hero itself is always dark; its popover is not)
  @Environment(\.colorScheme) private var windowScheme

  var body: some View {
    ZStack(alignment: .topTrailing) {
      HStack(spacing: 20) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 84, height: 84)
          .shadow(color: accent.opacity(0.55), radius: 18)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("SWTOR on Mac")
              .font(.system(size: 32, weight: .bold, design: .rounded))
            #if SWTOR_DEV
            DevBuildBadge()
            #endif
          }
          Text("Faster graphics for the official SWTOR Mac app: Direct3D 9 straight to Metal, on a newer Wine.")
            .font(.title3)
            .foregroundStyle(.white.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      .foregroundStyle(.white)
      .environment(\.colorScheme, .dark)
      .padding(.horizontal, 28)
      .padding(.top, 46)
      .padding(.bottom, 22)
      .frame(maxWidth: .infinity, alignment: .leading)

      Button { showBadge.toggle() } label: {
        Label("Unofficial community project", systemImage: "exclamationmark.shield.fill")
          .font(.callout.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
      }
      .buttonStyle(.plain)
      .glassEffect(.regular.tint(.orange.opacity(0.35)).interactive(), in: .capsule)
      .pointerStyle(.link)
      .padding(.top, 14)
      .padding(.trailing, 18)
      .help("Not made, endorsed or supported by Broadsword Games, EA, Lucasfilm or Disney")
      .environment(\.colorScheme, .dark)
      .popover(isPresented: $showBadge, arrowEdge: .bottom) {
        NoticeText()
          .foregroundStyle(.primary)
          .padding(20)
          .frame(width: 380)
          .background(.regularMaterial)
          .environment(\.colorScheme, windowScheme)
      }
    }
    .background { HeroBackground() }
    .clipped()
  }
}

#if SWTOR_DEV
// "Development build 0.0.6-dev.1" next to the title in development builds (build.sh).
struct DevBuildBadge: View {
  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
  }

  var body: some View {
    Label("Development build \(version)", systemImage: "hammer.fill")
      .font(.callout.weight(.semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .glassEffect(.regular.tint(.purple.opacity(0.45)), in: .capsule)
      .help("A test build, published only as a GitHub pre-release: Debug Logging on by default, "
            + "no automatic update checks")
      .fixedSize()
  }
}
#endif

// Deep space: a slowly drifting mesh gradient (navy, teal, a touch of gold) under a
// twinkling starfield. Still with Reduce Motion, and paused while the window is not key.
struct HeroBackground: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.controlActiveState) private var activeState

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || activeState != .key)) { context in
      let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
      ZStack {
        MeshGradient(width: 3, height: 3, points: points(t), colors: [
          Color(red: 0.01, green: 0.02, blue: 0.07), Color(red: 0.03, green: 0.07, blue: 0.20), Color(red: 0.02, green: 0.04, blue: 0.12),
          Color(red: 0.04, green: 0.16, blue: 0.30), Color(red: 0.05, green: 0.24, blue: 0.32), Color(red: 0.06, green: 0.08, blue: 0.26),
          Color(red: 0.02, green: 0.04, blue: 0.10), Color(red: 0.05, green: 0.12, blue: 0.22), heroGold.opacity(0.55),
        ])
        Starfield(time: t)
      }
    }
    .accessibilityHidden(true)
  }

  private func points(_ t: Double) -> [SIMD2<Float>] {
    let a = Float(sin(t * 0.13)), b = Float(cos(t * 0.11)), c = Float(sin(t * 0.07 + 1))
    return [
      [0, 0], [0.5 + 0.08 * a, 0], [1, 0],
      [0, 0.5 + 0.12 * b], [0.5 + 0.14 * c, 0.5 + 0.12 * a], [1, 0.5 + 0.1 * c],
      [0, 1], [0.5 + 0.1 * b, 1], [1, 1],
    ]
  }
}

struct Starfield: View {
  let time: Double
  private static let stars: [(x: Double, y: Double, r: Double, speed: Double, phase: Double)] = {
    var seed: UInt64 = 0x5717_0E0F_2026
    func next() -> Double {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Double(seed >> 11) / Double(1 << 53)
    }
    return (0..<140).map { _ in (next(), next(), 0.4 + 1.3 * next() * next(), 0.4 + 1.6 * next(), next() * 6.28) }
  }()

  var body: some View {
    Canvas { context, size in
      for s in Starfield.stars {
        let twinkle = 0.35 + 0.65 * abs(sin(time * s.speed + s.phase))
        let rect = CGRect(x: s.x * size.width, y: s.y * size.height, width: s.r * 2, height: s.r * 2)
        context.opacity = twinkle * (s.r > 1.2 ? 1 : 0.7)
        context.fill(Path(ellipseIn: rect), with: .color(.white))
      }
    }
  }
}

// MARK: - Status tiles

struct StatusTiles: View {
  let installer: Installer

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("This Mac").font(.headline).padding(.leading, 4)
      if !installer.loaded {
        HStack { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
          .padding(.vertical, 8)
      } else {
        GlassEffectContainer(spacing: 10) {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
            ForEach(tiles) { StatusTile(tile: $0) }
          }
        }
        if !installer.officialPresent {
          Link(destination: URL(string: "https://www.swtor.com")!) {
            Label("Install SWTOR from swtor.com first and start it once. SWTOR on Mac never downloads "
                  + "the launcher or the game.", systemImage: "arrow.up.right.square")
              .font(.callout)
          }
          .pointerStyle(.link)
        }
      }
    }
  }

  struct Tile: Identifiable {
    enum Tone { case good, warning, bad, info, off }
    let id: String
    let symbol: String
    let detail: String
    let tone: Tone
  }

  private var tiles: [Tile] {
    var tiles = [
      Tile(id: "Official SWTOR app", symbol: "gamecontroller.fill",
           detail: installer.officialPresent ? "Found" : "Not found", tone: installer.officialPresent ? .good : .bad),
      Tile(id: "Rosetta", symbol: "cpu",
           detail: installer.rosetta ? "Installed" : "Not installed", tone: installer.rosetta ? .good : .bad),
    ]
    if !installer.appleSilicon {
      tiles.append(Tile(id: "Apple Silicon", symbol: "memorychip", detail: "Required", tone: .bad))
    }
    let version = installer.status["installed_version"] ?? "?"
    tiles.append(installer.installedOtherVersion
      ? Tile(id: "SWTOR on Mac", symbol: "checkmark.seal.fill", detail: "\(version) installed · Reinstall to update", tone: .warning)
      : installer.installed
        ? Tile(id: "SWTOR on Mac", symbol: "checkmark.seal.fill", detail: "Version \(version)", tone: .good)
        : Tile(id: "SWTOR on Mac", symbol: "seal", detail: "Not installed yet", tone: .off))
    tiles.append(hookTile)
    tiles.append(Tile(id: "Graphics", symbol: "sparkles",
                      detail: "d9mt \(installer.status["d9mt"] ?? "?") · Metal", tone: .info))
    tiles.append(Tile(id: "Engine", symbol: "gearshape.2.fill", detail: engineName, tone: .info))
    return tiles
  }

  private var hookTile: Tile {
    switch installer.wrapper {
    case "ours":
      return Tile(id: "Launcher hook", symbol: "link",
                  detail: installer.status["watch_agent"] == "yes" ? "Active · repairs itself" : "Active", tone: .good)
    case "replaced" where installer.installed:
      return Tile(id: "Launcher hook", symbol: "link.badge.plus", detail: "Removed by a launcher update", tone: .warning)
    case "replaced":
      return Tile(id: "Launcher hook", symbol: "questionmark.folder", detail: "Leftovers of another setup", tone: .warning)
    case "personal":
      return Tile(id: "Launcher hook", symbol: "hammer.fill", detail: "Developer setup installed", tone: .warning)
    case "foreign":
      return Tile(id: "Launcher hook", symbol: "exclamationmark.triangle.fill", detail: "Another wrapper installed", tone: .warning)
    case "stock":
      return Tile(id: "Launcher hook", symbol: "link", detail: "Broadsword's own Wine", tone: .off)
    default:
      return Tile(id: "Launcher hook", symbol: "link", detail: "Official Wine not found", tone: .off)
    }
  }

  // The engine in place (this version's if not installed): cx-26.3.0-8 -> CrossOver 26.3,
  // WS12WineCX24.0.7_7 (an install of 0.0.x until Reinstall) -> CrossOver 24.0.7
  private var engineName: String {
    let installed = installer.installed ? installer.status["installed_engine"] ?? "" : ""
    let name = installed.isEmpty ? installer.status["engine"] ?? "" : installed
    if let r = name.range(of: #"^cx-[0-9]+\.[0-9]+"#, options: .regularExpression) {
      return "Wine · CrossOver " + name[r].dropFirst(3)
    }
    if let r = name.range(of: #"CX[0-9.]+"#, options: .regularExpression) {
      return "Wine · CrossOver " + name[r].dropFirst(2)
    }
    return name.isEmpty ? "Wine" : name
  }
}

struct StatusTile: View {
  let tile: StatusTiles.Tile

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: tile.symbol)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .contentTransition(.symbolEffect(.replace))
        .symbolEffect(.bounce, value: tile.tone == .good)
        .frame(width: 34, height: 34)
        .background(color.gradient, in: .circle)
      VStack(alignment: .leading, spacing: 2) {
        Text(tile.id).font(.subheadline.weight(.semibold))
        Text(tile.detail).font(.caption).foregroundStyle(tile.tone == .warning || tile.tone == .bad ? color : .secondary)
          .fixedSize(horizontal: false, vertical: true)
          .contentTransition(.opacity)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
    .glassEffect(.regular, in: .rect(cornerRadius: 16))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(tile.id): \(tile.detail)")
  }

  private var color: Color {
    switch tile.tone {
    case .good: .green
    case .warning: .orange
    case .bad: .red
    case .info: accent
    case .off: .gray
    }
  }
}

// What SWTOR on Mac does, in four lines (fills the left column under the tiles).
struct Highlights: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("What it does").font(.headline).padding(.leading, 4)
      Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 12) {
        GridRow {
        item("bolt.fill", "Direct3D 9 straight to Metal", "d9mt replaces the official app's graphics layer.")
        item("gamecontroller.fill", "Game Mode", "macOS gives the game priority while it is in full screen.")
        }
        GridRow {
        item("arrow.triangle.2.circlepath", "Survives launcher updates", "It hooks itself back in when the launcher updates its Wine.")
        item("arrow.uturn.backward.circle.fill", "Fully reversible", "Uninstall puts the official app back exactly as Broadsword ships it.")
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quinary, in: .rect(cornerRadius: 16))
    }
  }

  private func item(_ symbol: String, _ title: String, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: symbol).foregroundStyle(accent).frame(width: 18)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Install panel

struct ActionPanel: View {
  @Bindable var installer: Installer
  let actions: PanelActions

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      PrimaryAction(installer: installer, actions: actions)
      if installer.loaded, !installer.isBusy, installer.leftovers {
        LeftoversNote(installer: installer, end: actions.endLeftovers)
      } else if let note = blockingNote {
        Label(note, systemImage: "pause.circle.fill")
          .font(.callout)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
      if case .succeeded = installer.phase {
        // done: the steps fold into one line of checkmarks
        CompactTimeline(count: installer.steps.count)
          .transition(.opacity)
      } else if showTimeline {
        Timeline(installer: installer)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
      Outcome(installer: installer)
      if installer.installed && installer.phase == .idle {
        ReadyNote()
      }
      if !installer.log.isEmpty {
        Button(action: actions.showLog) {
          Label("Show Log", systemImage: "text.alignleft")
        }
        .buttonStyle(.link)
        .pointerStyle(.link)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quinary, in: .rect(cornerRadius: 22))
  }

  // the steps: while working and after, and before a first install as a preview
  private var showTimeline: Bool {
    installer.phase != .idle || (installer.loaded && !installer.installed)
  }

  private var blockingNote: String? {
    guard installer.loaded, !installer.isBusy else { return nil }
    let names = installer.busyDetail.isEmpty ? "" : " (\(installer.busyDetail))"
    switch installer.busy {
    case "launcher": return "The SWTOR launcher is running. Quit it to install or uninstall."
    case "game": return "The game is running\(names). Quit it to install or uninstall."
    case "wine": return "Broadsword's Wine is still running\(names). Quit the SWTOR launcher and the game to install or uninstall."
    case "session": return "SWTOR on Mac's Wine is still running\(names). It ends by itself a few seconds after the launcher and the game have quit."
    default: break
    }
    switch installer.wrapper {
    case "personal": return "The developer setup from swtor-mac-proper is hooked into Broadsword's Wine folder. SWTOR on Mac asks before replacing it."
    case "foreign": return "Something else is hooked into Broadsword's Wine folder. SWTOR on Mac asks before replacing it."
    case "replaced" where !installer.installed: return "Broadsword's Wine folder has a bin-real folder SWTOR on Mac did not make. SWTOR on Mac asks before taking it over."
    default: return nil
    }
  }
}

// Neither the launcher nor the game runs, only what is left of a Wine session of SWTOR on Mac's
// engine: say so, and offer to end it (Install and Uninstall also do that first).
struct LeftoversNote: View {
  let installer: Installer
  let end: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Leftover Wine processes are still running"
            + (installer.busyDetail.isEmpty ? "" : " (\(installer.busyDetail))")
            + ", from a session that has ended. The SWTOR launcher and the game are not running. "
            + "They are not needed; Install and Uninstall end them first.",
            systemImage: "exclamationmark.triangle.fill")
        .font(.callout)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
      Button(action: end) {
        if installer.endingLeftovers {
          HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Ending…") }
        } else {
          Label("End Leftover Wine Processes", systemImage: "xmark.octagon")
        }
      }
      .buttonStyle(.glass)
      .disabled(installer.endingLeftovers)
      .pointerStyle(.link)
    }
  }
}

// The one big action (Install; once installed, Play SWTOR), and the secondary ones once
// installed.
struct PrimaryAction: View {
  @Bindable var installer: Installer
  let actions: PanelActions

  var body: some View {
    GlassEffectContainer(spacing: 10) {
      VStack(alignment: .leading, spacing: 10) {
        if installer.isBusy {
          working
        } else if installer.installed {
          installed
        } else {
          HStack {
            if installer.loaded && !installer.understood {
              big("Review the Notice…", symbol: "exclamationmark.shield.fill", action: actions.review)
            } else {
              big(failedInstall ? "Try Again" : "Install SWTOR on Mac", symbol: "arrow.down.circle.fill",
                  action: actions.install)
                .disabled(!installer.canInstall)
            }
          }
          if installer.canUninstall {
            Button("Remove the leftover hook…", action: actions.uninstall).buttonStyle(.link)
          }
        }
      }
    }
  }

  private var failedInstall: Bool { if case .failed(.install, _) = installer.phase { true } else { false } }

  private func big(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: symbol)
        .font(.title3.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
    .buttonStyle(.glassProminent)
    .controlSize(.extraLarge)
    .keyboardShortcut(.defaultAction)
    .pointerStyle(.link)
  }

  // "Installing… 42%" with the overall progress, and Cancel (an install rolls back; an
  // uninstall is quick and runs to the end)
  private var working: some View {
    HStack(spacing: 10) {
      HStack(spacing: 12) {
        ProgressView(value: installer.fraction)
          .progressViewStyle(.circular)
          .controlSize(.small)
        Text(installer.operation == .install ? "Installing…" : "Uninstalling…")
          .font(.title3.weight(.semibold))
        Spacer(minLength: 0)
        Text("\(Int((installer.fraction * 100).rounded()))%")
          .font(.title3.weight(.semibold).monospacedDigit())
          .contentTransition(.numericText(value: installer.fraction))
          .animation(.snappy, value: installer.fraction)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity)
      .glassEffect(.regular.tint(accent.opacity(0.25)), in: .capsule)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("\(installer.operation == .install ? "Installing" : "Uninstalling"), \(Int(installer.fraction * 100)) percent")
      if installer.phase == .working(.install) {
        Button("Cancel") { installer.cancel() }
          .buttonStyle(.glass)
          .controlSize(.extraLarge)
          .keyboardShortcut(.cancelAction)
          .pointerStyle(.link)
      }
    }
  }

  // Installed: Play SWTOR (or Repair/Update first, Play then among the secondary actions),
  // a line with the version or why Play can't go ahead, and Reinstall, Settings, Uninstall.
  private var installed: some View {
    VStack(alignment: .leading, spacing: 10) {
      let repair = installer.wrapper == "replaced"
      let fixFirst = repair || installer.installedOtherVersion
      if fixFirst {
        big(repair ? "Repair the Launcher Hook" : "Update to \(installer.appVersion)",
            symbol: repair ? "wrench.and.screwdriver.fill" : "arrow.triangle.2.circlepath", action: actions.install)
          .disabled(!installer.canInstall)
      } else {
        PlayButton(installer: installer, action: actions.play, prominent: true)
      }
      installedLine
      HStack(spacing: 10) {
        if fixFirst {
          PlayButton(installer: installer, action: actions.play, prominent: false)
        } else {
          Button(action: actions.install) { Label("Reinstall", systemImage: "arrow.clockwise") }
            .disabled(!installer.canInstall)
        }
        Button(action: actions.settings) { Label("Settings", systemImage: "slider.horizontal.3") }
        Spacer(minLength: 0)
        Button(role: .destructive, action: actions.uninstall) {
          Label("Uninstall…", systemImage: "trash").foregroundStyle(installer.canUninstall ? .red : .secondary)
        }
        .disabled(!installer.canUninstall)
      }
      .buttonStyle(.glass)
      .tint(nil)
      .controlSize(.large)
      .pointerStyle(.link)
    }
  }

  // "Installed · Version 0.0.3", or why Play can't go ahead
  @ViewBuilder private var installedLine: some View {
    if case .unavailable(let reason) = installer.playAction, installer.loaded {
      Label(reason, systemImage: "exclamationmark.circle.fill")
        .font(.callout)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
    } else {
      Label {
        Text("Installed · Version \(installer.status["installed_version"] ?? "?")")
      } icon: {
        Image(systemName: "checkmark.seal.fill")
          .foregroundStyle(.green)
          .symbolEffect(.bounce, value: installer.installed)
      }
      .font(.callout)
      .foregroundStyle(.secondary)
      .accessibilityElement(children: .combine)
    }
  }
}

// Play SWTOR: opens the official app; Show SWTOR Launcher (or Show SWTOR, the game) if it
// already runs; disabled with the reason when it can't (Play.swift).
struct PlayButton: View {
  let installer: Installer
  let action: () -> Void
  let prominent: Bool

  var body: some View {
    let play = installer.playAction
    let button = Button(action: action) {
      Group {
        if installer.launching {
          HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Opening SWTOR…") }
        } else {
          Label(title(play), systemImage: symbol(play))
        }
      }
      .font(prominent ? .title3.weight(.semibold) : nil)
      .frame(maxWidth: prominent ? .infinity : nil)
      .padding(.vertical, prominent ? 4 : 0)
    }
    .disabled(!enabled(play) || installer.launching)
    .accessibilityLabel(installer.launching ? "Opening SWTOR" : title(play))
    .accessibilityHint(hint(play))
    .help(hint(play))
    .pointerStyle(.link)
    if prominent {
      button
        .buttonStyle(.glassProminent)
        .controlSize(.extraLarge)
        .keyboardShortcut(.defaultAction)
    } else {
      button
    }
  }

  private func enabled(_ play: PlayAction) -> Bool {
    if case .unavailable = play { false } else { true }
  }

  private func title(_ play: PlayAction) -> String {
    switch play {
    case .show(let game): game ? "Show SWTOR" : "Show SWTOR Launcher"
    default: "Play SWTOR"
    }
  }

  private func symbol(_ play: PlayAction) -> String {
    if case .show = play { "macwindow" } else { "play.fill" }
  }

  private func hint(_ play: PlayAction) -> String {
    switch play {
    case .launch: "Opens the official SWTOR app; the game runs on SWTOR on Mac's engine."
    case .show(let game): game ? "Brings the game to the front." : "Brings the SWTOR launcher to the front."
    case .unavailable(let reason): reason
    }
  }
}

// The steps as a vertical timeline: nodes joined by a line that fills as they complete.
struct Timeline: View {
  let installer: Installer
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  enum State { case pending, active, done, failed }

  var body: some View {
    let steps = installer.steps
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
        row(step, state: state(i), last: i == steps.count - 1, fill: fill(i))
      }
    }
    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.3), value: installer.stepIndex)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(installer.operation == .install ? "Install steps" : "Uninstall steps")
  }

  private func state(_ i: Int) -> State {
    switch installer.phase {
    case .succeeded: return .done
    case .failed:
      let current = installer.stepIndex ?? 0
      return i < current ? .done : i == current ? .failed : .pending
    case .working:
      let current = installer.stepIndex ?? 0
      return i < current ? .done : i == current ? .active : .pending
    case .idle:
      return .pending
    }
  }

  // how much of the line below node i is filled
  private func fill(_ i: Int) -> Double {
    switch state(i) {
    case .done: return 1
    case .active:
      if let p = installer.progress, p.total > 0 { return min(1, Double(p.done) / Double(p.total)) }
      return 0
    default: return 0
    }
  }

  private func row(_ step: Installer.Step, state: State, last: Bool, fill: Double) -> some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(spacing: 0) {
        TimelineNode(number: step.id, symbol: step.symbol, state: state)
        if !last {
          ZStack(alignment: .top) {
            Capsule().fill(.quaternary)
            Capsule().fill(accent.gradient)
              .scaleEffect(x: 1, y: fill, anchor: .top)
          }
          .frame(width: 3)
          .frame(minHeight: 18, maxHeight: .infinity)
          .padding(.vertical, 4)
        }
      }
      .frame(width: 30)
      VStack(alignment: .leading, spacing: 4) {
        Text(step.title)
          .font(.body.weight(state == .active ? .semibold : .regular))
          .foregroundStyle(state == .pending ? .secondary : .primary)
        detail(step, state: state)
      }
      .padding(.top, 4)
      .padding(.bottom, last ? 0 : 10)
      Spacer(minLength: 0)
    }
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Step \(step.id), \(step.title): \(stateName(state))")
  }

  @ViewBuilder private func detail(_ step: Installer.Step, state: State) -> some View {
    switch state {
    case .active:
      if let p = installer.progress, p.total > 0 {
        VStack(alignment: .leading, spacing: 4) {
          ProgressView(value: Double(min(p.done, p.total)), total: Double(p.total))
            .controlSize(.small)
          Text("\(p.label): \(mb(p.done)) of \(mb(p.total))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .contentTransition(.numericText(value: Double(p.done)))
        }
      } else {
        Text(step.detail).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    case .failed:
      if case .failed(_, let message) = installer.phase {
        Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }
    default:
      Text(step.detail).font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
    }
  }

  private func stateName(_ s: State) -> String {
    switch s { case .pending: "to do"; case .active: "in progress"; case .done: "done"; case .failed: "failed" }
  }

  private func mb(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

struct TimelineNode: View {
  let number: Int
  let symbol: String
  let state: Timeline.State
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var spin = false

  var body: some View {
    ZStack {
      switch state {
      case .pending:
        Circle().strokeBorder(.quaternary, lineWidth: 2)
        Text("\(number)").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
      case .active:
        Circle().fill(accent.opacity(0.16))
        if !reduceMotion {
          Circle()
            .trim(from: 0, to: 0.28)
            .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
        } else {
          Circle().strokeBorder(accent, lineWidth: 2)
        }
        Image(systemName: symbol)
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(accent)
          .symbolEffect(.pulse, isActive: !reduceMotion)
      case .done:
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 26))
          .foregroundStyle(.white, .green)
          .transition(.scale.combined(with: .opacity))
          .symbolEffect(.bounce, options: .nonRepeating, value: state)
      case .failed:
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 26))
          .foregroundStyle(.white, .red)
          .transition(.scale.combined(with: .opacity))
      }
    }
    .frame(width: 28, height: 28)
  }
}

// A finished operation: its steps as a row of checkmarks.
struct CompactTimeline: View {
  let count: Int
  @State private var shown = false

  var body: some View {
    HStack(spacing: 6) {
      ForEach(0..<count, id: \.self) { i in
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 20))
          .foregroundStyle(.white, .green)
          .symbolEffect(.bounce, options: .nonRepeating, value: shown)
        if i < count - 1 {
          Capsule().fill(Color.green.gradient).frame(height: 3).frame(maxWidth: 40)
        }
      }
      Text("All steps done").font(.callout).foregroundStyle(.secondary).padding(.leading, 6)
      Spacer(minLength: 0)
    }
    .onAppear { shown = true }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("All \(count) steps done")
  }
}

// The result of the last operation (the timeline shows the steps).
struct Outcome: View {
  let installer: Installer

  var body: some View {
    switch installer.phase {
    case .succeeded(let op, let message):
      VStack(alignment: .leading, spacing: 10) {
        Label(message, systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .fixedSize(horizontal: false, vertical: true)
        if op == .install {
          Label(firstRunNote, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(installer.warnings, id: \.self) { w in
          Label(w, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    case .failed(_, let message) where installer.stepIndex == nil:
      // failed before the first step
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
    default:
      EmptyView()
    }
  }
}

// Installed: what to do next, and the first-run note.
struct ReadyNote: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Press Play SWTOR, or start the official SWTOR app as usual: the game runs on SWTOR on "
            + "Mac's engine.",
            systemImage: "play.circle.fill")
        .font(.callout)
      Label(firstRunNote, systemImage: "info.circle")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

// MARK: - Notice

struct NoticeText: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("SWTOR on Mac is an unofficial community project.")
        .font(.headline)
        .foregroundStyle(.primary)
      Text("It is not made, endorsed or supported by Broadsword Games, Electronic Arts, Lucasfilm or "
           + "Disney. Broadsword doesn't support third-party tools or compatibility layers, so you use "
           + "it at your own risk.")
      Text("It's not a game mod: it doesn't change the game's files, memory or network traffic. It only "
           + "replaces the compatibility layer the official Mac app already runs on (Wine, plus d9mt for "
           + "Direct3D 9 on Metal), and Uninstall puts that back the way Broadsword ships it.")
      Text("For help, contact Pharaphobia on Discord or open a GitHub issue. Please don't send logs or "
           + "bug reports about SWTOR on Mac to Broadsword or SWTOR customer support.")
      Text("Star Wars: The Old Republic and SWTOR are trademarks of their respective owners.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .font(.callout)
    .fixedSize(horizontal: false, vertical: true)
  }
}

// First run: the notice, to accept before anything can be installed.
struct NoticeSheet: View {
  @Bindable var installer: Installer
  @Binding var isPresented: Bool
  @State private var agreed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(spacing: 14) {
        Image(systemName: "exclamationmark.shield.fill")
          .font(.system(size: 34))
          .foregroundStyle(.orange)
          .symbolEffect(.bounce, options: .nonRepeating, value: isPresented)
        VStack(alignment: .leading, spacing: 2) {
          Text("Before you install").font(.title2.weight(.semibold))
          Text("Please read this once.").foregroundStyle(.secondary)
        }
      }
      NoticeText()
        .padding(18)
        .background(.quinary, in: .rect(cornerRadius: 16))
      Toggle("I understand, and I use SWTOR on Mac at my own risk", isOn: $agreed)
        .toggleStyle(.checkbox)
      HStack {
        // (a sheet keeps the app from quitting: this one can)
        Button("Quit") {
          isPresented = false
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NSApp.terminate(nil) }
        }
        Button("Not Now") { isPresented = false }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Continue") {
          installer.understood = true
          isPresented = false
        }
        .buttonStyle(.glassProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!agreed)
      }
      .controlSize(.large)
    }
    .padding(28)
    .frame(width: 520)
    .tint(accent)
  }
}

// MARK: - Log

struct LogSheet: View {
  let installer: Installer
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Log").font(.title2.weight(.semibold))
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(Array(installer.log.enumerated()), id: \.offset) { i, line in
              Text(line).id(i)
            }
          }
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
        }
        .background(.quinary, in: .rect(cornerRadius: 12))
        .onAppear { if !installer.log.isEmpty { proxy.scrollTo(installer.log.count - 1, anchor: .bottom) } }
        .onChange(of: installer.log.count) { _, n in if n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) } }
      }
      HStack {
        if let dir = installer.status["log_dir"] {
          Button("Show install.log in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: dir + "/install.log")])
          }
        }
        Spacer()
        Button("Done") { dismiss() }
          .buttonStyle(.glassProminent)
          .keyboardShortcut(.defaultAction)
      }
      .controlSize(.large)
    }
    .padding(24)
    .frame(minWidth: 640, idealWidth: 720, minHeight: 420, idealHeight: 520)
    .tint(accent)
  }
}

// MARK: - Footer

struct Footer: View {
  let credits: [String: String]

  var body: some View {
    HStack(spacing: 6) {
      Text("Unofficial. Not made, endorsed or supported by Broadsword Games, EA, Lucasfilm or Disney.")
      Text("·")
      Text("Developed by \(credits["author"] ?? "Jan Drlý")")
      if let link {
        Text("·")
        Link(link.absoluteString.replacingOccurrences(of: "https://", with: ""), destination: link)
          .foregroundStyle(.link)
          .pointerStyle(.link)
      }
    }
    .font(.caption)
    .foregroundStyle(.tertiary)
    .lineLimit(1)
    .minimumScaleFactor(0.8)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.bar)
    .overlay(alignment: .top) { Divider() }
  }

  private var link: URL? {
    let repo = credits["repo"] ?? "", github = credits["github"] ?? ""
    return URL(string: repo.isEmpty ? github : repo).flatMap { $0.host == nil ? nil : $0 }
  }
}
