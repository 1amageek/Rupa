/// Owns one shared reservation until mounted transfer or abandoned-candidate release.
@MainActor
final class RealityViewportSpatialPreparation {
    private let admission: RealityViewportSpatialStorageAdmission
    private var lease: OpticalVolumeFrameStore.StorageLease?
    private var ownsPreparation = true

    init(admission: RealityViewportSpatialStorageAdmission, maximumBytes: Int) throws {
        self.admission = admission
        admittedBytes = try Self.begin(admission, maximumBytes: maximumBytes)
        do {
            lease = try admission.images.retainStorage(bytes: admittedBytes)
        } catch {
            admission.abort()
            ownsPreparation = false
            throw error
        }
    }

    private static func begin(_ admission: RealityViewportSpatialStorageAdmission, maximumBytes: Int) throws -> Int {
        try admission.begin()
        do {
            let available = min(maximumBytes, try admission.images.remainingPreparationBytes())
            guard available > 0 else { throw RealityViewportSpatialBatch.exhausted() }
            return available
        } catch {
            admission.abort()
            throw error
        }
    }

    let admittedBytes: Int

    func refine(bytes: Int) throws {
        guard ownsPreparation, bytes >= 0, bytes <= admittedBytes, let lease else {
            throw RealityViewportSpatialBatch.exhausted()
        }
        try lease.resize(bytes: bytes)
    }

    /// The caller must finish or abort the same preparation after this transfer.
    func takeLease() -> OpticalVolumeFrameStore.StorageLease? {
        guard ownsPreparation else { return nil }
        ownsPreparation = false
        let result = lease
        lease = nil
        return result
    }

    isolated deinit {
        if ownsPreparation { admission.abort() }
    }
}
