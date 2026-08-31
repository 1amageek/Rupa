import AppKit
import Foundation
import RupaProjectAccess
import RupaProjectAccessPlatform

@MainActor
protocol ProjectApplicationWorkspaceOpening: Sendable {
    func applicationURL(bundleIdentifier: String) -> URL?

    func open(
        projectURL: URL,
        withApplicationAt applicationURL: URL,
        completionHandler: @escaping @Sendable (ProjectApplicationOpenResult) -> Void
    )
}

enum ProjectApplicationOpenResult: Equatable, Sendable {
    case opened
    case failed(errorDomain: String, errorCode: Int, message: String)
}

@MainActor
private final class ProjectApplicationOpenAwaiter {
    enum Outcome: Sendable {
        case completed(ProjectApplicationOpenResult)
        case deadlineExceeded
        case cancelled
    }

    private var outcome: Outcome?
    private var continuation: CheckedContinuation<Outcome, Never>?

    func wait() async -> Outcome {
        if let outcome {
            return outcome
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resolve(_ outcome: Outcome) {
        guard self.outcome == nil else {
            return
        }
        self.outcome = outcome
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: outcome)
    }
}

@MainActor
private struct DefaultProjectApplicationWorkspaceOpener:
    ProjectApplicationWorkspaceOpening {
    func applicationURL(bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        )
    }

    func open(
        projectURL: URL,
        withApplicationAt applicationURL: URL,
        completionHandler: @escaping @Sendable (ProjectApplicationOpenResult) -> Void
    ) {
        NSWorkspace.shared.open(
            [projectURL],
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: { _, error in
                if let error {
                    let cocoaError = error as NSError
                    completionHandler(
                        .failed(
                            errorDomain: cocoaError.domain,
                            errorCode: cocoaError.code,
                            message: cocoaError.localizedDescription
                        )
                    )
                } else {
                    completionHandler(.opened)
                }
            }
        )
    }
}

/// Opens the registered Rupa document through LaunchServices.
@MainActor
public struct LaunchServicesProjectApplicationLauncher: LiveProjectApplicationLaunching {
    private let applicationBundleIdentifier: String
    private let workspace: any ProjectApplicationWorkspaceOpening

    public init(
        applicationBundleIdentifier: String =
            RupaAgentEndpointComposition.applicationBundleIdentifier
    ) {
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.workspace = DefaultProjectApplicationWorkspaceOpener()
    }

    init(
        applicationBundleIdentifier: String,
        workspace: any ProjectApplicationWorkspaceOpening
    ) {
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.workspace = workspace
    }

    public func launch(
        projectURL: URL,
        deadline: ContinuousClock.Instant
    ) async throws {
        try checkLiveProjectDeadline(deadline)
        guard let applicationURL = workspace.applicationURL(
            bundleIdentifier: applicationBundleIdentifier
        ) else {
            throw LiveProjectAccessError.applicationUnavailable(
                bundleIdentifier: applicationBundleIdentifier
            )
        }
        let awaiter = ProjectApplicationOpenAwaiter()
        workspace.open(
            projectURL: projectURL,
            withApplicationAt: applicationURL,
            completionHandler: { result in
                Task { @MainActor in
                    awaiter.resolve(.completed(result))
                }
            }
        )

        let clock = ContinuousClock()
        let deadlineTask = Task { @MainActor in
            do {
                try await clock.sleep(until: deadline)
                awaiter.resolve(.deadlineExceeded)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        let outcome = await withTaskCancellationHandler {
            await awaiter.wait()
        } onCancel: {
            Task { @MainActor in
                awaiter.resolve(.cancelled)
            }
        }
        deadlineTask.cancel()

        switch outcome {
        case .completed(.opened):
            try checkLiveProjectDeadline(deadline)
        case .completed(
            .failed(let errorDomain, let errorCode, let message)
        ):
            throw LiveProjectAccessError.applicationLaunchFailed(
                bundleIdentifier: applicationBundleIdentifier,
                projectURL: projectURL,
                errorDomain: errorDomain,
                errorCode: errorCode,
                message: message
            )
        case .deadlineExceeded:
            throw ProjectAccessError.deadlineExceeded
        case .cancelled:
            throw CancellationError()
        }
    }
}
