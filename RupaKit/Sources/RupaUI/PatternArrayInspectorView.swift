import RupaCore
import SwiftUI

@MainActor
struct PatternArrayInspectorView: View {
    let state: PatternArrayInspectorState
    let session: EditorSession
    let positionSliderRange: ClosedRange<Double>

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
                        session.updatePatternArray(
                            id: state.sourceID,
                            outputMode: outputMode
                        )
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
                sliderRange: distanceSliderRange(for: distanceMeters)
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
                    sliderRange: distanceSliderRange(for: extentMeters)
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
                    sliderRange: 0.01 ... max(1.0, extentRatio * 2.0)
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

    private enum RectangularAxisSlot {
        case first
        case second
    }

    private func setRectangularAxisCopyCount(
        slot: RectangularAxisSlot,
        copyCount: Int
    ) {
        updateRectangularAxis(slot: slot) { axis in
            axis.copyCount = max(copyCount, 1)
        }
    }

    private func setRectangularAxisDistance(
        slot: RectangularAxisSlot,
        meters: Double
    ) {
        updateRectangularAxis(slot: slot) { axis in
            axis.distance = .length(max(meters, 0.0), .meter)
        }
    }

    private func setRectangularAxisDistanceMode(
        slot: RectangularAxisSlot,
        distanceMode: PatternArrayDistanceMode
    ) {
        updateRectangularAxis(slot: slot) { axis in
            axis.distanceMode = distanceMode
        }
    }

    private func setRectangularSecondAxisEnabled(_ isEnabled: Bool) {
        guard let source = session.document.productMetadata.patternArrays[state.sourceID],
              case .rectangular(var rectangular) = source.distribution else {
            return
        }
        if isEnabled {
            guard rectangular.secondAxis == nil else {
                return
            }
            let distanceMeters = state.rectangularFirstAxis?.distanceMeters ?? 0.01
            rectangular.secondAxis = PatternArrayLinearAxis(
                direction: defaultPerpendicularDirection(to: rectangular.firstAxis.direction),
                distance: .length(max(distanceMeters, 1.0e-9), .meter),
                copyCount: 1,
                distanceMode: rectangular.firstAxis.distanceMode
            )
        } else {
            rectangular.secondAxis = nil
        }
        session.updatePatternArray(
            id: state.sourceID,
            distribution: .rectangular(rectangular)
        )
    }

    private func updateRectangularAxis(
        slot: RectangularAxisSlot,
        update: (inout PatternArrayLinearAxis) -> Void
    ) {
        guard let source = session.document.productMetadata.patternArrays[state.sourceID],
              case .rectangular(var rectangular) = source.distribution else {
            return
        }
        switch slot {
        case .first:
            update(&rectangular.firstAxis)
        case .second:
            guard var secondAxis = rectangular.secondAxis else {
                return
            }
            update(&secondAxis)
            rectangular.secondAxis = secondAxis
        }
        session.updatePatternArray(
            id: state.sourceID,
            distribution: .rectangular(rectangular)
        )
    }

    private func setRadialCenter(
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil
    ) {
        updateRadialAngularAxis { angularAxis in
            angularAxis.center = Point3D(
                x: x ?? angularAxis.center.x,
                y: y ?? angularAxis.center.y,
                z: z ?? angularAxis.center.z
            )
        }
    }

    private func setRadialAxisDirection(
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil
    ) {
        updateRadialAngularAxis { angularAxis in
            angularAxis.axis = Vector3D(
                x: x ?? angularAxis.axis.x,
                y: y ?? angularAxis.axis.y,
                z: z ?? angularAxis.axis.z
            )
        }
    }

    private func setRadialAngularCopyCount(_ copyCount: Int) {
        updateRadialAngularAxis { angularAxis in
            angularAxis.copyCount = max(copyCount, 1)
        }
    }

    private func setRadialAngle(degrees: Double) {
        updateRadialAngularAxis { angularAxis in
            angularAxis.angle = .angle(degrees, .degree)
        }
    }

    private func setRadialAngleMode(_ angleMode: PatternArrayAngleMode) {
        updateRadialAngularAxis { angularAxis in
            angularAxis.angleMode = angleMode
        }
    }

    private func updateRadialAngularAxis(
        update: (inout PatternArrayAngularAxis) -> Void
    ) {
        guard let source = session.document.productMetadata.patternArrays[state.sourceID],
              case .radial(var radial) = source.distribution else {
            return
        }
        update(&radial.angularAxis)
        session.updatePatternArray(
            id: state.sourceID,
            distribution: .radial(radial)
        )
    }

    private func setRadialAxisCopyCount(_ copyCount: Int) {
        updateRadialAxis { radialAxis in
            radialAxis.copyCount = max(copyCount, 1)
        }
    }

    private func setRadialAxisDistance(_ meters: Double) {
        updateRadialAxis { radialAxis in
            radialAxis.distance = .length(max(meters, 0.0), .meter)
        }
    }

    private func setRadialAxisDistanceMode(_ distanceMode: PatternArrayDistanceMode) {
        updateRadialAxis { radialAxis in
            radialAxis.distanceMode = distanceMode
        }
    }

