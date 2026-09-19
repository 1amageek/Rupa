import RupaRendering
import SwiftUI
import Testing
@testable import RupaUI
#if os(macOS)
import AppKit
#endif

@Test
func workspaceViewportDisplayModeLabelsExposeAllNativeModes() {
    #expect(viewportDisplayModeTitle(.solid) == "Solid")
    #expect(viewportDisplayModeTitle(.solidWithEdges) == "Solid + Mesh Edges")
    #expect(viewportDisplayModeTitle(.wireframe) == "Wireframe")
    #expect(viewportDisplayModeTitle(.normals) == "Normals")
}

@Test
func workspaceViewportDisplayModeLabelsAreUnique() {
    let labels = ViewportDisplayMode.allCases.map(viewportDisplayModeTitle)
    #expect(Set(labels).count == ViewportDisplayMode.allCases.count)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceShadingControlsForwardOnlyTheEditedField() {
    var stored = ViewportShading(style: .matCap, studioRotationDegrees: 42, solidColor: .random)
    let panel = ViewportShadingPanel(
        shading: Binding(get: { stored }, set: { stored = $0 }),
        displayMode: .solid
    )
    panel.binding(for: \.style).wrappedValue = .flat
    #expect(stored.style == .flat)
    #expect(stored.studioRotationDegrees == 42)
    #expect(stored.solidColor == .random)
    panel.binding(for: \.isSpecularEnabled).wrappedValue = false
    #expect(!stored.isSpecularEnabled)
    #expect(stored.style == .flat)
    for angle in [0.0, 42.25, 359.0] {
        panel.binding(for: \.studioRotationDegrees).wrappedValue = angle
        #expect(stored.studioRotationDegrees == angle)
        #expect(stored.solidColor == .random)
        #expect(!stored.isSpecularEnabled)
    }
    #expect(ViewportControlSession().shading == .standard)
}

#if os(macOS)
@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceShadingRotationUsesContinuousNativeSliderLayout() {
    _ = NSApplication.shared
    let panel = ViewportShadingPanel(shading: .constant(.standard), displayMode: .solid)
    let actual = NSHostingView(rootView: panel.rotationSlider.controlSize(.small))
    let continuous = NSHostingView(rootView:
        Slider(value: .constant(0.0), in: 0...359).controlSize(.small)
    )
    let discrete = NSHostingView(rootView:
        Slider(value: .constant(0.0), in: 0...359, step: 1) {
            Text("Light Rotation")
        }.controlSize(.small)
    )
    #expect(actual.fittingSize.height == continuous.fittingSize.height)
    #expect(actual.fittingSize.height < discrete.fittingSize.height)
}
#endif

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: ViewportDisplayMode.allCases)
func workspaceShadingControlsDescribeEffectiveDisplayModes(mode: ViewportDisplayMode) {
    let panel = ViewportShadingPanel(shading: .constant(.standard), displayMode: mode)
    #expect(panel.supportsSurfaceShading == (mode == .solid || mode == .solidWithEdges))
    #expect(panel.supportsWireColor == (mode == .wireframe || mode == .solidWithEdges))
    #expect(panel.supportsCulling == (mode == .solid || mode == .normals))
}
