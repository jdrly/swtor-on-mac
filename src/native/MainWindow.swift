// The main window (SwiftUI, macOS 27 design) in the look of swonmac.com (Brand.swift): the
// site's jump point and warp behind the whole window (Warp.swift), the SWTOR wordmark, the state
// of this Mac as the site's spec list, and the launch panel with one big action (Install; once
// installed, Play SWTOR) and the steps (src/som.sh announces them with "@phase <n>"). The notice
// must be accepted, in a sheet, before anything can be installed; afterwards a badge in the hero
// shows it again.
//
// Resizable both ways: two columns when wide (nothing scrolls), one column when narrow (that
// column is the only scroll area). The install log is a sheet (Show Log).

import AppKit
import SwiftUI

// Shown once the install is done: d9mt compiles shaders and pipelines the first time it sees
// them and caches them.
let firstRunNote = "The first minutes of play may stutter while shaders are compiled and cached, and so may "
  + "each new area or effect the first time. After an update of SWTOR on Mac the cache is rebuilt once."

// The site's disclaimer, for this app.
let disclaimer = "SWTOR on Mac is an unofficial fan project and is not affiliated with or endorsed by "
  + "Lucasfilm, Disney, Electronic Arts or Broadsword Online Games."

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
          Hero(installer: installer, showNotice: $showNotice, wide: true)
          HStack(alignment: .top, spacing: 24) {
            // the highlights only if there is room for them
            ViewThatFits(in: .vertical) {
              VStack(alignment: .leading, spacing: 22) {
                StatusTiles(installer: installer)
                Highlights()
              }
              StatusTiles(installer: installer)
            }
            .frame(minWidth: 340, maxWidth: .infinity, alignment: .top)
            ActionPanel(installer: installer, actions: actions)
              .frame(minWidth: 380, maxWidth: 420)
          }
          .padding(.horizontal, 24)
          .padding(.top, 18)
          .padding(.bottom, 20)
          .frame(maxHeight: .infinity, alignment: .top)
        } else {
          ScrollView {
            VStack(spacing: 0) {
              Hero(installer: installer, showNotice: $showNotice, wide: false)
              VStack(alignment: .leading, spacing: 22) {
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
    // one background for the whole window, no edge between the hero and the rest
    .background { WindowBackground(quiet: installer.swtorRunning) }
    .frame(minWidth: 520, minHeight: 640)
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
  let wide: Bool
  @State private var showBadge = false

  private let tagline = "Faster graphics for the official SWTOR Mac app. Direct3D 9 goes straight to Metal, on a newer Wine."

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Group {
        if wide {
          HStack(alignment: .bottom, spacing: 32) {
            title
            Spacer(minLength: 0)
            taglineText.frame(maxWidth: 340, alignment: .leading).padding(.bottom, 4)
          }
        } else {
          VStack(alignment: .leading, spacing: 16) {
            title
            taglineText
          }
        }
      }
      .padding(.horizontal, 28)
      .padding(.top, 50)
      .padding(.bottom, 6)
      .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: 8) {
        #if SWTOR_DEV
        DevBuildBadge()
        #endif
        Button { showBadge.toggle() } label: {
          Chip(text: "Unofficial fan project", symbol: "exclamationmark.shield", fill: Brand.bg.opacity(0.8))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(disclaimer)
        .accessibilityLabel("Unofficial fan project")
        .accessibilityHint("Shows the notice")
        .popover(isPresented: $showBadge, arrowEdge: .bottom) {
          NoticeText()
            .foregroundStyle(.primary)
            .padding(20)
            .frame(width: 380)
        }
      }
      .padding(.top, 14)
      .padding(.trailing, 16)
    }
  }

  private var title: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("// Official SWTOR Mac app, accelerated")
        .font(.mono(11))
        .tracking(2)
        .textCase(.uppercase)
        .foregroundStyle(Brand.accent)
        .accessibilityLabel("Official SWTOR Mac app, accelerated")
      Wordmark(size: wide ? 60 : 52)
    }
  }

  private var taglineText: some View {
    Text(tagline)
      .font(.system(size: 15))
      .lineSpacing(3)
      .foregroundStyle(Brand.fg2)
      .fixedSize(horizontal: false, vertical: true)
  }
}

