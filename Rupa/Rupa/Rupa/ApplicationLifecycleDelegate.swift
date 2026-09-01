import AppKit
import Foundation

@MainActor
final class ApplicationLifecycleDelegate: NSObject, NSApplicationDelegate {
    private var projectCoordinator: ApplicationProjectCoordinator?
    private var agentLifecycle: ApplicationAgentHostLifecycle?
    private var pendingOpenURLs: [URL] = []
    private var didFinishLaunching = false
    private var startupTask: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?

    private(set) var agentFailureMessage: String?

    func configure(
        projectCoordinator: ApplicationProjectCoordinator,
        agentLifecycle: ApplicationAgentHostLifecycle?
    ) {
        precondition(
            self.projectCoordinator == nil,
            "The application lifecycle must be configured once."
        )
        self.projectCoordinator = projectCoordinator
        self.agentLifecycle = agentLifecycle
        startApplicationLifecycleIfReady()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        startApplicationLifecycleIfReady()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let standardizedURLs = urls.map(\.standardizedFileURL)
        guard !standardizedURLs.isEmpty else {
            return
        }
        guard didFinishLaunching, let projectCoordinator else {
            pendingOpenURLs.append(contentsOf: standardizedURLs)
            return
        }
        for url in standardizedURLs {
            projectCoordinator.receiveOpenURL(url)
        }
    }

    func waitForStartupCompletion() async {
        await startupTask?.value
    }

    private func startApplicationLifecycleIfReady() {
        guard didFinishLaunching,
              let projectCoordinator,
              startupTask == nil else {
            return
        }
        startupTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let initialOpenURLs = self.pendingOpenURLs
            self.pendingOpenURLs.removeAll(keepingCapacity: false)
            for url in initialOpenURLs {
                projectCoordinator.receiveOpenURL(url)
            }
            await projectCoordinator.launch()
            guard let agentLifecycle = self.agentLifecycle else {
                return
            }
            do {
                try await agentLifecycle.start()
            } catch is CancellationError {
                return
            } catch {
                self.agentFailureMessage = error.localizedDescription
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
