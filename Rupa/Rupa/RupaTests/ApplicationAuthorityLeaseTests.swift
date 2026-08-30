import Foundation
import Testing
@testable import Rupa

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationAuthorityLeaseRejectsASecondOwnerAndReleasesOnDeinit() throws {
    let directory = try makeApplicationAuthorityTestDirectory()
    defer { removeApplicationAuthorityTestDirectory(directory) }

    var first: ApplicationAuthorityLease? = try ApplicationAuthorityLease.acquire(
        in: directory
    )
    let expectedLockURL = directory.standardizedFileURL.appendingPathComponent(
        ApplicationAuthorityLease.lockFileName
    )

    #expect(throws: ApplicationAuthorityLeaseError.alreadyRunning(expectedLockURL)) {
        try ApplicationAuthorityLease.acquire(in: directory)
    }

    first = nil
    let reacquired = try ApplicationAuthorityLease.acquire(in: directory)
    #expect(reacquired.lockFileURL == expectedLockURL)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationAuthorityLeaseUsesOwnerOnlyPermissions() throws {
    let directory = try makeApplicationAuthorityTestDirectory()
    defer { removeApplicationAuthorityTestDirectory(directory) }

    let lease = try ApplicationAuthorityLease.acquire(in: directory)
    let directoryAttributes = try FileManager.default.attributesOfItem(
        atPath: directory.path
    )
    let lockAttributes = try FileManager.default.attributesOfItem(
        atPath: lease.lockFileURL.path
    )

    #expect(posixPermissions(in: directoryAttributes) == 0o700)
    #expect(posixPermissions(in: lockAttributes) == 0o600)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func duplicateApplicationAuthorityPublishesTypedUnavailableStateWithoutWorkspace() {
    let lockURL = URL(fileURLWithPath: "/tmp/rupa-application.lock")
    let coordinator = ApplicationProjectCoordinator(
        launchFailure: ApplicationAuthorityLeaseError.alreadyRunning(lockURL),
        agentRegistrar: ApplicationUnavailableAgentSessionRegistrar()
    )

    guard case .unavailable(let failure) = coordinator.lifecycle else {
        Issue.record("Expected an unavailable application authority state.")
        return
    }
    #expect(failure.kind == .applicationAuthority)
    #expect(coordinator.workspace == nil)
}

private func makeApplicationAuthorityTestDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "rupa-application-authority-tests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    return directory
}

private func removeApplicationAuthorityTestDirectory(_ directory: URL) {
    do {
        try FileManager.default.removeItem(at: directory)
    } catch {
        Issue.record("Failed to remove authority test directory: \(error)")
    }
}

private func posixPermissions(
    in attributes: [FileAttributeKey: Any]
) -> Int? {
    (attributes[.posixPermissions] as? NSNumber)?.intValue
}
