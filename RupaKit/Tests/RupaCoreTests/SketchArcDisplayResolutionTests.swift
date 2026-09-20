import Foundation
import Testing
@testable import RupaCore

/// The resolution a sketch object's own declaration draws its curves at.
///
/// `RupaCore/DESIGN.md` owns the contract these check.

private func sketchObject(
    typeID: ObjectTypeID,
    properties: ObjectPropertySet = ObjectPropertySet()
) -> ObjectDescriptor {
    ObjectDescriptor(
        category: .sketch,
        geometryRole: .curve,
        typeID: typeID,
        properties: properties
    )
}

@Test func aCircleIsDrawnAtTheFullTurnCountItsSchemaDeclares() {
    let resolution = SketchArcDisplayResolution(
        object: sketchObject(typeID: .circle),
        objectRegistry: .builtIn
    )

    // The schema's own default, reproduced rather than rounded to a frame constant.
    #expect(resolution.fullTurnSegmentCount == 64)
}

@Test func aStoredCircleCountReplacesTheSchemaDefault() {
    let resolution = SketchArcDisplayResolution(
        object: sketchObject(
            typeID: .circle,
            properties: ObjectPropertySet(values: ["sides.x": .integer(16)])
        ),
        objectRegistry: .builtIn
    )

    #expect(resolution.fullTurnSegmentCount == 16)
}

@Test func anExtrusionBevelCountNeverDrawsASketchCurve() {
    // Finer than the circle's own count, so counting it would be visible.
    let resolution = SketchArcDisplayResolution(
        object: sketchObject(
            typeID: .circle,
            properties: ObjectPropertySet(values: ["bevel.sides": .integer(256)])
        ),
        objectRegistry: .builtIn
    )

    #expect(resolution.fullTurnSegmentCount == 64)
}

@Test func aFullTurnCountGovernsTheHalfTurnArcsASlotDraws() {
    let resolution = SketchArcDisplayResolution(
        object: sketchObject(typeID: .slot),
        objectRegistry: .builtIn
    )

    // The slot declares thirty-two around a full turn; each cap arc turns through half of it.
    #expect(resolution.arcSegmentCount(spanning: .pi) == 16)
    #expect(resolution.fullTurnSegmentCount == 32)
}

@Test func aCornerCountDeclaresTheResolutionItsQuadrantNames() {
    let resolution = SketchArcDisplayResolution(
        object: sketchObject(
            typeID: .rectangle,
            properties: ObjectPropertySet(values: ["corner.sides": .integer(8)])
        ),
        objectRegistry: .builtIn
    )

    // Eight segments across a quadrant is thirty-two around a full turn.
    #expect(resolution.arcSegmentCount(spanning: .pi / 2.0) == 8)
    #expect(resolution.fullTurnSegmentCount == 32)
}

@Test func aSketchWhoseObjectDeclaresNoCountIsDrawnAtTheFramesOwnResolution() {
    let resolution = SketchArcDisplayResolution(object: nil, objectRegistry: .builtIn)

    #expect(resolution == .undeclared)
    #expect(resolution.fullTurnSegmentCount == SketchArcDisplayResolution.undeclaredFullTurnSegmentCount)
    #expect(resolution.arcSegmentCount(spanning: .pi / 2.0) == SketchArcDisplayResolution.undeclaredArcSegmentCount)
}

@Test func anArcDeclarationIsAbsentRatherThanBorrowedFromAnotherType() {
    let resolution = SketchArcDisplayResolution(
        object: sketchObject(typeID: .arc),
        objectRegistry: .builtIn
    )

    #expect(resolution == .undeclared)
}

@Test func turningPastAFullCircleEarnsNoMoreSegmentsThanTheCircleItself() {
    let resolution = SketchArcDisplayResolution(
        object: sketchObject(
            typeID: .circle,
            properties: ObjectPropertySet(values: ["sides.x": .integer(16)])
        ),
        objectRegistry: .builtIn
    )

    #expect(resolution.arcSegmentCount(spanning: 4.0 * .pi) == 16)
    #expect(resolution.arcSegmentCount(spanning: -(.pi)) == 8)
}

@Test func aDrawnArcIsNeverReducedBelowTheSegmentsItNeedsToCurve() {
    let resolution = SketchArcDisplayResolution(
        object: sketchObject(
            typeID: .circle,
            properties: ObjectPropertySet(values: ["sides.x": .integer(8)])
        ),
        objectRegistry: .builtIn
    )

    // A quadrant earns two at this resolution, and a sliver may not fall below that.
    #expect(resolution.arcSegmentCount(spanning: 0.001) == 2)
    #expect(resolution.fullTurnSegmentCount == 8)
}
