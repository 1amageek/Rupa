import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func sketchPlaneCanvasMapperKeepsStandardPlaneContracts() throws {
    let point = Point2D(x: 1.0, y: 2.0)
    let direction = Point2D(x: 3.0, y: 4.0)

    for plane in [SketchPlane.xy, .yz, .plane(Plane3D(origin: .origin, normal: .unitZ))] {
        let mapper = SketchPlaneCanvasMapper(sketchPlane: plane)
        let normalizedDirection = try #require(mapper.normalizedCanvasDirection(fromLocal: direction))

        #expect(mapper.localPoint(fromCanvas: point) == point)
        #expect(mapper.canvasPoint(fromLocal: point) == point)
        #expect(abs(normalizedDirection.x - 0.6) < 1.0e-12)
        #expect(abs(normalizedDirection.y - 0.8) < 1.0e-12)
    }
}

@Test func sketchPlaneCanvasMapperSwapsZXCanvasAndLocalCoordinates() throws {
    let mapper = SketchPlaneCanvasMapper(sketchPlane: .zx)
    let normalizedDirection = try #require(
        mapper.normalizedCanvasDirection(fromLocal: Point2D(x: 3.0, y: 4.0))
    )

    #expect(mapper.localPoint(fromCanvas: Point2D(x: 1.0, y: 2.0)) == Point2D(x: 2.0, y: 1.0))
    #expect(mapper.canvasPoint(fromLocal: Point2D(x: 3.0, y: 4.0)) == Point2D(x: 4.0, y: 3.0))
    #expect(abs(normalizedDirection.x - 0.8) < 1.0e-12)
    #expect(abs(normalizedDirection.y - 0.6) < 1.0e-12)
    #expect(mapper.normalizedCanvasDirection(fromLocal: Point2D(x: 0.0, y: 0.0)) == nil)
}

@Test func sketchAxisConstraintConstrainsXYPlaneCanvasPoints() {
    let reference = Point2D(x: 1.0, y: 2.0)
    let point = Point2D(x: 4.0, y: 7.0)

    #expect(SketchAxisConstraint.x.constrainedCanvasPoint(point, from: reference, on: .xy) == Point2D(x: 4.0, y: 2.0))
    #expect(SketchAxisConstraint.y.constrainedCanvasPoint(point, from: reference, on: .xy) == Point2D(x: 1.0, y: 7.0))
    #expect(SketchAxisConstraint.z.constrainedCanvasPoint(point, from: reference, on: .xy) == point)
}

@Test func sketchAxisConstraintConstrainsYZPlaneCanvasPoints() {
    let reference = Point2D(x: 1.0, y: 2.0)
    let point = Point2D(x: 4.0, y: 7.0)

    #expect(SketchAxisConstraint.x.constrainedCanvasPoint(point, from: reference, on: .yz) == point)
    #expect(SketchAxisConstraint.y.constrainedCanvasPoint(point, from: reference, on: .yz) == Point2D(x: 4.0, y: 2.0))
    #expect(SketchAxisConstraint.z.constrainedCanvasPoint(point, from: reference, on: .yz) == Point2D(x: 1.0, y: 7.0))
}

@Test func sketchAxisConstraintConstrainsZXPlaneCanvasPoints() {
    let reference = Point2D(x: 1.0, y: 2.0)
    let point = Point2D(x: 4.0, y: 7.0)

    #expect(SketchAxisConstraint.x.constrainedCanvasPoint(point, from: reference, on: .zx) == Point2D(x: 4.0, y: 2.0))
    #expect(SketchAxisConstraint.y.constrainedCanvasPoint(point, from: reference, on: .zx) == point)
    #expect(SketchAxisConstraint.z.constrainedCanvasPoint(point, from: reference, on: .zx) == Point2D(x: 1.0, y: 7.0))
}

@Test func sketchInputStateDeduplicatesAndLimitsReferenceLineAnchors() {
    var state = SketchInputState()

    state.addReferenceLineAnchor(
        SketchReferenceLineAnchor(point: Point2D(x: 1.0, y: 2.0))
    )
    state.addReferenceLineAnchor(
        SketchReferenceLineAnchor(point: Point2D(x: 1.0 + 1.0e-12, y: 2.0))
    )

    #expect(state.referenceLineAnchors.count == 1)

    for index in 0 ..< 10 {
        state.addReferenceLineAnchor(
            SketchReferenceLineAnchor(
                point: Point2D(x: Double(index), y: Double(index))
            )
        )
    }

    #expect(state.referenceLineAnchors.count == SketchInputState.maximumReferenceLineAnchorCount)
    #expect(state.referenceLineAnchors.first?.point == Point2D(x: 2.0, y: 2.0))
    #expect(state.referenceLineAnchors.last?.point == Point2D(x: 9.0, y: 9.0))
}

