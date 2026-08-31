import RupaAgentProtocol
import RupaCore

enum CLIResponseProjector {
    static func command(_ envelope: CLIReadEnvelope) throws -> CLIResponse {
        guard case .command(let result) = envelope.response else {
            throw unexpected("Command inspection returned an unexpected response.")
        }
        return CLIResponse(
            result: result,
            dirty: envelope.state.sourceDirty,
            saved: false
        )
    }

    static func parameters(_ response: AgentResponse) throws -> CLIParameterListResponse {
        guard case .parameters(let result) = response else {
            throw unexpected("Parameter inspection returned an unexpected response.")
        }
        return CLIParameterListResponse(result: result)
    }

    static func selection(_ response: AgentResponse) throws -> CLISelectionResponse {
        guard case .selection(let result) = response else {
            throw unexpected("Selection mutation returned an unexpected response.")
        }
        return CLISelectionResponse(result: result)
    }

    static func evaluation(_ envelope: CLIReadEnvelope) throws -> CLIEvaluationResponse {
        guard case .evaluation(let result) = envelope.response else {
            throw unexpected("Evaluation returned an unexpected response.")
        }
        return CLIEvaluationResponse(
            snapshot: result,
            dirty: envelope.state.sourceDirty
        )
    }

    static func measurement(_ envelope: CLIReadEnvelope) throws -> CLIMeasurementResponse {
        guard case .measurement(let result) = envelope.response else {
            throw unexpected("Measurement returned an unexpected response.")
        }
        return CLIMeasurementResponse(
            measurement: result,
            generation: envelope.state.generation,
            dirty: envelope.state.sourceDirty
        )
    }

    static func meshSummary(_ envelope: CLIReadEnvelope) throws -> CLIMeshSummaryResponse {
        guard case .meshSummary(let result) = envelope.response else {
            throw unexpected("Mesh inspection returned an unexpected response.")
        }
        return CLIMeshSummaryResponse(
            meshSummary: result,
            generation: envelope.state.generation,
            dirty: envelope.state.sourceDirty
        )
    }

    static func surfaceSourceSummary(
        _ envelope: CLIReadEnvelope
    ) throws -> CLISurfaceSourceSummaryResponse {
        guard case .surfaceSourceSummary(let result) = envelope.response else {
            throw unexpected("Surface-source inspection returned an unexpected response.")
        }
        return CLISurfaceSourceSummaryResponse(
            surfaceSourceSummary: result,
            generation: envelope.state.generation,
            dirty: envelope.state.sourceDirty
        )
    }

    static func sketchDimensionSummary(
        _ envelope: CLIReadEnvelope
    ) throws -> CLISketchDimensionSummaryResponse {
        guard case .sketchDimensionSummary(let result) = envelope.response else {
            throw unexpected("Sketch-dimension inspection returned an unexpected response.")
        }
        return CLISketchDimensionSummaryResponse(
            sketchDimensionSummary: result,
            generation: envelope.state.generation,
            dirty: envelope.state.sourceDirty
        )
    }

    static func objectDimensionSummary(
        _ envelope: CLIReadEnvelope
    ) throws -> CLIObjectDimensionSummaryResponse {
        guard case .objectDimensionSummary(let result) = envelope.response else {
            throw unexpected("Object-dimension inspection returned an unexpected response.")
        }
        return CLIObjectDimensionSummaryResponse(
            objectDimensionSummary: result,
            generation: envelope.state.generation,
            dirty: envelope.state.sourceDirty
        )
    }

    static func constructionPlanes(
        _ envelope: CLIReadEnvelope
    ) throws -> CLIConstructionPlaneSummaryResponse {
        guard case .constructionPlaneSummary(let result) = envelope.response else {
            throw unexpected("Construction-plane inspection returned an unexpected response.")
        }
        return CLIConstructionPlaneSummaryResponse(
            constructionPlaneSummary: result,
            generation: envelope.state.generation,
            dirty: envelope.state.sourceDirty
        )
    }

    static func sketches(
        _ envelope: CLIReadEnvelope
    ) throws -> CLISketchEntitySummaryResponse {
        guard case .sketchEntitySummary(let result) = envelope.response else {
            throw unexpected("Sketch inspection returned an unexpected response.")
        }
        return CLISketchEntitySummaryResponse(
            sketchEntitySummary: result,
            generation: envelope.state.generation,
            dirty: envelope.state.sourceDirty
        )
    }

