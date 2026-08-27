import Foundation
import RupaCoreTypes

/// The bounded reference executor for one complete Mesh edit plan.
public struct DefaultMeshEditPlanExecutor: MeshEditPlanExecuting {
    public init() {}

    public func execute(
        plan: MeshEditPlan,
        source: MeshSource
    ) throws -> MeshEditPlanExecution {
        let validatedPlan = try MeshEditPlan(steps: plan.steps, limits: plan.limits)
        var budget = ExecutionBudget(limits: validatedPlan.limits)
        try budget.scan(sourceRecordCount(in: source))
        try preflightStaticBudget(plan: validatedPlan, budget: &budget)

        do {
            try source.validate()
        } catch let error as MeshSourceError {
            throw MeshEditError(code: .sourceValidation, message: error.message)
        }

        if source.attributes.count > 0,
           validatedPlan.steps.contains(where: { $0.operation.isTopologyMutation }) {
            throw MeshEditError(
                code: .topologyAttributeRemappingUnsupported,
                message: "Topology edits on attributed Meshes require explicit attribute remapping."
            )
        }

        var buffer = MeshEditBuffer(source: source)
        var stepOutputs: [MeshEditStepID: [MeshEditOutputRole: [MeshSelectionElement]]] = [:]
        var stepReceipts: [MeshEditStepReceipt] = []
        var deletedElements: [MeshSelectionElement] = []

        for step in validatedPlan.steps {
            let result: StepExecutionResult
            do {
                result = try execute(
                    step: step,
                    buffer: &buffer,
                    outputs: stepOutputs,
                    budget: &budget
                )
            } catch let error as MeshEditError {
                throw error
            } catch let error as MeshSourceError {
                throw MeshEditError(code: .sourceMutation, message: error.message)
            }
            let receipt = try MeshEditStepReceipt(
                stepID: step.id,
                outputs: result.outputs
            )
            stepOutputs[step.id] = result.outputs
            stepReceipts.append(receipt)
            deletedElements.append(contentsOf: result.deletedElements)
        }

        let commit: MeshEditCommitResult
        do {
            commit = try buffer.commit()
        } catch let error as MeshSourceError {
            throw MeshEditError(code: .sourceMutation, message: error.message)
        }
        guard commit.telemetry.copiedBytes <= validatedPlan.limits.maxCopiedBytes else {
            throw MeshEditError(
                code: .copyBudgetExceeded,
                message: "Mesh edit copy telemetry exceeds its effective byte limit."
            )
        }
        let receipt = try MeshEditReceipt(
            stepReceipts: stepReceipts,
            deletedElements: deletedElements,
            didChange: commit.source != source,
            telemetry: commit.telemetry
        )
        return MeshEditPlanExecution(source: commit.source, receipt: receipt)
    }

