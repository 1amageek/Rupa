import RupaCore
import RupaRendering
import Testing
@testable import RupaUI

@Suite struct WorkspaceViewportPointerOwnerTests {
    private static let pickingCommands: [WorkspaceViewportPickingCommand] = [
        .viewAlignedConstructionPlane, .curvePick, .cutCurve, .boolean, .bodyCut, .deform,
        .freestyleOffset, .constrainedSurfacePoints,
    ]

    @Test func objectScopeEditsObjectsAndTheirEdgesButNotFaces() {
        let owner = WorkspaceViewportPointerOwner.directEditing(.object)
        #expect(owner.hitPolicy == .object)
        for affordance in [WorkspaceViewportAffordance.objectSelection, .objectPlacement, .objectHandles,
                           .edgeTreatment, .boundarySurface, .featureParameters, .constructionPlane] {
            #expect(owner.allows(affordance), "\(affordance)")
        }
        for affordance in [WorkspaceViewportAffordance.faceOffset, .bodyVertexEditing, .regionOffset,
                           .edgeOffset, .slotWidth, .sketchEntityEditing] {
            #expect(!owner.allows(affordance), "\(affordance)")
        }
    }

    @Test func eachSubshapeScopeEditsOnlyItsOwnSubshapes() {
        let face = WorkspaceViewportPointerOwner.directEditing(.face)
        #expect(face.allows(.faceOffset))
        #expect(!face.allows(.objectSelection) && !face.allows(.objectPlacement) && !face.allows(.edgeTreatment))

        let edge = WorkspaceViewportPointerOwner.directEditing(.edge)
        #expect(edge.allows(.edgeTreatment) && edge.allows(.boundarySurface) && edge.allows(.edgeOffset))
        #expect(!edge.allows(.faceOffset) && !edge.allows(.objectPlacement))

        let vertex = WorkspaceViewportPointerOwner.directEditing(.vertex)
        #expect(vertex.allows(.bodyVertexEditing))
        #expect(!vertex.allows(.faceOffset) && !vertex.allows(.edgeTreatment))

        #expect(WorkspaceViewportPointerOwner.directEditing(.region).allows(.regionOffset))
        let sketch = WorkspaceViewportPointerOwner.directEditing(.sketchEntity)
        #expect(sketch.allows(.sketchEntityEditing) && sketch.allows(.slotWidth))
        #expect(!sketch.allows(.bodyVertexEditing))
    }

    @Test func everyAffordanceEditsInSomeScope() {
        for affordance in WorkspaceViewportAffordance.allCases {
            #expect(!affordance.scopes.isEmpty, "\(affordance)")
            #expect(WorkspaceSelectionScope.allCases.contains {
                WorkspaceViewportPointerOwner.directEditing($0).allows(affordance)
            }, "\(affordance)")
        }
    }

    /// While a command takes the clicks, a press on a selected body reaches the command: no
    /// selection affordance stays live in any scope, and the command's hit policy decides the hit.
    @Test func aPickingCommandStandsDownEverySelectionAffordance() {
        for command in Self.pickingCommands {
            for scope in WorkspaceSelectionScope.allCases {
                let owner = WorkspaceViewportPointerOwner.pickingCommand(
                    command, hitPolicy: .face, scope: scope, transforming: false
                )
                #expect(owner.pickingCommand == command)
                #expect(owner.hitPolicy == .face)
                for affordance in WorkspaceViewportAffordance.allCases
                where affordance.owningPickingCommand != command {
                    #expect(!owner.allows(affordance), "\(command) \(scope) \(affordance)")
                }
            }
        }
    }

    @Test func freestyleOffsetKeepsItsOwnDistanceHandleOnTheSelectedCurve() {
        let onCurve = WorkspaceViewportPointerOwner.pickingCommand(
            .freestyleOffset, hitPolicy: .sketchEntity, scope: .sketchEntity, transforming: false
        )
        #expect(onCurve.allows(.slotWidth))
        #expect(!onCurve.allows(.sketchEntityEditing))
        let inObjectScope = WorkspaceViewportPointerOwner.pickingCommand(
            .freestyleOffset, hitPolicy: .object, scope: .object, transforming: false
        )
        #expect(!inObjectScope.allows(.slotWidth))
        let deform = WorkspaceViewportPointerOwner.pickingCommand(
            .deform, hitPolicy: .face, scope: .sketchEntity, transforming: false
        )
        #expect(!deform.allows(.slotWidth))
    }

    @Test func aCreationToolEditsNothingAndHitsInTheScope() {
        for tool in ModelingTool.allCases where tool != .select {
            let owner = WorkspaceViewportPointerOwner.tool(tool, scope: .edge)
            #expect(owner.pickingCommand == nil)
            #expect(owner.hitPolicy == .edge)
            for affordance in WorkspaceViewportAffordance.allCases {
                #expect(!owner.allows(affordance), "\(tool) \(affordance)")
            }
        }
    }

    /// Boolean's G, R and S move its tools while its dialog keeps the clicks: the running move
    /// owns the gizmo, so the drag commits, while the resize handles and selection stay down.
    @Test func aMoveInsideBooleanKeepsItsGizmo() {
        let owner = WorkspaceViewportPointerOwner.pickingCommand(
            .boolean, hitPolicy: .object, scope: .object, transforming: true
        )
        #expect(owner.pickingCommand == .boolean)
        #expect(owner.allows(.objectPlacement))
        for affordance in WorkspaceViewportAffordance.allCases where affordance != .objectPlacement {
            #expect(!owner.allows(affordance), "\(affordance)")
        }
        let inFaceScope = WorkspaceViewportPointerOwner.pickingCommand(
            .boolean, hitPolicy: .face, scope: .face, transforming: true
        )
        #expect(!inFaceScope.allows(.objectPlacement))
    }
}
