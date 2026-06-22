import SwiftCAD

public struct PolySplineMeshAnalysisService: Sendable {
    public init() {}

    public func analyze(
        sourceMesh: Mesh,
        options: PolySplineOptions = PolySplineOptions()
    ) -> PolySplineMeshAnalysisResult {
        PolySplineMeshAnalyzer().analyze(
            mesh: sourceMesh,
            options: options
        )
        .result
    }
}
