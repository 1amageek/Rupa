//
//  ApplicationRoot.swift
//  Rupa
//
//  Created by 1amageek on 2026/06/04.
//

import SwiftUI
import RupaUI

@main
struct ApplicationRoot: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var agentHost = AgentHost()

    var body: some Scene {
        WindowGroup {
            MainView(agentHost: agentHost)
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
