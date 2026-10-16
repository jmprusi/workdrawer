//
//  ContentView.swift
//  WorkDrawer
//
//  Created by Joaquim Moreno Prusi on 16/2/26.
//

import SwiftUI
internal import UniformTypeIdentifiers

struct ContentView: View {
    var onClose: () -> Void
    @State private var splitPosition: CGFloat = 0.3
    @State private var shouldLoadExisting = true
    @StateObject private var themePreferences = ThemePreferences.shared

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                DrawingCanvasView(shouldLoadExisting: $shouldLoadExisting)
                    .frame(width: geometry.size.width * splitPosition)

                DividerView(splitPosition: $splitPosition, totalWidth: geometry.size.width)
                    .frame(width: 8)

                SidePanelView(shouldLoadExisting: $shouldLoadExisting)
                    .frame(width: geometry.size.width * (1 - splitPosition) - 8)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .preferredColorScheme(themePreferences.currentTheme.colorScheme)
        .background {
            Button("", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
        }
    }
}

enum SidePanelTab: String, CaseIterable {
    case notes = "Notes"
    case pullRequests = "PRs"

    var shortcutLabel: String {
        switch self {
        case .notes: return "⌘1"
        case .pullRequests: return "⌘2"
        }
    }
}

struct SidePanelView: View {
    @Binding var shouldLoadExisting: Bool
    @State private var selectedTab: SidePanelTab = .notes

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(SidePanelTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        HStack(spacing: 4) {
                            Text(tab.rawValue)
                                .font(.system(size: 12))
                            Text(tab.shortcutLabel)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(selectedTab == tab
                            ? Color(NSColor.selectedControlColor)
                            : Color(NSColor.controlBackgroundColor))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                    .overlay(alignment: .bottom) {
                        if selectedTab == tab {
                            Color.accentColor.frame(height: 2)
                        }
                    }
                }
            }
            .frame(height: 28)

            switch selectedTab {
            case .notes:
                NotesEditorView(shouldLoadExisting: $shouldLoadExisting)
            case .pullRequests:
                PullRequestsView()
            }
        }
        .background {
            Group {
                Button("", action: { selectedTab = .notes })
                    .keyboardShortcut("1", modifiers: .command)
                Button("", action: { selectedTab = .pullRequests })
                    .keyboardShortcut("2", modifiers: .command)
            }
            .hidden()
        }
    }
}

struct DividerView: View {
    @Binding var splitPosition: CGFloat
    let totalWidth: CGFloat
    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(width: 8)
            .cursor(NSCursor.resizeLeftRight)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let newPosition = (value.location.x + (splitPosition * totalWidth)) / totalWidth
                        splitPosition = min(max(newPosition, 0.2), 0.8)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onContinuousHover { phase in
            switch phase {
            case .active:
                cursor.push()
            case .ended:
                NSCursor.pop()
            }
        }
    }
}

struct DrawingCanvasView: View {
    @Binding var shouldLoadExisting: Bool
    @State private var lines: [Line] = []
    @State private var undoStack: [Line] = []
    @State private var undoneLines: [Line] = []
    @State private var currentLine: Line?
    @State private var penWidth: CGFloat = 2
    @State private var isEraserMode: Bool = false
    @State private var eraserWidth: CGFloat = 24
    @State private var hoverLocation: CGPoint?
    @State private var zoomLevel: CGFloat = 1.0
    @State private var baseZoomLevel: CGFloat = 1.0
    @State private var canvasSize: CGSize = .zero
    @State private var hasLoadedInitial = false
    @Environment(\.colorScheme) var colorScheme

