import RupaCoreTypes
import RupaEvaluation
import Testing
@testable import RupaGeometry

/// The counts the recorded RESPI-0.4 baseline measured for the standard
/// responsiveness fixture, which the shipped ceilings are derived from.
private enum RecordedFixture {
    static let sourceCount = 12
    static let vertexCount = 150_840
    static let faceCount = 301_632
    /// Every fixture face is a triangle, so a face contributes three corners
    /// and one triangle.
    static let cornerCount = 904_896
    static let triangleCount = 301_632

    /// RESPI-0.4 recorded no byte row, so the footprint is derived rather than
    /// measured. Every fixture body is a closed triangulated manifold, so its
    /// edge count is three halves of its face count, which Euler's formula
    /// confirms for one body: 12,570 - 37,704 + 25,136 = 2.
    static let edgeCount = faceCount * 3 / 2

    /// The bytes `MeshSource.resourceUsage()` charges for the whole fixture,
    /// buffer by buffer. The shipped `EvaluationResourceLimits` doc-comment
    /// cites this figure, so a stride change fails here instead of leaving the
    /// documented headroom silently wrong.
    static var byteCount: Int {
        vertexCount
            * (MemoryLayout<MeshVertexID>.stride + MemoryLayout<GeometryPoint3D>.stride)
            + edgeCount
            * (MemoryLayout<MeshEdgeID>.stride + MemoryLayout<MeshEdgeEndpoints>.stride)
            + faceCount
            * (MemoryLayout<MeshFaceID>.stride + MemoryLayout<MeshIndexRange>.stride)
            + cornerCount
            * (MemoryLayout<MeshCornerID>.stride
                + MemoryLayout<MeshVertexID>.stride
                + MemoryLayout<MeshEdgeID>.stride)
    }
}

@Suite("Evaluation resource limits")
struct EvaluationResourceLimitsTests {
    @Test("The shipped ceilings are admissible", .timeLimit(.minutes(1)))
    func shippedCeilingsAreAdmissible() throws {
        try EvaluationResourceLimits.hardCeiling.validate()
        try EvaluationResourceLimits.standard.validate()
    }

