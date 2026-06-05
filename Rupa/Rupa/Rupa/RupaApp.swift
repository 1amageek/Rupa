//
//  RupaApp.swift
//  Rupa
//
//  Created by 1amageek on 2026/06/04.
//

import SwiftUI
import RupaUI

@main
struct RupaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var agentHost = RupaAgentHost()

    var body: some Scene {
        WindowGroup {
            RupaMainView(agentHost: agentHost)
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
