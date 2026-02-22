# WorkDrawer

A macOS menubar app that slides a scratch-pad window up from the bottom of the screen on a configurable keyboard shortcut. (heavily inspired by https://caligra.com/workbench/) 

<img width="2056" height="1329" alt="image" src="https://github.com/user-attachments/assets/ee5397dd-b7d7-4f1a-a0fc-a0205c85a63e" />

The window is split into two panes:
- **Left**: a freehand drawing canvas with undo/redo, zoom, copy, and save to PNG
- **Right**: a markdown notes editor with syntax highlighting and rendered preview (supports Mermaid diagrams), across four tabs (Command + 1-4 to switch notes, and Command+R to toggle the markdown rendering)

Notes and drawings are persisted automatically on a choosen path.

Support dark/light/auto theme modes.

(The whole app is vibecoded)

## Requirements

- macOS 15+
- Xcode 16+

## Building

Open `WorkDrawer.xcodeproj` in Xcode and build the `WorkDrawer` scheme.
