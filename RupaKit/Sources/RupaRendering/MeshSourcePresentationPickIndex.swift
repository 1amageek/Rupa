import RupaCore
import RupaCoreTypes
import RupaViewportScene

public struct MeshSourcePresentationPickIndex: Sendable {
    public let snapshotID: EvaluationSnapshotID
    public let records: [MeshSourcePresentationPickRecord]
    private let recordsByIdentity: [MeshSourcePresentationPickIdentity: MeshSourcePresentationPickRecord]
    private let identitiesByOccurrence: [SceneOccurrenceID: MeshSourcePresentationPickIdentity]

    public init(
        scene: UniversalViewportScene,
        navigation: MeshSourcePresentationNavigationMap
    ) throws {
        var occurrenceIDs = Set<SceneOccurrenceID>()
        var records: [MeshSourcePresentationPickRecord] = []
        var recordsByIdentity: [MeshSourcePresentationPickIdentity: MeshSourcePresentationPickRecord] = [:]
        var identitiesByOccurrence: [SceneOccurrenceID: MeshSourcePresentationPickIdentity] = [:]
        occurrenceIDs.reserveCapacity(scene.items.count)
        records.reserveCapacity(scene.items.count)
        recordsByIdentity.reserveCapacity(scene.items.count)
        identitiesByOccurrence.reserveCapacity(scene.items.count)

        for (ordinal, item) in scene.items.enumerated() {
            guard occurrenceIDs.insert(item.occurrenceID).inserted else {
                throw MeshSourcePresentationPickError(
                    code: .duplicateOccurrence,
                    message: "Presentation scene occurrence identities must be unique."
                )
            }
            guard let sceneNodeID = navigation.sceneNodeID(for: item.occurrenceID) else {
                throw MeshSourcePresentationPickError(
                    code: .missingNavigation,
                    message: "Presentation occurrence \(item.occurrenceID.rawValue) has no scene-node navigation mapping."
                )
            }
            let identity = try MeshSourcePresentationPickIdentity(ordinal: ordinal)
            let record = MeshSourcePresentationPickRecord(
                identity: identity,
                snapshotID: scene.snapshotID,
                occurrenceID: item.occurrenceID,
                sceneNodeID: sceneNodeID
            )
            records.append(record)
            recordsByIdentity[identity] = record
            identitiesByOccurrence[item.occurrenceID] = identity
        }

        guard navigation.count == scene.items.count,
              navigation.occurrenceIDs.allSatisfy({ occurrenceIDs.contains($0) }) else {
            throw MeshSourcePresentationPickError(
                code: .staleNavigation,
                message: "Presentation navigation mappings do not match the scene occurrence snapshot."
            )
        }

        self.snapshotID = scene.snapshotID
        self.records = records
        self.recordsByIdentity = recordsByIdentity
        self.identitiesByOccurrence = identitiesByOccurrence
    }

    public var count: Int {
        records.count
    }

    public func identity(
        for occurrenceID: SceneOccurrenceID
    ) throws -> MeshSourcePresentationPickIdentity {
        guard let identity = identitiesByOccurrence[occurrenceID] else {
            throw MeshSourcePresentationPickError(
                code: .unknownIdentity,
                message: "Presentation occurrence \(occurrenceID.rawValue) has no pick identity."
            )
        }
        return identity
    }

    public func record(
        for identity: MeshSourcePresentationPickIdentity,
        expectedSnapshotID: EvaluationSnapshotID
    ) throws -> MeshSourcePresentationPickRecord {
        guard expectedSnapshotID == snapshotID else {
            throw MeshSourcePresentationPickError(
                code: .staleSnapshot,
                message: "Presentation pick identity belongs to a different scene snapshot."
            )
        }
        guard let record = recordsByIdentity[identity] else {
            throw MeshSourcePresentationPickError(
                code: .unknownIdentity,
                message: "Presentation pick identity is not present in this scene snapshot."
            )
        }
        return record
    }
}
