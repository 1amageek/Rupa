import Testing

@Suite
struct CLIProcessGateTests {
    @Test(.timeLimit(.minutes(1)))
    func cancelledWaiterDoesNotConsumeReleasedSlot() async throws {
        let gate = CLIProcessGate(limit: 1)
        try await gate.acquire()
        let waiter = Task {
            try await gate.acquire()
        }
        try await waitForGateState("waiter to queue") {
            await gate.snapshotForTesting().waiterCount == 1
        }

        waiter.cancel()
        do {
            try await waiter.value
            Issue.record("Cancelled CLI process waiter must throw CancellationError.")
        } catch is CancellationError {
        }

        let cancelledSnapshot = await gate.snapshotForTesting()
        #expect(cancelledSnapshot.availableSlotCount == 0)
        #expect(cancelledSnapshot.waiterCount == 0)

        await gate.release()
        let releasedSnapshot = await gate.snapshotForTesting()
        #expect(releasedSnapshot == CLIProcessGateSnapshot(
            availableSlotCount: 1,
            waiterCount: 0,
            cancelledWaiterCount: 0
        ))
    }

    private func waitForGateState(
        _ description: String,
        condition: () async -> Bool
    ) async throws {
        for _ in 0..<200 {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        Issue.record("Timed out waiting for CLIProcessGate \(description).")
    }
}
