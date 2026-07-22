import SwiftCAD
import CADModeling

public struct PolySplineMeshAnalysisService: Sendable {
    public init() {}

    public func analyze(
        sourceMesh: Mesh,
        options: PolySplineOptions = PolySplineOptions(),
        tolerance: ModelingTolerance
    ) -> PolySplineMeshAnalysisResult {
        PolySplineMeshAnalyzer().analyze(
            mesh: sourceMesh,
            options: options,
            tolerance: tolerance
        )
        .result
    }
}
