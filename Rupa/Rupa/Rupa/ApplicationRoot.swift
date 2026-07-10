//
//  ApplicationRoot.swift
//  Rupa
//
//  Created by 1amageek on 2026/06/04.
//

import SwiftUI
import RupaAgentUI
import RupaCore
import RupaUI

@main
struct ApplicationRoot: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var agentHost: AgentHost
    @State private var editorSession: EditorSession

    private let domainConfiguration: ApplicationDomainRegistryConfiguration

    init() {
        let domainConfiguration = ApplicationDomainRegistry.makeConfiguration()
        self.domainConfiguration = domainConfiguration
        self._agentHost = State(
            initialValue: AgentHost(
                exportService: domainConfiguration.exportService,
                domainRegistry: domainConfiguration.registry
            )
        )
        self._editorSession = State(
            initialValue: WorkspaceLaunchSessionFactory.makeSession()
        )
    }

    var body: some Scene {
        WindowGroup {
            MainView(
                session: editorSession,
                domainRegistry: domainConfiguration.registry,
                agentSessionPublisher: agentHost
            )
            .overlay(alignment: .top) {
                ApplicationDomainStartupDiagnosticsView(
                    messages: domainConfiguration.startupDiagnostics
                )
            }
        }
        .windowResizability(.contentMinSize)
        .onChange(of: scenePhase) { _, phase in
            Task {
                switch phase {
                case .active:
                    await agentHost.start()
                case .background:
                    await agentHost.stop()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
        }
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
