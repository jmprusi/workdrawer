//
//  SettingsView.swift
//  WorkDrawer
//
//  Created by Joaquim Moreno Prusi on 16/2/26.
//

import SwiftUI
import Combine
import Carbon
import ServiceManagement

enum AppTheme: String, CaseIterable {
    case light = "Light"
    case dark = "Dark"
    case auto = "Auto"

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil
        }
    }
}

class ThemePreferences: ObservableObject {
    static let shared = ThemePreferences()

    @Published var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "appTheme")
            NotificationCenter.default.post(name: .themeChanged, object: nil)
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "appTheme") ?? "Auto"
        currentTheme = AppTheme(rawValue: saved) ?? .auto
    }
}

class FontPreferences: ObservableObject {
    static let shared = FontPreferences()

    @Published var fontSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(fontSize), forKey: "editorFontSize") }
    }

    @Published var fontFamily: String {
        didSet { UserDefaults.standard.set(fontFamily, forKey: "editorFontFamily") }
    }

    init() {
        let size = UserDefaults.standard.double(forKey: "editorFontSize")
        fontSize = size > 0 ? CGFloat(size) : 14
        fontFamily = UserDefaults.standard.string(forKey: "editorFontFamily") ?? ""
    }
}

class ShortcutPreferences: ObservableObject {
    static let shared = ShortcutPreferences()

    var keyCode: UInt32? {
        get {
            let value = UserDefaults.standard.integer(forKey: "shortcutKeyCode")
            return value == 0 ? nil : UInt32(value)
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(Int(v), forKey: "shortcutKeyCode")
            } else {
                UserDefaults.standard.removeObject(forKey: "shortcutKeyCode")
            }
        }
    }

    var modifiers: UInt32 {
        get { UInt32(UserDefaults.standard.integer(forKey: "shortcutModifiers")) }
        set { UserDefaults.standard.set(Int(newValue), forKey: "shortcutModifiers") }
    }

    init() {
        if UserDefaults.standard.object(forKey: "shortcutKeyCode") == nil {
            UserDefaults.standard.set(Int(kVK_Space), forKey: "shortcutKeyCode")
            UserDefaults.standard.set(Int(cmdKey | shiftKey), forKey: "shortcutModifiers")
        }
    }
}

struct SettingsView: View {
    @StateObject private var themePrefs = ThemePreferences.shared
    @StateObject private var fontPrefs = FontPreferences.shared
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var openBehavior = UserDefaults.standard.string(forKey: "openBehavior") ?? "mouseCursor"
    @State private var savePath = UserDefaults.standard.string(forKey: "savePath") ?? ""

    private let fontFamilies = ["System Default"] + NSFontManager.shared.availableFontFamilies

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $themePrefs.currentTheme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Behavior") {
                LabeledContent("Keyboard Shortcut") {
                    ShortcutRecorderView()
                }
                
                Picker("Open on screen of", selection: $openBehavior) {
                    Text("Mouse Cursor").tag("mouseCursor")
                    Text("Focused Window").tag("focusedWindow")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: openBehavior) { _, new in
                    UserDefaults.standard.set(new, forKey: "openBehavior")
                }

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Failed to update launch at login: \(error)")
                        }
                    }
            }

            Section("Editor") {
                Picker("Font", selection: $fontPrefs.fontFamily) {
                    ForEach(fontFamilies, id: \.self) { family in
                        Text(family).tag(family == "System Default" ? "" : family)
                    }
                }

                Stepper("Size: \(Int(fontPrefs.fontSize))pt", value: $fontPrefs.fontSize, in: 10...32, step: 1)
            }

            Section("Save Location") {
                HStack {
                    Text(savePath.isEmpty ? "Default (Application Support/WorkDrawer)" : savePath)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose...") {
                        chooseSavePath()
                    }
                    if !savePath.isEmpty {
                        Button("Reset") {
                            savePath = ""
                            UserDefaults.standard.removeObject(forKey: "savePath")
                            NotificationCenter.default.post(name: .savePathChanged, object: nil)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 500)
    }

    func chooseSavePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            savePath = url.path
            UserDefaults.standard.set(url.path, forKey: "savePath")
            NotificationCenter.default.post(name: .savePathChanged, object: nil)
        }
    }
}
