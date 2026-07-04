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
                workspaceInspectorValueRow("Kind", state.planeKindTitle)
                workspaceInspectorValueRow("Active", state.isActive ? "Yes" : "No")
                if let sceneNodeID = state.sceneNodeID {
                    workspaceInspectorValueRow("Scene Node", shortID(sceneNodeID))
                }

                workspaceLengthControl(
                    "Origin X",
                    values: [state.origin.x],
                    displayUnit: displayUnit,
                    sliderMetersRange: originSliderMetersRange
                ) { meters in
                    onSetOriginComponent(.x, meters)
                }
                workspaceLengthControl(
                    "Origin Y",
                    values: [state.origin.y],
                    displayUnit: displayUnit,
                    sliderMetersRange: originSliderMetersRange
                ) { meters in
                    onSetOriginComponent(.y, meters)
                }
                workspaceLengthControl(
                    "Origin Z",
                    values: [state.origin.z],
                    displayUnit: displayUnit,
                    sliderMetersRange: originSliderMetersRange
                ) { meters in
                    onSetOriginComponent(.z, meters)
                }

                numericControl(
                    "Normal X",
                    values: [state.normal.x],
                    sliderRange: -1.0 ... 1.0
                ) { value in
                    onSetNormalComponent(.x, value)
                }
                numericControl(
                    "Normal Y",
                    values: [state.normal.y],
                    sliderRange: -1.0 ... 1.0
                ) { value in
                    onSetNormalComponent(.y, value)
                }
                numericControl(
                    "Normal Z",
                    values: [state.normal.z],
                    sliderRange: -1.0 ... 1.0
                ) { value in
                    onSetNormalComponent(.z, value)
                }

                inspectorActionRow {
                    Button("Activate") {
                        onActivate()
                    }
                    .disabled(state.isActive)

                    Button("From View") {
                        onUpdateFromView()
                    }
                }
            }
        }
    }

    private func shortID<T: CustomStringConvertible>(_ id: T) -> String {
        String(id.description.prefix(8))
    }
}
