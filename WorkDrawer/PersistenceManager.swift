//
//  PersistenceManager.swift
//  WorkDrawer
//
//  Created by Joaquim Moreno Prusi on 16/2/26.
//

import SwiftUI

extension Notification.Name {
    static let savePathChanged = Notification.Name("savePathChanged")
    static let shortcutChanged = Notification.Name("shortcutChanged")
    static let themeChanged = Notification.Name("themeChanged")
}

private struct CodableLine: Codable {
    var points: [CodablePoint]
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    var width: CGFloat

    init(from line: Line) {
        self.points = line.points.map { CodablePoint(x: $0.x, y: $0.y) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(line.color).usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = r; self.green = g; self.blue = b; self.alpha = a
        self.width = line.width
    }

    func toLine() -> Line {
        Line(
            points: points.map { CGPoint(x: $0.x, y: $0.y) },
            color: Color(red: red, green: green, blue: blue, opacity: alpha),
            width: width
        )
    }
}

private struct CodablePoint: Codable {
    var x: CGFloat
    var y: CGFloat
}

class PersistenceManager {
    static let shared = PersistenceManager()

    private var saveDirectory: URL {
        if let path = UserDefaults.standard.string(forKey: "savePath"), !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("WorkDrawer")
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
    }

    func saveDrawing(_ lines: [Line]) {
        ensureDirectory()
        let codable = lines.map { CodableLine(from: $0) }
        if let data = try? JSONEncoder().encode(codable) {
            try? data.write(to: saveDirectory.appendingPathComponent("drawing.json"))
        }
    }

    func loadDrawing() -> [Line] {
        let url = saveDirectory.appendingPathComponent("drawing.json")
        guard let data = try? Data(contentsOf: url),
              let codable = try? JSONDecoder().decode([CodableLine].self, from: data) else {
            return []
        }
        return codable.map { $0.toLine() }
    }

    func exportDrawingAsImage(_ lines: [Line], size: CGSize) {
        ensureDirectory()
        let view = DrawingExportView(lines: lines, size: size)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        guard let nsImage = renderer.nsImage,
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        try? pngData.write(to: saveDirectory.appendingPathComponent("drawing.png"))
    }

    func saveNote(_ text: String, tabIndex: Int) {
        ensureDirectory()
        let url = saveDirectory.appendingPathComponent("note_\(tabIndex).txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    func loadAllNotes(count: Int) -> [String] {
        return (0..<count).map { index in
            let url = saveDirectory.appendingPathComponent("note_\(index).txt")
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
    }
}

private struct DrawingExportView: View {
    let lines: [Line]
    let size: CGSize

    var body: some View {
        Canvas { context, _ in
            for line in lines {
                var path = Path()
                guard let first = line.points.first else { continue }
                path.move(to: first)
                for point in line.points.dropFirst() {
                    path.addLine(to: point)
                }
                context.stroke(path, with: .color(line.color), lineWidth: line.width)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.white)
    }
}