    static func topology(
        _ envelope: CLIReadEnvelope
    ) throws -> CLITopologySummaryResponse {
        guard case .topologySummary(let result) = envelope.response else {
            throw unexpected("Topology inspection returned an unexpected response.")
        }
        return CLITopologySummaryResponse(
            topologySummary: result,
            generation: envelope.state.generation,
            dirty: envelope.state.sourceDirty
        )
    }

    static func curves(
        _ envelope: CLIReadEnvelope
    ) throws -> CLICurveAnalysisResponse {
        guard case .curveAnalysis(let result) = envelope.response else {
            throw unexpected("Curve inspection returned an unexpected response.")
        }
        return CLICurveAnalysisResponse(
            curveAnalysis: result,
            generation: envelope.state.generation,
            dirty: envelope.state.sourceDirty
        )
    }

    static func surfaces(
        _ envelope: CLIReadEnvelope
    ) throws -> CLISurfaceAnalysisResponse {
        guard case .surfaceAnalysis(let result) = envelope.response else {
            throw unexpected("Surface inspection returned an unexpected response.")
        }
        return CLISurfaceAnalysisResponse(
            surfaceAnalysis: result,
            generation: envelope.state.generation,
            dirty: envelope.state.sourceDirty
        )
    }

    static func surfaceContinuity(
        _ envelope: CLIReadEnvelope
    ) throws -> CLISurfaceContinuitySummaryResponse {
        guard case .surfaceContinuitySummary(let result) = envelope.response else {
            throw unexpected("Surface-continuity inspection returned an unexpected response.")
        }
        return CLISurfaceContinuitySummaryResponse(
            surfaceContinuitySummary: result,
            generation: envelope.state.generation,
            dirty: envelope.state.sourceDirty
        )
    }

    static func surfaceBoundaryCompatibility(
        _ envelope: CLIReadEnvelope
    ) throws -> CLISurfaceBoundaryContinuityCompatibilityResponse {
        guard case .surfaceBoundaryContinuityCompatibility(let result) = envelope.response else {
            throw unexpected("Surface-boundary inspection returned an unexpected response.")
        }
        return CLISurfaceBoundaryContinuityCompatibilityResponse(
            surfaceBoundaryContinuityCompatibility: result,
            generation: envelope.state.generation,
            dirty: envelope.state.sourceDirty
        )
    }

    static func surfaceFrames(
        _ envelope: CLIReadEnvelope
    ) throws -> CLISurfaceFramesResponse {
        guard case .surfaceFrames(let result) = envelope.response else {
            throw unexpected("Surface-frame inspection returned an unexpected response.")
        }
        return CLISurfaceFramesResponse(
            surfaceFrames: result,
            generation: envelope.state.generation,
            dirty: envelope.state.sourceDirty
        )
    }

    static func snap(
        _ envelope: CLIReadEnvelope
    ) throws -> CLISnapResolutionResponse {
        guard case .snapResolution(let result) = envelope.response else {
            throw unexpected("Snap inspection returned an unexpected response.")
        }
        return CLISnapResolutionResponse(
            snapResolution: result,
            generation: envelope.state.generation,
            dirty: envelope.state.sourceDirty
        )
    }

    static func selectionMeasurement(
        _ envelope: CLIReadEnvelope
    ) throws -> CLISelectionMeasurementResponse {
        guard case .selectionMeasurement(let result) = envelope.response else {
            throw unexpected("Selection measurement returned an unexpected response.")
        }
        return CLISelectionMeasurementResponse(
            selectionMeasurement: result,
            generation: envelope.state.generation,
            dirty: envelope.state.sourceDirty
        )
    }

    static func sceneGraph(
        _ envelope: CLIReadEnvelope
    ) throws -> SceneGraphSnapshotResult {
        guard case .sceneGraphSnapshot(let result) = envelope.response else {
            throw unexpected("Scene-graph inspection returned an unexpected response.")
        }
        return result
    }

    static func viewport(
        _ envelope: CLIReadEnvelope
    ) throws -> AgentProjectViewportSnapshot {
        guard case .viewportSnapshot(let result) = envelope.response else {
            throw unexpected("Viewport inspection returned an unexpected response.")
        }
        return result
    }

    private static func unexpected(_ message: String) -> EditorError {
        EditorError(code: .commandFailed, message: message)
    }
}
