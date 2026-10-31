// The Settings window (SWTOR on Mac > Settings…, ⌘,), only while SWTOR on Mac is installed:
// a sidebar of panes (SettingsPane), the selected one's settings next to it.
// Reads and changes the settings through Resources/som.sh (`settings`, `set <key> <value>`),
// which keeps them in settings.conf and writes the env file, dxvk.conf, the prefix's Mac
// driver options (RetinaMode, PhysicalKeyboard, raw mouse-look and its speed) and the engine's
// Mac driver from it. They take effect the
// next time the game starts. "Quit SWTOR on Mac after launching" is the app's own
// (UserDefaults).

import AppKit
import Carbon
import SwiftUI

// What the current keyboard layout types on the number row without modifiers, if that isn't
// 1–0 (Czech: "+ ě š č ř ž ý á í é"): then "Game keys by keyboard position" is worth turning
// on, and Settings says so.
enum NumberRow {
  // Mac key codes of the number row, 1 to 0 (kVK_ANSI_1 ... kVK_ANSI_0)
  private static let keyCodes: [UInt16] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]

  static func nonDigitLayout() -> (name: String, keys: String)? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    let typed: [String] = data.withUnsafeBytes { bytes in
      guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return [] }
      return keyCodes.map { code in
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, chars.count,
                                    &length, &chars)
        return status == noErr ? String(utf16CodeUnits: chars, count: length) : ""
      }
    }
    guard typed.count == keyCodes.count, typed.joined() != "1234567890" else { return nil }
    let name = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
      .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "Your keyboard layout"
    return (name, typed.joined(separator: " "))
  }
}

@MainActor @Observable
final class GameSettings {
  static let memoryProfiles: [(String, String)] = [
    ("auto", "Automatic"), ("low", "Low"), ("medium", "Medium"), ("high", "High"),
    ("ultra", "Ultra"), ("unlimited", "Unlimited"),
  ]

  private(set) var values: [String: String] = [:]
  // the current keyboard layout, if its number row doesn't type 1–0 (looked at on reload)
  private(set) var nonDigitLayout: (name: String, keys: String)?
  var error: String?
  var saving = false
  // Sparkle's automatic checks follow the "updates" setting (set by SWTORonMacApp)
  var updates: Updates?

  private let script = Bundle.main.resourceURL!.appendingPathComponent("som.sh")

  var loaded: Bool { !values.isEmpty }
  var installed: Bool { values["installed"] == "yes" }
  var running: Bool { values["running"] == "yes" }

  func reload() {
    nonDigitLayout = NumberRow.nonDigitLayout()
    Task {
      let output = await Installer.capture(script: script, arguments: ["settings"])
      var parsed: [String: String] = [:]
      for line in output.split(separator: "\n") {
        guard let eq = line.firstIndex(of: "=") else { continue }
        parsed[String(line[..<eq])] = String(line[line.index(after: eq)...])
      }
      values = parsed
      // Sparkle follows the setting (it lives in settings.conf, which survives app updates)
      if let updates, let value = parsed["updates"], parsed["installed"] == "yes" {
        updates.automaticChecks = value == "on"
      }
    }
  }

  func toggle(_ key: String) -> Binding<Bool> {
    Binding(get: { self.values[key] == "on" }, set: { self.set(key, $0 ? "on" : "off") })
  }

  var memory: Binding<String> {
    Binding(get: { self.values["memory"] ?? "auto" }, set: { self.set("memory", $0) })
  }

  // Frame Rate Limit: d9mt's cap for the game (som.sh FPS_LIMITS)
  static let fpsLimits: [(String, String)] = [
    ("off", "Off"), ("30", "30 fps"), ("40", "40 fps"), ("45", "45 fps"), ("60", "60 fps"),
  ]

  var fpsLimit: Binding<String> {
    Binding(get: { self.values["fpslimit"] ?? "off" }, set: { self.set("fpslimit", $0) })
  }

  // Mouse-Look Speed: a factor on the macOS pointer's speed (som.sh MOUSE_SPEEDS)
  static let mouseSpeeds = ["0.5", "0.75", "1", "1.25", "1.5", "1.75", "2", "2.5", "3"]

  var mouseSpeed: Binding<String> {
    Binding(get: { self.values["mousespeed"] ?? "1" }, set: { self.set("mousespeed", $0) })
  }

