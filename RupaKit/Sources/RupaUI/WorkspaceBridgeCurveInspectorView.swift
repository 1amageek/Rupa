import SwiftUI
import RupaCore

typealias BridgeCurveParameterHandler = (InspectorBridgeCurve, InspectorBridgeCurveEndpoint, Double) -> Void
typealias BridgeCurveEndpointHandler = (InspectorBridgeCurve, InspectorBridgeCurveEndpoint) -> Void
typealias BridgeCurveTrimHandler = (InspectorBridgeCurve) -> Void
typealias BridgeCurveTensionHandler = (
    InspectorBridgeCurve,
    InspectorBridgeCurveEndpoint,
    InspectorBridgeCurveTensionLevel,
    Double
) -> Void
typealias BridgeCurveContinuityHandler = (
    InspectorBridgeCurve,
    InspectorBridgeCurveEndpoint,
    BridgeCurveEndpointContinuity
) -> Void

struct WorkspaceBridgeCurveInspectorView: View {
    var bridgeCurve: InspectorBridgeCurve
    var onSetParameter: BridgeCurveParameterHandler
    var onSetSense: BridgeCurveEndpointHandler
    var onTrimSources: BridgeCurveTrimHandler
    var onSetTension: BridgeCurveTensionHandler
    var onSetContinuity: BridgeCurveContinuityHandler

    var body: some View {
        inspectorSection("Bridge Source") {
            workspaceInspectorValueRow("Source ID", shortID(bridgeCurve.sourceID))
            workspaceInspectorValueRow("Continuity", bridgeContinuityTitle(bridgeCurve.continuity))
            workspaceInspectorValueRow("Trim", bridgeCurve.trimsSourceCurves ? "Source curves trimmed" : "Off")
            workspaceInspectorValueRow(
                "Start Continuity",
                bridgeEndpointContinuityTitle(bridgeCurve.continuity.first)
            )
            workspaceInspectorValueRow(
                "End Continuity",
                bridgeEndpointContinuityTitle(bridgeCurve.continuity.second)
            )
            workspaceInspectorValueRow("First", sketchReferenceTitle(bridgeCurve.firstEndpoint.reference))
            workspaceInspectorValueRow("Second", sketchReferenceTitle(bridgeCurve.secondEndpoint.reference))
            bridgeCurveParameterControl(
                "Start Value",
                value: bridgeCurve.firstParameter
            ) { value in
                onSetParameter(bridgeCurve, .first, value)
            }
            bridgeCurveParameterControl(
                "End Value",
                value: bridgeCurve.secondParameter
            ) { value in
                onSetParameter(bridgeCurve, .second, value)
            }
            senseControls
            trimControl
            tensionControls
            startContinuityControls
            endContinuityControls
        }
    }

    private var senseControls: some View {
        inspectorActionRow {
            Button {
                onSetSense(bridgeCurve, .first)
            } label: {
                Label(
                    bridgeCurve.firstEndpoint.reversesSense ? "Start Sense Reversed" : "Start Sense",
                    systemImage: "arrow.left.and.right"
                )
            }
            .accessibilityIdentifier("InspectorCurve.bridge.startSense")

            Button {
                onSetSense(bridgeCurve, .second)
            } label: {
                Label(
                    bridgeCurve.secondEndpoint.reversesSense ? "End Sense Reversed" : "End Sense",
                    systemImage: "arrow.left.and.right"
                )
            }
            .accessibilityIdentifier("InspectorCurve.bridge.endSense")
        }
    }

    private var trimControl: some View {
        inspectorActionRow {
            Button {
                onTrimSources(bridgeCurve)
            } label: {
                Label("Trim Sources", systemImage: "scissors")
            }
            .disabled(bridgeCurve.trimsSourceCurves)
            .accessibilityIdentifier("InspectorCurve.bridge.trimSources")
        }
    }

    private var tensionControls: some View {
        Group {
            bridgeCurveTensionControl(
                "Start Tension 1",
                value: bridgeCurve.firstTension.first
            ) { value in
                onSetTension(bridgeCurve, .first, .first, value)
            }
            bridgeCurveTensionControl(
                "Start Tension 2",
                value: bridgeCurve.firstTension.second
            ) { value in
                onSetTension(bridgeCurve, .first, .second, value)
            }
            bridgeCurveTensionControl(
                "Start Tension 3",
                value: bridgeCurve.firstTension.third
            ) { value in
                onSetTension(bridgeCurve, .first, .third, value)
            }
            bridgeCurveTensionControl(
                "End Tension 1",
                value: bridgeCurve.secondTension.first
            ) { value in
                onSetTension(bridgeCurve, .second, .first, value)
            }
            bridgeCurveTensionControl(
                "End Tension 2",
                value: bridgeCurve.secondTension.second
            ) { value in
                onSetTension(bridgeCurve, .second, .second, value)
            }
            bridgeCurveTensionControl(
                "End Tension 3",
                value: bridgeCurve.secondTension.third
            ) { value in
                onSetTension(bridgeCurve, .second, .third, value)
            }
        }
    }

