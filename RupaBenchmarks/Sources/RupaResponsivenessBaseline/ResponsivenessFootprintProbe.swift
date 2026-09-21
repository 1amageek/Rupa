import Darwin
import Foundation
import Synchronization

/// Reads `phys_footprint` for the current process.
///
/// The value is a proxy for resident memory. A failed read is a typed failure so
/// a missing sample is never reported as zero bytes.
public enum ResponsivenessFootprintProbe {
    public static func physicalFootprintBytes() throws -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard status == KERN_SUCCESS else {
            throw ResponsivenessBaselineError(
                code: .footprintSampleUnavailable,
                message: "task_info(TASK_VM_INFO) failed with status \(status)."
            )
        }
        return UInt64(info.phys_footprint)
    }
}

/// Samples `phys_footprint` from a background task while the MainActor performs
/// one synchronous preparation, so the peak of an uninterruptible interval is
/// observable from inside the process.
public final class ResponsivenessFootprintPeakSampler: Sendable {
    private struct State {
        var peakBytes: UInt64 = 0
        var sampleCount: Int = 0
        var failureMessage: String?
    }

    private let state = Mutex(State())
    private let intervalSeconds: Double
    private let task: Mutex<Task<Void, Never>?> = Mutex(nil)

    public init(intervalSeconds: Double) {
        self.intervalSeconds = intervalSeconds
    }

    public func start() {
        let interval = intervalSeconds
        let sampler = self
        let started = Task.detached(priority: .userInitiated) {
            while Task.isCancelled == false {
                sampler.sample()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    break
                }
            }
            sampler.sample()
        }
        task.withLock { $0 = started }
    }

    public func stop() async {
        let running = task.withLock { value -> Task<Void, Never>? in
            let running = value
            value = nil
            return running
        }
        guard let running else {
            return
        }
        running.cancel()
        await running.value
    }

    /// Throws when any sample failed, so an incomplete series is never reported
    /// as a measurement.
    public func peakBytes() throws -> (bytes: UInt64, sampleCount: Int) {
        try state.withLock { state in
            if let failureMessage = state.failureMessage {
                throw ResponsivenessBaselineError(
                    code: .footprintSampleUnavailable,
                    message: failureMessage
                )
            }
            guard state.sampleCount > 0 else {
                throw ResponsivenessBaselineError(
                    code: .footprintSampleUnavailable,
                    message: "The footprint sampler completed no samples."
                )
            }
            return (state.peakBytes, state.sampleCount)
        }
    }

    private func sample() {
        do {
            let bytes = try ResponsivenessFootprintProbe.physicalFootprintBytes()
            state.withLock { state in
                state.peakBytes = max(state.peakBytes, bytes)
                state.sampleCount += 1
            }
        } catch {
            state.withLock { state in
                if state.failureMessage == nil {
                    state.failureMessage = String(describing: error)
                }
            }
        }
    }
}
