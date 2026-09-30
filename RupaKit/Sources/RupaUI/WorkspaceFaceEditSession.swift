import RupaCore
import SwiftCAD

/// The dialog of a local face operation while it runs, on the faces selected when it started:
/// Push Face (the faces pushed a Distance along their outward side, with an Angle Adjacent tilting
/// the planar faces beside them), Draft Face (the faces turned by Degrees about their crossing
/// with the last-selected face's plane, moved by an Offset), and Match Face (the faces put onto the
/// last-selected face's surface, facing its Front when chosen), and Remove Fillets From Shell (the
/// selected solid's fillets within a Max Radius and a Convexity). Tab steps the Grow mode, or
/// Remove Fillets' Convexity; OK, Return or right-click applies; Escape ends it without a change.
struct WorkspaceFaceEditSession: Equatable {
    /// This dialog, apart from the one the command starts next (`WorkspaceDialogSubmissions`).
    let instance = WorkspaceDialogInstance()

    enum Kind: Equatable {
        case push(faces: [SelectionTarget])
        case draft(faces: [SelectionTarget], neutral: SelectionTarget)
        case match(faces: [SelectionTarget], reference: SelectionTarget)
        case removeFillets(object: SceneNodeID)
        case hollow(targets: [SelectionTarget])
        case thicken(targets: [SelectionTarget])
    }

    let kind: Kind
    /// Push Face's distance, in meters.
    var distanceMeters = 0.001
    /// Push Face's adjacent angle in degrees; zero leaves the faces beside unturned.
    var adjacentAngleDegrees = 0.0
    var draftAngleDegrees = 3.0
    /// Draft Face's neutral plane offset along the neutral face's outward side, in meters.
    var neutralOffsetMeters = 0.0
    var front = false
    var grow: FaceEditGrow = .moving
    /// Remove Fillets' largest radius, in meters; zero takes fillets of any radius.
    var maximumRadiusMeters = 0.0
    var convexity: FilletConvexity = .any
    /// Hollow's wall thickness, in meters.
    var wallThicknessMeters = 0.001
    /// Thicken's thicknesses along the sheet's normal and against it, in meters; locked, the back
    /// follows the front.
    var frontMeters = 0.001
    var backMeters = 0.0
    var locksThicknesses = false

    init(kind: Kind) {
        self.kind = kind
    }

    var title: String {
        switch kind {
        case .push: "Push Face"
        case .draft: "Draft Face"
        case .match: "Match Face"
        case .removeFillets: "Remove Fillets"
        case .hollow: "Hollow"
        case .thicken: "Thicken"
        }
    }

    /// Whether the operation has a Grow mode: Push Face, Draft Face and Match Face do.
    var hasGrow: Bool {
        switch kind {
        case .push, .draft, .match: true
        case .removeFillets, .hollow, .thicken: false
        }
    }

    /// Tab's step through the Grow modes, or Remove Fillets' convexities.
    mutating func stepGrow() {
        if case .removeFillets = kind {
            let all = FilletConvexity.allCases
            convexity = all[((all.firstIndex(of: convexity) ?? 0) + 1) % all.count]
            return
        }
        guard hasGrow else { return }
        let all = FaceEditGrow.allCases
        grow = all[((all.firstIndex(of: grow) ?? 0) + 1) % all.count]
    }

    /// The command OK submits.
    func command() -> EditorCommand {
        switch kind {
        case let .push(faces):
            return .pushFaces(
                targets: faces, distance: .length(distanceMeters, .meter),
                adjacentAngle: adjacentAngleDegrees == 0 ? nil : .angle(adjacentAngleDegrees, .degree), grow: grow
            )
        case let .draft(faces, neutral):
            return .draftBodyFaces(
                targets: faces, neutralTarget: neutral, angle: .angle(draftAngleDegrees, .degree),
                neutralOffset: neutralOffsetMeters == 0 ? nil : .length(neutralOffsetMeters, .meter), grow: grow
            )
        case let .match(faces, reference):
            return .matchFaces(targets: faces, reference: reference, front: front, grow: grow)
        case let .hollow(targets):
            return .hollow(targets: targets, thickness: .length(wallThicknessMeters, .meter))
        case let .thicken(targets):
            return .thicken(
                targets: targets, front: .length(frontMeters, .meter),
                back: .length(locksThicknesses ? frontMeters : backMeters, .meter)
            )
        case let .removeFillets(object):
            return .removeFillets(
                target: object, maximumRadius: maximumRadiusMeters > 0 ? .length(maximumRadiusMeters, .meter) : nil, convexity: convexity
            )
        }
    }
}
