//
//  ApplicationRoot.swift
//  Rupa
//
//  Created by 1amageek on 2026/06/04.
//

import Foundation
import SwiftUI
import RupaAgentProtocol
import RupaAgentRuntime
import RupaAgentUI
import RupaKit
import RupaProjectAccessPlatform
import RupaUI

@main
struct ApplicationRoot: App {
    @NSApplicationDelegateAdaptor(ApplicationLifecycleDelegate.self)
    private var applicationDelegate
    @State private var projectCoordinator: ApplicationProjectCoordinator
    @State private var viewportRegistry: ApplicationViewportRegistry?

    private let domainConfiguration: ApplicationDomainRegistryConfiguration
    private let projectOperationSequencer: ProjectWorkspaceOperationSequencer
    private let applicationAuthorityLease: ApplicationAuthorityLease?

    init() {
        let domainConfiguration = ApplicationDomainRegistry.makeConfiguration()
        let projectOperationSequencer = ProjectWorkspaceOperationSequencer()
        self.domainConfiguration = domainConfiguration
        self.projectOperationSequencer = projectOperationSequencer
        do {
            let applicationAuthorityLease = try ApplicationAuthorityLease
                .acquireProductAuthority()
            self.applicationAuthorityLease = applicationAuthorityLease
        } catch {
            self.applicationAuthorityLease = nil
            let projectCoordinator = ApplicationProjectCoordinator(
                launchFailure: error,
                agentRegistrar: ApplicationUnavailableAgentSessionRegistrar(),
                operationSequencer: projectOperationSequencer
            )
            self._projectCoordinator = State(initialValue: projectCoordinator)
            applicationDelegate.configure(
                projectCoordinator: projectCoordinator,
                agentLifecycle: nil
            )
            return
        }
        do {
            let semanticProtocolEncodingLimits = AgentProtocolEncodingLimits()
            let agentController = ProjectAgentCommandController(
                semanticProgramCompiler: try ApplicationDomainRegistry
                    .makeCADSemanticCompiler(),
                domainRegistry: domainConfiguration.registry,
                semanticProtocolEncodingLimits: semanticProtocolEncodingLimits,
                exportExecutor: ProjectAgentExportExecutor(
                    exportService: domainConfiguration.exportService
                )
            )
            let workspace = try DefaultProjectWorkspaceFactory().makeWorkspace()
            let projectCoordinator = ApplicationProjectCoordinator(
                workspace: workspace,
                agentRegistrar: agentController,
                operationSequencer: projectOperationSequencer,
                initialURL: Self.initialProjectURL()
            )
            let requestRouter = ApplicationAgentRequestRouter(
                projectHandler: agentController,
                lifecycle: projectCoordinator
            )
            let viewportRegistry = ApplicationViewportRegistry(coordinator: projectCoordinator)
            let viewportRouter = ApplicationViewportRequestRouter(
                downstream: requestRouter, viewports: viewportRegistry
            )
            let agentLifecycle = try ApplicationAgentHostLifecycle(
                handler: viewportRouter,
                discoveryStore: ApplicationProductConfiguration
                    .makeDiscoveryStore(),
                requestTimeout: ApplicationProductConfiguration
                    .access.requestTimeout,
                protocolEncodingLimits: semanticProtocolEncodingLimits
            )
            self._projectCoordinator = State(initialValue: projectCoordinator)
            self._viewportRegistry = State(initialValue: viewportRegistry)
            applicationDelegate.configure(
                projectCoordinator: projectCoordinator,
                agentLifecycle: agentLifecycle
            )
        } catch {
            let projectCoordinator = ApplicationProjectCoordinator(
                launchFailure: error,
                agentRegistrar: ApplicationUnavailableAgentSessionRegistrar(),
                operationSequencer: projectOperationSequencer
            )
            self._projectCoordinator = State(initialValue: projectCoordinator)
            applicationDelegate.configure(
                projectCoordinator: projectCoordinator,
                agentLifecycle: nil
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            applicationContent
            .overlay(alignment: .top) {
                ApplicationDomainStartupDiagnosticsView(
                    messages: domainConfiguration.startupDiagnostics
                )
            }
            .alert(
                projectCoordinator.failure?.didCommit == true
                    ? "Project Operation Completed with a Presentation Error"
                    : "Project Operation Failed",
                isPresented: Binding(
                    get: { projectCoordinator.failure != nil },
                    set: { isPresented in
                        if !isPresented {
                            projectCoordinator.clearFailure()
                        }
                    }
                ),
                presenting: projectCoordinator.failure
            ) { _ in
                Button("OK") {
                    projectCoordinator.clearFailure()
                }
            } message: { failure in
                Text(failure.message)
            }
        }
        .windowResizability(.contentMinSize)
        .commands {
            ApplicationProjectCommands(coordinator: projectCoordinator)
            ApplicationToolCommands()
        }
    }

    @ViewBuilder
    private var applicationContent: some View {
        switch projectCoordinator.lifecycle {
        case .preparing:
            ProgressView("Opening Project")
                .frame(minWidth: 1_120, minHeight: 720)
                .accessibilityIdentifier("ApplicationProject.preparing")
        case .ready:
            if let workspace = projectCoordinator.workspace {
                MainView(
                    workspace: workspace,
                    domainRegistry: domainConfiguration.registry,
                    operationSequencer: projectOperationSequencer,
                    newProject: {
                        projectCoordinator.startNewProject()
                    },
                    onViewportMount: { lifetime, control in
                        viewportRegistry?.mount(lifetime: lifetime, control: control)
                    },
                    onViewportUnmount: { id in
                        viewportRegistry?.unmount(id)
                    }
                )
                .accessibilityIdentifier("ApplicationProject.ready")
            } else {
                projectUnavailableView(
                    message: "The project workspace is unavailable."
                )
            }
        case .unavailable(let failure):
            projectUnavailableView(message: failure.message)
        }
    }

    private func projectUnavailableView(message: String) -> some View {
        ContentUnavailableView(
            "Project Unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
        .frame(minWidth: 1_120, minHeight: 720)
        .accessibilityIdentifier("ApplicationProject.unavailable")
    }

    private static func initialProjectURL(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> URL? {
        let prefix = "--rupa-project="
        guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        let path = String(argument.dropFirst(prefix.count))
        guard !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
}

private struct ApplicationDomainStartupDiagnosticsView: View {
    var messages: [String]

    var body: some View {
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(messages, id: \.self) { message in
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.top, 8)
        }
    }
}