@Test func sketchInputStateCyclesDimensionInputFocus() {
    var state = SketchInputState()

    #expect(state.dimensionInputFocus == nil)
    #expect(state.focusNextDimensionInput() == .length)
    #expect(state.focusNextDimensionInput() == .angle)
    #expect(state.focusNextDimensionInput() == .width)
    #expect(state.focusNextDimensionInput() == .height)
    #expect(state.focusNextDimensionInput() == .length)

    state.clearDimensionInputFocus()

    #expect(state.dimensionInputFocus == nil)
}

@Test func sketchInputStateValidatesDimensionInputValues() throws {
    var state = SketchInputState()

    try state.setDimensionInputLengthMeters(0.012)
    #expect(state.dimensionInputFocus == .length)
    #expect(state.dimensionInputLengthMeters == 0.012)

    try state.setDimensionInputAngleRadians(Double.pi / 4.0)
    #expect(state.dimensionInputFocus == .angle)
    #expect(state.dimensionInputAngleRadians == Double.pi / 4.0)

    try state.setDimensionInputWidthMeters(0.032)
    #expect(state.dimensionInputFocus == .width)
    #expect(state.dimensionInputWidthMeters == 0.032)

    try state.setDimensionInputHeightMeters(0.014)
    #expect(state.dimensionInputFocus == .height)
    #expect(state.dimensionInputHeightMeters == 0.014)

    #expect(throws: SketchDimensionInputValueError.nonPositiveLength) {
        try state.setDimensionInputLengthMeters(0.0)
    }
    #expect(throws: SketchDimensionInputValueError.nonFiniteAngle) {
        try state.setDimensionInputAngleRadians(.infinity)
    }
    #expect(throws: SketchDimensionInputValueError.nonPositiveWidth) {
        try state.setDimensionInputWidthMeters(0.0)
    }
    #expect(throws: SketchDimensionInputValueError.nonFiniteHeight) {
        try state.setDimensionInputHeightMeters(.nan)
    }
}

@Test func sketchInputStateClearsDimensionInputFocusWithTransientInput() {
    var state = SketchInputState(
        axisConstraint: .x,
        dimensionInputFocus: .angle,
        dimensionInputLengthMeters: 0.012,
        dimensionInputAngleRadians: Double.pi / 4.0,
        dimensionInputWidthMeters: 0.032,
        dimensionInputHeightMeters: 0.014,
        referenceLineAnchors: [
            SketchReferenceLineAnchor(point: Point2D(x: 1.0, y: 2.0)),
        ]
    )

    state.clearTransientInput()

    #expect(state.axisConstraint == nil)
    #expect(state.dimensionInputFocus == nil)
    #expect(state.dimensionInputLengthMeters == nil)
    #expect(state.dimensionInputAngleRadians == nil)
    #expect(state.dimensionInputWidthMeters == nil)
    #expect(state.dimensionInputHeightMeters == nil)
    #expect(state.referenceLineAnchors.isEmpty)
}

@MainActor
@Test func editorSessionSketchInputStateTogglesAndClearsOutsideSketchTools() {
    let session = EditorSession(selectedTool: .polygon)

    #expect(session.toggleSketchAxisConstraint(.x) == .x)
    #expect(session.toggleSketchAxisConstraint(.x) == nil)
    #expect(session.toggleSketchAxisConstraint(.z) == .z)
    #expect(session.focusNextSketchDimensionInput() == .length)
    #expect(session.focusNextSketchDimensionInput() == .angle)
    #expect(session.setSketchDimensionInputLength(0.016))
    #expect(session.sketchInputState.dimensionInputFocus == .length)
    #expect(session.setSketchDimensionInputWidth(0.032))
    #expect(session.sketchInputState.dimensionInputFocus == .width)
    #expect(session.setSketchDimensionInputHeight(0.014))
    #expect(session.sketchInputState.dimensionInputFocus == .height)
    #expect(!session.setSketchDimensionInputLength(-0.001))

    session.selectTool(.select)

    #expect(session.sketchInputState.axisConstraint == nil)
    #expect(session.sketchInputState.dimensionInputFocus == nil)
    #expect(session.sketchInputState.dimensionInputLengthMeters == nil)
    #expect(session.sketchInputState.dimensionInputWidthMeters == nil)
    #expect(session.sketchInputState.dimensionInputHeightMeters == nil)
    #expect(session.sketchInputState.referenceLineAnchors.isEmpty)
}
