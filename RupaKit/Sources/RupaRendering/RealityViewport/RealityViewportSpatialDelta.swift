import CoreGraphics
import Foundation

/// What a hover-only change asks of a mounted overlay: the items of the complete overlay the
/// mounted one lacks, the mounted items the complete overlay no longer draws, and the handle
/// records every hit resolves against afterwards.
///
/// Items compare by value. An item's handle compares by the identity of the record it indexes,
/// not by the index, which a different set of handles renumbers. Drawing the mounted items that
/// are not suppressed together with the added items draws exactly the complete overlay, so the
/// mounted frame keeps its native resources and only the difference is prepared.
struct RealityViewportSpatialDelta: Sendable {
    /// Mounted item ordinals, per item kind, that the complete overlay no longer draws.
    struct Suppression: Equatable, Sendable {
        var meshes: Set<Int> = []
        var paths: Set<Int> = []
        var labels: Set<Int> = []
        var markers: Set<Int> = []
        var cameraLines: Set<Int> = []
        var cameraPaths: Set<Int> = []

        var count: Int {
            meshes.count + paths.count + labels.count + markers.count + cameraLines.count + cameraPaths.count
        }
    }

    let suppressed: Suppression
    /// The complete overlay's items the mounted overlay lacks, at the mounted render origin; its
    /// handle indexes name `records`. Nil when nothing is added.
    let added: RealityViewportSpatialBatch?
    /// The complete overlay's handle records.
    let records: [ViewportSpatialInteractionRecord]
    /// The complete overlay's handle index for each mounted handle index an unsuppressed item
    /// still carries.
    let retainedHandles: [UInt32: UInt32]

    var isEmpty: Bool { suppressed.count == 0 && added == nil }

