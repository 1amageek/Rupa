import Testing
import RupaCore

@Test func sectionAnalysisClippingPlanClassifiesBodiesForRetainedFrontSide() {
    let result = sectionAnalysisClippingFixture()
    let plan = SectionAnalysisClippingPlan(
        result: result,
        retaining: .front
    )

    #expect(plan.retainedSide == .front)
    #expect(plan.action(for: "front") == .visible)
    #expect(plan.action(forSourceFeatureID: "feature-front") == .visible)
    #expect(plan.action(forPersistentName: "persistent-front") == .visible)
    #expect(plan.action(for: "behind") == .hidden)
    #expect(plan.action(for: "touching") == .visible)
    #expect(plan.action(for: "coplanar") == .visible)
    #expect(plan.action(for: "intersects") == .clipped)
    #expect(plan.action(for: "spans") == .clipped)
    #expect(plan.visibleBodyCount == 3)
    #expect(plan.hiddenBodyCount == 1)
    #expect(plan.clippedBodyCount == 2)
}

@Test func sectionAnalysisClippingPlanClassifiesBodiesForRetainedBehindSide() {
    let result = sectionAnalysisClippingFixture()
    let plan = SectionAnalysisClippingPlan(
        result: result,
        retaining: .behind
    )

    #expect(plan.retainedSide == .behind)
    #expect(plan.action(for: "front") == .hidden)
    #expect(plan.action(for: "behind") == .visible)
    #expect(plan.action(for: "intersects") == .clipped)
    #expect(plan.visibleBodyCount == 3)
    #expect(plan.hiddenBodyCount == 1)
    #expect(plan.clippedBodyCount == 2)
}

private func sectionAnalysisClippingFixture() -> SectionAnalysisResult {
    SectionAnalysisResult(
        displayUnit: .meter,
        plane: SectionAnalysisResult.Plane(
            sourceKind: .sketchPlane,
            sourceID: nil,
            sourceName: nil,
            origin: .origin,
            normal: .unitZ,
            u: .unitX,
            v: .unitY
        ),
        toleranceMeters: 1.0e-8,
        bodies: [
            sectionAnalysisClippingBody(id: "front", classification: .inFront),
            sectionAnalysisClippingBody(id: "behind", classification: .behind),
            sectionAnalysisClippingBody(id: "touching", classification: .touching),
            sectionAnalysisClippingBody(id: "coplanar", classification: .coplanar),
            sectionAnalysisClippingBody(id: "intersects", classification: .intersects),
            sectionAnalysisClippingBody(id: "spans", classification: .spansPlane),
        ],
        intersectionSegments: [],
        truncatedIntersectionSegments: false,
        diagnostics: []
    )
}

private func sectionAnalysisClippingBody(
    id: String,
    classification: SectionAnalysisResult.BodyClassification
) -> SectionAnalysisResult.Body {
    SectionAnalysisResult.Body(
        bodyID: id,
        sourceFeatureID: "feature-\(id)",
        persistentName: "persistent-\(id)",
        name: id,
        kind: nil,
        materialID: nil,
        classification: classification,
        vertexCount: 0,
        triangleCount: 0,
        frontVertexCount: 0,
        behindVertexCount: 0,
        coplanarVertexCount: 0,
        frontTriangleCount: 0,
        behindTriangleCount: 0,
        coplanarTriangleCount: 0,
        touchingTriangleCount: 0,
        intersectingTriangleCount: 0,
        intersectionSegmentCount: 0
    )
}