    private static let penWidths: [CGFloat] = [1, 2, 4, 6, 10]
    private static let eraserWidths: [CGFloat] = [12, 24, 40, 60, 90]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 20, height: 20)
                }
                .disabled(undoStack.isEmpty)
                .help("Undo")

                Button(action: redo) {
                    Image(systemName: "arrow.uturn.forward")
                        .frame(width: 20, height: 20)
                }
                .disabled(undoneLines.isEmpty)
                .help("Redo")

                Divider()
                    .frame(height: 20)

                Button(action: clear) {
                    Image(systemName: "trash")
                        .frame(width: 20, height: 20)
                }
                .disabled(lines.isEmpty)
                .help("Clear All")

                Divider()
                    .frame(height: 20)

                Button(action: { isEraserMode = false }) {
                    Image(systemName: "pencil")
                        .frame(width: 20, height: 20)
                        .padding(4)
                        .background(isEraserMode ? Color.clear : Color.accentColor.opacity(0.3))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Pencil")

                Button(action: { isEraserMode = true }) {
                    Image(systemName: "eraser")
                        .frame(width: 20, height: 20)
                        .padding(4)
                        .background(isEraserMode ? Color.accentColor.opacity(0.3) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Eraser")

                Divider()
                    .frame(height: 20)

                Menu {
                    ForEach(isEraserMode ? Self.eraserWidths : Self.penWidths, id: \.self) { width in
                        Button(action: {
                            if isEraserMode { eraserWidth = width } else { penWidth = width }
                        }) {
                            Label("\(Int(width)) pt", systemImage: (isEraserMode ? eraserWidth : penWidth) == width ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: "scribble")
                        .frame(width: 20, height: 20)
                        .padding(4)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .help(isEraserMode ? "Eraser Size" : "Pen Width")

                Divider()
                    .frame(height: 20)

                Button(action: zoomOut) {
                    Image(systemName: "minus.magnifyingglass")
                        .frame(width: 20, height: 20)
                }
                .disabled(zoomLevel <= 0.5)
                .help("Zoom Out")

                Text("\(Int(zoomLevel * 100))%")
                    .font(.system(size: 11))
                    .frame(width: 40)
                    .help("Zoom Level")

                Button(action: zoomIn) {
                    Image(systemName: "plus.magnifyingglass")
                        .frame(width: 20, height: 20)
                }
                .disabled(zoomLevel >= 3.0)
                .help("Zoom In")

                Button(action: resetZoom) {
                    Image(systemName: "1.magnifyingglass")
                        .frame(width: 20, height: 20)
                }
                .disabled(zoomLevel == 1.0)
                .help("Reset Zoom")

                Spacer()

                Button(action: copyDrawing) {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 20, height: 20)
                }
                .disabled(lines.isEmpty)
                .help("Copy Drawing")

                Button(action: saveDrawing) {
                    Image(systemName: "square.and.arrow.down")
                        .frame(width: 20, height: 20)
                }
                .disabled(lines.isEmpty)
                .help("Save Drawing")
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Canvas { context, size in
                        renderLines(lines, in: &context)
                        if let currentLine = currentLine {
                            renderLines([currentLine], in: &context)
                        }
                        if isEraserMode, let hoverLocation {
                            let radius = eraserWidth / 2
                            let rect = CGRect(x: hoverLocation.x - radius, y: hoverLocation.y - radius, width: eraserWidth, height: eraserWidth)
                            let outline = Path(ellipseIn: rect)
                            context.fill(outline, with: .color(.gray.opacity(0.25)))
                            context.stroke(outline, with: .color(.gray), lineWidth: 1)
                        }
                    }
                    .frame(
                        width: max(geometry.size.width, geometry.size.width * zoomLevel),
                        height: max(geometry.size.height, geometry.size.height * zoomLevel)
                    )
                    .background(Color.white)
                    .scaleEffect(zoomLevel, anchor: .topLeading)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverLocation = CGPoint(x: location.x / zoomLevel, y: location.y / zoomLevel)
                        case .ended:
                            hoverLocation = nil
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let adjustedLocation = CGPoint(
                                    x: value.location.x / zoomLevel,
                                    y: value.location.y / zoomLevel
                                )
                                hoverLocation = adjustedLocation
                                if currentLine == nil {
                                    currentLine = Line(points: [adjustedLocation], color: .black, width: isEraserMode ? eraserWidth : penWidth, isEraser: isEraserMode)
                                } else {
                                    currentLine?.points.append(adjustedLocation)
                                }
                            }
                            .onEnded { _ in
                                if let line = currentLine {
                                    lines.append(line)
                                    undoStack.append(line)
                                    if undoStack.count > 10 { undoStack.removeFirst() }
                                    undoneLines.removeAll()
                                    currentLine = nil
                                }
                            }
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let newZoom = baseZoomLevel * value
                                zoomLevel = min(max(newZoom, 0.5), 3.0)
                            }
                            .onEnded { value in
                                baseZoomLevel = zoomLevel
                            }
                    )
                }
                .onAppear {
                    canvasSize = geometry.size
                }
            }
            .modifier(ConditionalColorInvert(shouldInvert: colorScheme == .dark))
        }
        .border(Color.gray.opacity(0.3), width: 1)
        .onChange(of: lines) { _, newLines in
            PersistenceManager.shared.saveDrawing(newLines)
            if !newLines.isEmpty {
                let size = CGSize(width: 1920, height: 1080)
                PersistenceManager.shared.exportDrawingAsImage(newLines, size: size)
            }
        }
        .onAppear {
            if !hasLoadedInitial {
                hasLoadedInitial = true
                if shouldLoadExisting {
                    lines = PersistenceManager.shared.loadDrawing()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .savePathChanged)) { _ in
            lines = PersistenceManager.shared.loadDrawing()
            undoStack = []
            undoneLines = []
            currentLine = nil
        }
    }

    func undo() {
        guard !undoStack.isEmpty else { return }
        undoStack.removeLast()
        let lastLine = lines.removeLast()
        undoneLines.append(lastLine)
        if undoneLines.count > 10 { undoneLines.removeFirst() }
    }

    func redo() {
        guard !undoneLines.isEmpty else { return }
        let line = undoneLines.removeLast()
        lines.append(line)
        undoStack.append(line)
        if undoStack.count > 10 { undoStack.removeFirst() }
    }

    func clear() {
        lines.removeAll()
        undoStack.removeAll()
        undoneLines.removeAll()
        currentLine = nil
    }

    func zoomIn() {
        zoomLevel = min(zoomLevel + 0.25, 3.0)
        baseZoomLevel = zoomLevel
    }

    func zoomOut() {
        zoomLevel = max(zoomLevel - 0.25, 0.5)
        baseZoomLevel = zoomLevel
    }

    func resetZoom() {
        zoomLevel = 1.0
        baseZoomLevel = 1.0
    }

    func copyDrawing() {
        let renderer = ImageRenderer(content: drawingContent)
        renderer.scale = 2.0

        if let nsImage = renderer.nsImage {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([nsImage])
        }
    }

    func saveDrawing() {
        let renderer = ImageRenderer(content: drawingContent)
        renderer.scale = 2.0

        if let nsImage = renderer.nsImage {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.png]
            savePanel.nameFieldStringValue = "drawing.png"

            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    if let tiffData = nsImage.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        try? pngData.write(to: url)
                    }
                }
            }
        }
    }

    var drawingContent: some View {
        Canvas { context, size in
            renderLines(lines, in: &context)
        }
        .frame(width: 800, height: 600)
        .background(Color.white)
    }
}

