import Foundation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

/// Mirror's keys, face clicks and freestyle line choose one plane, and its options submit one command.
@Suite struct WorkspaceMirrorSessionTests {
    private let box = SceneNodeID()

    @Test func planeStartsAtPositiveXAndFollowsAxisKeysFacesAndFreestyle() throws {
        var mirror = try WorkspaceMirrorSession(sceneNodeIDs: [box], constructionPlane: .xy)
        #expect(mirror.plane.normal == .unitX)
        #expect(mirror.planeName == "+X")

        try mirror.choose(axis: .z, positive: false, constructionPlane: .xy)
        #expect(mirror.plane.normal == Vector3D(x: 0, y: 0, z: -1))
        #expect(mirror.planeName == "−Z")

        try mirror.choose(facePoint: Point3D(x: 0, y: 0, z: 1), normal: .unitZ)
        #expect(mirror.plane.origin == Point3D(x: 0, y: 0, z: 1))
        #expect(mirror.planeName == "Face")

        mirror.beginFreestyle()
        try mirror.addFreestylePoint(.origin, constructionPlane: .xy)
        #expect(mirror.freestylePoints == [.origin])
        try mirror.addFreestylePoint(Point3D(x: 0, y: 1, z: 0), constructionPlane: .xy)
        #expect(mirror.freestylePoints == nil)
        #expect((mirror.plane.normal - Vector3D(x: -1, y: 0, z: 0)).length < 1e-12)
        #expect(mirror.planeName == "Freestyle")
    }

    @Test func unionAndInstancesExcludeEachOtherAndTheCommandCarriesTheOptions() throws {
        var mirror = try WorkspaceMirrorSession(sceneNodeIDs: [box], constructionPlane: .xy)
        mirror.toggleInstances()
        mirror.toggleUnion()
        #expect(mirror.options.unionsHalves)
        #expect(!mirror.options.makesInstances)
        mirror.toggleInstances()
        #expect(!mirror.options.unionsHalves)
        mirror.options.cutsAtPlane = true
        guard case .mirrorSceneNodes(let ids, let plane, let options) = mirror.command else {
            Issue.record("Mirror submits mirrorSceneNodes.")
            return
        }
        #expect(ids == [box])
        #expect(plane == mirror.plane)
        #expect(options == SceneMirrorOptions(cutsAtPlane: true, unionsHalves: false, makesInstances: true))
    }
}
