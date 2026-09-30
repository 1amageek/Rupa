/// A hover delta prepared over one mounted frame's overlay: the prepared items it withholds, the
/// native resources of the items it adds, and the complete overlay's handle index for each handle
/// a retained item carries.
///
/// `RealityViewport.prepareSpatialDelta(_:)` makes it off-scene; `applySpatialDelta(_:)` draws it
/// only over the overlay it was prepared over (`base`).
struct RealityViewportSpatialDeltaLayer: Sendable {
    let base: RealityViewportSpatialResources
    let suppressed: RealityViewportSpatialDelta.Suppression
    /// Nil when the delta adds nothing. Its handle indexes name the complete overlay's records.
    let added: RealityViewportSpatialResources?
    /// Mounted handle index to complete handle index, for every handle a retained item carries.
    let retainedHandles: [UInt32: UInt32]
    /// The complete overlay's handle count.
    let handleCount: Int
}