    private func execute(
        step: MeshEditStep,
        buffer: inout MeshEditBuffer,
        outputs: [MeshEditStepID: [MeshEditOutputRole: [MeshSelectionElement]]],
        budget: inout ExecutionBudget
    ) throws -> StepExecutionResult {
        switch step.operation {
        case .primitive(let primitive):
            switch primitive {
            case .setVertexPositions(let edits):
                let elements = edits.map { MeshSelectionElement.vertex($0.vertexID) }
                for edit in edits {
                    try buffer.setVertexPosition(edit.position, for: edit.vertexID)
                }
                return StepExecutionResult(
                    outputs: [.affectedVertices: elements],
                    deletedElements: []
                )

            case .addFace(let vertexIDs):
                let expectedEdgeCount = try missingEdgeCount(vertexIDs: vertexIDs, in: buffer)
                // Face and corner IDs are reserved before the staging buffer is created.
                // Only edge IDs depend on the current staged topology and are charged here.
                try budget.generate(expectedEdgeCount)
                try budget.recordReceiptIDs(expectedEdgeCount)
                let staged = try buffer.stageFace(vertexIDs: vertexIDs)
                let faceElements = [MeshSelectionElement.face(staged.face.id)]
                let edgeElements = staged.createdEdgeIDs.map(MeshSelectionElement.edge)
                let cornerElements = staged.face.cornerIDs.map(MeshSelectionElement.corner)
                let result: [MeshEditOutputRole: [MeshSelectionElement]] = [
                    .createdFaces: faceElements,
                    .createdEdges: edgeElements,
                    .createdCorners: cornerElements,
                ]
                return StepExecutionResult(
                    outputs: result,
                    deletedElements: []
                )

            case .deleteFaces(let selector):
                let selected = try resolve(
                    selector,
                    in: buffer,
                    outputs: outputs,
                    budget: &budget
                )
                let faces = try selected.map { element -> MeshFaceID in
                    guard case .face(let faceID) = element else {
                        throw MeshEditError(
                            code: .invalidOperationDomain,
                            message: "Face deletion requires face selections."
                        )
                    }
                    return faceID
                }
                if case .output = selector {
                    try budget.recordReceiptIDs(faces.count)
                }
                for faceID in faces {
                    try buffer.deleteFace(faceID)
                }
                return StepExecutionResult(
                    outputs: [:],
                    deletedElements: faces.map(MeshSelectionElement.face)
                )
            }

        case .translateElements(let selector, let offset):
            let selected = try resolve(
                selector,
                in: buffer,
                outputs: outputs,
                budget: &budget
            )
            let vertexIDs = try translatedVertexIDs(
                from: selected,
                in: buffer,
                budget: &budget
            )
            let movedPositions = try vertexIDs.map { vertexID in
                (vertexID, try offset.applying(to: buffer.position(for: vertexID)))
            }
            try budget.recordReceiptIDs(vertexIDs.count)
            for (vertexID, position) in movedPositions {
                try buffer.setVertexPosition(position, for: vertexID)
            }
            let elements = vertexIDs.map(MeshSelectionElement.vertex)
            return StepExecutionResult(
                outputs: [.affectedVertices: elements],
                deletedElements: []
            )

        case .extrudeFaces(let selector, let offset):
            let selected = try resolve(
                selector,
                in: buffer,
                outputs: outputs,
                budget: &budget
            )
            let faceIDs = try selected.map { element -> MeshFaceID in
                guard case .face(let faceID) = element else {
                    throw MeshEditError(
                        code: .invalidOperationDomain,
                        message: "Face extrusion requires face selections."
                    )
                }
                return faceID
            }
            let extrusion = try makeExtrusion(
                faceIDs: faceIDs,
                offset: offset,
                in: buffer,
                budget: &budget
            )
            let duplicatedVertexCount = extrusion.vertexIDs.count
            let capEdgeCount = extrusion.boundaryEdges.count
            let longitudinalEdgeCount = extrusion.boundaryVertices.count
            let sideFaceCount = extrusion.boundaryEdges.count
            let sideCornerCount = try checkedProduct(
                sideFaceCount,
                by: 4,
                label: "side corner"
            )
            let generatedCount = try checkedSum(
                [
                    duplicatedVertexCount,
                    capEdgeCount,
                    longitudinalEdgeCount,
                    sideFaceCount,
                    sideCornerCount,
                ],
                label: "generated ID"
            )
            try budget.generate(generatedCount)
            let receiptCount = try checkedSum(
                [
                    duplicatedVertexCount,
                    capEdgeCount,
                    longitudinalEdgeCount,
                    sideFaceCount,
                    sideFaceCount,
                    faceIDs.count,
                    sideCornerCount,
                ],
                label: "receipt ID"
            )
            try budget.recordReceiptIDs(receiptCount)
            let edgeAllocationCount = try checkedSum(
                [capEdgeCount, longitudinalEdgeCount],
                label: "edge allocation"
            )
            try buffer.preflightAllocation(
                vertexCount: duplicatedVertexCount,
                edgeCount: edgeAllocationCount,
                faceCount: sideFaceCount,
                cornerCount: sideCornerCount
            )
            let positions = try extrusionPositions(
                for: extrusion,
                offset: offset,
                in: buffer
            )
            let applied = try applyExtrusion(
                extrusion,
                positions: positions,
                in: &buffer
            )
            let createdVertices = applied.createdVertexIDs.map(MeshSelectionElement.vertex)
            let createdEdges = applied.createdEdgeIDs.map(MeshSelectionElement.edge)
            let sideFaces = applied.sideFaceIDs.map(MeshSelectionElement.face)
            let capFaces = applied.capFaceIDs.map(MeshSelectionElement.face)
            let createdCorners = applied.createdCornerIDs.map(MeshSelectionElement.corner)
            return StepExecutionResult(
                outputs: [
                    .createdVertices: createdVertices,
                    .createdEdges: createdEdges,
                    .createdFaces: sideFaces,
                    .capFaces: capFaces,
                    .sideFaces: sideFaces,
                    .createdCorners: createdCorners,
                ],
                deletedElements: []
            )
        }
    }

