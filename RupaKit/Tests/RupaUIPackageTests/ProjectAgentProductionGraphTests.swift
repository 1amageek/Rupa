import Foundation
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

    let retiredInvocationName = ["Capability", "Invocation"].joined()
    let retiredExecutionBaseName = ["Agent", "Capability", "Execution"].joined()
    let forbiddenPatterns = [
        #"\bEditorSession\b"#,
        #"\bAgentCommandController\b"#,
        #"\bAgentCommandHandler\b"#,
        #"\bMainActorAgentBridge\b"#,
        #"\b"# + retiredInvocationName + #"\b"#,
        #"\b"# + retiredExecutionBaseName + "(Result|Error)\\b",
    ]
    for sourceURL in sourceURLs {
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        for pattern in forbiddenPatterns {
            #expect(
                source.range(of: pattern, options: .regularExpression) == nil,
                "Production Agent Runtime still references a legacy authority or capability payload in \(sourceURL.lastPathComponent)."
            )
        }
    }

    let legacyFiles = [
        "AgentCommandController.swift",
        "AgentCommandHandler.swift",
        "MainActorAgentBridge.swift",
        "WorkspaceRegistry.swift",
        ["Agent", "Capability", "Invocation", "Executor"].joined() + ".swift",
    ]
    for file in legacyFiles {
        #expect(FileManager.default.fileExists(atPath: runtime.appendingPathComponent(file).path) == false)
    }
}

@Test(.timeLimit(.minutes(1)))
func projectAgentSemanticRoutesAreExplicitAndRawPayloadsHaveNoProductionOwner() throws {
    let root = packageRoot()
    let messageSource = try String(
        contentsOf: root.appendingPathComponent("Sources/RupaAgentProtocol/AgentMessage.swift"),
        encoding: .utf8
    )
    let requestSource = try String(
        contentsOf: root.appendingPathComponent("Sources/RupaAgentProtocol/AgentRequestEnvelope.swift"),
        encoding: .utf8
    )
    let controllerSource = try String(
        contentsOf: root.appendingPathComponent("Sources/RupaAgentRuntime/ProjectAgentCommandController.swift"),
        encoding: .utf8
    )

    #expect(messageSource.contains("case invokeCapability(AgentSemanticDirectExecutionRequest)"))
    #expect(messageSource.contains("case executeProgram(AgentSemanticProgramExecutionRequest)"))
    #expect(messageSource.contains("\"capability.invoke\""))
    #expect(messageSource.contains("\"program.execute\""))
    #expect(requestSource.contains("authority"))
    #expect(requestSource.contains("dryRun"))
    #expect(requestSource.contains("AgentSemanticDirectRequest"))
    #expect(requestSource.contains("AgentSemanticProgramRequest"))
    #expect(controllerSource.contains("stage: .dispatchUnavailable"))
    #expect(controllerSource.contains("case .invokeCapability"))
    #expect(controllerSource.contains("case .executeProgram"))
    #expect(controllerSource.contains("FIXME(INCOMPLETE_IMPLEMENTATION)"))
    let protocolDirectory = root.appendingPathComponent("Sources/RupaAgentProtocol")
    let capabilitiesDirectory = root.appendingPathComponent("Sources/RupaCapabilities")
    #expect(FileManager.default.fileExists(
        atPath: protocolDirectory.appendingPathComponent(
            ["Agent", "Capability", "Execution", "Result"].joined() + ".swift"
        ).path
    ) == false)
    #expect(FileManager.default.fileExists(
        atPath: capabilitiesDirectory.appendingPathComponent(
            ["Capability", "Invocation"].joined() + ".swift"
        ).path
    ) == false)
}

private func packageRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
