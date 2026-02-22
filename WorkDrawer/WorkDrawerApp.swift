//
//  WorkDrawerApp.swift
//  WorkDrawer
//
//  Created by Joaquim Moreno Prusi on 16/2/26.
//

import SwiftUI
import Carbon

@main
struct WorkDrawerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var settingsWindow: NSWindow?
    var eventMonitor: Any?
    var hotKeyRef: EventHotKeyRef?
    var statusItem: NSStatusItem?
    var eventHandlerRef: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusBarItem()
        setupHotKey()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutChanged),
            name: .shortcutChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeChanged),
            name: .themeChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let preferences = ShortcutPreferences.shared
        print("WorkDrawer started. Press \(shortcutDescription(preferences.keyCode, preferences.modifiers)) to show/hide.")
    }

    @objc func shortcutChanged() {
        unregisterHotKey()
        setupHotKey()
    }

    @objc func themeChanged() {
        updateWindowAppearance()
    }

    @objc func screenParametersChanged() {
        updateWindowFrame()
    }

    func mouseScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func focusedWindowScreen() -> NSScreen {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return mouseScreen() }
        let pid = frontApp.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return mouseScreen() }

        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0

        for windowInfo in windowList {
            guard let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                  windowPID == pid,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] else { continue }

            let cgX = boundsDict["X"] ?? 0
            let cgY = boundsDict["Y"] ?? 0
            let cgWidth = boundsDict["Width"] ?? 0
            let cgHeight = boundsDict["Height"] ?? 0

            let nsY = primaryScreenHeight - cgY - cgHeight
            let windowFrame = CGRect(x: cgX, y: nsY, width: cgWidth, height: cgHeight)

            if let screen = NSScreen.screens.first(where: { $0.frame.intersects(windowFrame) }) {
                return screen
            }
        }
        return mouseScreen()
    }

    func activeScreen() -> NSScreen {
        let behavior = UserDefaults.standard.string(forKey: "openBehavior") ?? "mouseCursor"
        return behavior == "focusedWindow" ? focusedWindowScreen() : mouseScreen()
    }

    func updateWindowFrame() {
        guard let window = window else { return }
        let screenRect = activeScreen().visibleFrame
        let windowRect = NSRect(
            x: screenRect.minX,
            y: screenRect.minY,
            width: screenRect.width,
            height: screenRect.height / 2
        )
        window.setFrame(windowRect, display: true)
    }

    func updateWindowAppearance() {
        let theme = ThemePreferences.shared.currentTheme
        let appearance: NSAppearance?

        switch theme {
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        case .auto:
            appearance = nil
        }

        window?.appearance = appearance
        settingsWindow?.appearance = appearance
    }

    func shortcutDescription(_ keyCode: UInt32?, _ modifiers: UInt32) -> String {
        guard let keyCode = keyCode else { return "no shortcut set" }

        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Cmd") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("Ctrl") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Option") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }

        switch Int(keyCode) {
        case kVK_Space: parts.append("Space")
        default: parts.append("key")
        }

        return parts.joined(separator: "+")
    }

    func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "pencil.and.scribble", accessibilityDescription: "WorkDrawer")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show/Hide WorkDrawer", action: #selector(toggleWindowFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc func toggleWindowFromMenu() {
        toggleWindow()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 550, height: 500),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "WorkDrawer Settings"
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        updateWindowAppearance()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func setupHotKey() {
        let preferences = ShortcutPreferences.shared
        guard let keyCode = preferences.keyCode else {
            print("No keyboard shortcut set")
            return
        }

        var eventHotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: FourCharCode(fromString: "WDRW"), id: 1)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        if eventHandlerRef == nil {
            let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

            let handler: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
                print("Hotkey pressed! Event received")
                guard let userData = userData else {
                    print("No userData")
                    return noErr
                }

                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                print("Got AppDelegate, calling toggleWindow")

                DispatchQueue.main.async {
                    appDelegate.toggleWindow()
                }
                return noErr
            }

            InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, selfPtr, &eventHandlerRef)
            print("Event handler installed with userData")
        }

        let status = RegisterEventHotKey(keyCode, preferences.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &eventHotKey)

        if status == noErr {
            self.hotKeyRef = eventHotKey
            print("Hotkey registered successfully with keyCode: \(keyCode), modifiers: \(preferences.modifiers)")
        } else {
            print("Failed to register hotkey: \(status)")
        }
    }

    func unregisterHotKey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
            print("Hotkey unregistered")
        }
    }

    func toggleWindow() {
        print("toggleWindow called")
        if let window = window, window.isVisible {
            print("Window exists and is visible, hiding...")
            hideWindow()
        } else {
            print("Window doesn't exist or not visible, showing...")
            showWindow()
        }
    }

    func showWindow() {
        print("Showing window...")
        if window == nil {
            createWindow()
            print("Window created")
        }

        updateWindowFrame()
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        setupClickOutsideMonitor()
        print("Window should be visible now")
    }

    func hideWindow() {
        print("Hiding window")
        window?.orderOut(nil)
        removeClickOutsideMonitor()
        print("Window hidden")
    }

    func createWindow() {
        let screenRect = activeScreen().visibleFrame
        let windowHeight = screenRect.height / 2
        let windowRect = NSRect(
            x: screenRect.minX,
            y: screenRect.minY,
            width: screenRect.width,
            height: windowHeight
        )

        let window = BorderlessWindow(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let contentView = ContentView(onClose: { [weak self] in
            self?.hideWindow()
        })
        window.contentView = NSHostingView(rootView: contentView)

        self.window = window
        updateWindowAppearance()
    }

    func setupClickOutsideMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let window = self?.window, window.isVisible else { return }

            let mouseLocation = NSEvent.mouseLocation
            if !window.frame.contains(mouseLocation) {
                self?.hideWindow()
            }
        }
    }

    func removeClickOutsideMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeClickOutsideMonitor()
        unregisterHotKey()
    }
}

class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }
}

extension FourCharCode {
    init(fromString string: String) {
        var result: FourCharCode = 0
        for char in string.utf16 {
            result = (result << 8) + FourCharCode(char)
        }
        self = result
    }
}