  // Metal HUD Position: MTL_HUD_ALIGNMENT (som.sh HUD_POSITIONS, libMTLHud's values)
  static let hudPositions: [(String, String)] = [
    ("topleft", "Top Left"), ("topcenter", "Top Center"), ("topright", "Top Right"),
    ("centerleft", "Center Left"), ("centered", "Centered"), ("centerright", "Center Right"),
    ("bottomleft", "Bottom Left"), ("bottomcenter", "Bottom Center"), ("bottomright", "Bottom Right"),
  ]

  var hudPosition: Binding<String> {
    Binding(get: { self.values["hudpos"] ?? "topcenter" }, set: { self.set("hudpos", $0) })
  }

  private func set(_ key: String, _ value: String) {
    let previous = values[key]
    values[key] = value
    error = nil
    saving = true
    if key == "updates" { updates?.automaticChecks = value == "on" }
    let script = script
    Task {
      let output = await Installer.capture(script: script, arguments: ["set", key, value])
      saving = false
      if !output.contains("@done ") {
        values[key] = previous
        if key == "updates" { updates?.automaticChecks = previous != "off" }
        error = output.split(separator: "\n").first { $0.hasPrefix("@error ") }.map { String($0.dropFirst(7)) }
          ?? "The setting could not be saved."
      }
      reload()
    }
  }
}

// The panes of the Settings window, in sidebar order. A new pane (e.g. Advanced, for the Wine
// engine) is a case here, its title and symbol, whether it changes the game, and its sections
// in SettingsView.sections(for:).
enum SettingsPane: String, CaseIterable, Identifiable {
  case graphics, game, keyboard, mouse, playButton, updates, troubleshooting

  var id: Self { self }

  var title: String {
    switch self {
    case .graphics: "Graphics"
    case .game: "Game"
    case .keyboard: "Keyboard"
    case .mouse: "Mouse"
    case .playButton: "Play Button"
    case .updates: "Updates"
    case .troubleshooting: "Troubleshooting"
    }
  }

  var symbol: String {
    switch self {
    case .graphics: "sparkles.tv"
    case .game: "gamecontroller"
    case .keyboard: "keyboard"
    case .mouse: "computermouse"
    case .playButton: "play.circle"
    case .updates: "arrow.down.circle"
    case .troubleshooting: "stethoscope"
    }
  }

  // settings.conf settings the game reads when it starts (not the app's own Play Button
  // preference, and not Updates, which Sparkle follows at once)
  var appliesAtNextGameStart: Bool {
    switch self {
    case .graphics, .game, .keyboard, .mouse, .troubleshooting: true
    case .playButton, .updates: false
    }
  }
}

struct SettingsView: View {
  static let selectedPaneKey = "settingsPane"

  @Bindable var settings: GameSettings
  // the app's own preference (UserDefaults, not settings.conf; Play.swift)
  @AppStorage(Installer.quitAfterLaunchKey) private var quitAfterLaunch = false
  // the pane shown last time
  @AppStorage(Self.selectedPaneKey) private var selectedPane: SettingsPane = .graphics
  // the sidebar has the keyboard focus when the window opens: ↑ ↓ switch panes
  @FocusState private var sidebarFocused: Bool