    private func resolve(
        _ selector: MeshElementSelector,
        in buffer: MeshEditBuffer,
        outputs: [MeshEditStepID: [MeshEditOutputRole: [MeshSelectionElement]]],
        budget: inout ExecutionBudget
    ) throws -> [MeshSelectionElement] {
        let elements: [MeshSelectionElement]
        switch selector {
        case .explicit(let selection):
            elements = selection.elements
        case .output(let stepID, let role):
            guard let stepOutput = outputs[stepID],
                  let output = stepOutput[role] else {
                throw MeshEditError(
                    code: .missingOutputReference,
                    message: "Mesh edit selector references an unavailable step output."
                )
            }
            elements = output
        }
        guard !elements.isEmpty else {
            throw MeshEditError(
                code: .emptySelection,
                message: "Mesh edit selectors must resolve to at least one active element."
            )
        }
        if case .output = selector {
            try budget.select(elements.count)
        }
        for element in elements {
            guard buffer.contains(element) else {
                throw MeshEditError(
                    code: .invalidReference,
                    message: "Mesh edit selector references an element that is not active."
                )
            }
        }
        return elements
    }

    private func translatedVertexIDs(
        from elements: [MeshSelectionElement],
        in buffer: MeshEditBuffer,
        budget: inout ExecutionBudget
    ) throws -> [MeshVertexID] {
        var selected: Set<MeshVertexID> = []
        func insert(_ vertexID: MeshVertexID) throws {
            guard !selected.contains(vertexID) else {
                return
            }
            try budget.select(1)
            selected.insert(vertexID)
        }
        for element in elements {
            switch element {
            case .vertex(let vertexID):
                try insert(vertexID)
            case .edge(let edgeID):
                let endpoints = try buffer.edgeEndpoints(for: edgeID)
                try insert(endpoints.start)
                try insert(endpoints.end)
            case .face(let faceID):
                let face = try buffer.faceState(for: faceID)
                for vertexID in face.vertexIDs {
                    try insert(vertexID)
                }
            case .corner(let cornerID):
                try insert(try buffer.vertexID(for: cornerID))
            }
        }
        let ordered = buffer.orderedActiveVertexIDs(containing: selected)
        guard !ordered.isEmpty else {
            throw MeshEditError(
                code: .emptySelection,
                message: "Translation selection must resolve to at least one vertex."
            )
        }
        return ordered
    }

    private func missingEdgeCount(
        vertexIDs: [MeshVertexID],
        in buffer: MeshEditBuffer
    ) throws -> Int {
        var count = 0
        for index in vertexIDs.indices {
            let next = index + 1 == vertexIDs.count ? 0 : index + 1
            if buffer.existingEdgeID(
                start: vertexIDs[index],
                end: vertexIDs[next]
            ) == nil {
                count += 1
            }
        }
        return count
    }

    private func sourceRecordCount(in source: MeshSource) throws -> Int {
        var count = 0
        for recordCount in [
            source.vertexIDs.count,
            source.edgeIDs.count,
            source.faceIDs.count,
            source.cornerIDs.count,
        ] {
            count = try addingSourceRecordCount(recordCount, to: count)
        }
        do {
            count = try addingSourceRecordCount(
                source.attributes.scanRecordCount(),
                to: count
            )
        } catch let error as MeshSourceError {
            throw MeshEditError(code: .integerOverflow, message: error.message)
        }
        return count
    }

    private func addingSourceRecordCount(
        _ recordCount: Int,
        to count: Int
    ) throws -> Int {
        let next = count.addingReportingOverflow(recordCount)
        guard !next.overflow else {
            throw MeshEditError(
                code: .integerOverflow,
                message: "Mesh source record count overflowed its integer domain."
            )
        }
        return next.partialValue
    }

    private func preflightStaticBudget(
        plan: MeshEditPlan,
        budget: inout ExecutionBudget
    ) throws {
        for step in plan.steps {
            switch step.operation {
            case .primitive(let primitive):
                switch primitive {
                case .setVertexPositions(let edits):
                    try budget.select(edits.count)
                    try budget.recordReceiptIDs(edits.count)
                case .addFace(let vertexIDs):
                    try budget.select(vertexIDs.count)
                    let knownGeneratedCount = try checkedSum(
                        [1, vertexIDs.count],
                        label: "generated ID"
                    )
                    try budget.generate(knownGeneratedCount)
                    try budget.recordReceiptIDs(knownGeneratedCount)
                case .deleteFaces(let selector):
                    if let count = Self.explicitSelectionCount(in: selector) {
                        try budget.select(count)
                        try budget.recordReceiptIDs(count)
                    }
                }
            case .translateElements(let selector, _),
                 .extrudeFaces(let selector, _):
                if let count = Self.explicitSelectionCount(in: selector) {
                    try budget.select(count)
                }
            }
        }
    }