    private func setRadialAxisEnabled(_ isEnabled: Bool) {
        guard let source = session.document.productMetadata.patternArrays[state.sourceID],
              case .radial(var radial) = source.distribution else {
            return
        }
        if isEnabled {
            guard radial.radialAxis == nil else {
                return
            }
            radial.radialAxis = PatternArrayLinearAxis(
                direction: defaultPerpendicularDirection(to: radial.angularAxis.axis),
                distance: .length(0.01, .meter),
                copyCount: 1,
                distanceMode: .spacing
            )
        } else {
            radial.radialAxis = nil
        }
        session.updatePatternArray(
            id: state.sourceID,
            distribution: .radial(radial)
        )
    }

    private func updateRadialAxis(
        update: (inout PatternArrayLinearAxis) -> Void
    ) {
        guard let source = session.document.productMetadata.patternArrays[state.sourceID],
              case .radial(var radial) = source.distribution,
              var radialAxis = radial.radialAxis else {
            return
        }
        update(&radialAxis)
        radial.radialAxis = radialAxis
        session.updatePatternArray(
            id: state.sourceID,
            distribution: .radial(radial)
        )
    }

    private func setCurveCopyCount(_ copyCount: Int) {
        updateCurve { curve in
            curve.copyCount = max(copyCount, 1)
        }
    }

    private func setCurveTwist(degrees: Double) {
        updateCurve { curve in
            curve.twist = .angle(degrees, .degree)
        }
    }

    private func setCurveEndScale(_ scale: Double) {
        updateCurve { curve in
            curve.endScale = .scalar(max(scale, 1.0e-9))
        }
    }

    private func setCurveAlignment(_ alignment: PatternArrayCurveAlignment) {
        updateCurve { curve in
            curve.alignment = alignment
        }
    }

    private func setCurveExtentMode(
        curve: PatternArrayInspectorState.CurveDistribution,
        extentMode: PatternArrayCurveExtentMode
    ) {
        updateCurve { sourceCurve in
            sourceCurve.extentMode = extentMode
            switch extentMode {
            case .distance:
                sourceCurve.extent = .length(max(curve.extentMeters ?? 0.01, 1.0e-9), .meter)
            case .ratio:
                sourceCurve.extent = .scalar(max(curve.extentRatio ?? 1.0, 1.0e-9))
            }
        }
    }

    private func setCurveExtentDistance(_ meters: Double) {
        updateCurve { curve in
            curve.extentMode = .distance
            curve.extent = .length(max(meters, 1.0e-9), .meter)
        }
    }

    private func setCurveExtentRatio(_ ratio: Double) {
        updateCurve { curve in
            curve.extentMode = .ratio
            curve.extent = .scalar(max(ratio, 1.0e-9))
        }
    }

    private func updateCurve(update: (inout CurvePatternArray) -> Void) {
        guard let source = session.document.productMetadata.patternArrays[state.sourceID],
              case .curve(var curve) = source.distribution else {
            return
        }
        update(&curve)
        session.updatePatternArray(
            id: state.sourceID,
            distribution: .curve(curve)
        )
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
        let unit = session.document.displayUnit
        return numericControl(
            title,
            values: values.map { unit.value(fromMeters: $0) },
            sliderRange: positionSliderRange
        ) { value in
            onChange(unit.meters(from: value))
        } unitLabel: {
            unit.symbol
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
                    return commonValue.formatted(.number.precision(.fractionLength(0...6)))
                }
                return "Mixed"
            },
            set: { text in
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = Double(trimmedText), value.isFinite else {
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
        sliderRange: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        let unit = session.document.displayUnit
        let value = unit.value(fromMeters: meters)
        let fieldBinding = Binding<Double>(
            get: { value },
            set: { newValue in
                onChange(unit.meters(from: max(newValue, 0.0)))
            }
        )
        let sliderBinding = Binding<Double>(
            get: { min(max(value, sliderRange.lowerBound), sliderRange.upperBound) },
            set: { newValue in
                onChange(unit.meters(from: newValue))
            }
        )

        return VStack(alignment: .leading, spacing: 5) {
            inspectorControlRow(title) {
                HStack(spacing: 6) {
                    TextField(title, value: fieldBinding, formatter: numberFormatter)
                        .multilineTextAlignment(.trailing)
                        .frame(width: inspectorControlWidth)
                    Text(unit.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: inspectorUnitWidth, alignment: .leading)
                }
            }
            Slider(value: sliderBinding, in: sliderRange)
                .padding(.leading, inspectorSliderLeadingPadding)
        }
        .padding(.vertical, 1)
    }

    private func distanceSliderRange(for meters: Double) -> ClosedRange<Double> {
        let unit = session.document.displayUnit
        let currentValue = max(unit.value(fromMeters: meters), 0.001)
        return 0.0 ... max(currentValue * 2.0, 1.0)
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

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter
    }

    private func defaultPerpendicularDirection(to direction: Vector3D) -> Vector3D {
        let length = direction.length
        guard length.isFinite, length > 1.0e-9 else {
            return .unitY
        }
        let unitDirection = Vector3D(
            x: direction.x / length,
            y: direction.y / length,
            z: direction.z / length
        )
        return abs(unitDirection.dot(.unitY)) < 0.9 ? .unitY : .unitX
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