struct NotesEditorView: View {
    @Binding var shouldLoadExisting: Bool
    @State private var noteContent: String = ""
    @State private var hasLoadedInitial = false
    @State private var isPreviewMode: Bool = false
    @StateObject private var fontPrefs = FontPreferences.shared
    @State private var showSearch = false
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer()

                Button(action: { isPreviewMode.toggle() }) {
                    Image(systemName: isPreviewMode ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)
                .help(isPreviewMode ? "Edit Markdown" : "Preview")
                .keyboardShortcut(KeyEquivalent("r"), modifiers: .command)
            }
            .frame(height: 32)

            if showSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($searchFieldFocused)
                    Spacer()
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Done") {
                        showSearch = false
                        searchText = ""
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .onAppear { searchFieldFocused = true }
            }

            if isPreviewMode {
                WebPreviewView(
                    text: $noteContent,
                    fontSize: fontPrefs.fontSize,
                    fontFamily: fontPrefs.fontFamily,
                    searchText: searchText
                )
            } else {
                NotesTextView(
                    text: $noteContent,
                    fontSize: fontPrefs.fontSize,
                    fontFamily: fontPrefs.fontFamily,
                    searchText: searchText
                )
            }
        }
        .border(Color.gray.opacity(0.3), width: 1)
        .background {
            Button("", action: {
                showSearch.toggle()
                if !showSearch { searchText = "" }
            })
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
        }
        .onChange(of: noteContent) { old, new in
            if old != new {
                PersistenceManager.shared.saveNote(new)
            }
        }
        .onAppear {
            if !hasLoadedInitial {
                hasLoadedInitial = true
                if shouldLoadExisting {
                    noteContent = PersistenceManager.shared.loadNote()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .savePathChanged)) { _ in
            noteContent = PersistenceManager.shared.loadNote()
        }
    }
}

