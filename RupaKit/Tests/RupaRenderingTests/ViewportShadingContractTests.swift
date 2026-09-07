import CoreGraphics
import Foundation
import RupaCore
import RupaCoreTypes
import RupaGeometry
import SwiftCAD
import Testing
@testable import RupaRendering

@Test
func viewportShadingValidationRejectsNonFiniteAndOutOfRangeValues() throws {
    var nonFinite = ViewportShading.standard
    nonFinite.studioRotationDegrees = .infinity
    #expect(throws: ViewportShadingError.nonFiniteStudioRotation) {
        try nonFinite.validate()
    }

    var outOfRange = ViewportShading.standard
    outOfRange.studioRotationDegrees = 360
    #expect(throws: ViewportShadingError.studioRotationOutOfRange) {
        try outOfRange.validate()
    }

    let invalidColor = ViewportShading(
        solidColor: .single(ColorRGBA(r: .nan, g: 0, b: 0, a: 1))
    )
    #expect(throws: ViewportShadingError.self) {
        try invalidColor.validate()
    }
}

@Test
func viewportShadingUsesStableOccurrenceAndMaterialColors() {
    let occurrence = SceneOccurrenceID(rawValue: "stable-occurrence")
    let random = ViewportShading(solidColor: .random)
    #expect(random.resolvedColor(for: occurrence, materialColor: nil)
        == random.resolvedColor(for: occurrence, materialColor: nil))

    let material = ColorRGBA(r: 0.12, g: 0.34, b: 0.56, a: 1)
    let materialShading = ViewportShading(solidColor: .material)
    #expect(materialShading.resolvedColor(for: occurrence, materialColor: material)
        == SIMD4<Float>(0.12, 0.34, 0.56, 1))
    #expect(materialShading.resolvedWireColor(
        for: occurrence,
        objectColor: SIMD4<Float>(0.12, 0.34, 0.56, 1)
    ) == SIMD4<Float>(0.48, 0.56, 0.64, 1))
}

@MainActor
@Test
func viewportShadingSessionMutationIsAtomicAndDoesNotChangeCameraOrDisplayMode() throws {
    let session = ViewportControlSession()
    let viewportID = ViewportInstanceID()
    _ = session.mount(viewportID: viewportID)
    session.updateContext(ViewportControlMountContext(
        viewportID: viewportID,
        viewportSize: CGSize(width: 800, height: 600),
        fittingInsets: .zero,
        modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
        verticalBounds: -1...1,
        ruler: .standard(for: .millimeter),
        sceneBounds: try GeometryBounds3D(
            minimum: .init(x: -1, y: -1, z: -1),
            maximum: .init(x: 1, y: 1, z: 1)
        ),
        selectedBounds: nil
    ))
    let before = try session.snapshot()

    var invalid = ViewportShading.standard
    invalid.studioRotationDegrees = .nan
    #expect(throws: ViewportControlError.self) {
        try session.perform(.setShading(invalid))
    }
    #expect(try session.snapshot() == before)

    let valid = ViewportShading(
        style: .matCap,
        studioRotationDegrees: 45,
        isSpecularEnabled: false,
        solidColor: .random,
        background: .custom(ColorRGBA(r: 0.2, g: 0.3, b: 0.4, a: 1)),
        wireColor: .object,
        isBackfaceCullingEnabled: true
    )
    let after = try session.perform(.setShading(valid), expectedRevision: before.revision)
    #expect(after.revision == before.revision + 1)
    #expect(after.camera == before.camera)
    #expect(after.basis == before.basis)
    #expect(after.displayMode == before.displayMode)
    #expect(after.shading == valid)
}
