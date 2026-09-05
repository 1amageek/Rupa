import RupaProject

/// Builds transient render inputs from a staged source-preview payload.
public protocol ProjectPreviewRenderPayloadBuilding: Sendable {
    func build(
        from payload: ProjectSourcePreviewRenderPayload
    ) throws -> ProjectPreviewRenderPayload
}
