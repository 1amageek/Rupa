import RupaCore
import SwiftUI

@MainActor
struct PatternArrayInspectorView: View {
    let state: PatternArrayInspectorState
    let session: EditorSession
    let positionSliderMetersRange: ClosedRange<Double>
    let isCurvePathPickActive: Bool
    let onStartCurvePathPick: (PatternArraySourceID) -> Void
    let onCancelCurvePathPick: () -> Void

    var body: some View {
        inspectorSection("Pattern Array") {
            inspectorRow("Name", state.name)
            inspectorRow("Role", state.selectionRoleTitle)
            inspectorRow("Source ID", shortID(state.sourceID))
            inspectorRow("Definition", state.definitionName ?? shortID(state.definitionID))
            inspectorRow("Root", state.rootSceneNodeName ?? shortID(state.rootSceneNodeID))
            inspectorRow("Distribution", state.distributionTitle)
            outputModePicker
            inspectorRow("Outputs", "\(state.outputCount)")
            inspectorRow("Selected Output", state.selectedOutputTitle)
            inspectorRow("Ownership", state.ownershipTitle)
            inspectorRow("Direct Edit", state.directEditTitle)
            inspectorRow("Feature Edit", state.featureEditTitle)
            if state.outputMode == .independentCopy {
                inspectorRow("Copy State", state.independentCopyOutputStateTitle)
                inspectorRow("Regeneration", state.independentCopyRegenerationTitle)
            }
            inspectorRow("Source Edit", state.sourceEditTitle)
            inspectorRow("Detach", state.detachTitle)
            inspectorRow("Diagnostics", state.diagnosticsTitle)
            distributionControls
        }
    }

    @ViewBuilder
    private var distributionControls: some View {
        if let firstAxis = state.rectangularFirstAxis {
            linearAxisControls(
                "First Axis",
                axis: firstAxis,
                accessibilityPrefix: "InspectorPatternArray.rectangular.firstAxis",
                setCopyCount: { setRectangularAxisCopyCount(slot: .first, copyCount: $0) },
                setDistance: { setRectangularAxisDistance(slot: .first, meters: $0) },
                setDistanceMode: { setRectangularAxisDistanceMode(slot: .first, distanceMode: $0) }
            )
            if let secondAxis = state.rectangularSecondAxis {
                linearAxisControls(
                    "Second Axis",
                    axis: secondAxis,
                    accessibilityPrefix: "InspectorPatternArray.rectangular.secondAxis",
                    setCopyCount: { setRectangularAxisCopyCount(slot: .second, copyCount: $0) },
                    setDistance: { setRectangularAxisDistance(slot: .second, meters: $0) },
                    setDistanceMode: { setRectangularAxisDistanceMode(slot: .second, distanceMode: $0) }
                )
                removeRectangularSecondAxisButton
            } else {
                addRectangularSecondAxisButton
            }
        }
        if let angularAxis = state.radialAngularAxis {
            radialAngularAxisControls(angularAxis)
            if let radialAxis = state.radialAxis {
                linearAxisControls(
                    "Radial Axis",
                    axis: radialAxis,
                    accessibilityPrefix: "InspectorPatternArray.radial.radialAxis",
                    setCopyCount: { setRadialAxisCopyCount($0) },
                    setDistance: { setRadialAxisDistance($0) },
                    setDistanceMode: { setRadialAxisDistanceMode($0) }
                )
                removeRadialAxisButton
            } else {
                addRadialAxisButton
            }
        }
        if let curve = state.curve {
            curveControls(curve)
        }
    }