#if SWTOR_DEV
// "Dev build · 0.1.3-dev.1" next to the Unofficial badge in development builds (build.sh): the
// site's warning colour, a test build being a caution.
struct DevBuildBadge: View {
  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
  }

  var body: some View {
    Chip(text: "Dev build · \(version)", symbol: "hammer", tint: Brand.warning, fill: Brand.warningSoft,
         stroke: Brand.warning)
      .help("A test build, published only as a GitHub pre-release: Debug Logging on by default, "
            + "no automatic update checks")
      .accessibilityLabel("Development build \(version)")
  }
}
#endif

// MARK: - Status

// The state of this Mac as the site's spec list: a pip in the state's colour, a mono label, the
// value; two columns of cells in one panel.
struct StatusTiles: View {
  let installer: Installer

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionLabel(title: "This Mac") {
        if installer.loaded { HUDNote(text: summary) }
      }
      if !installer.loaded {
        HStack { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(Brand.fg2) }
          .padding(.vertical, 8)
      } else {
        let cells = tiles
        // (an empty cell evens out the last row, so no gap shows the grid's lines)
        let padded = cells.count % 2 == 1 ? cells + [nil] : cells.map { Optional($0) }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)], spacing: 1) {
          ForEach(Array(padded.enumerated()), id: \.offset) { _, tile in
            if let tile { StatusTile(tile: tile) } else { Brand.bgRaised.frame(maxWidth: .infinity, maxHeight: .infinity) }
          }
        }
        .background(Brand.border)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.border, lineWidth: 1))
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

  // "6 checks · all good", or how many need a look
  private var summary: String {
    let attention = tiles.filter { $0.tone == .warning || $0.tone == .bad }.count
    return "\(tiles.count) checks · " + (attention == 0 ? "all good" : attention == 1 ? "1 needs a look" : "\(attention) need a look")
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
                  detail: "Active · checked when SWTOR on Mac opens", tone: .good)
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
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 8) {
        StatusPip(color: color)
        Text(tile.id)
          .font(.mono(9.5))
          .tracking(1.6)
          .textCase(.uppercase)
          .foregroundStyle(Brand.fg3)
          .lineLimit(1)
      }
      Text(tile.detail)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(valueColor)
        .fixedSize(horizontal: false, vertical: true)
        .contentTransition(.opacity)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Brand.bgRaised)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(tile.id): \(tile.detail)")
  }

  private var color: Color {
    switch tile.tone {
    case .good: Brand.good
    case .warning: Brand.warning
    case .bad: Brand.bad
    case .info: Brand.fg3
    case .off: Brand.borderStrong
    }
  }

  private var valueColor: Color {
    switch tile.tone {
    case .warning: Brand.warning
    case .bad: Brand.bad
    case .off: Brand.fg2
    default: Brand.fg
    }
  }
}

// What SWTOR on Mac does, in four lines (fills the left column under the tiles).
struct Highlights: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionLabel(title: "What it does") { HUDNote(text: "04 modules") }
      Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 10) {
        GridRow {
          item("bolt", "Direct3D 9 straight to Metal", "d9mt replaces the official app's graphics layer.")
          item("gamecontroller", "Game Mode", "macOS gives the game priority while it is in full screen.")
        }
        GridRow {
          item("arrow.triangle.2.circlepath", "After launcher updates", "Hooks itself back in the next time you open SWTOR on Mac after a launcher update.")
          item("arrow.uturn.backward", "Fully reversible", "Uninstall puts the official app back exactly as Broadsword ships it.")
        }
      }
    }
  }

  private func item(_ symbol: String, _ title: String, _ text: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 8) {
        Image(systemName: symbol)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Brand.accent)
          .frame(width: 16)
        Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.fg)
      }
      Text(text)
        .font(.system(size: 12))
        .foregroundStyle(Brand.fg2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.top, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .top) { Rectangle().fill(Brand.borderStrong).frame(height: 1) }
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Install panel

