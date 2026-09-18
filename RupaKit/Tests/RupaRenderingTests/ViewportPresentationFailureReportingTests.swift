import AppKit
import RupaCore
import SwiftUI
import Testing
@testable import RupaRendering

@MainActor
@Test(.timeLimit(.minutes(1)))
func presentationFailuresReachLogOncePerTransitionWithoutCanvasText() async throws {
    _ = NSApplication.shared
    let document = DesignDocument.empty()
    var reported: [MeshSourcePresentationRenderError] = []
    let viewport = Viewport(
        document: document,
        sourceIdentity: .document(id: document.id, generation: DocumentGeneration(0)),
        workspaceRenderState: .init(revision: WorkspaceRevision(), ruler: .standard(for: .meter)),
        objectSelectionIndex: .init(document: document, selection: .empty),
        selectedPresentationHasExactCADContext: false,
        onPresentationFailure: { error in
            if let error = error as? MeshSourcePresentationRenderError { reported.append(error) }
        }
    )
    let failure = MeshSourcePresentationRenderError(code: .resourceExhausted, message: "Render limit exceeded")
    func content(_ error: MeshSourcePresentationRenderError?, preview: String? = nil) -> some View {
        viewport.presentationFailureReporter(error: error, previewFailureMessage: preview)
            .frame(width: 200, height: 100)
    }
    let host = NSHostingController(rootView: content(failure))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = host
    defer { window.contentViewController = nil; window.close() }
    func settle() async throws {
        host.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
    }
    try await settle()
    #expect(reported == [failure])
    host.rootView = content(failure)
    try await settle()
    #expect(reported == [failure])
    host.rootView = content(nil)
    try await settle()
    host.rootView = content(failure)
    try await settle()
    #expect(reported == [failure, failure])
    host.rootView = content(nil, preview: "Preview failed")
    try await settle()
    #expect(reported.last?.message == "Preview failed")
    #expect(reported.count == 3)
    #expect(!window.isVisible && !window.isKeyWindow)
    #expect(host.view.accessibilityChildren()?.isEmpty != false)
}
