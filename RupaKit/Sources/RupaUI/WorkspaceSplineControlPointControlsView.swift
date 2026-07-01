import SwiftUI
import RupaCore

struct WorkspaceSplineControlPointControlsView: View {
    var entity: InspectorSketchEntity
    var displayUnit: LengthDisplayUnit
    var selectedControlPointIndexes: [Int]
    @Binding var selectedControlPointIndex: Int
    @Binding var slideDistanceMeters: Double
    @Binding var slideCount: Int
    var moveStepMeters: Double
    var slideDistanceSliderRange: ClosedRange<Double>
    var onAddSmoothControlPoint: (InspectorSketchEntity, Int) -> Void
    var onMoveControlPoint: (SelectionTarget, Int, Double, Double) -> Void
    var onSlideControlPoints: (SelectionTarget, [Int], SplineControlPointSlideDirection) -> Void

    var body: some View {
        if entity.controlPoints.isEmpty {
            workspaceInspectorValueRow("Control Point", "None")
        } else {
            controls
        }
    }

    private var controls: some View {
        let index = clampedControlPointIndex
        let slideIndexes = selectedControlPointIndexes.isEmpty
            ? selectedSlideIndexes(startIndex: index, maximumControlPointCount: entity.controlPoints.count)
            : selectedControlPointIndexes

        return Group {
            controlPointIndexControl(index: index)
            workspaceInspectorValueRow("Point", sketchPointSummary(entity.controlPoints[index]))
            smoothConstraintControls(controlPointIndex: index)
            controlPointMoveControls(index: index)
            slideDistanceControl
            slideCountOrSelectionControls(index: index)
            slideControls(controlPointIndexes: slideIndexes)
        }
    }

    private func controlPointIndexControl(index: Int) -> some View {
        let indexBounds = 0 ... max(entity.controlPoints.count - 1, 0)
        return inspectorControlRow("Control Point") {
            Stepper(
                value: Binding<Int>(
                    get: { clampedControlPointIndex },
                    set: { selectedControlPointIndex = clamped($0, in: entity.controlPoints.indices) }
                ),
                in: indexBounds
            ) {
                Text("\(index + 1) / \(entity.controlPoints.count)")
                    .monospacedDigit()
            }
            .accessibilityIdentifier("InspectorCurve.spline.controlPointIndex")
        }
    }

