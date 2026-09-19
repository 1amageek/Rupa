import RupaRendering
import SwiftCAD
import SwiftUI

@MainActor
struct ViewportShadingPanel: View {
    @Binding var shading: ViewportShading
    let displayMode: ViewportDisplayMode
    @Environment(\.self) private var environment

    private enum ColorSource: String, CaseIterable {
        case single = "Single"
        case material = "Material"
        case random = "Random"
    }

    var supportsSurfaceShading: Bool {
        displayMode == .solid || displayMode == .solidWithEdges
    }

    var supportsWireColor: Bool {
        displayMode == .wireframe || displayMode == .solidWithEdges
    }

    var supportsCulling: Bool {
        ViewportShading(isBackfaceCullingEnabled: true)
            .isBackfaceCullingActive(in: displayMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Viewport Shading")
                .font(.headline)
            Text(viewportDisplayModeTitle(displayMode))
                .font(.caption)
                .foregroundStyle(.secondary)

            GroupBox("Lighting") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Lighting", selection: binding(for: \.style)) {
                        Text("Studio").tag(ViewportShading.Style.studio)
                        Text("MatCap").tag(ViewportShading.Style.matCap)
                        Text("Flat").tag(ViewportShading.Style.flat)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("WorkspaceViewport.shading.lighting")

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Light Rotation")
                            Spacer()
                            Text("\(shading.studioRotationDegrees, format: .number.precision(.fractionLength(1)))°")
                                .monospacedDigit()
                        }
                        rotationSlider
                    }
                    .disabled(shading.style != .studio)
                    Toggle("Specular Lighting", isOn: binding(for: \.isSpecularEnabled))
                        .disabled(shading.style != .studio)
                        .accessibilityIdentifier("WorkspaceViewport.shading.specular")
                    Text(lightingDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            }
            .disabled(!supportsSurfaceShading)

            GroupBox("Surface Color") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Surface Color", selection: colorSourceBinding) {
                        ForEach(ColorSource.allCases, id: \.self) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("WorkspaceViewport.shading.surfaceColor")
                    if case .single = shading.solidColor {
                        ColorPicker("Color", selection: solidColorBinding, supportsOpacity: false)
                    } else if case .material = shading.solidColor {
                        Text("Uses assigned material base colors; materials are not edited.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            }
            .disabled(!supportsSurfaceShading)

            GroupBox("Wire Color") {
                Picker("Wire Color", selection: binding(for: \.wireColor)) {
                    Text("Theme").tag(ViewportShading.WireColor.theme)
                    Text("Object").tag(ViewportShading.WireColor.object)
                    Text("Random").tag(ViewportShading.WireColor.random)
                }
                .pickerStyle(.segmented)
                .padding(4)
                .accessibilityIdentifier("WorkspaceViewport.shading.wireColor")
            }
            .disabled(!supportsWireColor)
            .help("Applies to Wireframe and Solid + Mesh Edges.")

            GroupBox("Background") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Background", selection: customBackgroundBinding) {
                        Text("Theme").tag(false)
                        Text("Custom").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("WorkspaceViewport.shading.background")
                    if case .custom = shading.background {
                        ColorPicker("Color", selection: backgroundColorBinding, supportsOpacity: false)
                    }
                }
                .padding(4)
            }

            Toggle("Backface Culling", isOn: binding(for: \.isBackfaceCullingEnabled))
                .disabled(!supportsCulling)
                .accessibilityIdentifier("WorkspaceViewport.shading.backfaceCulling")
            if !supportsSurfaceShading || !supportsCulling {
                Text(applicabilityDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .controlSize(.small)
        .padding(16)
        .frame(width: 304)
        .accessibilityIdentifier("WorkspaceViewport.shading.panel")
    }

    var rotationSlider: some View {
        Slider(value: binding(for: \.studioRotationDegrees), in: 0...359)
            .accessibilityLabel("Light Rotation")
            .accessibilityIdentifier("WorkspaceViewport.shading.rotation")
    }

    private var lightingDescription: String {
        switch shading.style {
        case .studio: "View-relative lights with adjustable rotation."
        case .matCap: "Built-in material capture, sampled by surface normal."
        case .flat: "Unlit base color."
        }
    }

    private var applicabilityDescription: String {
        switch displayMode {
        case .solid: ""
        case .solidWithEdges: "Backface culling is available in Solid and Normals, without edge overlays."
        case .wireframe: "Wireframe uses wire and background colors. Surface lighting and culling are inactive."
        case .normals: "Normals preserves direction colors. Background and backface culling remain available."
        }
    }

    func binding<Value>(for keyPath: WritableKeyPath<ViewportShading, Value>) -> Binding<Value> {
        Binding(
            get: { shading[keyPath: keyPath] },
            set: { value in
                var next = shading
                next[keyPath: keyPath] = value
                shading = next
            }
        )
    }

    private var colorSource: ColorSource {
        switch shading.solidColor {
        case .single: .single
        case .material: .material
        case .random: .random
        }
    }

    private var colorSourceBinding: Binding<ColorSource> {
        Binding(
            get: { colorSource },
            set: { source in
                guard source != colorSource else { return }
                switch source {
                case .single: shading.solidColor = ViewportShading.standard.solidColor
                case .material: shading.solidColor = .material
                case .random: shading.solidColor = .random
                }
            }
        )
    }

    private var isCustomBackground: Bool {
        if case .custom = shading.background { true } else { false }
    }

    private var customBackgroundBinding: Binding<Bool> {
        Binding(
            get: { isCustomBackground },
            set: { custom in
                guard custom != isCustomBackground else { return }
                shading.background = custom
                    ? .custom(ColorRGBA(r: 0.08, g: 0.09, b: 0.11, a: 1))
                    : .theme
            }
        )
    }

    private var solidColorBinding: Binding<Color> {
        Binding(
            get: {
                guard case .single(let color) = shading.solidColor else { return .clear }
                return Color(red: color.r, green: color.g, blue: color.b)
            },
            set: { shading.solidColor = .single(opaqueColor($0)) }
        )
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                guard case .custom(let color) = shading.background else { return .clear }
                return Color(red: color.r, green: color.g, blue: color.b)
            },
            set: { shading.background = .custom(opaqueColor($0)) }
        )
    }

    private func opaqueColor(_ color: Color) -> ColorRGBA {
        let resolved = color.resolve(in: environment)
        return ColorRGBA(r: Double(resolved.red), g: Double(resolved.green), b: Double(resolved.blue), a: 1)
    }
}
