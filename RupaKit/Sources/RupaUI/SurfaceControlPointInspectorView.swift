import RupaCore
import SwiftUI

@MainActor
struct SurfaceControlPointInspectorView: View {
    let state: SurfaceControlPointInspectorState
    let session: EditorSession
    let positionSliderMetersRange: ClosedRange<Double>
    @Binding var slideDistanceMeters: Double
    @Binding var frameMoveUMeters: Double
    @Binding var frameMoveVMeters: Double
    @Binding var frameMoveNormalMeters: Double
    let isSlideActive: Bool
    let slideRouteTitle: String
    let onSetPointDisplay: ([SelectionReference], Bool) -> Void
    let onSetFrameDisplay: ([SurfaceFrameQuery], Bool) -> Void
    let onSetCoordinate: (SurfaceControlPointInspectorState.CoordinateAxis, Double) -> Void
    let onSetWeight: ([SelectionReference], Double) -> Void
    let onMoveInFrame: (SurfaceFrameQuery, Double, Double, Double) -> Void
    let onActivateSlide: () -> Void
    let onSlide: (PolySplineSurfaceVertexSlideDirection) -> Void

    var body: some View {
        inspectorSection("Surface CV") {
            inspectorRow("CVs", "\(state.selectionCount)")
            inspectorRow("Source", state.sourceTitle)
            inspectorRow("Patch", state.patchTitle)
            inspectorRow("Basis", state.basisTitle)
            inspectorRow("Index", state.indexTitle)
            inspectorRow("Role", state.roleTitle)
            inspectorRow("Boundary", state.boundaryTitle)
            inspectorRow("Edit", state.editabilityTitle)
            inspectorRow("Point Display", state.displayTitle)
            inspectorRow("Frame Display", state.frameDisplayTitle)
            coordinateControls
            weightControls
            pointDisplayControls
            frameDisplayControls
            frameDetailRows
            frameMoveControls
            slideControls
        }
    }

    @ViewBuilder
    private var coordinateControls: some View {
        if state.canEditCoordinates,
           let entry = state.entries.first {
            transformLengthControl("X", values: [entry.point.x]) { meters in
                onSetCoordinate(.x, meters)
            }
            .accessibilityIdentifier("InspectorSurfaceCV.point.x")
            transformLengthControl("Y", values: [entry.point.y]) { meters in
                onSetCoordinate(.y, meters)
            }
            .accessibilityIdentifier("InspectorSurfaceCV.point.y")
            transformLengthControl("Z", values: [entry.point.z]) { meters in
                onSetCoordinate(.z, meters)
            }
            .accessibilityIdentifier("InspectorSurfaceCV.point.z")
        } else {
            inspectorRow("Point", state.pointTitle)
        }
    }

    @ViewBuilder
    private var weightControls: some View {
        if state.canEditWeight {
            numericControl(
                "Weight",
                values: state.entries.map(\.weight),
                sliderRange: weightSliderRange
            ) { value in
                onSetWeight(state.selectedReferences, max(value, 1.0e-9))
            }
            .accessibilityIdentifier("InspectorSurfaceCV.weight")
        } else {
            inspectorRow("Weight", state.weightTitle)
        }
    }

    @ViewBuilder
    private var frameMoveControls: some View {
        inspectorRow("Frame", state.frameTitle)
        signedLengthControl(
            "U",
            meters: frameMoveUMeters,
            sliderMetersRange: frameMoveSliderMetersRange(for: frameMoveUMeters)
        ) { meters in
            frameMoveUMeters = meters
        }
        .accessibilityIdentifier("InspectorSurfaceCV.frame.u")

        signedLengthControl(
            "V",
            meters: frameMoveVMeters,
            sliderMetersRange: frameMoveSliderMetersRange(for: frameMoveVMeters)
        ) { meters in
            frameMoveVMeters = meters
        }
        .accessibilityIdentifier("InspectorSurfaceCV.frame.v")

        signedLengthControl(
            "N",
            meters: frameMoveNormalMeters,
            sliderMetersRange: frameMoveSliderMetersRange(for: frameMoveNormalMeters)
        ) { meters in
            frameMoveNormalMeters = meters
        }
        .accessibilityIdentifier("InspectorSurfaceCV.frame.normal")

        inspectorActionRow {
            inspectorIconButton(
                systemImage: "arrow.up.and.down.and.arrow.left.and.right",
                help: "Move Surface CV In Frame",
                accessibilityIdentifier: "InspectorSurfaceCV.frame.apply"
            ) {
                guard let frame = state.frameMoveQuery else {
                    return
                }
                onMoveInFrame(
                    frame,
                    frameMoveUMeters,
                    frameMoveVMeters,
                    frameMoveNormalMeters
                )
            }
            .disabled(!state.canMoveInFrame || !hasFrameMoveOffset)
        }
    }

