public struct DesignProcessFlowGraph: Codable, Equatable, Sendable {
    public var nodes: [DesignProcessFlowNode]
    public var edges: [DesignProcessFlowEdge]
    public var requiredPorts: [DesignProcessFlowPortRequirement]

    public init(
        nodes: [DesignProcessFlowNode] = [],
        edges: [DesignProcessFlowEdge] = [],
        requiredPorts: [DesignProcessFlowPortRequirement] = []
    ) {
        self.nodes = nodes
        self.edges = edges
        self.requiredPorts = requiredPorts
    }

    public func validate() -> DesignProcessFlowGraphValidationResult {
        var issues: [DesignProcessFlowGraphValidationIssue] = []
        var nodeMap: [String: DesignProcessFlowNode] = [:]

        for node in nodes {
            if nodeMap[node.id] != nil {
                issues.append(
                    DesignProcessFlowGraphValidationIssue(
                        kind: .duplicateNode,
                        nodeID: node.id,
                        message: "Flow graph contains duplicate node IDs."
                    )
                )
            } else {
                nodeMap[node.id] = node
            }

            var portIDs: Set<String> = []
            for port in node.ports where !portIDs.insert(port.id).inserted {
                issues.append(
                    DesignProcessFlowGraphValidationIssue(
                        kind: .duplicatePort,
                        nodeID: node.id,
                        portID: port.id,
                        message: "Flow graph node contains duplicate port IDs."
                    )
                )
            }
        }

        for edge in edges {
            guard let sourceNode = nodeMap[edge.sourceNodeID] else {
                issues.append(
                    DesignProcessFlowGraphValidationIssue(
                        kind: .danglingEdgeSourceNode,
                        nodeID: edge.sourceNodeID,
                        edgeID: edge.id,
                        message: "Flow edge references a missing source node."
                    )
                )
                continue
            }
            if !hasPort(edge.sourcePortID, in: sourceNode, matching: [.output, .bidirectional]) {
                issues.append(
                    DesignProcessFlowGraphValidationIssue(
                        kind: .danglingEdgeSourcePort,
                        nodeID: edge.sourceNodeID,
                        portID: edge.sourcePortID,
                        edgeID: edge.id,
                        message: "Flow edge references a missing source output port."
                    )
                )
            }

            guard let targetNode = nodeMap[edge.targetNodeID] else {
                issues.append(
                    DesignProcessFlowGraphValidationIssue(
                        kind: .danglingEdgeTargetNode,
                        nodeID: edge.targetNodeID,
                        edgeID: edge.id,
                        message: "Flow edge references a missing target node."
                    )
                )
                continue
            }
            if !hasPort(edge.targetPortID, in: targetNode, matching: [.input, .bidirectional]) {
                issues.append(
                    DesignProcessFlowGraphValidationIssue(
                        kind: .danglingEdgeTargetPort,
                        nodeID: edge.targetNodeID,
                        portID: edge.targetPortID,
                        edgeID: edge.id,
                        message: "Flow edge targets an input port that the node does not accept."
                    )
                )
            }
        }

        for requirement in requiredPorts {
            guard let node = nodeMap[requirement.nodeID] else {
                issues.append(
                    DesignProcessFlowGraphValidationIssue(
                        kind: .missingRequiredNode,
                        nodeID: requirement.nodeID,
                        portID: requirement.portID,
                        message: "Required port references a missing node."
                    )
                )
                continue
            }
            guard node.ports.contains(where: { $0.id == requirement.portID }) else {
                issues.append(
                    DesignProcessFlowGraphValidationIssue(
                        kind: .missingRequiredPort,
                        nodeID: requirement.nodeID,
                        portID: requirement.portID,
                        message: "Required port is not present on its node."
                    )
                )
                continue
            }

            if requiresIncoming(requirement.connection),
               !hasIncomingConnection(toNodeID: requirement.nodeID, portID: requirement.portID) {
                issues.append(
                    DesignProcessFlowGraphValidationIssue(
                        kind: .unreachableRequiredInput,
                        nodeID: requirement.nodeID,
                        portID: requirement.portID,
                        message: "Required input port has no incoming connection."
                    )
                )
            }

            if requiresOutgoing(requirement.connection),
               !hasValidOutgoingConnection(fromNodeID: requirement.nodeID, portID: requirement.portID, nodeMap: nodeMap) {
                issues.append(
                    DesignProcessFlowGraphValidationIssue(
                        kind: .floatingRequiredOutput,
                        nodeID: requirement.nodeID,
                        portID: requirement.portID,
                        message: "Required output port has no valid outgoing connection."
                    )
                )
            }
        }

        for node in nodes where isDeadEnd(node, nodeMap: nodeMap) {
            issues.append(
                DesignProcessFlowGraphValidationIssue(
                    kind: .deadEndNode,
                    nodeID: node.id,
                    message: "Node has no incoming connection, outgoing connection, or required terminal role."
                )
            )
        }

        return DesignProcessFlowGraphValidationResult(issues: issues)
    }

