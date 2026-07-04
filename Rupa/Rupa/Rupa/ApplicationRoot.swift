//
//  ApplicationRoot.swift
//  Rupa
//
//  Created by 1amageek on 2026/06/04.
//

import SwiftUI
import RupaAgentUI
import RupaUI

@main
struct ApplicationRoot: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var agentHost = AgentHost()
    @State private var editorSession = WorkspaceLaunchSessionFactory.makeSession()

    var body: some Scene {
        WindowGroup {
            MainView(
                session: editorSession,
                agentHost: agentHost
            )
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
