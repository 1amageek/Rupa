import AppKit
import SwiftUI
import Testing
@testable import RupaUI

/// The workspace keyboard scope, mounted in a window and driven by key events: a text field
/// inside it owns the keys typed into it, and its Return comes back to the scope as the canvas's.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct WorkspaceKeyboardScopeTests {
    @MainActor
    private final class Record {
        var events: [String] = []
    }

    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private struct Probe: View {
        let record: Record
        @FocusState private var isFocused: Bool
        @State private var text = ""

        var body: some View {
            VStack {
                Color.gray.frame(width: 160, height: 60)
                TextField("Value", text: $text).frame(width: 80)
            }
            .modifier(WorkspaceKeyboardScope(
                isFocused: $isFocused,
                handle: { input in
                    guard input.phases.contains(.down) else { return .ignored }
                    let name = input.isReturn ? "return" : input.isEscape ? "escape" : input.isDelete ? "delete" : input.characters
                    record.events.append("handle:\(name)")
                    return input.isReturn || input.isEscape || input.characters == "g" ? .handled : .ignored
                },
                submit: { record.events.append("submit:\(text)") }
            ))
            .onAppear { isFocused = true }
        }
    }

    private struct Mounted {
        let record: Record
        let window: NSWindow
        let host: NSView
    }

    private func mount() async throws -> Mounted {
        let record = Record()
        let host = NSHostingView(rootView: Probe(record: record))
        let window = KeyableWindow(contentRect: NSRect(x: -20000, y: -20000, width: 240, height: 160),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        try await settle(host)
        return Mounted(record: record, window: window, host: host)
    }

    private func settle(_ host: NSView) async throws {
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    private func field(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { field(in: $0) }.first
    }

    private func press(_ characters: String, keyCode: UInt16, in mounted: Mounted) async throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: mounted.window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            ))
            mounted.window.sendEvent(event)
        }
        try await settle(mounted.host)
    }

    private func editField(_ mounted: Mounted) async throws -> NSTextField {
        let textField = try #require(field(in: mounted.host))
        #expect(mounted.window.makeFirstResponder(textField))
        try await settle(mounted.host)
        return textField
    }

    @Test func aFieldOwnsItsKeysAndItsReturnComesBackAsTheCanvasReturn() async throws {
        let mounted = try await mount()
        defer { mounted.window.contentView = nil; mounted.window.close() }
        let textField = try await editField(mounted)

        try await press("1", keyCode: 18, in: mounted)
        try await press("0", keyCode: 29, in: mounted)
        try await press("\u{7f}", keyCode: 51, in: mounted)
        try await press("5", keyCode: 23, in: mounted)
        #expect(textField.currentEditor()?.string == "15")
        #expect(mounted.record.events.isEmpty)

        try await press("\r", keyCode: 36, in: mounted)
        #expect(mounted.record.events == ["submit:15", "handle:return"])

        // The keyboard is back with the canvas: G reaches the scope's handler.
        try await press("g", keyCode: 5, in: mounted)
        #expect(mounted.record.events.last == "handle:g")
    }

    @Test func anEscapeTheScopeHandlesGivesTheKeyboardBack() async throws {
        let mounted = try await mount()
        defer { mounted.window.contentView = nil; mounted.window.close() }
        _ = try await editField(mounted)

        try await press("\u{1b}", keyCode: 53, in: mounted)
        #expect(mounted.record.events == ["handle:escape"])
        try await press("g", keyCode: 5, in: mounted)
        #expect(mounted.record.events.last == "handle:g")
    }

    @Test func withNoFieldBeingEditedTheScopeTakesEveryKey() async throws {
        let mounted = try await mount()
        defer { mounted.window.contentView = nil; mounted.window.close() }

        try await press("1", keyCode: 18, in: mounted)
        try await press("g", keyCode: 5, in: mounted)
        #expect(mounted.record.events == ["handle:1", "handle:g"])
    }
}