    /// The delta from `mounted` to `complete`, or nil when a hover-only change cannot be expressed
    /// against the mounted overlay: another render origin, limits, grid, axes, grid placement or
    /// bounds rulers, which live in the mounted frame's own resources, or a mounted handle that
    /// would answer for two different complete handles.
    static func make(
        mounted: RealityViewportSpatialBatch,
        mountedRecords: [ViewportSpatialInteractionRecord],
        complete: RealityViewportSpatialBatch,
        completeRecords: [ViewportSpatialInteractionRecord]
    ) throws -> Self? {
        guard mounted.renderOrigin == complete.renderOrigin,
              mounted.limits == complete.limits,
              mounted.includesGrid == complete.includesGrid,
              mounted.includesAxes == complete.includesAxes,
              mounted.gridPlacement == complete.gridPlacement,
              mounted.boundsRulers == complete.boundsRulers,
              mounted.handleCount == mountedRecords.count,
              complete.handleCount == completeRecords.count else {
            return nil
        }
        var retainedHandles: [UInt32: UInt32] = [:]
        var consistent = true
        func handle(_ index: UInt32?, in records: [ViewportSpatialInteractionRecord]) -> ViewportSpatialHandleIdentity? {
            index.map { records[Int($0)].identity }
        }
        /// Matches `complete` items against `mounted` ones, returning the unmatched complete
        /// items and the unmatched mounted ordinals.
        func match<Item: Equatable>(
            _ mountedItems: [Item], _ completeItems: [Item],
            handleIndex: (Item) -> UInt32?, removingHandle: (Item) -> Item, hash: (Item, inout Hasher) -> Void
        ) throws -> (added: [Item], suppressed: Set<Int>) {
            typealias Key = RealityViewportSpatialDeltaKey<Item>
            func key(_ item: Item, records: [ViewportSpatialInteractionRecord]) -> Key {
                let bare = removingHandle(item)
                var hasher = Hasher()
                hash(bare, &hasher)
                return Key(item: bare, handle: handle(handleIndex(item), in: records), hashSeed: hasher.finalize())
            }
            var available: [Key: [Int]] = [:]
            available.reserveCapacity(mountedItems.count)
            for (ordinal, item) in mountedItems.enumerated() {
                try Task.checkCancellation()
                available[key(item, records: mountedRecords), default: []].append(ordinal)
            }
            var added: [Item] = []
            var kept = Set<Int>()
            for item in completeItems {
                try Task.checkCancellation()
                let itemKey = key(item, records: completeRecords)
                if var ordinals = available[itemKey], let ordinal = ordinals.first {
                    ordinals.removeFirst()
                    available[itemKey] = ordinals
                    kept.insert(ordinal)
                    if let mountedHandle = handleIndex(mountedItems[ordinal]), let completeHandle = handleIndex(item) {
                        if let existing = retainedHandles[mountedHandle], existing != completeHandle {
                            consistent = false
                        }
                        retainedHandles[mountedHandle] = completeHandle
                    }
                } else {
                    added.append(item)
                }
            }
            return (added, Set(mountedItems.indices).subtracting(kept))
        }
        let meshes = try match(mounted.meshes, complete.meshes, handleIndex: \.handleIndex,
            removingHandle: { var item = $0; item.handleIndex = nil; return item },
            hash: { item, hasher in
                hasher.combine(item.positions.count); hasher.combine(item.indices.count)
                hasher.combine(item.positions.first); hasher.combine(item.positions.last)
                hasher.combine(item.color); hasher.combine(item.depth); hasher.combine(item.attachment)
            })
        let paths = try match(mounted.paths, complete.paths, handleIndex: \.handleIndex,
            removingHandle: { var item = $0; item.handleIndex = nil; return item },
            hash: { item, hasher in
                hasher.combine(item.origin); hasher.combine(item.color); hasher.combine(item.depth)
                let bounds = item.path.boundingRect
                hasher.combine(bounds.minX); hasher.combine(bounds.minY)
                hasher.combine(bounds.width); hasher.combine(bounds.height)
            })
        let labels = try match(mounted.labels, complete.labels, handleIndex: \.handleIndex,
            removingHandle: { var item = $0; item.handleIndex = nil; return item },
            hash: { item, hasher in
                hasher.combine(item.text); hasher.combine(item.anchor); hasher.combine(item.color)
            })
        let markers = try match(mounted.markers, complete.markers, handleIndex: \.handleIndex,
            removingHandle: { var item = $0; item.handleIndex = nil; return item },
            hash: { item, hasher in
                hasher.combine(item.anchor); hasher.combine(item.diameterPoints); hasher.combine(item.color)
            })
        let cameraLines = try match(mounted.cameraLines, complete.cameraLines, handleIndex: \.handleIndex,
            removingHandle: { var item = $0; item.handleIndex = nil; return item },
            hash: { item, hasher in
                hasher.combine(item.points.count); hasher.combine(item.points.first?.anchor)
                hasher.combine(item.points.last?.anchor); hasher.combine(item.color)
            })
        let cameraPaths = try match(mounted.cameraPaths, complete.cameraPaths, handleIndex: \.handleIndex,
            removingHandle: { var item = $0; item.handleIndex = nil; return item },
            hash: { item, hasher in
                hasher.combine(item.anchor); hasher.combine(item.color)
                let bounds = item.path.boundingRect
                hasher.combine(bounds.width); hasher.combine(bounds.height)
            })
        guard consistent else { return nil }
        // A mounted handle whose items are all suppressed answers for nothing.
        let suppressed = Suppression(
            meshes: meshes.suppressed, paths: paths.suppressed, labels: labels.suppressed,
            markers: markers.suppressed, cameraLines: cameraLines.suppressed, cameraPaths: cameraPaths.suppressed
        )
        let hasAdditions = !meshes.added.isEmpty || !paths.added.isEmpty || !labels.added.isEmpty
            || !markers.added.isEmpty || !cameraLines.added.isEmpty || !cameraPaths.added.isEmpty
        let added = hasAdditions ? try RealityViewportSpatialBatch(
            meshes: meshes.added, paths: paths.added, labels: labels.added, markers: markers.added,
            cameraLines: cameraLines.added, cameraPaths: cameraPaths.added,
            handleCount: completeRecords.count,
            retainedSemanticByteCount: complete.retainedSemanticByteCount,
            renderOrigin: complete.renderOrigin,
            retainedSurfaceByteCount: mounted.admittedByteCount,
            limits: complete.limits
        ) : nil
        return Self(suppressed: suppressed, added: added, records: completeRecords, retainedHandles: retainedHandles)
    }
}

/// An overlay item without its handle index, and the identity of the handle it carries. Two keys
/// are equal when the items and handles are; the hash is a cheap summary of the item's fields.
struct RealityViewportSpatialDeltaKey<Item: Equatable>: Hashable {
    let item: Item
    let handle: ViewportSpatialHandleIdentity?
    let hashSeed: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.handle == rhs.handle && lhs.item == rhs.item
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(hashSeed)
    }
}