    @Test("A non-positive ceiling is refused", .timeLimit(.minutes(1)))
    func nonPositiveCeilingIsRefused() throws {
        for resource in EvaluationResource.allCases {
            var limits = EvaluationResourceLimits.standard
            switch resource {
            case .sourceCount: limits.maximumSourceCount = 0
            case .vertexCount: limits.maximumVertexCount = 0
            case .faceCount: limits.maximumFaceCount = 0
            case .cornerCount: limits.maximumCornerCount = 0
            case .triangleCount: limits.maximumTriangleCount = 0
            case .byteCount: limits.maximumByteCount = 0
            }
            let error = #expect(throws: EvaluationError.self) {
                try limits.validate()
            }
            #expect(error?.code == .invalidLimit)
        }
    }

    @Test("A ceiling above the module hard ceiling is refused", .timeLimit(.minutes(1)))
    func ceilingAboveHardCeilingIsRefused() throws {
        for resource in EvaluationResource.allCases {
            var limits = EvaluationResourceLimits.hardCeiling
            switch resource {
            case .sourceCount: limits.maximumSourceCount += 1
            case .vertexCount: limits.maximumVertexCount += 1
            case .faceCount: limits.maximumFaceCount += 1
            case .cornerCount: limits.maximumCornerCount += 1
            case .triangleCount: limits.maximumTriangleCount += 1
            case .byteCount: limits.maximumByteCount += 1
            }
            let error = #expect(throws: EvaluationError.self) {
                try limits.validate()
            }
            #expect(error?.code == .invalidLimit)
        }
    }

    @Test("Lowering only narrows", .timeLimit(.minutes(1)))
    func loweringOnlyNarrows() throws {
        let base = EvaluationResourceLimits.standard
        let widened = EvaluationResourceLimits.hardCeiling

        let lowered = base.lowered(to: widened)

        for resource in EvaluationResource.allCases {
            #expect(lowered.limit(for: resource) == base.limit(for: resource))
        }

        let narrowed = base.lowered(to: EvaluationResourceLimits.standard.lowered(
            to: EvaluationResourceLimits(
                maximumSourceCount: 1,
                maximumVertexCount: 1,
                maximumFaceCount: 1,
                maximumCornerCount: 1,
                maximumTriangleCount: 1,
                maximumByteCount: 1
            )
        ))
        for resource in EvaluationResource.allCases {
            #expect(narrowed.limit(for: resource) == 1)
        }
    }

    @Test("The standard ceiling admits the recorded fixture", .timeLimit(.minutes(1)))
    func standardCeilingAdmitsTheRecordedFixture() throws {
        var budget = try EvaluationBudget(limits: .standard)
        // The fixture's bytes are the storage its recorded elements occupy, which
        // is what `MeshSource.resourceUsage()` accounts for.
        // The whole fixture is charged one body at a time, so the ceiling has to
        // admit the accumulated total and not merely the largest single mesh.
        #expect(RecordedFixture.byteCount == 44_642_304)
        let usage = MeshResourceUsage(
            vertexCount: RecordedFixture.vertexCount / RecordedFixture.sourceCount,
            edgeCount: RecordedFixture.edgeCount / RecordedFixture.sourceCount,
            faceCount: RecordedFixture.faceCount / RecordedFixture.sourceCount,
            cornerCount: RecordedFixture.cornerCount / RecordedFixture.sourceCount,
            triangleCount: RecordedFixture.triangleCount / RecordedFixture.sourceCount,
            byteCount: RecordedFixture.byteCount / RecordedFixture.sourceCount
        )

        for _ in 0..<RecordedFixture.sourceCount {
            try budget.chargeSource()
            try budget.charge(usage)
        }

        for resource in EvaluationResource.allCases {
            #expect(budget.remaining.amount(for: resource) > 0)
        }
        // The shipped headroom the ceiling documents, which is what makes the
        // fixture admissible rather than merely fitting.
        #expect(
            budget.remaining.byteCount
                > EvaluationResourceLimits.standard.maximumByteCount / 2
        )
    }
}

@Suite("Evaluation budget")
struct EvaluationBudgetTests {
    private static func limits(sources: Int, vertices: Int) -> EvaluationResourceLimits {
        EvaluationResourceLimits(
            maximumSourceCount: sources,
            maximumVertexCount: vertices,
            maximumFaceCount: EvaluationResourceLimits.standard.maximumFaceCount,
            maximumCornerCount: EvaluationResourceLimits.standard.maximumCornerCount,
            maximumTriangleCount: EvaluationResourceLimits.standard.maximumTriangleCount,
            maximumByteCount: EvaluationResourceLimits.standard.maximumByteCount
        )
    }

