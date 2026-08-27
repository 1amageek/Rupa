import Foundation
import RupaAgentRuntime
import RupaDomainFoundation
import Testing

@Test(.timeLimit(.minutes(1)))
func projectAgentProductionGraphHasOneProjectAuthority() throws {
    let root = packageRoot()
    let runtime = root.appendingPathComponent("Sources/RupaAgentRuntime")
    let productionDirectories = [
        runtime,
        root.appendingPathComponent("Sources/RupaAgentUI"),
    ]
    let sourceURLs = try productionDirectories.flatMap { directory in
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
    }

    let forbiddenPatterns = [
        #"\bEditorSession\b"#,
        #"\bAgentCommandController\b"#,
        #"\bAgentCommandHandler\b"#,
        #"\bMainActorAgentBridge\b"#,
    ]
    for sourceURL in sourceURLs {
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        for pattern in forbiddenPatterns {
            #expect(
                source.range(of: pattern, options: .regularExpression) == nil,
                "Production Agent Runtime still references a legacy authority in \(sourceURL.lastPathComponent)."
            )
        }
    }

    let legacyFiles = [
        "AgentCommandController.swift",
        "AgentCommandHandler.swift",
        "MainActorAgentBridge.swift",
        "WorkspaceRegistry.swift",
        "AgentCapabilityInvocationExecutor.swift",
    ]
    for file in legacyFiles {
        #expect(FileManager.default.fileExists(atPath: runtime.appendingPathComponent(file).path) == false)
    }
}

@Test(.timeLimit(.minutes(1)))
func projectAgentRouteInventoriesAreFixedAndExhaustiveAtTheirOwners() throws {
    let root = packageRoot()
    let requestSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/RupaAgentProtocol/AgentMessage.swift"
        ),
        encoding: .utf8
    )
    let requestDeclaration = try #require(
        requestSource.split(separator: "public enum AgentResponse", maxSplits: 1).first
    )
    #expect(caseCount(in: String(requestDeclaration)) == 53)

    let automationSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/RupaAutomation/AutomationCommand.swift"
        ),
        encoding: .utf8
    )
    #expect(caseCount(in: automationSource) == 127)

    let staticCapabilities = AgentCapabilityCatalog.descriptors(
        domainRegistry: DomainRegistry()
    )
    #expect(staticCapabilities.count == 170)
    #expect(Set(staticCapabilities.map(\.name)).count == 170)
    #expect(staticCapabilities.contains { $0.name == "setFeatureSuppression" } == false)
    for descriptor in staticCapabilities {
        switch descriptor.access {
        case .automationCommand, .agentRequest, .domainCapability:
            break
        }
    }
}

private func packageRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func caseCount(in source: String) -> Int {
    source.split(separator: "\n").count { line in
        line.hasPrefix("    case ")
    }
}