struct NotesTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 14
    var fontFamily: String = ""
    var searchText: String = ""

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.isRichText = true
        textView.allowsUndo = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let fontChanged = context.coordinator.lastFontSize != fontSize || context.coordinator.lastFontFamily != fontFamily
        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastFontFamily = fontFamily

        let textChanged = textView.string != text
        if textChanged || fontChanged {
            let cursorPosition = textView.selectedRanges.first?.rangeValue.location ?? 0
            context.coordinator.isUpdating = true
            textView.string = text
            context.coordinator.applyMarkdownHighlighting(to: textView, text: text, fontSize: fontSize, fontFamily: fontFamily)
            textView.setSelectedRange(NSRange(location: min(cursorPosition, textView.string.count), length: 0))
            context.coordinator.isUpdating = false
        }

        let searchChanged = context.coordinator.lastSearchText != searchText
        if searchChanged || (textChanged && !searchText.isEmpty) {
            context.coordinator.lastSearchText = searchText
            context.coordinator.performSearch(in: textView, query: searchText)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesTextView
        var isUpdating = false
        var lastFontSize: CGFloat = 0
        var lastFontFamily: String = ""
        var lastSearchText: String = ""

        init(_ parent: NotesTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isUpdating else { return }

            isUpdating = true
            let cursorPosition = textView.selectedRanges.first?.rangeValue.location ?? 0
            parent.text = textView.string
            applyMarkdownHighlighting(to: textView, text: textView.string, fontSize: parent.fontSize, fontFamily: parent.fontFamily)
            textView.setSelectedRange(NSRange(location: min(cursorPosition, textView.string.count), length: 0))
            isUpdating = false
        }

        func performSearch(in textView: NSTextView, query: String) {
            guard !query.isEmpty else {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                return
            }
            let text = textView.string
            guard let range = text.range(of: query, options: .caseInsensitive) else { return }
            let nsRange = NSRange(range, in: text)
            textView.setSelectedRange(nsRange)
            textView.scrollRangeToVisible(nsRange)
            textView.showFindIndicator(for: nsRange)
        }

        func resolvedFont(size: CGFloat, family: String) -> NSFont {
            guard !family.isEmpty else { return NSFont.systemFont(ofSize: size) }
            return NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size)
        }

        func resolvedBoldFont(size: CGFloat, family: String) -> NSFont {
            guard !family.isEmpty else { return NSFont.boldSystemFont(ofSize: size) }
            let descriptor = NSFontDescriptor(name: family, size: size).withSymbolicTraits(.bold)
            return NSFont(descriptor: descriptor, size: size) ?? NSFont.boldSystemFont(ofSize: size)
        }

        func applyMarkdownHighlighting(to textView: NSTextView, text: String, fontSize: CGFloat, fontFamily: String) {
            let storage = textView.textStorage!
            let fullRange = NSRange(location: 0, length: storage.length)

            let baseFont = resolvedFont(size: fontSize, family: fontFamily)
            let baseColor = NSColor.textColor

            storage.beginEditing()
            storage.setAttributes([
                .font: baseFont,
                .foregroundColor: baseColor
            ], range: fullRange)

            let patterns: [(pattern: String, attributes: [NSAttributedString.Key: Any])] = [
                ("^#{1,6} .+$", [
                    .font: resolvedBoldFont(size: fontSize + 2, family: fontFamily),
                    .foregroundColor: NSColor.systemBlue
                ]),
                ("\\*\\*(.+?)\\*\\*", [
                    .font: resolvedBoldFont(size: fontSize, family: fontFamily),
                    .foregroundColor: baseColor
                ]),
                ("\\*(.+?)\\*", [
                    .font: resolvedFont(size: fontSize, family: fontFamily).italic(),
                    .foregroundColor: baseColor
                ]),
                ("`([^`]+)`", [
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular),
                    .foregroundColor: NSColor.systemPink,
                    .backgroundColor: NSColor.systemGray.withAlphaComponent(0.2)
                ]),
                ("```[\\s\\S]*?```", [
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular),
                    .foregroundColor: NSColor.systemPink,
                    .backgroundColor: NSColor.systemGray.withAlphaComponent(0.2)
                ]),
                ("\\[(.+?)\\]\\((.+?)\\)", [
                    .foregroundColor: NSColor.systemBlue,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]),
                ("^[-*+] .+$", [
                    .foregroundColor: NSColor.systemGreen
                ]),
                ("^> .+$", [
                    .font: resolvedFont(size: fontSize, family: fontFamily).italic(),
                    .foregroundColor: NSColor.systemGray
                ])
            ]

            for (pattern, attributes) in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                    let matches = regex.matches(in: text, options: [], range: fullRange)
                    for match in matches {
                        storage.addAttributes(attributes, range: match.range)
                    }
                }
            }

            storage.endEditing()
        }
    }
}

struct ConditionalColorInvert: ViewModifier {
    let shouldInvert: Bool

    func body(content: Content) -> some View {
        if shouldInvert {
            content.colorInvert()
        } else {
            content
        }
    }
}

extension NSFont {
    func italic() -> NSFont {
        let descriptor = self.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: self.pointSize) ?? self
    }
}

struct Line: Equatable {
    var points: [CGPoint]
    var color: Color
    var width: CGFloat
    var isEraser: Bool = false
}

func renderLines(_ lines: [Line], in context: inout GraphicsContext) {
    for line in lines {
        guard let firstPoint = line.points.first else { continue }
        var path = Path()
        path.move(to: firstPoint)
        for point in line.points.dropFirst() {
            path.addLine(to: point)
        }
        if line.isEraser {
            context.blendMode = .clear
            context.stroke(path, with: .color(.black), lineWidth: line.width)
            context.blendMode = .normal
        } else {
            context.stroke(path, with: .color(line.color), lineWidth: line.width)
        }
    }
}

#Preview {
    ContentView(onClose: {})
        .frame(width: 800, height: 400)
}
