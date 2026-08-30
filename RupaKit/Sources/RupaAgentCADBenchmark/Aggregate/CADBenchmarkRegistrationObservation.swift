import Foundation

enum CADBenchmarkRegistrationObservation {
    @TaskLocal static var ledger: CADBenchmarkRegistrationLedger?
}

actor CADBenchmarkRegistrationLedger {
    private var activeSessionIDs = Set<UUID>()

    func registered(_ sessionID: UUID) {
        activeSessionIDs.insert(sessionID)
    }

    func unregistered(_ sessionID: UUID) {
        activeSessionIDs.remove(sessionID)
    }

    func activeRegistrationCount() -> Int {
        activeSessionIDs.count
    }
}