struct ActionPanel: View {
  @Bindable var installer: Installer
  let actions: PanelActions

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      SectionLabel(title: installer.installed && !installer.isBusy ? "Launch" : installer.operation == .uninstall && installer.isBusy ? "Uninstall" : "Install") {
        stateChip
      }
      PrimaryAction(installer: installer, actions: actions)
      if installer.loaded, !installer.isBusy, installer.leftovers {
        LeftoversNote(installer: installer, end: actions.endLeftovers)
      } else if let note = blockingNote {
        Label(note, systemImage: "pause.circle.fill")
          .font(.callout)
          .foregroundStyle(Brand.warning)
          .fixedSize(horizontal: false, vertical: true)
      }
      if installer.installed, installer.showBackgroundNote {
        BackgroundNote(installer: installer)
      }
      if case .succeeded = installer.phase {
        // done: the steps fold into one line of checkmarks
        CompactTimeline(count: installer.steps.count)
          .transition(.opacity)
      } else if showTimeline {
        Rectangle().fill(Brand.border).frame(height: 1)
        Timeline(installer: installer)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
      Outcome(installer: installer)
      if installer.installed && installer.phase == .idle {
        Rectangle().fill(Brand.border).frame(height: 1)
        ReadyNote()
      }
      if !installer.log.isEmpty {
        Button(action: actions.showLog) {
          Label("Show Log", systemImage: "text.alignleft")
            .font(.mono(10))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(Brand.fg2)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .brandPanel()
  }

  // Top right of the panel: installed and its version, working, or not installed
  @ViewBuilder private var stateChip: some View {
    if installer.isBusy {
      Chip(text: "Working", pip: Brand.accent)
    } else if installer.installed {
      Chip(text: "Installed · \(installer.status["installed_version"] ?? "?")", pip: installer.installedOtherVersion ? Brand.warning : Brand.good)
    } else if installer.loaded {
      Chip(text: "Not installed", pip: Brand.fg3)
    }
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
        .foregroundStyle(Brand.warning)
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

// macOS ended what the launcher left running when it quit, the game's Wine with it, because the
// launcher is not allowed in the background (Installer.checkBackground, when the app opens): say
// so, with the setting to change and a button to it. Dismiss hides it until it happens again.
struct BackgroundNote: View {
  let installer: Installer

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("macOS ended the game's Wine when the SWTOR launcher quit (\(when)), so the game could not "
            + "open its window. The launcher is not allowed to run in the background. In System Settings > "
            + "Login Items, under App Background Activity, turn on Star Wars - The Old Republic (it may be "
            + "listed as Broadsword), then press Play SWTOR again.",
            systemImage: "exclamationmark.triangle.fill")
        .font(.callout)
        .foregroundStyle(Brand.warning)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 10) {
        Button { NSWorkspace.shared.open(Installer.loginItemsSettings) } label: {
          Label("Open Login Items", systemImage: "gearshape")
        }
        .buttonStyle(.glass)
        .pointerStyle(.link)
        Button("Dismiss") { installer.dismissBackgroundNote() }
          .buttonStyle(.plain)
          .foregroundStyle(Brand.fg2)
          .pointerStyle(.link)
      }
    }
  }

  // "Oct 25, 2026 at 6:04 PM", or "3 times in the last 24 hours, last Oct 25, 2026 at 6:04 PM"
  private var when: String {
    let ends = installer.backgroundEnds
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let last = ends.last.flatMap { parser.date(from: $0) }
      .map { $0.formatted(date: .abbreviated, time: .shortened) } ?? ends.last ?? ""
    return ends.count > 1 ? "\(ends.count) times in the last 24 hours, last \(last)" : last
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
    }
    .buttonStyle(.brandPrimary)
    .keyboardShortcut(.defaultAction)
    .pointerStyle(.link)
  }

  // "Installing… 42%" with the overall progress, and Cancel (an install rolls back; an
  // uninstall is quick and runs to the end)
  private var working: some View {
    HStack(spacing: 8) {
      VStack(spacing: 0) {
        HStack {
          Text(installer.operation == .install ? "Installing…" : "Uninstalling…")
            .font(.mono(13, .bold, relativeTo: .title3))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(Brand.fg)
          Spacer(minLength: 0)
          Text("\(Int((installer.fraction * 100).rounded()))%")
            .font(.mono(13, .bold, relativeTo: .title3).monospacedDigit())
            .foregroundStyle(Brand.accent)
            .contentTransition(.numericText(value: installer.fraction))
            .animation(.snappy, value: installer.fraction)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        GeometryReader { bar in
          ZStack(alignment: .leading) {
            Rectangle().fill(Brand.border)
            Rectangle().fill(Brand.accent).frame(width: bar.size.width * installer.fraction)
              .animation(.smooth, value: installer.fraction)
          }
        }
        .frame(height: 3)
      }
      .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
      .background(Brand.surface, in: .rect(cornerRadius: 6))
      .clipShape(.rect(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.borderStrong, lineWidth: 1))
      .accessibilityElement(children: .combine)
      .accessibilityLabel("\(installer.operation == .install ? "Installing" : "Uninstalling"), \(Int(installer.fraction * 100)) percent")
      if installer.phase == .working(.install) {
        Button { installer.cancel() } label: { Text("Cancel").foregroundStyle(Brand.fg) }
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
          Button(action: actions.install) { Label("Reinstall", systemImage: "arrow.clockwise").foregroundStyle(Brand.fg) }
            .disabled(!installer.canInstall)
        }
        Button(action: actions.settings) { Label("Settings", systemImage: "slider.horizontal.3").foregroundStyle(Brand.fg) }
        Spacer(minLength: 0)
        // (neutral: red is the brand's action colour here; the alert that follows is destructive)
        Button(role: .destructive, action: actions.uninstall) {
          Label("Uninstall…", systemImage: "trash").foregroundStyle(Brand.fg2)
        }
        .disabled(!installer.canUninstall)
      }
      .buttonStyle(.glass)
      .controlSize(.large)
      .pointerStyle(.link)
    }
  }

