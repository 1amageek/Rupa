struct CADInteractionDesignProcessGeometryBenchmarkFixture: Sendable {
    var area: CADInteractionQualityArea
    var title: String
    var sourceEntityCount: Int
    var topologyElementCount: Int
    var constraintOrRelationCount: Int
    var sampleCount: Int
    var variantCount: Int
    var operationBudgetUnits: Double

    var operationUnits: Double {
        Double(sourceEntityCount)
            + Double(topologyElementCount) * 1.5
            + Double(constraintOrRelationCount) * 2.0
            + Double(sampleCount) * 0.25
            + Double(variantCount) * 5.0
    }

    static func fixture(
        for area: CADInteractionQualityArea
    ) -> CADInteractionDesignProcessGeometryBenchmarkFixture {
        switch area {
        case .selection:
            fixture(area, "Dense subobject selection scene", 360, 900, 160, 1_200, 14, 3_500)
        case .sketchPrecision:
            fixture(area, "Large constrained sketch workspace", 220, 280, 320, 640, 10, 2_200)
        case .snapping:
            fixture(area, "Dense snap candidate field", 300, 500, 120, 900, 12, 2_400)
        case .constructionGeometry:
            fixture(area, "Construction plane projection set", 140, 220, 90, 360, 8, 1_400)
        case .dimensions:
            fixture(area, "Bulk dimension reference set", 160, 240, 220, 480, 8, 1_800)
        case .filletingAndBlending:
            fixture(area, "Ordered blend edge set", 90, 320, 80, 360, 10, 1_500)
        case .booleanModeling:
            fixture(area, "Dense boolean operand pair", 80, 420, 60, 320, 8, 1_700)
        case .directModeling:
            fixture(area, "Direct edit topology healing set", 120, 380, 120, 420, 12, 1_800)
        case .exchangeAndDrawings:
            fixture(area, "Large exchange and drawing readback set", 240, 500, 160, 1_000, 14, 2_600)
        case .patternsAndArrays:
            fixture(area, "Large pattern array preview set", 420, 700, 240, 900, 16, 3_200)
        case .sectionAnalysis:
            fixture(area, "Dense section analysis sampling set", 220, 600, 160, 1_200, 12, 2_800)
        case .sweep:
            fixture(area, "Dense guided sweep section set", 120, 480, 180, 640, 14, 2_300)
        case .surfaceModeling:
            fixture(area, "Dense B-spline surface control net", 180, 900, 220, 1_400, 16, 3_600)
        case .curveContinuity:
            fixture(area, "Dense curve comb and continuity set", 180, 360, 180, 900, 12, 2_200)
        case .agentOperability:
            fixture(area, "Large Agent readback route set", 260, 400, 180, 720, 18, 2_400)
        case .performance:
            fixture(area, "Whole-pipeline dense performance scene", 500, 1_000, 260, 1_600, 20, 4_200)
        }
    }

    private static func fixture(
        _ area: CADInteractionQualityArea,
        _ title: String,
        _ sourceEntityCount: Int,
        _ topologyElementCount: Int,
        _ constraintOrRelationCount: Int,
        _ sampleCount: Int,
        _ variantCount: Int,
        _ operationBudgetUnits: Double
    ) -> CADInteractionDesignProcessGeometryBenchmarkFixture {
        CADInteractionDesignProcessGeometryBenchmarkFixture(
            area: area,
            title: title,
            sourceEntityCount: sourceEntityCount,
            topologyElementCount: topologyElementCount,
            constraintOrRelationCount: constraintOrRelationCount,
            sampleCount: sampleCount,
            variantCount: variantCount,
            operationBudgetUnits: operationBudgetUnits
        )
    }
}
