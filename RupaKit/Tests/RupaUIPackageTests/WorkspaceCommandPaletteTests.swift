import AppKit
import SwiftUI
import Testing
@testable import RupaUI

/// The Command Palette: its search, and its keys when mounted inside the workspace keyboard scope.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WorkspaceCommandPaletteTests {
    @Test func theSearchMatchesTitlesAndAliasesByEveryWord() {
        let catalog = WorkspacePaletteCatalog.standard
        #expect(catalog.matches("").count == catalog.commands.count)
        #expect(catalog.matches("cut").map(\.title) == ["Cut", "Cut Curve"])
        #expect(catalog.matches("slice").map(\.title) == ["Boolean"])
        #expect(catalog.matches("offset vertex").map(\.title) == ["Offset Curve"])
        #expect(catalog.matches("PROJECT outline").map(\.title) == ["Alternative Duplicate"])
        #expect(catalog.matches("no such command").isEmpty)
        #expect(catalog.matches("reverse").map(\.title) == ["Reverse Curve"])
        #expect(Set(catalog.commands.map(\.title)).count == catalog.commands.count)
    }

    @MainActor
    private final class Record {
        var events: [String] = []
    }

    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private struct Host: View {
        let record: Record
        @FocusState private var isFocused: Bool

        var body: some View {
            VStack {
                Color.gray.frame(width: 360, height: 40)
                WorkspaceCommandPaletteView(
                    isAvailable: { _ in true },
                    run: { record.events.append("run:\($0.title)") },
                    close: { record.events.append("close") }
                )
            }
            .modifier(WorkspaceKeyboardScope(
                isFocused: $isFocused,
                handle: { input in
                    guard input.phases.contains(.down) else { return .ignored }
                    record.events.append(input.isReturn ? "canvas:return" : input.isEscape ? "canvas:escape" : "canvas:\(input.characters)")
                    // A workspace with nothing to back out of leaves Escape to the palette.
                    return input.isEscape ? .ignored : .handled
                },
                submit: { true }
            ))
        }
    }

    private func press(_ characters: String, keyCode: UInt16, in window: NSWindow, host: NSView) async throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            ))
            window.sendEvent(event)
        }
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    private func field(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { field(in: $0) }.first
    }

    @Test func returnRunsTheMatchAndEscapeClosesWithoutReachingTheCanvas() async throws {
        let record = Record()
        let host = NSHostingView(rootView: Host(record: record))
        let window = KeyableWindow(contentRect: NSRect(x: -20000, y: -20000, width: 420, height: 420),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        let search = try #require(field(in: host))
        #expect(window.makeFirstResponder(search))

        try await press("c", keyCode: 8, in: window, host: host)
        try await press("u", keyCode: 32, in: window, host: host)
        try await press("t", keyCode: 17, in: window, host: host)
        try await press("\r", keyCode: 36, in: window, host: host)
        #expect(record.events == ["run:Cut"])

        try await press("\u{1b}", keyCode: 53, in: window, host: host)
        #expect(record.events == ["run:Cut", "canvas:escape", "close"])
    }
}