    private var frameDisplayControls: some View {
        inspectorActionRow {
            inspectorIconButton(
                systemImage: "scope",
                help: "Show Surface CV Frame",
                accessibilityIdentifier: "InspectorSurfaceCV.frameDisplay.show"
            ) {
                onSetFrameDisplay(state.selectedFrameQueries, true)
            }
            .disabled(state.entries.allSatisfy(\.isFrameDisplayVisible))

            inspectorIconButton(
                systemImage: "scope",
                help: "Hide Surface CV Frame",
                accessibilityIdentifier: "InspectorSurfaceCV.frameDisplay.hide"
            ) {
                onSetFrameDisplay(state.selectedFrameQueries, false)
            }
            .disabled(state.entries.allSatisfy { !$0.isFrameDisplayVisible })
        }
    }

    private var pointDisplayControls: some View {
        inspectorActionRow {
            inspectorIconButton(
                systemImage: "eye",
                help: "Show Surface CV Point",
                accessibilityIdentifier: "InspectorSurfaceCV.display.show"
            ) {
                onSetPointDisplay(state.selectedReferences, true)
            }
            .disabled(state.entries.allSatisfy(\.isPointDisplayVisible))

            inspectorIconButton(
                systemImage: "eye.slash",
                help: "Hide Surface CV Point",
                accessibilityIdentifier: "InspectorSurfaceCV.display.hide"
            ) {
                onSetPointDisplay(state.selectedReferences, false)
            }
            .disabled(state.entries.allSatisfy { !$0.isPointDisplayVisible })
        }
    }

    @ViewBuilder
    private var frameDetailRows: some View {
        if state.hasResolvedFrames {
            inspectorRow("Position", state.framePositionTitle)
            inspectorRow("U Axis", state.frameUAxisTitle)
            inspectorRow("V Axis", state.frameVAxisTitle)
            inspectorRow("Normal", state.frameNormalTitle)
            inspectorRow("Handedness", state.frameHandednessTitle)
            inspectorRow("Normal Curvature", state.frameNormalCurvatureTitle)
            inspectorRow("Principal Curvature", state.framePrincipalCurvatureTitle)
            inspectorRow("Gaussian Curvature", state.frameGaussianCurvatureTitle)
        }
    }

    @ViewBuilder
    private var slideControls: some View {
        inspectorRow("Slide", isSlideActive ? "Active" : "Ready")
        inspectorRow("Route", slideRouteTitle)
        lengthControl(
            "Distance",
            meters: max(slideDistanceMeters, 1.0e-9),
            sliderMetersRange: distanceSliderMetersRange(for: slideDistanceMeters)
        ) { meters in
            slideDistanceMeters = max(meters, 1.0e-9)
        }
        .accessibilityIdentifier("InspectorSurfaceCV.slide.distance")

        inspectorActionRow {
            inspectorIconButton(
                systemImage: "arrow.triangle.2.circlepath",
                help: "Activate Slide Surface CV",
                accessibilityIdentifier: "InspectorSurfaceCV.slide.activate"
            ) {
                onActivateSlide()
            }
            .disabled(!state.canSlide)
        }

        inspectorActionRow {
            inspectorIconButton(
                systemImage: "arrow.right",
                help: "Slide Surface CV Positive U",
                accessibilityIdentifier: "InspectorSurfaceCV.slide.positiveU"
            ) {
                onSlide(.positiveU)
            }
            .disabled(!state.canSlide)

            inspectorIconButton(
                systemImage: "arrow.left",
                help: "Slide Surface CV Negative U",
                accessibilityIdentifier: "InspectorSurfaceCV.slide.negativeU"
            ) {
                onSlide(.negativeU)
            }
            .disabled(!state.canSlide)

            inspectorIconButton(
                systemImage: "arrow.up.right",
                help: "Slide Surface CV Normal",
                accessibilityIdentifier: "InspectorSurfaceCV.slide.normal"
            ) {
                onSlide(.normal)
            }
            .disabled(!state.canSlide)

            inspectorIconButton(
                systemImage: "arrow.up",
                help: "Slide Surface CV Positive V",
                accessibilityIdentifier: "InspectorSurfaceCV.slide.positiveV"
            ) {
                onSlide(.positiveV)
            }
            .disabled(!state.canSlide)

            inspectorIconButton(
                systemImage: "arrow.down",
                help: "Slide Surface CV Negative V",
                accessibilityIdentifier: "InspectorSurfaceCV.slide.negativeV"
            ) {
                onSlide(.negativeV)
            }
            .disabled(!state.canSlide)
        }
    }