    private var outputModePicker: some View {
        inspectorControlRow("Output Mode") {
            Picker(
                "",
                selection: Binding(
                    get: { state.outputMode },
                    set: { outputMode in
                        editingService.setOutputMode(outputMode)
                    }
                )
            ) {
                Text("Component")
                    .tag(PatternArrayOutputMode.componentInstance)
                Text("Independent")
                    .tag(PatternArrayOutputMode.independentCopy)
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(minWidth: inspectorControlWidth)
            .accessibilityIdentifier("InspectorPatternArray.outputMode")
        }
    }

    @ViewBuilder
    private func linearAxisControls(
        _ title: String,
        axis: PatternArrayInspectorState.LinearAxis,
        accessibilityPrefix: String,
        setCopyCount: @escaping (Int) -> Void,
        setDistance: @escaping (Double) -> Void,
        setDistanceMode: @escaping (PatternArrayDistanceMode) -> Void
    ) -> some View {
        inspectorRow(title, "Linear")
        inspectorControlRow("\(title) Copies") {
            Stepper(
                value: Binding(
                    get: { axis.copyCount },
                    set: { setCopyCount($0) }
                ),
                in: 1 ... 10_000
            ) {
                Text("\(axis.copyCount)")
                    .monospacedDigit()
            }
            .accessibilityIdentifier("\(accessibilityPrefix).copyCount")
        }
        if let distanceMeters = axis.distanceMeters {
            lengthControl(
                "\(title) \(axis.distanceModeTitle)",
                meters: distanceMeters,
                sliderMetersRange: distanceSliderMetersRange(for: distanceMeters)
            ) { meters in
                setDistance(meters)
            }
            .accessibilityIdentifier("\(accessibilityPrefix).distance")
        } else {
            inspectorRow("\(title) \(axis.distanceModeTitle)", "Expression")
        }
        inspectorControlRow("\(title) Mode") {
            Picker(
                "",
                selection: Binding(
                    get: { axis.distanceMode },
                    set: { setDistanceMode($0) }
                )
            ) {
                Text("Spacing")
                    .tag(PatternArrayDistanceMode.spacing)
                Text("Extent")
                    .tag(PatternArrayDistanceMode.extent)
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(minWidth: inspectorControlWidth)
            .accessibilityIdentifier("\(accessibilityPrefix).distanceMode")
        }
    }

    @ViewBuilder
    private func radialAngularAxisControls(
        _ angularAxis: PatternArrayInspectorState.AngularAxis
    ) -> some View {
        inspectorRow("Angular Axis", vectorSummary(angularAxis.axis))
        transformLengthControl("Center X", values: [angularAxis.center.x]) { meters in
            setRadialCenter(x: meters)
        }
        .accessibilityIdentifier("InspectorPatternArray.radial.center.x")
        transformLengthControl("Center Y", values: [angularAxis.center.y]) { meters in
            setRadialCenter(y: meters)
        }
        .accessibilityIdentifier("InspectorPatternArray.radial.center.y")
        transformLengthControl("Center Z", values: [angularAxis.center.z]) { meters in
            setRadialCenter(z: meters)
        }
        .accessibilityIdentifier("InspectorPatternArray.radial.center.z")
        vectorComponentControl(
            "Axis X",
            value: angularAxis.axis.x,
            accessibilityIdentifier: "InspectorPatternArray.radial.axis.x"
        ) { value in
            setRadialAxisDirection(x: value)
        }
        vectorComponentControl(
            "Axis Y",
            value: angularAxis.axis.y,
            accessibilityIdentifier: "InspectorPatternArray.radial.axis.y"
        ) { value in
            setRadialAxisDirection(y: value)
        }
        vectorComponentControl(
            "Axis Z",
            value: angularAxis.axis.z,
            accessibilityIdentifier: "InspectorPatternArray.radial.axis.z"
        ) { value in
            setRadialAxisDirection(z: value)
        }
        inspectorControlRow("Angle Copies") {
            Stepper(
                value: Binding(
                    get: { angularAxis.copyCount },
                    set: { setRadialAngularCopyCount($0) }
                ),
                in: 1 ... 10_000
            ) {
                Text("\(angularAxis.copyCount)")
                    .monospacedDigit()
            }
            .accessibilityIdentifier("InspectorPatternArray.radial.angular.copyCount")
        }
        if let angleRadians = angularAxis.angleRadians {
            numericControl(
                angularAxis.angleModeTitle,
                values: [degrees(fromRadians: angleRadians)],
                sliderRange: -360.0 ... 360.0
            ) { degrees in
                setRadialAngle(degrees: degrees)
            } unitLabel: {
                "deg"
            }
            .accessibilityIdentifier("InspectorPatternArray.radial.angular.angle")
        } else {
            inspectorRow(angularAxis.angleModeTitle, "Expression")
        }
        inspectorControlRow("Angle Mode") {
            Picker(
                "",
                selection: Binding(
                    get: { angularAxis.angleMode },
                    set: { setRadialAngleMode($0) }
                )
            ) {
                Text("Spacing")
                    .tag(PatternArrayAngleMode.spacing)
                Text("Extent")
                    .tag(PatternArrayAngleMode.extent)
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(minWidth: inspectorControlWidth)
            .accessibilityIdentifier("InspectorPatternArray.radial.angular.angleMode")
        }
    }

    @ViewBuilder
    private func curveControls(
        _ curve: PatternArrayInspectorState.CurveDistribution
    ) -> some View {
        inspectorRow("Path", curve.pathTitle)
        curvePathReplacementControls
        inspectorControlRow("Curve Copies") {
            Stepper(
                value: Binding(
                    get: { curve.copyCount },
                    set: { setCurveCopyCount($0) }
                ),
                in: 1 ... 10_000
            ) {
                Text("\(curve.copyCount)")
                    .monospacedDigit()
            }
            .accessibilityIdentifier("InspectorPatternArray.curve.copyCount")
        }
        if let twistRadians = curve.twistRadians {
            numericControl(
                "Twist",
                values: [degrees(fromRadians: twistRadians)],
                sliderRange: -360.0 ... 360.0
            ) { degrees in
                setCurveTwist(degrees: degrees)
            } unitLabel: {
                "deg"
            }
            .accessibilityIdentifier("InspectorPatternArray.curve.twist")
        } else {
            inspectorRow("Twist", "Expression")
        }
        if let endScale = curve.endScale {
            numericControl(
                "End Scale",
                values: [endScale],
                sliderRange: 0.01 ... max(2.0, endScale * 2.0)
            ) { scale in
                setCurveEndScale(scale)
            } unitLabel: {
                "x"
            }
            .accessibilityIdentifier("InspectorPatternArray.curve.endScale")
        } else {
            inspectorRow("End Scale", "Expression")
        }
        curveAlignmentPicker(alignment: curve.alignment)
        curveExtentModePicker(curve: curve)
        switch curve.extentMode {
        case .distance:
            if let extentMeters = curve.extentMeters {
                lengthControl(
                    "Curve Extent",
                    meters: extentMeters,
                    sliderMetersRange: distanceSliderMetersRange(for: extentMeters)
                ) { meters in
                    setCurveExtentDistance(meters)
                }
                .accessibilityIdentifier("InspectorPatternArray.curve.extent.distance")
            } else {
                inspectorRow("Curve Extent", "Expression")
            }
        case .ratio:
            if let extentRatio = curve.extentRatio {
                numericControl(
                    "Curve Extent",
                    values: [extentRatio],
                    sliderRange: 0.01 ... 1.0
                ) { ratio in
                    setCurveExtentRatio(ratio)
                } unitLabel: {
                    "t"
                }
                .accessibilityIdentifier("InspectorPatternArray.curve.extent.ratio")
            } else {
                inspectorRow("Curve Extent", "Expression")
            }
        }
    }

    @ViewBuilder
    private var curvePathReplacementControls: some View {
        inspectorRow("Path Pick", isCurvePathPickActive ? "Pick Sketch Curve" : "Ready")
        inspectorActionRow {
            Button {
                if isCurvePathPickActive {
                    onCancelCurvePathPick()
                } else {
                    onStartCurvePathPick(state.sourceID)
                }
            } label: {
                Label(
                    isCurvePathPickActive ? "Cancel Path Pick" : "Pick Path in Viewport",
                    systemImage: isCurvePathPickActive ? "xmark.circle" : "cursorarrow.click"
                )
            }
            .controlSize(.small)
            .accessibilityIdentifier("InspectorPatternArray.curve.path.pick")
        }
    }

    private func vectorComponentControl(
        _ title: String,
        value: Double,
        accessibilityIdentifier: String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        numericControl(
            title,
            values: [value],
            sliderRange: -1.0 ... 1.0,
            onChange: onChange
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func curveAlignmentPicker(
        alignment: PatternArrayCurveAlignment
    ) -> some View {
        inspectorControlRow("Alignment") {
            Picker(
                "",
                selection: Binding(
                    get: { alignment },
                    set: { setCurveAlignment($0) }
                )
            ) {
                Text("Normal")
                    .tag(PatternArrayCurveAlignment.normal)
                Text("Parallel")
                    .tag(PatternArrayCurveAlignment.parallel)
                Text("Transport")
                    .tag(PatternArrayCurveAlignment.transport)
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(minWidth: inspectorControlWidth)
            .accessibilityIdentifier("InspectorPatternArray.curve.alignment")
        }
    }

    private func curveExtentModePicker(
        curve: PatternArrayInspectorState.CurveDistribution
    ) -> some View {
        inspectorControlRow("Extent Mode") {
            Picker(
                "",
                selection: Binding(
                    get: { curve.extentMode },
                    set: { setCurveExtentMode(curve: curve, extentMode: $0) }
                )
            ) {
                Text("Ratio")
                    .tag(PatternArrayCurveExtentMode.ratio)
                Text("Distance")
                    .tag(PatternArrayCurveExtentMode.distance)
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(minWidth: inspectorControlWidth)
            .accessibilityIdentifier("InspectorPatternArray.curve.extentMode")
        }
    }

    private var addRectangularSecondAxisButton: some View {
        inspectorActionRow {
            Button {
                setRectangularSecondAxisEnabled(true)
            } label: {
                Label("Add Second Axis", systemImage: "plus")
            }
            .controlSize(.small)
            .accessibilityIdentifier("InspectorPatternArray.rectangular.secondAxis.add")
        }
    }

    private var removeRectangularSecondAxisButton: some View {
        inspectorActionRow {
            Button(role: .destructive) {
                setRectangularSecondAxisEnabled(false)
            } label: {
                Label("Remove Second Axis", systemImage: "minus")
            }
            .controlSize(.small)
            .accessibilityIdentifier("InspectorPatternArray.rectangular.secondAxis.remove")
        }
    }

    private var addRadialAxisButton: some View {
        inspectorActionRow {
            Button {
                setRadialAxisEnabled(true)
            } label: {
                Label("Add Radial Repetition", systemImage: "plus")
            }
            .controlSize(.small)
            .accessibilityIdentifier("InspectorPatternArray.radial.radialAxis.add")
        }
    }

    private var removeRadialAxisButton: some View {
        inspectorActionRow {
            Button(role: .destructive) {
                setRadialAxisEnabled(false)
            } label: {
                Label("Remove Radial Repetition", systemImage: "minus")
            }
            .controlSize(.small)
            .accessibilityIdentifier("InspectorPatternArray.radial.radialAxis.remove")
        }
    }

    private var editingService: PatternArrayEditingService {
        PatternArrayEditingService(
            session: session,
            sourceID: state.sourceID
        )
    }

    private func setRectangularAxisCopyCount(
        slot: PatternArrayEditingService.RectangularAxisSlot,
        copyCount: Int
    ) {
        editingService.setRectangularAxisCopyCount(slot: slot, copyCount: copyCount)
    }

    private func setRectangularAxisDistance(
        slot: PatternArrayEditingService.RectangularAxisSlot,
        meters: Double
    ) {
        editingService.setRectangularAxisDistance(slot: slot, meters: meters)
    }

    private func setRectangularAxisDistanceMode(
        slot: PatternArrayEditingService.RectangularAxisSlot,
        distanceMode: PatternArrayDistanceMode
    ) {
        editingService.setRectangularAxisDistanceMode(slot: slot, distanceMode: distanceMode)
    }

    private func setRectangularSecondAxisEnabled(_ isEnabled: Bool) {
        editingService.setRectangularSecondAxisEnabled(
            isEnabled,
            fallbackDistanceMeters: state.rectangularFirstAxis?.distanceMeters
        )
    }

    private func setRadialCenter(
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil
    ) {
        editingService.setRadialCenter(x: x, y: y, z: z)
    }

    private func setRadialAxisDirection(
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil
    ) {
        editingService.setRadialAxisDirection(x: x, y: y, z: z)
    }

    private func setRadialAngularCopyCount(_ copyCount: Int) {
        editingService.setRadialAngularCopyCount(copyCount)
    }

    private func setRadialAngle(degrees: Double) {
        editingService.setRadialAngle(degrees: degrees)
    }

    private func setRadialAngleMode(_ angleMode: PatternArrayAngleMode) {
        editingService.setRadialAngleMode(angleMode)
    }

    private func setRadialAxisCopyCount(_ copyCount: Int) {
        editingService.setRadialAxisCopyCount(copyCount)
    }

    private func setRadialAxisDistance(_ meters: Double) {
        editingService.setRadialAxisDistance(meters)
    }

    private func setRadialAxisDistanceMode(_ distanceMode: PatternArrayDistanceMode) {
        editingService.setRadialAxisDistanceMode(distanceMode)
    }

    private func setRadialAxisEnabled(_ isEnabled: Bool) {
        editingService.setRadialAxisEnabled(isEnabled)
    }

    private func setCurveCopyCount(_ copyCount: Int) {
        editingService.setCurveCopyCount(copyCount)
    }

    private func setCurveTwist(degrees: Double) {
        editingService.setCurveTwist(degrees: degrees)
    }

    private func setCurveEndScale(_ scale: Double) {
        editingService.setCurveEndScale(scale)
    }

    private func setCurveAlignment(_ alignment: PatternArrayCurveAlignment) {
        editingService.setCurveAlignment(alignment)
    }

    private func setCurveExtentMode(
        curve: PatternArrayInspectorState.CurveDistribution,
        extentMode: PatternArrayCurveExtentMode
    ) {
        editingService.setCurveExtentMode(
            extentMode,
            fallbackDistanceMeters: curve.extentMeters,
            fallbackRatio: curve.extentRatio
        )
    }

    private func setCurveExtentDistance(_ meters: Double) {
        editingService.setCurveExtentDistance(meters)
    }

    private func setCurveExtentRatio(_ ratio: Double) {
        editingService.setCurveExtentRatio(ratio)
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
        HStack(spacing: inspectorRowSpacing) {
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

    private func distanceSliderMetersRange(for meters: Double) -> ClosedRange<Double> {
        workspaceLengthSliderMetersRange(
            for: meters,
            ruler: session.document.ruler,
            expansionMultiplier: 2.0
        )
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

    private func vectorSummary(_ vector: Vector3D) -> String {
        "(\(shortNumber(vector.x)), \(shortNumber(vector.y)), \(shortNumber(vector.z)))"
    }

    private func shortID<T: CustomStringConvertible>(_ id: T) -> String {
        String(id.description.prefix(8))
    }

    private func shortNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }

    private func degrees(fromRadians radians: Double) -> Double {
        radians * 180.0 / Double.pi
    }

    private var inspectorLabelWidth: CGFloat { 124 }
    private var inspectorControlWidth: CGFloat { 104 }
    private var inspectorUnitWidth: CGFloat { 36 }
    private var inspectorRowSpacing: CGFloat { 10 }
    private var inspectorSliderLeadingPadding: CGFloat {
        inspectorLabelWidth + inspectorRowSpacing
    }
}
