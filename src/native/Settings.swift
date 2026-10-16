// The Settings window (SWTOR on Mac > Settings…, ⌘,), only while SWTOR on Mac is installed.
// Reads and changes the settings through Resources/som.sh (`settings`, `set <key> <value>`),
// which keeps them in settings.conf and writes the env file, dxvk.conf and the prefix's
// RetinaMode from it. They take effect the next time the game starts.

import AppKit
import SwiftUI

@MainActor @Observable
final class GameSettings {
  static let memoryProfiles: [(String, String)] = [
    ("auto", "Automatic"), ("low", "Low"), ("medium", "Medium"), ("high", "High"),
    ("ultra", "Ultra"), ("unlimited", "Unlimited"),
  ]

  private(set) var values: [String: String] = [:]
  var error: String?
  var saving = false
  // Sparkle's automatic checks follow the "updates" setting (set by SWTORonMacApp)
  var updates: Updates?

  private let script = Bundle.main.resourceURL!.appendingPathComponent("som.sh")

  var loaded: Bool { !values.isEmpty }
  var installed: Bool { values["installed"] == "yes" }
  var running: Bool { values["running"] == "yes" }

  func reload() {
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

struct SettingsView: View {
  @Bindable var settings: GameSettings

  var body: some View {
    Form {
      Section("Graphics") {
        Toggle(isOn: settings.toggle("retina")) {
          Text("Retina Mode")
          Text(settings.running
               ? "Quit the SWTOR launcher and the game to change this."
               : "Renders the game at your display's full resolution. Sharper, at some cost in frame rate.")
        }
        .disabled(settings.running)
        Toggle(isOn: settings.toggle("vsync")) {
          Text("Vsync")
          Text("Waits for the display between frames: no tearing in borderless windowed mode, frame "
               + "rate capped at the display's refresh rate.")
        }
        Picker(selection: settings.memory) {
          ForEach(GameSettings.memoryProfiles, id: \.0) { value, title in Text(title).tag(value) }
        } label: {
          Text("Video Memory Profile")
          Text("How much memory d9mt reports to the game and keeps pooled. Automatic picks by your "
               + "Mac's memory (8 GB: Low, 16 GB: Medium, 24 GB: High, more: Ultra). Lower it if "
               + "macOS runs short of memory; Unlimited is for comparisons.")
        }
      }

      Section("Game") {
        Toggle(isOn: settings.toggle("gamemode")) {
          Text("Game Mode")
          Text("While the game is in full screen, macOS gives it priority on the CPU and GPU and "
               + "lowers the latency of Bluetooth controllers and headphones.")
        }
        Toggle(isOn: settings.toggle("hud")) {
          Text("Show Metal HUD")
          Text("Apple's overlay with the frame rate and frame times, over the game. Turn it on here "
               + "before starting the game: it can't be switched with a key while the game runs.")
        }
      }

      Section("Updates") {
        Toggle(isOn: settings.toggle("updates")) {
          Text("Check for updates automatically")
          Text("SWTOR on Mac looks for a new version once a day, and so does the game's start (a "
               + "notification if there is one). Updates install only when you choose to.")
        }
      }

      Section("Troubleshooting") {
        Toggle(isOn: settings.toggle("debug")) {
          Text("Debug Logging")
          Text("Much more detailed d9mt logs (timings, memory statistics) for bug reports, at some "
               + "cost in performance. Turn it on only when asked to, and off again afterwards.")
        }
      }
    }
    .formStyle(.grouped)
    .disabled(!settings.loaded || !settings.installed)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 6) {
        if let error = settings.error {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        } else if settings.loaded && !settings.installed {
          Text("Install SWTOR on Mac first.")
            .foregroundStyle(.secondary)
        }
        Text("Changes take effect the next time the game starts.")
          .foregroundStyle(.red)
      }
      .font(.callout)
      .padding(.horizontal, 20)
      .padding(.bottom, 18)
    }
    .frame(width: 540)
    .fixedSize(horizontal: false, vertical: true)
    .onAppear { settings.reload() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      settings.reload()
    }
  }
}