    private func inspectorIconButton(
        systemImage: String,
        help: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func inspectorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: inspectorRowSpacing) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: inspectorLabelWidth, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .monospacedDigit()
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorControlRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: inspectorRowSpacing) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: inspectorLabelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorActionRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Spacer()
                .frame(width: inspectorLabelWidth)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transformLengthControl(
        _ title: String,
        values: [Double],
        onChange: @escaping (Double) -> Void
    ) -> some View {
        workspaceLengthControl(
            title,
            values: values,
            displayUnit: session.document.displayUnit,
            sliderMetersRange: positionSliderMetersRange
        ) { meters in
            onChange(meters)
        }
    }

    private func lengthControl(
        _ title: String,
        meters: Double,
        sliderMetersRange: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        workspaceLengthControl(
            title,
            values: [meters],
            displayUnit: session.document.displayUnit,
            sliderMetersRange: sliderMetersRange
        ) { nextMeters in
            onChange(max(nextMeters, 0.0))
        }
    }

    private func signedLengthControl(
        _ title: String,
        meters: Double,
        sliderMetersRange: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        workspaceLengthControl(
            title,
            values: [meters],
            displayUnit: session.document.displayUnit,
            sliderMetersRange: sliderMetersRange
        ) { nextMeters in
            guard nextMeters.isFinite else {
                return
            }
            onChange(nextMeters)
        }
    }

    private func numericControl(
        _ title: String,
        values: [Double],
        sliderRange: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void,
        unitLabel: () -> String = { "" }
    ) -> some View {
        let commonValue = commonValue(values)
        let textBinding = Binding<String>(
            get: {
                if let commonValue {
                    return WorkspaceInspectorNumberText.string(from: commonValue)
                }
                return "Mixed"
            },
            set: { text in
                guard let value = WorkspaceInspectorNumberText.value(from: text) else {
                    return
                }
                onChange(value)
            }
        )
        let sliderBinding = Binding<Double>(
            get: {
                min(max(commonValue ?? 0.0, sliderRange.lowerBound), sliderRange.upperBound)
            },
            set: { value in
                onChange(value)
            }
        )
        let unit = unitLabel()

        return VStack(alignment: .leading, spacing: 5) {
            inspectorControlRow(title) {
                HStack(spacing: 6) {
                    TextField(title, text: textBinding)
                        .multilineTextAlignment(.trailing)
                        .frame(width: inspectorControlWidth)
                    if !unit.isEmpty {
                        Text(unit)
                            .foregroundStyle(.secondary)
                            .frame(width: inspectorUnitWidth, alignment: .leading)
                    }
                }
            }
            Slider(value: sliderBinding, in: sliderRange)
                .padding(.leading, inspectorSliderLeadingPadding)
        }
        .padding(.vertical, 1)
    }

    private func distanceSliderMetersRange(for meters: Double) -> ClosedRange<Double> {
        workspaceLengthSliderMetersRange(
            for: meters,
            ruler: session.document.ruler,
            expansionMultiplier: 2.0
        )
    }

    private func frameMoveSliderMetersRange(for meters: Double) -> ClosedRange<Double> {
        workspaceSignedLengthSliderMetersRange(
            for: meters,
            ruler: session.document.ruler,
            expansionMultiplier: 2.0
        )
    }

    private var weightSliderRange: ClosedRange<Double> {
        let weights = state.entries.map(\.weight).filter { $0.isFinite }
        let currentMaximum = weights.max() ?? 1.0
        return 0.001 ... max(currentMaximum * 2.0, 4.0)
    }

    private var hasFrameMoveOffset: Bool {
        abs(frameMoveUMeters) > 1.0e-12
            || abs(frameMoveVMeters) > 1.0e-12
            || abs(frameMoveNormalMeters) > 1.0e-12
    }

    private func commonValue(_ values: [Double]) -> Double? {
        guard let first = values.first,
              first.isFinite else {
            return nil
        }
        guard values.allSatisfy({ $0.isFinite && abs($0 - first) < 1.0e-9 }) else {
            return nil
        }
        return first
    }

    private var inspectorLabelWidth: CGFloat { 124 }
    private var inspectorControlWidth: CGFloat { 104 }
    private var inspectorUnitWidth: CGFloat { 36 }
    private var inspectorRowSpacing: CGFloat { 10 }
    private var inspectorSliderLeadingPadding: CGFloat {
        inspectorLabelWidth + inspectorRowSpacing
    }
}