    private static func explicitSelectionCount(
        in selector: MeshElementSelector
    ) -> Int? {
        guard case .explicit(let selection) = selector else {
            return nil
        }
        return selection.elements.count
    }

    private func checkedSum(_ values: [Int], label: String) throws -> Int {
        var total = 0
        for value in values {
            let next = total.addingReportingOverflow(value)
            guard !next.overflow else {
                throw MeshEditError(
                    code: .integerOverflow,
                    message: "Mesh edit \(label) count overflowed."
                )
            }
            total = next.partialValue
        }
        return total
    }

    private func checkedProduct(
        _ value: Int,
        by multiplier: Int,
        label: String
    ) throws -> Int {
        let result = value.multipliedReportingOverflow(by: multiplier)
        guard !result.overflow else {
            throw MeshEditError(
                code: .integerOverflow,
                message: "Mesh edit \(label) count overflowed."
            )
        }
        return result.partialValue
    }

    private struct ExecutionBudget {
        let limits: MeshEditLimits
        var scannedRecords = 0
        var selectedIDs = 0
        var generatedIDs = 0
        var receiptIDs = 0

        mutating func scan(_ count: Int) throws {
            scannedRecords = try increment(
                scannedRecords,
                by: count,
                limit: limits.maxScannedRecords,
                label: "scanned record"
            )
        }

        mutating func select(_ count: Int) throws {
            selectedIDs = try increment(
                selectedIDs,
                by: count,
                limit: limits.maxSelectedIDs,
                label: "selected ID"
            )
        }

        mutating func generate(_ count: Int) throws {
            generatedIDs = try increment(
                generatedIDs,
                by: count,
                limit: limits.maxGeneratedIDs,
                label: "generated ID"
            )
        }

        mutating func recordReceiptIDs(_ count: Int) throws {
            receiptIDs = try increment(
                receiptIDs,
                by: count,
                limit: limits.maxReceiptIDs,
                label: "receipt ID"
            )
        }

        private func increment(
            _ current: Int,
            by count: Int,
            limit: Int,
            label: String
        ) throws -> Int {
            guard count >= 0 else {
                throw MeshEditError(
                    code: .integerOverflow,
                    message: "Mesh edit \(label) count cannot be negative."
                )
            }
            let next = current.addingReportingOverflow(count)
            guard !next.overflow else {
                throw MeshEditError(
                    code: .integerOverflow,
                    message: "Mesh edit \(label) count overflowed."
                )
            }
            guard next.partialValue <= limit else {
                throw MeshEditError(
                    code: .limitExceeded,
                    message: "Mesh edit \(label) count exceeds its effective limit."
                )
            }
            return next.partialValue
        }
    }

    private struct StepExecutionResult {
        let outputs: [MeshEditOutputRole: [MeshSelectionElement]]
        let deletedElements: [MeshSelectionElement]
    }

    private struct BoundaryEdge {
        let edgeID: MeshEdgeID
        let start: MeshVertexID
        let end: MeshVertexID
    }

    private struct BoundaryLoop {
        let edges: [BoundaryEdge]
    }

    private struct ExtrusionGeometry {
        let faces: [MeshEditBuffer.FaceState]
        let vertexIDs: [MeshVertexID]
        let boundaryVertices: [MeshVertexID]
        let boundaryEdges: [BoundaryEdge]
        let loops: [BoundaryLoop]
    }

    private struct AppliedExtrusion {
        let createdVertexIDs: [MeshVertexID]
        let createdEdgeIDs: [MeshEdgeID]
        let sideFaceIDs: [MeshFaceID]
        let capFaceIDs: [MeshFaceID]
        let createdCornerIDs: [MeshCornerID]
    }

    private struct EdgeIncidence {
        let faceID: MeshFaceID
        let start: MeshVertexID
        let end: MeshVertexID
    }