    private var startContinuityControls: some View {
        inspectorActionRow {
            continuityButton(
                title: "Start G0",
                systemImage: "smallcircle.filled.circle",
                endpoint: .first,
                continuity: .g0,
                current: bridgeCurve.continuity.first,
                accessibilityIdentifier: "InspectorCurve.bridge.startContinuityG0"
            )
            continuityButton(
                title: "Start G1",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                endpoint: .first,
                continuity: .g1,
                current: bridgeCurve.continuity.first,
                accessibilityIdentifier: "InspectorCurve.bridge.startContinuityG1"
            )
            continuityButton(
                title: "Start G2",
                systemImage: "point.3.connected.trianglepath.dotted",
                endpoint: .first,
                continuity: .g2,
                current: bridgeCurve.continuity.first,
                accessibilityIdentifier: "InspectorCurve.bridge.startContinuityG2"
            )
        }
    }

    private var endContinuityControls: some View {
        inspectorActionRow {
            continuityButton(
                title: "End G0",
                systemImage: "smallcircle.filled.circle",
                endpoint: .second,
                continuity: .g0,
                current: bridgeCurve.continuity.second,
                accessibilityIdentifier: "InspectorCurve.bridge.endContinuityG0"
            )
            continuityButton(
                title: "End G1",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                endpoint: .second,
                continuity: .g1,
                current: bridgeCurve.continuity.second,
                accessibilityIdentifier: "InspectorCurve.bridge.endContinuityG1"
            )
            continuityButton(
                title: "End G2",
                systemImage: "point.3.connected.trianglepath.dotted",
                endpoint: .second,
                continuity: .g2,
                current: bridgeCurve.continuity.second,
                accessibilityIdentifier: "InspectorCurve.bridge.endContinuityG2"
            )
        }
    }

    private func continuityButton(
        title: String,
        systemImage: String,
        endpoint: InspectorBridgeCurveEndpoint,
        continuity: BridgeCurveEndpointContinuity,
        current: BridgeCurveEndpointContinuity,
        accessibilityIdentifier: String
    ) -> some View {
        Button {
            onSetContinuity(bridgeCurve, endpoint, continuity)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .disabled(current == continuity)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func bridgeCurveTensionControl(
        _ title: String,
        value: Double,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        numericControl(
            title,
            values: [value],
            sliderRange: bridgeTensionSliderRange(for: value)
        ) { nextValue in
            onChange(max(nextValue, 1.0e-6))
        }
    }

    private func bridgeCurveParameterControl(
        _ title: String,
        value: Double,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        numericControl(
            title,
            values: [value],
            sliderRange: 0.0 ... 1.0
        ) { nextValue in
            onChange(min(max(nextValue, 0.0), 1.0))
        }
    }

    private func bridgeTensionSliderRange(for value: Double) -> ClosedRange<Double> {
        0.05 ... max(3.0, value * 2.0)
    }

    private func bridgeContinuityTitle(_ continuity: BridgeCurveContinuity) -> String {
        "\(bridgeEndpointContinuityTitle(continuity.first)) / \(bridgeEndpointContinuityTitle(continuity.second))"
    }

    private func bridgeEndpointContinuityTitle(_ continuity: BridgeCurveEndpointContinuity) -> String {
        switch continuity {
        case .g0:
            return "G0 Position"
        case .g1:
            return "G1 Tangent"
        case .g2:
            return "G2 Curvature"
        case .g3:
            return "G3 Curvature"
        }
    }

    private func sketchReferenceTitle(_ reference: SketchReference) -> String {
        switch reference {
        case .entity(let entityID):
            return "Entity \(shortID(entityID))"
        case .lineStart(let entityID):
            return "Line \(shortID(entityID)) Start"
        case .lineEnd(let entityID):
            return "Line \(shortID(entityID)) End"
        case .circleCenter(let entityID):
            return "Circle \(shortID(entityID)) Center"
        case .circleRadius(let entityID):
            return "Circle \(shortID(entityID)) Radius"
        case .arcCenter(let entityID):
            return "Arc \(shortID(entityID)) Center"
        case .arcStart(let entityID):
            return "Arc \(shortID(entityID)) Start"
        case .arcEnd(let entityID):
            return "Arc \(shortID(entityID)) End"
        case .arcRadius(let entityID):
            return "Arc \(shortID(entityID)) Radius"
        case .splineControlPoint(let entityID, let index):
            return "Spline \(shortID(entityID)) Point \(index + 1)"
        }
    }

    private func shortID<T: CustomStringConvertible>(_ id: T) -> String {
        String(id.description.prefix(8))
    }
}
