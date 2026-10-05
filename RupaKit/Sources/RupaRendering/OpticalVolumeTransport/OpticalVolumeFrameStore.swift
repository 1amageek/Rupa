import Metal
import Synchronization

/// Last complete image and all in-flight allocations share one byte admission.
final class OpticalVolumeFrameStore: Sendable {
    struct Receipt: Sendable {
        let sequence: UInt64
        let previous: (any MTLTexture)?
        let reservedBytes: Int
    }
    struct Preparation: Sendable {
        let remainingBytes: Int
    }
    final class StorageLease: Sendable {
        private let store: OpticalVolumeFrameStore
        private let retainedBytes: Mutex<Int>
        fileprivate init(store: OpticalVolumeFrameStore, bytes: Int) {
            self.store = store; retainedBytes = Mutex(bytes)
        }
        func resize(bytes: Int) throws {
            try retainedBytes.withLock { original in
                try store.resizeStorage(from: original, to: bytes)
                original = bytes
            }
        }
        fileprivate func transfer(into destination: OpticalVolumeFrameStore, externalBytes: Int) throws {
            guard store === destination else { throw OpticalVolumeFrameStore.exhausted() }
            try retainedBytes.withLock { original in
                try store.finishPreparationStorage(externalBytes: externalBytes, releasingBytes: original)
                original = 0
            }
        }
        deinit { store.releaseStorage(bytes: retainedBytes.withLock { $0 }) }
    }
    private struct Image: Sendable {
        let texture: any MTLTexture
        var leases: Int
    }
    private struct State: Sendable {
        var images: [ObjectIdentifier: Image] = [:]
        var current: ObjectIdentifier?
        var completedSequence: UInt64 = 0
        var nextSequence: UInt64 = 0
        var inFlightBytes: Int = 0
        var sceneBytes: Int = 0
        var externalBytes: Int = 0
        var byteLimit: Int = 0
        var preparationDepth: Int = 0
        var storageFailure: MeshSourcePresentationRenderError?
    }
    private let state = Mutex(State())

    var lastCompleteImage: (any MTLTexture)? {
        state.withLock { value in value.current.flatMap { value.images[$0]?.texture } }
    }

    private static func retainedBytes(_ value: State) throws -> Int {
        var total = value.inFlightBytes
        for count in [value.sceneBytes, value.externalBytes] {
            let sum = total.addingReportingOverflow(count)
            guard !sum.overflow else { throw exhausted() }
            total = sum.partialValue
        }
        for image in value.images.values {
            let sum = total.addingReportingOverflow(image.texture.allocatedSize)
            guard !sum.overflow else { throw exhausted() }
            total = sum.partialValue
        }
        return total
    }

    func beginPreparation(byteLimit: Int, externalBytes: Int) throws -> Preparation {
        try state.withLock { value in
            guard byteLimit > 0, externalBytes >= 0, value.preparationDepth < Int.max else { throw Self.exhausted() }
            var candidate = value
            candidate.byteLimit = byteLimit
            candidate.externalBytes = externalBytes
            let total = try Self.retainedBytes(candidate)
            guard total <= byteLimit else { throw Self.exhausted() }
            value.byteLimit = byteLimit; value.externalBytes = externalBytes
            value.preparationDepth += 1
            value.storageFailure = nil
            return .init(remainingBytes: byteLimit - total)
        }
    }

    func remainingPreparationBytes() throws -> Int {
        try state.withLock { value in
            guard value.preparationDepth > 0 else { throw Self.exhausted() }
            let retained = try Self.retainedBytes(value)
            guard retained <= value.byteLimit else { throw Self.exhausted() }
            return value.byteLimit - retained
        }
    }

    func finishPreparation(externalBytes: Int, releasing lease: StorageLease? = nil) throws {
        if let lease { try lease.transfer(into: self, externalBytes: externalBytes) }
        else { try finishPreparationStorage(externalBytes: externalBytes, releasingBytes: 0) }
    }

