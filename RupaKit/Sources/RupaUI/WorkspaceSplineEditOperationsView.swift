import SwiftUI
import RupaCore

struct WorkspaceSplineEditOperationsView: View {
    var target: SelectionTarget
    @Binding var rebuildControlPointCount: Int
    @Binding var rebuildToleranceMeters: Double
    var rebuildToleranceMetersRange: ClosedRange<Double>
    @Binding var rebuildKeepsCorners: Bool
    @Binding var explicitDegree: Int
    @Binding var explicitSpanCount: Int
    @Binding var explicitWeight: Double
    var onReverse: (SelectionTarget) -> Void
    var onSplit: (SelectionTarget) -> Void
    var onInsertControlPoint: (SelectionTarget) -> Void
    var onRebuild: (SelectionTarget) -> Void
    var onRefit: (SelectionTarget) -> Void
    var onExplicit: (SelectionTarget) -> Void
    var onTrim: (SelectionTarget) -> Void

    var body: some View {
        inspectorControlRow("Rebuild CVs") {
            Stepper(
                value: $rebuildControlPointCount,
                in: 4 ... 31,
                step: 3
            ) {
                Text("\(rebuildControlPointCount)")
                    .monospacedDigit()
            }
            .accessibilityIdentifier("InspectorCurve.spline.rebuildControlPointCount")
        }
        numericControl(
            "Refit Tol",
            values: [rebuildToleranceMeters],
            sliderRange: rebuildToleranceMetersRange
        ) { tolerance in
            rebuildToleranceMeters = min(
                max(tolerance, rebuildToleranceMetersRange.lowerBound),
                rebuildToleranceMetersRange.upperBound
            )
        } unitLabel: {
            "m"
        }
        inspectorControlRow("Keep Corners") {
            Toggle("", isOn: $rebuildKeepsCorners)
                .labelsHidden()
                .accessibilityIdentifier("InspectorCurve.spline.refitKeepCorners")
        }
        inspectorControlRow("Degree") {
            Stepper(
                value: $explicitDegree,
                in: 1 ... 7
            ) {
                Text("\(explicitDegree)")
                    .monospacedDigit()
            }
            .accessibilityIdentifier("InspectorCurve.spline.explicitDegree")
        }
        inspectorControlRow("Spans") {
            Stepper(
                value: $explicitSpanCount,
                in: 1 ... 64
            ) {
                Text("\(explicitSpanCount)")
                    .monospacedDigit()
            }
            .accessibilityIdentifier("InspectorCurve.spline.explicitSpans")
        }
        numericControl(
            "Weight",
            values: [explicitWeight],
            sliderRange: 0.0 ... 1.0
        ) { weight in
            explicitWeight = min(max(weight, 0.0), 1.0)
        }
        .accessibilityIdentifier("InspectorCurve.spline.explicitWeight")
        inspectorActionRow {
            Button {
                onReverse(target)
            } label: {
                Label("Reverse", systemImage: "arrow.left.arrow.right")
            }
            .accessibilityIdentifier("InspectorCurve.spline.reverse")

            Button {
                onSplit(target)
            } label: {
                Label("Split", systemImage: "scissors")
            }
            .accessibilityIdentifier("InspectorCurve.spline.split")

            Button {
                onInsertControlPoint(target)
            } label: {
                Label("Insert CV", systemImage: "plus")
            }
            .accessibilityIdentifier("InspectorCurve.spline.insertControlPoint")

            Button {
                onRebuild(target)
            } label: {
                Label("Rebuild", systemImage: "point.3.filled.connected.trianglepath.dotted")
            }
            .accessibilityIdentifier("InspectorCurve.spline.rebuild")

            Button {
                onRefit(target)
            } label: {
                Label("Refit", systemImage: "arrow.triangle.2.circlepath")
            }
            .accessibilityIdentifier("InspectorCurve.spline.refit")

            Button {
                onExplicit(target)
            } label: {
                Label("Explicit", systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("InspectorCurve.spline.explicit")

            Button {
                onTrim(target)
            } label: {
                Label("Trim", systemImage: "delete.left")
            }
            .accessibilityIdentifier("InspectorCurve.spline.trim")
        }
    }
}