    private func makeExtrusion(
        faceIDs: [MeshFaceID],
        offset: GeometryVector3D,
        in buffer: MeshEditBuffer,
        budget: inout ExecutionBudget
    ) throws -> ExtrusionGeometry {
        guard !faceIDs.isEmpty else {
            throw MeshEditError(
                code: .emptySelection,
                message: "Face extrusion requires at least one face."
            )
        }
        try offset.validate()
        guard !offset.isZero else {
            throw MeshEditError(
                code: .zeroExtrusionOffset,
                message: "Face extrusion requires a non-zero offset."
            )
        }

        let analysisRecordCount: Int
        do {
            analysisRecordCount = try buffer.activeFaceAnalysisRecordCount()
        } catch let error as MeshSourceError {
            throw MeshEditError(code: .integerOverflow, message: error.message)
        }
        try budget.scan(analysisRecordCount)
        let faces = try buffer.activeFaceStates()
        let facesByID = Dictionary(uniqueKeysWithValues: faces.map { ($0.id, $0) })
        var selectedFaces: [MeshEditBuffer.FaceState] = []
        var selectedSet: Set<MeshFaceID> = []
        for faceID in faceIDs {
            guard let face = facesByID[faceID] else {
                throw MeshEditError(
                    code: .invalidReference,
                    message: "Face extrusion references an inactive face."
                )
            }
            guard selectedSet.insert(faceID).inserted else {
                throw MeshEditError(
                    code: .invalidReference,
                    message: "Face extrusion cannot repeat a face ID."
                )
            }
            selectedFaces.append(face)
        }

        var incidences: [MeshEdgeID: [EdgeIncidence]] = [:]
        for face in faces {
            for index in face.vertexIDs.indices {
                let next = index + 1 == face.vertexIDs.count ? 0 : index + 1
                let edgeID = face.edgeIDs[index]
                incidences[edgeID, default: []].append(
                    EdgeIncidence(
                        faceID: face.id,
                        start: face.vertexIDs[index],
                        end: face.vertexIDs[next]
                    )
                )
            }
        }

        var adjacency: [MeshFaceID: Set<MeshFaceID>] = [:]
        var boundaryEdges: [BoundaryEdge] = []
        for face in selectedFaces {
            for index in face.vertexIDs.indices {
                let next = index + 1 == face.vertexIDs.count ? 0 : index + 1
                let edgeID = face.edgeIDs[index]
                guard let edgeIncidences = incidences[edgeID],
                      edgeIncidences.count <= 2 else {
                    throw MeshEditError(
                        code: .nonManifoldFaceRegion,
                        message: "Face extrusion requires every touched edge to have at most two incident faces."
                    )
                }
                let selectedIncidences = edgeIncidences.filter { selectedSet.contains($0.faceID) }
                if selectedIncidences.count == 2 {
                    guard selectedIncidences.count == 2 else {
                        throw MeshEditError(
                            code: .invalidFaceRegion,
                            message: "Face extrusion internal edge incidence is invalid."
                        )
                    }
                    let first = selectedIncidences[0]
                    let second = selectedIncidences[1]
                    guard first.start == second.end, first.end == second.start else {
                        throw MeshEditError(
                            code: .inconsistentFaceOrientation,
                            message: "Selected faces must have opposite directed edges along internal boundaries."
                        )
                    }
                    adjacency[first.faceID, default: []].insert(second.faceID)
                    adjacency[second.faceID, default: []].insert(first.faceID)
                } else if selectedIncidences.count == 1 {
                    boundaryEdges.append(
                        BoundaryEdge(
                            edgeID: edgeID,
                            start: face.vertexIDs[index],
                            end: face.vertexIDs[next]
                        )
                    )
                } else {
                    throw MeshEditError(
                        code: .invalidFaceRegion,
                        message: "Selected face edge incidence must be one or two."
                    )
                }
            }
        }

        var visited: Set<MeshFaceID> = []
        var queue: [MeshFaceID] = [selectedFaces[0].id]
        while let current = queue.popLast() {
            guard visited.insert(current).inserted else {
                continue
            }
            queue.append(contentsOf: adjacency[current, default: []])
        }
        guard visited.count == selectedFaces.count else {
            throw MeshEditError(
                code: .disconnectedFaceRegion,
                message: "Face extrusion requires one connected face region."
            )
        }
        guard !boundaryEdges.isEmpty else {
            throw MeshEditError(
                code: .invalidFaceRegion,
                message: "Closed face regions are not valid extrusion inputs."
            )
        }

        let boundaryVertexSet = Set(
            boundaryEdges.flatMap { [$0.start, $0.end] }
        )
        var outgoing: [MeshVertexID: [BoundaryEdge]] = [:]
        var incoming: [MeshVertexID: [BoundaryEdge]] = [:]
        for edge in boundaryEdges {
            outgoing[edge.start, default: []].append(edge)
            incoming[edge.end, default: []].append(edge)
        }
        for vertexID in boundaryVertexSet {
            guard outgoing[vertexID]?.count == 1,
                  incoming[vertexID]?.count == 1 else {
                throw MeshEditError(
                    code: .invalidFaceRegion,
                    message: "Every boundary vertex must have degree two in the boundary loops."
                )
            }
        }

        let orderedBoundaryVertices = boundaryVertexSet.sorted()
        var remaining = Set(boundaryEdges.map(\.edgeID))
        var loops: [BoundaryLoop] = []
        var nextStartIndex = 0
        while !remaining.isEmpty {
            var start: MeshVertexID?
            while nextStartIndex < orderedBoundaryVertices.count {
                let candidate = orderedBoundaryVertices[nextStartIndex]
                nextStartIndex += 1
                if let edge = outgoing[candidate]?.first,
                   remaining.contains(edge.edgeID) {
                    start = candidate
                    break
                }
            }
            guard let start else {
                throw MeshEditError(
                    code: .invalidFaceRegion,
                    message: "Boundary edges could not be ordered into closed loops."
                )
            }
            var current = start
            var loop: [BoundaryEdge] = []
            while true {
                guard let edge = outgoing[current]?.first,
                      remaining.contains(edge.edgeID) else {
                    throw MeshEditError(
                        code: .invalidFaceRegion,
                        message: "Boundary loops must be closed and non-branching."
                    )
                }
                loop.append(edge)
                remaining.remove(edge.edgeID)
                current = edge.end
                if current == start {
                    break
                }
                guard loop.count <= boundaryEdges.count else {
                    throw MeshEditError(
                        code: .invalidFaceRegion,
                        message: "Boundary loop traversal exceeded its edge count."
                    )
                }
            }
            loops.append(BoundaryLoop(edges: loop))
        }
        loops.sort { lhs, rhs in
            (lhs.edges.map(\.start).min() ?? MeshVertexID(0))
                < (rhs.edges.map(\.start).min() ?? MeshVertexID(0))
        }

        var selectedVertexSet: Set<MeshVertexID> = []
        for face in selectedFaces {
            selectedVertexSet.formUnion(face.vertexIDs)
        }
        let vertexIDs = buffer.orderedActiveVertexIDs(containing: selectedVertexSet)
        let boundaryVertices = orderedBoundaryVertices
        return ExtrusionGeometry(
            faces: selectedFaces,
            vertexIDs: vertexIDs,
            boundaryVertices: boundaryVertices,
            boundaryEdges: boundaryEdges,
            loops: loops
        )
    }