    @Test("A budget starts at the full allowance", .timeLimit(.minutes(1)))
    func budgetStartsAtFullAllowance() throws {
        let budget = try EvaluationBudget(limits: .standard)
        for resource in EvaluationResource.allCases {
            #expect(
                budget.remaining.amount(for: resource)
                    == EvaluationResourceLimits.standard.limit(for: resource)
            )
        }
    }

    @Test("An invalid ceiling refuses the budget", .timeLimit(.minutes(1)))
    func invalidCeilingRefusesTheBudget() throws {
        var limits = EvaluationResourceLimits.standard
        limits.maximumVertexCount = 0
        let error = #expect(throws: EvaluationError.self) {
            _ = try EvaluationBudget(limits: limits)
        }
        #expect(error?.code == .invalidLimit)
    }

    @Test("Charges accumulate across meshes", .timeLimit(.minutes(1)))
    func chargesAccumulateAcrossMeshes() throws {
        var budget = try EvaluationBudget(limits: Self.limits(sources: 4, vertices: 10))
        let usage = MeshResourceUsage(
            vertexCount: 4,
            edgeCount: 4,
            faceCount: 1,
            cornerCount: 4,
            triangleCount: 2,
            byteCount: 128
        )

        try budget.charge(usage)
        #expect(budget.remaining.vertexCount == 6)
        try budget.charge(usage)
        #expect(budget.remaining.vertexCount == 2)

        // The third mesh fits no single dimension's remainder, so it is refused
        // rather than driving the remainder negative.
        let error = #expect(throws: EvaluationError.self) {
            try budget.charge(usage)
        }
        #expect(error?.code == .resourceExhausted)
        #expect(budget.remaining.vertexCount == 2)
        try budget.remaining.validate()
    }

    @Test("The source dimension is charged separately", .timeLimit(.minutes(1)))
    func sourceDimensionIsChargedSeparately() throws {
        var budget = try EvaluationBudget(limits: Self.limits(sources: 2, vertices: 1_000))

        try budget.chargeSource()
        try budget.chargeSource()
        #expect(budget.remaining.sourceCount == 0)

        let error = #expect(throws: EvaluationError.self) {
            try budget.chargeSource()
        }
        #expect(error?.code == .resourceExhausted)
    }

    @Test("An exhausted allowance admits nothing", .timeLimit(.minutes(1)))
    func exhaustedAllowanceAdmitsNothing() throws {
        let usage = MeshResourceUsage(
            vertexCount: 1,
            edgeCount: 0,
            faceCount: 0,
            cornerCount: 0,
            triangleCount: 0,
            byteCount: 0
        )
        #expect(EvaluationAllowance.exhausted.firstResourceExceeded(by: usage) == .vertexCount)
        #expect(EvaluationAllowance.exhausted.firstResourceExceeded(by: .zero) == nil)
        try EvaluationAllowance.exhausted.validate()
    }

    @Test("A negative remainder is refused", .timeLimit(.minutes(1)))
    func negativeRemainderIsRefused() throws {
        var allowance = EvaluationAllowance(.standard)
        allowance.byteCount = -1
        let error = #expect(throws: EvaluationError.self) {
            try allowance.validate()
        }
        #expect(error?.code == .invalidLimit)
    }
}

@Suite("Evaluation resource policy")
struct EvaluationResourcePolicyTests {
    @Test("The standard policy states every purpose", .timeLimit(.minutes(1)))
    func standardPolicyStatesEveryPurpose() throws {
        for purpose in GeometryRepresentationPurpose.allCases {
            #expect(EvaluationResourcePolicy.standard.limits(for: purpose) == .standard)
        }
    }

    @Test("A missing purpose is refused", .timeLimit(.minutes(1)))
    func missingPurposeIsRefused() throws {
        let error = #expect(throws: EvaluationError.self) {
            _ = try EvaluationResourcePolicy(limitsByPurpose: [.modeling: .standard])
        }
        #expect(error?.code == .invalidLimit)
    }

    @Test("A widened purpose is refused at construction", .timeLimit(.minutes(1)))
    func widenedPurposeIsRefusedAtConstruction() throws {
        var widened = EvaluationResourceLimits.hardCeiling
        widened.maximumVertexCount += 1
        let error = #expect(throws: EvaluationError.self) {
            _ = try EvaluationResourcePolicy(everyPurpose: widened)
        }
        #expect(error?.code == .invalidLimit)
    }

    @Test("Lowering a policy narrows every purpose", .timeLimit(.minutes(1)))
    func loweringAPolicyNarrowsEveryPurpose() throws {
        var narrow = EvaluationResourceLimits.standard
        narrow.maximumVertexCount = 16

        let lowered = try EvaluationResourcePolicy.standard.lowered(to: narrow)

        for purpose in GeometryRepresentationPurpose.allCases {
            #expect(lowered.limits(for: purpose).maximumVertexCount == 16)
            #expect(
                lowered.limits(for: purpose).maximumFaceCount
                    == EvaluationResourceLimits.standard.maximumFaceCount
            )
        }
    }

    @Test("Lowering never widens", .timeLimit(.minutes(1)))
    func loweringNeverWidens() throws {
        let lowered = try EvaluationResourcePolicy.standard.lowered(to: .hardCeiling)
        for purpose in GeometryRepresentationPurpose.allCases {
            #expect(lowered.limits(for: purpose) == .standard)
        }
    }
}