  // Why Play can't go ahead, if it can't (the panel's chip shows the version)
  @ViewBuilder private var installedLine: some View {
    if case .unavailable(let reason) = installer.playAction, installer.loaded {
      Label(reason, systemImage: "exclamationmark.circle.fill")
        .font(.callout)
        .foregroundStyle(Brand.warning)
        .fixedSize(horizontal: false, vertical: true)
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
    let play = installer.playButtonAction
    let button = Button(action: action) {
      if installer.launching {
        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Opening SWTOR…") }
      } else {
        Label(title(play), systemImage: symbol(play))
      }
    }
    .disabled(!enabled(play) || installer.launching)
    .accessibilityLabel(installer.launching ? "Opening SWTOR" : title(play))
    .accessibilityHint(hint(play))
    .help(hint(play))
    .pointerStyle(.link)
    if prominent {
      button
        .buttonStyle(.brandPrimary)
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
            Rectangle().fill(Brand.border)
            Rectangle().fill(state == .done ? Brand.good : Brand.accent)
              .scaleEffect(x: 1, y: fill, anchor: .top)
          }
          .frame(width: 2)
          .frame(minHeight: 18, maxHeight: .infinity)
          .padding(.vertical, 4)
        }
      }
      .frame(width: 30)
      VStack(alignment: .leading, spacing: 4) {
        Text(step.title)
          .font(.system(size: 13, weight: state == .active ? .semibold : .regular))
          .foregroundStyle(state == .pending ? Brand.fg2 : Brand.fg)
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
          Text("\(p.label) · \(mb(p.done)) of \(mb(p.total))")
            .font(.mono(9.5, .medium).monospacedDigit())
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(Brand.accent)
            .contentTransition(.numericText(value: Double(p.done)))
        }
      } else {
        Text(step.detail).font(.system(size: 11.5)).foregroundStyle(Brand.fg2)
          .fixedSize(horizontal: false, vertical: true)
      }
    case .failed:
      if case .failed(_, let message) = installer.phase {
        Text(message).font(.system(size: 11.5)).foregroundStyle(Brand.bad).fixedSize(horizontal: false, vertical: true)
      }
    default:
      Text(step.detail).font(.system(size: 11.5)).foregroundStyle(Brand.fg3).fixedSize(horizontal: false, vertical: true)
    }
  }

  private func stateName(_ s: State) -> String {
    switch s { case .pending: "to do"; case .active: "in progress"; case .done: "done"; case .failed: "failed" }
  }

  private func mb(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

// A step's node: a square with the step's number in mono, as the site's numbered lists. Pending:
// a hairline frame; active: the accent, its frame breathing; done: green with a check; failed:
// red with a cross.
struct TimelineNode: View {
  let number: Int
  let symbol: String
  let state: Timeline.State
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var breathe = false

  var body: some View {
    ZStack {
      switch state {
      case .pending:
        RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.borderStrong, lineWidth: 1.5)
        numberText.foregroundStyle(Brand.fg3)
      case .active:
        RoundedRectangle(cornerRadius: 4).fill(Brand.accentSoft)
        RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.accent, lineWidth: 1.5)
          .opacity(breathe ? 0.45 : 1)
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: breathe)
          .onAppear { breathe = !reduceMotion }
        numberText.foregroundStyle(Brand.accent)
      case .done:
        RoundedRectangle(cornerRadius: 4).fill(Brand.good)
        Image(systemName: "checkmark")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white)
          .transition(.scale.combined(with: .opacity))
          .symbolEffect(.bounce, options: .nonRepeating, value: state)
      case .failed:
        RoundedRectangle(cornerRadius: 4).fill(Brand.bad)
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white)
          .transition(.scale.combined(with: .opacity))
      }
    }
    .frame(width: 28, height: 28)
  }

  private var numberText: some View {
    Text(String(format: "%02d", number)).font(.mono(10.5)).tracking(0.5)
  }
}