    @ViewBuilder
    private func smoothConstraintControls(controlPointIndex index: Int) -> some View {
        if isSmoothableSplineControlPoint(index, controlPointCount: entity.controlPoints.count) {
            if entity.smoothSplineControlPointIndexes.contains(index) {
                workspaceInspectorValueRow("Smooth", "On")
            } else {
                inspectorActionRow {
                    Button {
                        onAddSmoothControlPoint(entity, index)
                    } label: {
                        Label("Smooth", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .accessibilityIdentifier("InspectorCurve.spline.smoothControlPoint")
                }
            }
        } else {
            workspaceInspectorValueRow("Smooth", "Unavailable")
        }
    }

    @ViewBuilder
    private func controlPointMoveControls(index: Int) -> some View {
        let title = "Point \(index + 1)"
        let accessibilityPrefix = "InspectorCurve.spline.controlPoint"
        inspectorControlRow("\(title) X") {
            HStack(spacing: 6) {
                moveButton(
                    systemImage: "arrow.left",
                    help: "Move \(title.lowercased()) negative X",
                    accessibilityIdentifier: "\(accessibilityPrefix).moveXNegative"
                ) {
                    onMoveControlPoint(entity.target, index, -moveStepMeters, 0.0)
                }
                moveButton(
                    systemImage: "arrow.right",
                    help: "Move \(title.lowercased()) positive X",
                    accessibilityIdentifier: "\(accessibilityPrefix).moveXPositive"
                ) {
                    onMoveControlPoint(entity.target, index, moveStepMeters, 0.0)
                }
            }
        }
        inspectorControlRow("\(title) Y") {
            HStack(spacing: 6) {
                moveButton(
                    systemImage: "arrow.down",
                    help: "Move \(title.lowercased()) negative Y",
                    accessibilityIdentifier: "\(accessibilityPrefix).moveYNegative"
                ) {
                    onMoveControlPoint(entity.target, index, 0.0, -moveStepMeters)
                }
                moveButton(
                    systemImage: "arrow.up",
                    help: "Move \(title.lowercased()) positive Y",
                    accessibilityIdentifier: "\(accessibilityPrefix).moveYPositive"
                ) {
                    onMoveControlPoint(entity.target, index, 0.0, moveStepMeters)
                }
            }
        }
    }

    private var slideDistanceControl: some View {
        numericControl(
            "Slide CV",
            values: [slideDistanceMeters],
            sliderRange: slideDistanceSliderRange
        ) { distance in
            slideDistanceMeters = max(distance, 1.0e-9)
        } unitLabel: {
            "m"
        }
    }

    @ViewBuilder
    private func slideCountOrSelectionControls(index: Int) -> some View {
        if selectedControlPointIndexes.isEmpty {
            let slideCountBounds = 1 ... max(entity.controlPoints.count - index, 1)
            inspectorControlRow("Slide Count") {
                Stepper(
                    value: Binding<Int>(
                        get: { min(max(slideCount, slideCountBounds.lowerBound), slideCountBounds.upperBound) },
                        set: { slideCount = min(max($0, slideCountBounds.lowerBound), slideCountBounds.upperBound) }
                    ),
                    in: slideCountBounds
                ) {
                    Text("\(min(max(slideCount, slideCountBounds.lowerBound), slideCountBounds.upperBound))")
                        .monospacedDigit()
                }
                .accessibilityIdentifier("InspectorCurve.spline.slideCount")
            }
        } else {
            workspaceInspectorValueRow(
                "Selected CVs",
                splineControlPointSelectionSummary(selectedControlPointIndexes)
            )
        }
    }

    private func slideControls(controlPointIndexes: [Int]) -> some View {
        let accessibilityPrefix = "InspectorCurve.spline.controlPoint"
        return inspectorControlRow("Slide") {
            HStack(spacing: 6) {
                moveButton(
                    systemImage: "arrow.right",
                    help: "Slide control point positive U",
                    accessibilityIdentifier: "\(accessibilityPrefix).slidePositiveU"
                ) {
                    onSlideControlPoints(entity.target, controlPointIndexes, .positiveU)
                }
                moveButton(
                    systemImage: "arrow.left",
                    help: "Slide control point negative U",
                    accessibilityIdentifier: "\(accessibilityPrefix).slideNegativeU"
                ) {
                    onSlideControlPoints(entity.target, controlPointIndexes, .negativeU)
                }
                moveButton(
                    systemImage: "arrow.up.right",
                    help: "Slide control point normal",
                    accessibilityIdentifier: "\(accessibilityPrefix).slideNormal"
                ) {
                    onSlideControlPoints(entity.target, controlPointIndexes, .normal)
                }
            }
        }
    }

    private var clampedControlPointIndex: Int {
        clamped(selectedControlPointIndex, in: entity.controlPoints.indices)
    }

    private func selectedSlideIndexes(
        startIndex: Int,
        maximumControlPointCount: Int
    ) -> [Int] {
        guard maximumControlPointCount > 0 else {
            return []
        }
        let clampedStartIndex = min(max(startIndex, 0), maximumControlPointCount - 1)
        let requestedCount = max(slideCount, 1)
        let upperBound = min(maximumControlPointCount, clampedStartIndex + requestedCount)
        return Array(clampedStartIndex..<upperBound)
    }

    private func splineControlPointSelectionSummary(_ indexes: [Int]) -> String {
        guard indexes.isEmpty == false else {
            return "None"
        }
        let labels = indexes.sorted().map { String($0 + 1) }.joined(separator: ", ")
        if indexes.count == 1 {
            return "1 CV: \(labels)"
        }
        return "\(indexes.count) CVs: \(labels)"
    }

    private func isSmoothableSplineControlPoint(_ index: Int, controlPointCount: Int) -> Bool {
        index > 0 && index < controlPointCount - 1 && index.isMultiple(of: 3)
    }

    private func sketchPointSummary(_ point: SketchEntitySummaryResult.Point) -> String {
        "x \(formatted(point.x)), y \(formatted(point.y))"
    }

    private func formatted(_ meters: Double) -> String {
        WorkspaceInspectorNumberText.lengthString(
            fromMeters: meters,
            unit: displayUnit
        )
    }

    private func clamped(_ value: Int, in range: Range<Int>) -> Int {
        guard let lowerBound = range.first,
              let upperBound = range.last else {
            return 0
        }
        return min(max(value, lowerBound), upperBound)
    }

    private func moveButton(
        systemImage: String,
        help: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
