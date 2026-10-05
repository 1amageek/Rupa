import SwiftCAD
import RupaCoreTypes

extension SceneNodeHierarchy {
    /// Expands the complete original scene without creating composed display matrices.
    public static func originalDrawingOccurrences(in metadata: ProductMetadata,
        usage: inout DrawingExchangeUsage) throws -> [OriginalDrawingSceneOccurrence] {
        func invalid(_ message: String) -> EditorError {
            EditorError(code: .referenceUnresolved, message: message)
        }
        func reserve<T>(_ count: Int, _ type: T.Type, usage: inout DrawingExchangeUsage) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
            guard !bytes.overflow else { throw invalid("Original occurrence capacity overflowed.") }
            try usage.charge(bytes: bytes.partialValue)
        }
        // Complete source forest ownership is checked without temporary hash indexes.
        for (index, root) in metadata.rootSceneNodeIDs.enumerated() {
            for prior in 0..<index {
                try usage.charge(work: 1)
                guard metadata.rootSceneNodeIDs[prior] != root else {
                    throw invalid("Original scene roots contain duplicate identities.")
                }
            }
        }
        for (id, _) in metadata.sceneNodes {
            var parentCount = 0
            for (_, parent) in metadata.sceneNodes {
                for child in parent.childIDs {
                    try usage.charge(work: 1)
                    guard metadata.sceneNodes[child] != nil else {
                        throw invalid("Original scene has a missing child.")
                    }
                    if child == id {
                        parentCount += 1
                        guard parentCount <= 1 else { throw invalid("Original scene child has multiple parents.") }
                    }
                }
            }
            guard parentCount <= 1 else { throw invalid("Original scene child has multiple parents.") }
            for root in metadata.rootSceneNodeIDs {
                try usage.charge(work: 1)
                if root == id, parentCount != 0 { throw invalid("Original scene root is also a child.") }
            }
        }
        try reserve(metadata.sceneNodes.count, SceneNodeID.self, usage: &usage)
        var visited: [SceneNodeID] = []
        visited.reserveCapacity(metadata.sceneNodes.count)
        func forest(_ id: SceneNodeID, depth: Int, usage: inout DrawingExchangeUsage) throws {
            try usage.check(); try usage.charge(work: 1)
            guard depth <= usage.maximumNesting, let node = metadata.sceneNodes[id] else {
                throw invalid("Original scene forest source depth or identity is invalid.")
            }
            for prior in visited {
                try usage.charge(work: 1)
                guard prior != id else { throw invalid("Original scene forest is cyclic or repeated.") }
            }
            visited.append(id)
            for child in node.childIDs { try forest(child, depth: depth + 1, usage: &usage) }
        }
        for root in metadata.rootSceneNodeIDs { try forest(root, depth: 0, usage: &usage) }
        guard visited.count == metadata.sceneNodes.count else {
            throw invalid("Original scene contains unreachable nodes.")
        }
        var result: [OriginalDrawingSceneOccurrence] = []
        var capacity = 0
        func append(_ nodeID: SceneNodeID, prefix: String?, owner: SceneNodeID?,
            parentFactors: [Transform3D], localPrefix: Transform3D?,
            rootPlacement: ComponentDefinition.RootPlacement?, visible: Bool,
            definitions: [ComponentDefinitionID], depth: Int,
            usage: inout DrawingExchangeUsage) throws {
            try usage.check(); try usage.charge(work: 1)
            guard depth <= usage.maximumNesting, let node = metadata.sceneNodes[nodeID] else {
                throw invalid("Original occurrence source depth or node is invalid.")
            }
            let raw = rootPlacement?.transform ?? node.localTransform
            try usage.charge(work: 16)
            try raw.validateAffinePlacement()
            let factorCount = parentFactors.count.addingReportingOverflow(localPrefix == nil ? 1 : 2)
            guard !factorCount.overflow else { throw invalid("Original occurrence factor count overflowed.") }
            try reserve(factorCount.partialValue, Transform3D.self, usage: &usage)
            var factors: [Transform3D] = []
            factors.reserveCapacity(factorCount.partialValue)
            factors.append(raw)
            if let localPrefix { factors.append(localPrefix) }
            for factor in parentFactors { try usage.charge(work: 1); factors.append(factor) }
            // Tagged source IDs have the canonical 128-bit identifier description.
            try usage.charge(bytes: 36)
            let nodeName = nodeID.description
            let nameCount = (prefix?.utf8.count ?? 6).addingReportingOverflow(nodeName.utf8.count + 1)
            guard !nameCount.overflow else { throw invalid("Original occurrence identity overflowed.") }
            try usage.charge(bytes: nameCount.partialValue)
            let id = SceneOccurrenceID(rawValue: prefix.map { $0 + "/" + nodeName } ?? "scene." + nodeName)
            if result.count == capacity {
                let doubled = capacity.multipliedReportingOverflow(by: 2)
                guard !doubled.overflow else { throw invalid("Original occurrence storage overflowed.") }
                let next = max(1, doubled.partialValue)
                guard next > capacity else { throw invalid("Original occurrence storage overflowed.") }
                try reserve(next, OriginalDrawingSceneOccurrence.self, usage: &usage)
                result.reserveCapacity(next); capacity = next
            }
            let isVisible = visible && (rootPlacement?.isVisible ?? node.isVisible)
            result.append(.init(id: id, sourceSceneNodeID: nodeID, sceneNodeID: owner ?? nodeID,
                originalTransformFactors: factors, isVisible: isVisible))
            if node.reference?.kind == .componentInstance {
                guard let instanceID = node.reference?.componentInstanceID,
                    let instance = metadata.componentInstances[instanceID],
                    let definition = metadata.componentDefinitions[instance.definitionID] else {
                    throw invalid("Original component occurrence has no instance or definition.")
                }
                for ancestor in definitions {
                    try usage.charge(work: 1)
                    guard ancestor != definition.id else { throw invalid("Original component definitions recurse.") }
                }
                try usage.charge(work: 16)
                try instance.localTransform.validateAffinePlacement()
                try reserve(definitions.count + 1, ComponentDefinitionID.self, usage: &usage)
                var path: [ComponentDefinitionID] = []
                path.reserveCapacity(definitions.count + 1)
                for ancestor in definitions { try usage.charge(work: 1); path.append(ancestor) }
                path.append(definition.id)
                for (index, root) in definition.rootSceneNodeIDs.enumerated() {
                    for prior in 0..<index {
                        try usage.charge(work: 1)
                        guard root != definition.rootSceneNodeIDs[prior] else {
                            throw invalid("Original component roots repeat.")
                        }
                    }
                    try append(root, prefix: id.rawValue, owner: owner ?? nodeID,
                        parentFactors: factors, localPrefix: instance.localTransform,
                        rootPlacement: try definition.rootPlacement(for: root),
                        visible: isVisible && instance.isVisible, definitions: path,
                        depth: depth + 1, usage: &usage)
                }
            }
            for child in node.childIDs {
                try append(child, prefix: prefix == nil ? nil : id.rawValue, owner: owner,
                    parentFactors: factors, localPrefix: nil, rootPlacement: nil,
                    visible: isVisible, definitions: definitions, depth: depth + 1, usage: &usage)
            }
        }
        for root in metadata.rootSceneNodeIDs {
            try append(root, prefix: nil, owner: nil, parentFactors: [], localPrefix: nil,
                rootPlacement: nil, visible: true, definitions: [], depth: 0, usage: &usage)
        }
        return result
    }
}
