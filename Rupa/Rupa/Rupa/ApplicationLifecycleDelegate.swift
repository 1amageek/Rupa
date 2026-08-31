import AppKit
import Foundation

@MainActor
final class ApplicationLifecycleDelegate: NSObject, NSApplicationDelegate {
    private var agentLifecycle: ApplicationAgentHostLifecycle?
    private var startupTask: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?

    private(set) var agentFailureMessage: String?

    func configure(agentLifecycle: ApplicationAgentHostLifecycle) {
        precondition(
            self.agentLifecycle == nil,
            "The application Agent lifecycle must be configured once."
        )
        self.agentLifecycle = agentLifecycle
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let agentLifecycle, startupTask == nil else {
            return
        }
        startupTask = Task { @MainActor [weak self] in
            do {
                try await agentLifecycle.start()
            } catch is CancellationError {
                return
            } catch {
                self?.agentFailureMessage = error.localizedDescription
                NSLog("Rupa Agent API startup failed: %@", error.localizedDescription)
            }
        }
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard let agentLifecycle else {
            return .terminateNow
        }
        guard shutdownTask == nil else {
            return .terminateLater
        }

        startupTask?.cancel()
        shutdownTask = Task { @MainActor [weak self] in
            do {
                try await agentLifecycle.stop()
            } catch {
                self?.agentFailureMessage = error.localizedDescription
                NSLog("Rupa Agent API shutdown failed: %@", error.localizedDescription)
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