// A finished operation: its steps as a row of green squares.
struct CompactTimeline: View {
  let count: Int
  @State private var shown = false

  var body: some View {
    HStack(spacing: 6) {
      ForEach(0..<count, id: \.self) { i in
        Image(systemName: "checkmark")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 20, height: 20)
          .background(Brand.good, in: .rect(cornerRadius: 3))
          .symbolEffect(.bounce, options: .nonRepeating, value: shown)
        if i < count - 1 {
          Rectangle().fill(Brand.good).frame(height: 2).frame(maxWidth: 28)
        }
      }
      Text("All \(count) steps done")
        .font(.mono(9.5))
        .tracking(1.6)
        .textCase(.uppercase)
        .foregroundStyle(Brand.fg2)
        .padding(.leading, 6)
        .fixedSize()
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
          .foregroundStyle(Brand.good)
          .fixedSize(horizontal: false, vertical: true)
        if op == .install {
          Label(firstRunNote, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(Brand.fg2)
            .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(installer.warnings, id: \.self) { w in
          Label(w, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    case .failed(_, let message) where installer.stepIndex == nil:
      // failed before the first step
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(Brand.bad)
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
      Label("Press Play SWTOR, or start the official SWTOR app as usual. The game runs on SWTOR on "
            + "Mac's engine.",
            systemImage: "play.circle")
      Label(firstRunNote, systemImage: "info.circle")
    }
    .font(.system(size: 12.5))
    .foregroundStyle(Brand.fg2)
    .lineSpacing(2)
    .fixedSize(horizontal: false, vertical: true)
  }
}

// MARK: - Notice

struct NoticeText: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("SWTOR on Mac is an unofficial fan project.")
        .font(.headline)
        .foregroundStyle(.primary)
      Text("It is not affiliated with or endorsed by Lucasfilm, Disney, Electronic Arts or Broadsword "
           + "Online Games. Broadsword doesn't support third-party tools or compatibility layers, so you "
           + "use it at your own risk.")
      Text("It's not a game mod: it doesn't change the game's files, memory or network traffic. It only "
           + "replaces the compatibility layer the official Mac app already runs on (Wine, plus d9mt for "
           + "Direct3D 9 on Metal), and Uninstall puts that back the way Broadsword ships it.")
      // a LocalizedStringKey, so the Markdown link renders
      Text(LocalizedStringKey("For help, create a post in #swtor-on-mac-issues on the [SWTOR on Mac "
           + "Discord](\(AppActions.discord.absoluteString)) and tag @Pharaphobia, or open a GitHub issue. "
           + "Please don't send logs or bug reports about SWTOR on Mac to Broadsword or SWTOR customer support."))
      Text("STAR WARS is a registered trademark of Lucasfilm Ltd. Star Wars: The Old Republic and SWTOR "
           + "are trademarks of their respective owners. Mac is a trademark of Apple Inc.")
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
  }
}

// MARK: - Footer

struct Footer: View {
  let credits: [String: String]

  var body: some View {
    HStack(spacing: 8) {
      Text(disclaimer)
        .help(disclaimer)
      if let link {
        Text("·").accessibilityHidden(true)
        Link(destination: link) {
          HStack(spacing: 3) {
            Text(link.absoluteString.replacingOccurrences(of: "https://", with: ""))
            Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
          }
          .foregroundStyle(Brand.fg2)
        }
        .pointerStyle(.link)
        .fixedSize()
      }
    }
    .font(.system(size: 10.5))
    .foregroundStyle(Brand.fg3)
    .lineLimit(1)
    .truncationMode(.tail)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .overlay(alignment: .top) { Rectangle().fill(Brand.border).frame(height: 1) }
  }

  private var link: URL? {
    let repo = credits["repo"] ?? "", github = credits["github"] ?? ""
    return URL(string: repo.isEmpty ? github : repo).flatMap { $0.host == nil ? nil : $0 }
  }
}