    private func extrusionPositions(
        for extrusion: ExtrusionGeometry,
        offset: GeometryVector3D,
        in buffer: MeshEditBuffer
    ) throws -> [MeshVertexID: GeometryPoint3D] {
        var positions: [MeshVertexID: GeometryPoint3D] = [:]
        positions.reserveCapacity(extrusion.vertexIDs.count)
        for vertexID in extrusion.vertexIDs {
            positions[vertexID] = try offset.applying(to: buffer.position(for: vertexID))
        }
        return positions
    }

    private func applyExtrusion(
        _ extrusion: ExtrusionGeometry,
        positions: [MeshVertexID: GeometryPoint3D],
        in buffer: inout MeshEditBuffer
    ) throws -> AppliedExtrusion {
        var duplicatedVertexIDs: [MeshVertexID: MeshVertexID] = [:]
        var createdVertexIDs: [MeshVertexID] = []
        for vertexID in extrusion.vertexIDs {
            guard let position = positions[vertexID] else {
                throw MeshEditError(
                    code: .invalidReference,
                    message: "Extrusion is missing a prepared duplicated vertex position."
                )
            }
            let duplicated = try buffer.addVertex(position)
            duplicatedVertexIDs[vertexID] = duplicated
            createdVertexIDs.append(duplicated)
        }

        var capEdgeIDs: [MeshEdgeID: MeshEdgeID] = [:]
        var createdEdgeIDs: [MeshEdgeID] = []
        for loop in extrusion.loops {
            for boundaryEdge in loop.edges {
                guard let duplicatedStart = duplicatedVertexIDs[boundaryEdge.start],
                      let duplicatedEnd = duplicatedVertexIDs[boundaryEdge.end] else {
                    throw MeshEditError(
                        code: .invalidReference,
                        message: "Extrusion boundary vertices were not duplicated."
                    )
                }
                let capEdge = try buffer.stageEdge(
                    start: duplicatedStart,
                    end: duplicatedEnd,
                    forceNew: true
                )
                capEdgeIDs[boundaryEdge.edgeID] = capEdge.id
                createdEdgeIDs.append(capEdge.id)
            }
        }

        var longitudinalEdgeIDs: [MeshVertexID: MeshEdgeID] = [:]
        for vertexID in extrusion.boundaryVertices {
            guard let duplicated = duplicatedVertexIDs[vertexID] else {
                throw MeshEditError(
                    code: .invalidReference,
                    message: "Extrusion boundary vertex was not duplicated."
                )
            }
            let edge = try buffer.stageEdge(
                start: vertexID,
                end: duplicated,
                forceNew: true
            )
            longitudinalEdgeIDs[vertexID] = edge.id
            createdEdgeIDs.append(edge.id)
        }

        var sideFaceIDs: [MeshFaceID] = []
        var createdCornerIDs: [MeshCornerID] = []
        for loop in extrusion.loops {
            for boundaryEdge in loop.edges {
                guard let duplicatedStart = duplicatedVertexIDs[boundaryEdge.start],
                      let duplicatedEnd = duplicatedVertexIDs[boundaryEdge.end],
                      let endLongitudinal = longitudinalEdgeIDs[boundaryEdge.end],
                      let startLongitudinal = longitudinalEdgeIDs[boundaryEdge.start],
                      let capEdge = capEdgeIDs[boundaryEdge.edgeID] else {
                    throw MeshEditError(
                        code: .invalidReference,
                        message: "Extrusion side-face references were not prepared."
                    )
                }
                let side = try buffer.stageFace(
                    vertexIDs: [
                        boundaryEdge.start,
                        boundaryEdge.end,
                        duplicatedEnd,
                        duplicatedStart,
                    ],
                    edgeIDs: [
                        boundaryEdge.edgeID,
                        endLongitudinal,
                        capEdge,
                        startLongitudinal,
                    ]
                )
                sideFaceIDs.append(side.face.id)
                createdCornerIDs.append(contentsOf: side.face.cornerIDs)
            }
        }

        var rewiredEdges: Set<MeshEdgeID> = []
        let boundaryEdgeIDs = Set(extrusion.boundaryEdges.map(\.edgeID))
        for face in extrusion.faces {
            for index in face.vertexIDs.indices {
                let next = index + 1 == face.vertexIDs.count ? 0 : index + 1
                let edgeID = face.edgeIDs[index]
                guard !rewiredEdges.contains(edgeID),
                      !boundaryEdgeIDs.contains(edgeID),
                      let start = duplicatedVertexIDs[face.vertexIDs[index]],
                      let end = duplicatedVertexIDs[face.vertexIDs[next]] else {
                    continue
                }
                try buffer.replaceEdgeEndpoints(edgeID, start: start, end: end)
                rewiredEdges.insert(edgeID)
            }
        }

        let capEdgeByOriginalID = capEdgeIDs
        for face in extrusion.faces {
            let vertices = try face.vertexIDs.map { vertexID in
                guard let duplicated = duplicatedVertexIDs[vertexID] else {
                    throw MeshEditError(
                        code: .invalidReference,
                        message: "Extrusion cap references a missing duplicated vertex."
                    )
                }
                return duplicated
            }
            let edges = face.edgeIDs.map { edgeID in
                if let capEdge = capEdgeByOriginalID[edgeID] {
                    return capEdge
                }
                return edgeID
            }
            try buffer.replaceFaceLoop(
                faceID: face.id,
                vertexIDs: vertices,
                edgeIDs: edges
            )
        }

        return AppliedExtrusion(
            createdVertexIDs: createdVertexIDs,
            createdEdgeIDs: createdEdgeIDs,
            sideFaceIDs: sideFaceIDs,
            capFaceIDs: extrusion.faces.map(\.id),
            createdCornerIDs: createdCornerIDs
        )
    }
}
