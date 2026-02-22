# WorkDrawer

A macOS menubar app that slides a scratch-pad window up from the bottom of the screen on a configurable keyboard shortcut.

The window is split into two panes:
- **Left**: a freehand drawing canvas with undo/redo, zoom, copy, and save to PNG
- **Right**: a markdown notes editor with syntax highlighting and rendered preview (supports Mermaid diagrams), across four tabs

Notes and drawings are persisted automatically.

## Requirements

- macOS 15+
- Xcode 16+

## Building

Open `WorkDrawer.xcodeproj` in Xcode and build the `WorkDrawer` scheme.
