import SwiftUI
import RupaCore

struct WorkspaceConstructionPlaneInspectorView: View {
    var state: WorkspaceConstructionPlaneInspectorState?
    var displayUnit: LengthDisplayUnit
    var originSliderMetersRange: ClosedRange<Double>
    var onSetOriginComponent: (WorkspaceConstructionPlaneOriginComponent, Double) -> Void
    var onSetNormalComponent: (WorkspaceConstructionPlaneNormalComponent, Double) -> Void
    var onActivate: () -> Void
    var onUpdateFromView: () -> Void

    var body: some View {
        if let state {
            inspectorSection("Construction Plane") {
                workspaceInspectorValueRow("Name", state.name)
                    .accessibilityIdentifier("InspectorConstructionPlane.name")
                workspaceInspectorValueRow("Kind", state.planeKindTitle)
                    .accessibilityIdentifier("InspectorConstructionPlane.kind")
                workspaceInspectorValueRow("Active", state.isActive ? "Yes" : "No")
                    .accessibilityIdentifier("InspectorConstructionPlane.active")
                if let sceneNodeID = state.sceneNodeID {
                    workspaceInspectorValueRow("Scene Node", shortID(sceneNodeID))
                        .accessibilityIdentifier("InspectorConstructionPlane.sceneNode")
                }

                workspaceLengthControl(
                    "Origin X",
                    values: [state.origin.x],
                    displayUnit: displayUnit,
                    sliderMetersRange: originSliderMetersRange
                ) { meters in
                    onSetOriginComponent(.x, meters)
                }
                .accessibilityIdentifier("InspectorConstructionPlane.origin.x")
                workspaceLengthControl(
                    "Origin Y",
                    values: [state.origin.y],
                    displayUnit: displayUnit,
                    sliderMetersRange: originSliderMetersRange
                ) { meters in
                    onSetOriginComponent(.y, meters)
                }
                .accessibilityIdentifier("InspectorConstructionPlane.origin.y")
                workspaceLengthControl(
                    "Origin Z",
                    values: [state.origin.z],
                    displayUnit: displayUnit,
                    sliderMetersRange: originSliderMetersRange
                ) { meters in
                    onSetOriginComponent(.z, meters)
                }
                .accessibilityIdentifier("InspectorConstructionPlane.origin.z")

                numericControl(
                    "Normal X",
                    values: [state.normal.x],
                    sliderRange: -1.0 ... 1.0
                ) { value in
                    onSetNormalComponent(.x, value)
                }
                .accessibilityIdentifier("InspectorConstructionPlane.normal.x")
                numericControl(
                    "Normal Y",
                    values: [state.normal.y],
                    sliderRange: -1.0 ... 1.0
                ) { value in
                    onSetNormalComponent(.y, value)
                }
                .accessibilityIdentifier("InspectorConstructionPlane.normal.y")
                numericControl(
                    "Normal Z",
                    values: [state.normal.z],
                    sliderRange: -1.0 ... 1.0
                ) { value in
                    onSetNormalComponent(.z, value)
                }
                .accessibilityIdentifier("InspectorConstructionPlane.normal.z")

                inspectorActionRow {
                    Button("Activate") {
                        onActivate()
                    }
                    .disabled(state.isActive)
                    .accessibilityIdentifier("InspectorConstructionPlane.activate")

                    Button("From View") {
                        onUpdateFromView()
                    }
                    .accessibilityIdentifier("InspectorConstructionPlane.fromView")
                }
            }
        }
    }

    private func shortID<T: CustomStringConvertible>(_ id: T) -> String {
        String(id.description.prefix(8))
    }
}
