/// Callback composition for the original viewport-owned shared byte ledger.
@MainActor
struct RealityViewportSpatialStorageAdmission {
    let images: OpticalVolumeFrameStore
    let begin: @MainActor () throws -> Void
    let finish: @MainActor (OpticalVolumeFrameStore.StorageLease?) throws -> Void
    let abort: @MainActor () -> Void
}