    private func hasPort(
        _ portID: String,
        in node: DesignProcessFlowNode,
        matching directions: [DesignProcessFlowPortDirection]
    ) -> Bool {
        node.ports.contains { port in
            port.id == portID && directions.contains(port.direction)
        }
    }

    private func requiresIncoming(_ connection: DesignProcessFlowPortConnection) -> Bool {
        switch connection {
        case .incoming, .any:
            true
        case .outgoing, .terminal:
            false
        }
    }

    private func requiresOutgoing(_ connection: DesignProcessFlowPortConnection) -> Bool {
        switch connection {
        case .outgoing, .any:
            true
        case .incoming, .terminal:
            false
        }
    }

    private func hasIncomingConnection(toNodeID nodeID: String, portID: String) -> Bool {
        edges.contains { edge in
            edge.targetNodeID == nodeID && edge.targetPortID == portID
        }
    }

    private func hasValidOutgoingConnection(
        fromNodeID nodeID: String,
        portID: String,
        nodeMap: [String: DesignProcessFlowNode]
    ) -> Bool {
        edges.contains { edge in
            edge.sourceNodeID == nodeID
                && edge.sourcePortID == portID
                && nodeMap[edge.targetNodeID] != nil
        }
    }

    private func isDeadEnd(
        _ node: DesignProcessFlowNode,
        nodeMap: [String: DesignProcessFlowNode]
    ) -> Bool {
        if requiredPorts.contains(where: { $0.nodeID == node.id && $0.connection == .terminal }) {
            return false
        }
        let hasIncoming = edges.contains { edge in
            edge.targetNodeID == node.id && nodeMap[edge.sourceNodeID] != nil
        }
        let hasValidOutgoing = edges.contains { edge in
            edge.sourceNodeID == node.id && nodeMap[edge.targetNodeID] != nil
        }
        let hasRequiredOutgoing = requiredPorts.contains { requirement in
            requirement.nodeID == node.id && requiresOutgoing(requirement.connection)
        }
        if hasRequiredOutgoing && hasIncoming && !hasValidOutgoing {
            return true
        }
        let hasRequiredPort = requiredPorts.contains { $0.nodeID == node.id }
        if hasRequiredPort {
            return !hasIncoming && !hasValidOutgoing
        }
        if node.ports.contains(where: { $0.direction == .output || $0.direction == .bidirectional }) {
            return false
        }
        return !hasIncoming && !hasValidOutgoing
    }

    public func hasPath(from sourceNodeID: String, to targetNodeID: String) -> Bool {
        var visited: Set<String> = []
        var stack = [sourceNodeID]

        while let nodeID = stack.popLast() {
            if nodeID == targetNodeID {
                return true
            }
            guard visited.insert(nodeID).inserted else {
                continue
            }
            for edge in edges where edge.sourceNodeID == nodeID {
                stack.append(edge.targetNodeID)
            }
        }

        return false
    }
}