    private func finishPreparationStorage(externalBytes: Int, releasingBytes: Int) throws {
        try state.withLock { value in
            guard value.preparationDepth > 0, externalBytes >= 0 else { throw Self.exhausted() }
            var candidate = value
            candidate.externalBytes = externalBytes
            guard releasingBytes >= 0, releasingBytes <= value.sceneBytes else { throw Self.exhausted() }
            candidate.sceneBytes -= releasingBytes
            guard try Self.retainedBytes(candidate) <= value.byteLimit else {
                value.storageFailure = Self.exhausted()
                throw Self.exhausted()
            }
            value.externalBytes = externalBytes
            value.sceneBytes = candidate.sceneBytes
            value.preparationDepth -= 1
        }
    }

    func failStoragePublication() {
        state.withLock { $0.storageFailure = Self.exhausted() }
    }

    func abortPreparation() {
        state.withLock { value in if value.preparationDepth > 0 { value.preparationDepth -= 1 } }
    }

    func retainStorage(bytes: Int) throws -> StorageLease {
        try state.withLock { value in
            guard bytes >= 0, value.preparationDepth > 0 else { throw Self.exhausted() }
            let total = try Self.retainedBytes(value)
            guard bytes <= value.byteLimit - total else { throw Self.exhausted() }
            value.sceneBytes += bytes
        }
        return .init(store: self, bytes: bytes)
    }

    private func resizeStorage(from old: Int, to new: Int) throws {
        try state.withLock { value in
            guard old >= 0, new >= 0, old <= value.sceneBytes else { throw Self.exhausted() }
            let retained = try Self.retainedBytes(value)
            if new > old {
                guard value.preparationDepth > 0, new - old <= value.byteLimit - retained else { throw Self.exhausted() }
            }
            value.sceneBytes = value.sceneBytes - old + new
        }
    }

    private func releaseStorage(bytes: Int) {
        state.withLock { value in value.sceneBytes -= bytes }
    }

    func retainedFailure() -> Receipt {
        state.withLock { value in
            let previous = value.current.flatMap { value.images[$0]?.texture }
            if let current = value.current { value.images[current]?.leases += 1 }
            return .init(sequence: 0, previous: previous, reservedBytes: 0)
        }
    }

    func candidate(additionalBytes: Int) throws -> Receipt {
        try state.withLock { value in
            guard value.nextSequence < UInt64.max, additionalBytes > 0 else {
                throw MeshSourcePresentationRenderError(code: .resourceExhausted, message: "Optical frame sequence or storage exhausted.")
            }
            if let failure = value.storageFailure { throw failure }
            guard value.preparationDepth == 0 else {
                throw MeshSourcePresentationRenderError(code: .frameNotReady,
                    message: "Optical frame waits for complete source storage publication.")
            }
            let total = try Self.retainedBytes(value)
            let (required, overflow) = total.addingReportingOverflow(additionalBytes)
            guard !overflow, required <= value.byteLimit else { throw Self.exhausted() }
            value.nextSequence += 1
            value.inFlightBytes += additionalBytes
            let previous = value.current.flatMap { value.images[$0]?.texture }
            if let current = value.current { value.images[current]?.leases += 1 }
            return Receipt(sequence: value.nextSequence, previous: previous, reservedBytes: additionalBytes)
        }
    }

    func finish(_ receipt: Receipt, completed image: (any MTLTexture)?) {
        state.withLock { value in
            value.inFlightBytes -= receipt.reservedBytes
            if let image, receipt.sequence > value.completedSequence {
                let key = ObjectIdentifier(image)
                value.images[key] = Image(texture: image, leases: 0)
                value.current = key
                value.completedSequence = receipt.sequence
            }
            if let previous = receipt.previous {
                let key = ObjectIdentifier(previous)
                value.images[key]?.leases -= 1
            }
            let retired = value.images.filter { $0.key != value.current && $0.value.leases == 0 }.map(\.key)
            for key in retired { value.images.removeValue(forKey: key) }
        }
    }

    private static func exhausted() -> MeshSourcePresentationRenderError {
        .init(code: .resourceExhausted, message: "Optical retained and in-flight images exceed their shared byte allowance.")
    }
}