  var body: some View {
    NavigationSplitView {
      List(SettingsPane.allCases, selection: Binding(get: { selectedPane }, set: { if let p = $0 { selectedPane = p } })) { pane in
        Label(pane.title, systemImage: pane.symbol)
      }
      .accessibilityLabel("Settings sections")
      .focused($sidebarFocused)
      .safeAreaInset(edge: .bottom, spacing: 0) { SidebarBrand() }
      .toolbar(removing: .sidebarToggle)
      .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 260)
    } detail: {
      Form {
        sections(for: selectedPane)
          .disabled(!settings.loaded || !settings.installed)
        notes(for: selectedPane)
      }
      .formStyle(.grouped)
      .navigationTitle(selectedPane.title)
    }
    .frame(minWidth: 640, minHeight: 400)
    .onAppear {
      settings.reload()
      sidebarFocused = true
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      settings.reload()
    }
  }

  // Under the pane's settings: a failed save, why everything is disabled, and (once per pane,
  // for the panes whose settings the game reads) when changes apply.
  @ViewBuilder private func notes(for pane: SettingsPane) -> some View {
    let notInstalled = settings.loaded && !settings.installed
    if settings.error != nil || notInstalled || pane.appliesAtNextGameStart {
      Section {
      } footer: {
        VStack(alignment: .leading, spacing: 8) {
          if let error = settings.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
          } else if notInstalled {
            Label("Install SWTOR on Mac first.", systemImage: "exclamationmark.circle")
          }
          if pane.appliesAtNextGameStart {
            Label("Changes take effect the next time the game starts.", systemImage: "info.circle")
          }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var gameRunningNote: String { "Quit the SWTOR launcher and the game to change this." }

  @ViewBuilder private func sections(for pane: SettingsPane) -> some View {
    switch pane {
    case .graphics:
      Section {
        Toggle(isOn: settings.toggle("retina")) {
          Text("Retina Mode")
          Text(settings.running
               ? gameRunningNote
               : "Renders the game at your display's full resolution. Sharper, at some cost in frame rate.")
        }
        .disabled(settings.running)
        Toggle(isOn: settings.toggle("vsync")) {
          Text("Vsync")
          Text("Waits for the display between frames: no tearing in borderless windowed mode, frame "
               + "rate capped at the display's refresh rate.")
        }
      }
      Section {
        Picker(selection: settings.fpsLimit) {
          ForEach(GameSettings.fpsLimits, id: \.0) { value, title in Text(title).tag(value) }
        } label: {
          Text("Frame Rate Limit")
          Text("A steady, lower frame rate for less heat and a longer battery life: the Mac stays "
               + "cooler, so a long session keeps its frame rate instead of throttling. 30 is even "
               + "on a 60 or 120 Hz display (every frame stays on screen for two or four refreshes). 40 and "
               + "45 keep the load even but show frames unevenly on a 60 Hz display; 40 is even on "
               + "a 120 Hz ProMotion display. 60 limits only with Vsync off or on a faster display.")
        }
        Toggle(isOn: settings.toggle("fpsbattery")) {
          Text("Only on battery")
          Text("Limits the frame rate only if your Mac runs on battery when the game starts.")
        }
        .disabled((settings.values["fpslimit"] ?? "off") == "off")
      }
      Section {
        Picker(selection: settings.memory) {
          ForEach(GameSettings.memoryProfiles, id: \.0) { value, title in Text(title).tag(value) }
        } label: {
          Text("Video Memory Profile")
          Text("Automatic picks by your Mac's memory: 8 GB → Low (2 GB for the game), 16 GB → "
               + "Medium (3 GB), 24 GB → High (4 GB), more → Ultra (4 GB). Raise it if you have "
               + "headroom and want sharper textures in busy places; lower it if macOS runs short "
               + "of memory. Unlimited is for comparisons.")
        }
      }
      Section {
        // d9mt's flush cap, D9MT_FLUSH_CAP=1 for the game (som.sh flushcap)
        Toggle(isOn: settings.toggle("flushcap")) {
          Text("Fewer GPU Batches (Experimental)")
          Text("Sends each frame to the GPU in fewer, larger batches, so less data moves through "
               + "memory. Recommended for lower-end MacBooks and MacBook Airs. Turn it off if the "
               + "game stutters more.")
        }
      }

    case .game:
      Section {
        Toggle(isOn: settings.toggle("gamemode")) {
          Text("Game Mode")
          Text("While the game is in full screen, macOS gives it priority on the CPU and GPU and "
               + "lowers the latency of Bluetooth controllers and headphones.")
        }
        Toggle(isOn: settings.toggle("hud")) {
          Text("Show Metal HUD")
          Text("Apple's overlay with the frame rate and frame times, over the game, from the next "
               + "game start. In the game, Shift+F9 hides and shows it. Shift+F12, or three quick "
               + "clicks on the HUD (also while it is hidden), open macOS's HUD settings panel.")
        }
        Picker(selection: settings.hudPosition) {
          ForEach(GameSettings.hudPositions, id: \.0) { value, title in Text(title).tag(value) }
        } label: {
          Text("Metal HUD Position")
          Text("Where the HUD sits. Top Center keeps it away from the buttons you click quickly, "
               + "such as Randomize in character creation.")
        }
        .disabled(settings.values["hud"] != "on")
      }

    case .keyboard:
      Section {
        Toggle(isOn: settings.toggle("physkeys")) {
          Text("Game keys by keyboard position")
          Text(settings.running
               ? gameRunningNote
               : "For non-US layouts (Czech, German, French…): the game sees keys by their position "
                 + "on a US keyboard, so the number row is 1–0 in key binds and action bars. Typing "
                 + "in chat still uses your layout.")
        }
        .disabled(settings.running)
      } footer: {
        if let layout = settings.nonDigitLayout, settings.values["physkeys"] != "on" {
          Label("Your keyboard layout (\(layout.name)) types \(layout.keys) on the number row: "
                + "turn this on to have 1–0 in the game.", systemImage: "keyboard")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

    case .mouse:
      Section {
        Toggle(isOn: settings.toggle("rawmouse")) {
          Text("Raw mouse-look")
          Text(settings.running
               ? gameRunningNote
               : "While you hold a mouse button to turn the camera, the game gets every movement of "
                 + "the mouse as it happens, straight from the mouse, instead of once per screen "
                 + "refresh, and the pointer stays put. Turn it off to compare with the previous "
                 + "behavior.")
        }
        .disabled(settings.running)
        Picker(selection: settings.mouseSpeed) {
          ForEach(GameSettings.mouseSpeeds, id: \.self) { speed in
            Text(speed == "1" ? "1× (as fast as the pointer)" : "\(speed)×").tag(speed)
          }
        } label: {
          Text("Mouse-Look Speed")
          Text(settings.running
               ? gameRunningNote
               : "How fast the camera turns with raw mouse-look, compared with your pointer speed "
                 + "in System Settings. The game's own mouse sensitivity applies on top.")
        }
        .disabled(settings.running || settings.values["rawmouse"] != "on")
      }

    case .playButton:
      Section {
        Toggle(isOn: $quitAfterLaunch) {
          Text("Quit SWTOR on Mac after launching")
          Text("Play SWTOR opens the official SWTOR app, then SWTOR on Mac quits. It doesn't need "
               + "to stay open while you play.")
        }
      }

    case .updates:
      Section {
        #if SWTOR_DEV
          Toggle(isOn: .constant(false)) {
            Text("Check for updates automatically")
            Text("Off in development builds. SWTOR on Mac > Check for Updates… still offers a newer "
                 + "public version, never an older one.")
          }
          .disabled(true)
        #else
          Toggle(isOn: settings.toggle("updates")) {
            Text("Check for updates automatically")
            Text("SWTOR on Mac looks for a new version once a day, and so does the game's start (a "
                 + "notification if there is one). Updates install only when you choose to.")
          }
        #endif
      }

    case .troubleshooting:
      Section {
        Toggle(isOn: settings.toggle("debug")) {
          Text("Debug Logging")
          #if SWTOR_DEV
          Text("On by default in development builds: d9mt logs frame times, hitches, render-pass and "
               + "memory statistics, the Mac driver the game's CPU time per thread and raw mouse-look "
               + "statistics, for the test session (scripts/session-report.sh, Collect Logs). Costs a "
               + "little performance.")
          #else
          Text("Much more detailed d9mt logs (timings, memory statistics) for bug reports, at some "
               + "cost in performance. Turn it on only when asked to, and off again afterwards.")
          #endif
        }
      }
    }
  }
}

// The foot of the Settings sidebar: the wordmark small, and the versions (selectable, for bug
// reports). The rest of the window is a stock macOS settings window.
struct SidebarBrand: View {
  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Divider()
      HStack(alignment: .lastTextBaseline, spacing: 7) {
        Text("SWTOR")
          .font(.display(16, relativeTo: .headline))
          .tracking(-0.6)
          .foregroundStyle(Brand.fg)
        Text("ON MAC")
          .font(.display(8.5, .regular, relativeTo: .caption2))
          .tracking(2.4)
          .foregroundStyle(Brand.accent)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("SWTOR on Mac")
      Text(([version] + [AppActions.componentVersions().components(separatedBy: " · ").first ?? ""])
        .filter { !$0.isEmpty }.joined(separator: " · "))
        .font(.mono(9, .medium))
        .tracking(0.6)
        .foregroundStyle(Brand.fg3)
        .textSelection(.enabled)
        .lineLimit(1)
    }
    .padding(.horizontal, 18)
    .padding(.bottom, 14)
  }
}
