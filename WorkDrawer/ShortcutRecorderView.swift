//
//  ShortcutRecorderView.swift
//  WorkDrawer
//
//  Created by Joaquim Moreno Prusi on 3/3/26.
//

import SwiftUI
import Carbon

struct ShortcutRecorderView: View {
    @StateObject private var shortcutPrefs = ShortcutPreferences.shared
    @State private var isRecording = false
    @State private var showClearButton = false
    
    var body: some View {
        HStack {
            ShortcutButton(
                isRecording: $isRecording,
                keyCode: shortcutPrefs.keyCode,
                modifiers: shortcutPrefs.modifiers
            )
            .onAppear {
                showClearButton = shortcutPrefs.keyCode != nil
            }
            
            if showClearButton && !isRecording {
                Button {
                    clearShortcut()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
    }
    
    func clearShortcut() {
        shortcutPrefs.keyCode = nil
        shortcutPrefs.modifiers = 0
        showClearButton = false
        NotificationCenter.default.post(name: .shortcutChanged, object: nil)
    }
}

struct ShortcutButton: NSViewRepresentable {
    @Binding var isRecording: Bool
    let keyCode: UInt32?
    let modifiers: UInt32
    
    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.coordinator = context.coordinator
        return button
    }
    
    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        nsView.keyCode = keyCode
        nsView.modifiers = modifiers
        nsView.isRecording = isRecording
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isRecording: $isRecording)
    }
    
    class Coordinator {
        @Binding var isRecording: Bool
        
        init(isRecording: Binding<Bool>) {
            self._isRecording = isRecording
        }
        
        func startRecording() {
            isRecording = true
        }
        
        func stopRecording() {
            isRecording = false
        }
    }
}

class ShortcutRecorderButton: NSView {
    var coordinator: ShortcutButton.Coordinator?
    var keyCode: UInt32?
    var modifiers: UInt32 = 0
    var isRecording = false {
        didSet {
            needsDisplay = true
        }
    }
    
    private var localMonitor: Any?
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
    
    override var intrinsicContentSize: NSSize {
        return NSSize(width: 200, height: 28)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let backgroundColor: NSColor = isRecording ? .controlAccentColor.withAlphaComponent(0.1) : .controlBackgroundColor
        backgroundColor.setFill()
        bounds.fill()
        
        let text = displayText()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let textRect = NSRect(
            x: bounds.minX,
            y: bounds.midY - 8,
            width: bounds.width,
            height: 16
        )
        
        text.draw(in: textRect, withAttributes: attributes)
    }
    
    func displayText() -> String {
        if isRecording {
            return "Press shortcut..."
        }
        
        guard let keyCode = keyCode else {
            return "Click to record shortcut"
        }
        
        var parts: [String] = []
        
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        
        if let keyString = keyCodeToString(keyCode) {
            parts.append(keyString)
        }
        
        return parts.isEmpty ? "Click to record shortcut" : parts.joined()
    }
    
    func keyCodeToString(_ code: UInt32) -> String? {
        switch Int(code) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1...kVK_F20:
            return "F\(Int(code) - kVK_F1 + 1)"
        default:
            // Try to get the character representation
            let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
            guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
            let dataRef = unsafeBitCast(layoutData, to: CFData.self)
            let keyLayout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)
            
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            
            UCKeyTranslate(
                keyLayout,
                UInt16(code),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                4,
                &length,
                &chars
            )
            
            if length > 0 {
                return String(utf16CodeUnits: chars, count: length).uppercased()
            }
            return nil
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if !isRecording {
            startRecording()
        }
    }
    
    func startRecording() {
        isRecording = true
        coordinator?.startRecording()
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            
            if event.type == .keyDown {
                self.captureKeyPress(event)
                return nil
            } else if event.type == .flagsChanged {
                // Handle escape key to cancel
                if event.keyCode == 53 { // Escape
                    self.stopRecording()
                    return nil
                }
            }
            
            return event
        }
        
        window?.makeFirstResponder(self)
    }
    
    func captureKeyPress(_ event: NSEvent) {
        let keyCode = event.keyCode
        var carbonModifiers: UInt32 = 0
        
        if event.modifierFlags.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        if event.modifierFlags.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }
        if event.modifierFlags.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if event.modifierFlags.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }
        
        // Require at least one modifier
        guard carbonModifiers != 0 else {
            stopRecording()
            return
        }
        
        // Save the shortcut
        let prefs = ShortcutPreferences.shared
        prefs.keyCode = UInt32(keyCode)
        prefs.modifiers = carbonModifiers
        
        self.keyCode = UInt32(keyCode)
        self.modifiers = carbonModifiers
        
        NotificationCenter.default.post(name: .shortcutChanged, object: nil)
        
        stopRecording()
    }
    
    func stopRecording() {
        isRecording = false
        coordinator?.stopRecording()
        
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        
        needsDisplay = true
    }
    
    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
