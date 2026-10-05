import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

/// Material layers reach the drawn surface, and a curve's material colors it.
@Suite struct ViewportMaterialLayersTests {
    @Test func surfaceCarriesTheLayersTheNativeMaterialDrawsAndBlendsTransmission() {
        var material = Material.neutral(named: "Glass")
        material.clearcoat = 0.6
        material.clearcoatRoughness = 0.2
        material.ior = 1.7
        material.sheen = 0.5
        material.sheenColor = ColorRGBA(r: 1, g: 0.5, b: 0, a: 1)
        material.sheenRoughness = 0.35
        material.specularColor = ColorRGBA(r: 0.8, g: 0.7, b: 0.6, a: 1)
        material.specularIntensity = 0.4
        material.iridescence = 0.25
        material.iridescenceIOR = 1.4
        material.thickness = 0.002
        material.transmission = 1
        let surface = ViewportSurface(color: material.baseColor, authoring: material)
        #expect(surface.clearcoat == 0.6)
        #expect(surface.clearcoatRoughness == 0.2)
        #expect(surface.ior == 1.7)
        #expect(surface.sheen == ColorRGBA(r: 0.5, g: 0.25, b: 0, a: 1))
        #expect(surface.sheenRoughness == 0.35)
        #expect(surface.specularColor == ColorRGBA(r: 0.8, g: 0.7, b: 0.6, a: 1))
        #expect(surface.specularIntensity == 0.4)
        #expect(surface.iridescence == 0.25)
        #expect(surface.iridescenceIOR == 1.4)
        #expect(surface.thickness == 0.002)
        #expect(surface.displayedOpacity == 0.5)
        #expect(surface.isTransparent)
        #expect(!ViewportSurface(color: material.baseColor, authoring: nil).isTransparent)
    }

    @Test func aCurveWhoseNodeNamesAMaterialDrawsInItsColor() throws {
        let featureID = FeatureID()
        let nodeID = SceneNodeID()
        let segment = ViewportCurveSegment(
            reference: CurveOutputReference(featureID: featureID, curveIndex: 0),
            curve: EvaluatedCurve(sourceFeatureID: featureID, source: .generatedFeature, kind: .line,
                                  points: [.origin, Point3D(x: 1, y: 0, z: 0)])
        )
        let item = ViewportSceneItem(id: "curve", featureID: featureID, sceneNodeID: nodeID,
            modelBounds: CGRect(x: 0, y: 0, width: 1, height: 0.1),
            kind: .curve(component: ViewportCurveComponent(segments: [segment], yMinMeters: 0, yMaxMeters: 0)))
        func drawnColor(_ colors: [SceneNodeID: SIMD4<Float>]) throws -> SIMD4<Float>? {
            var snapshot = ViewportSpatialOverlaySemanticSnapshot(scene: .init(items: [item]),
                interaction: .init(selectedFeatureIDs: [], selectedSceneNodeIDs: [], hoveredFeatureIDs: [],
                    hoveredSceneNodeIDs: [], selectedSketchEntities: [], previewSketchEntities: [],
                    hoveredSketchEntity: nil, selectedSketchRegions: [], previewSketchRegions: [], hoveredSketchRegion: nil),
                editedBodies: [:], world: .init(modelBounds: item.modelBounds), measurement: nil,
                drawsLegacyBodies: true, drawsDragPreviewBodies: false)
            snapshot.curveColors = colors
            let result = try ViewportSpatialOverlayProducer.makeInput(from: snapshot,
                renderOrigin: .origin, retainedSurfaceByteCount: 0, topologyRevision: 1)
            return result.meshes.first { $0.family == .curve }?.value.color
        }
        let red = SIMD4<Float>(1, 0, 0, 0.5)
        #expect(try drawnColor([nodeID: red]) == red)
        #expect(try drawnColor([:]) == ViewportSpatialOverlayProducer.curveColor)
    }
}
