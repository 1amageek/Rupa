import AppKit
import SwiftUI

/// The workspace's keyboard input scope.
///
/// SwiftUI offers every key to this scope's key handler before a text field inside it sees the
/// key, so a handler that read them all would take the digits, deletes and Returns typed into a
/// command dialog. While one of the scope's text fields is being edited it owns every key but
/// Escape. Its Return, once the field has taken it, goes to `submit`; when `submit` accepts what
/// was typed the keyboard goes back to the scope and the Return reaches `handle` as a Return on
/// the canvas does, and when it refuses, the field keeps the keyboard and the text to be
/// corrected. An Escape the scope handles while a field is being edited gives the keyboard back
/// to the scope too, since the command it ends may take the field with it.
struct WorkspaceKeyboardScope: ViewModifier {
    var isFocused: FocusState<Bool>.Binding
    let handle: (WorkspaceKeyboardInput) -> KeyPress.Result
    /// Applies what was typed; false when it is refused.
    let submit: () -> Bool
    @State private var host = HostWindow()

    func body(content: Content) -> some View {
        content
            .background(HostWindowReader(host: host))
            .focusable()
            .focusEffectDisabled()
            .focused(isFocused)
            .onKeyPress(phases: .all) { keyPress in
                let input = WorkspaceKeyboardInput(keyPress: keyPress)
                let isEditingText = host.isEditingText
                guard !isEditingText || input.isEscape else { return .ignored }
                let result = handle(input)
                if isEditingText, result == .handled {
                    isFocused.wrappedValue = true
                }
                return result
            }
            .onSubmit {
                guard submit() else { return }
                isFocused.wrappedValue = true
                _ = handle(WorkspaceKeyboardInput(characters: "\r", isReturn: true))
            }
    }
}

/// The window the scope is hosted in. AppKit edits a text field through its window's field
/// editor, which is the window's first responder while the edit lasts.
@MainActor
private final class HostWindow {
    weak var window: NSWindow?

    var isEditingText: Bool {
        window?.firstResponder is NSText
    }
}

private struct HostWindowReader: NSViewRepresentable {
    let host: HostWindow

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.host = host
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.host = host
    }

    final class ReaderView: NSView {
        var host: HostWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            host?.window = window
        }
    }
}
