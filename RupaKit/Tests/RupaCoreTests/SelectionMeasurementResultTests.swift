import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func selectionMeasurementResultExposesPointDisplayValues() throws {
    let reference = selectionMeasurementResultReference("point")
    let rawPoint = SelectionMeasurementPoint(
        selection: reference,
        point: Point3D(x: 0.001, y: 0.002, z: 0.003),
        curvature: 1_000.0
    )

    let result = SelectionMeasurementResult(
        rawValue: .point(rawPoint),
        displayUnit: .millimeter
    )

    guard case .point(let point) = result else {
        Issue.record("Expected point measurement result.")
        return
    }
    #expect(point.point == rawPoint.point)
    #expect(point.displayUnit == .millimeter)
    #expect(point.displayUnitSymbol == "mm")
    #expect(point.displayPoint == Point3D(x: 1.0, y: 2.0, z: 3.0))
    #expect(point.displayCurvatureValue == 1.0)
    #expect(point.displayCurvatureUnitSymbol == "1/mm")
}

@Test func selectionMeasurementResultExposesDistanceDisplayValues() throws {
    let first = SelectionMeasurementPoint(
        selection: selectionMeasurementResultReference("distance:first"),
        point: Point3D(x: 0.0, y: 0.0, z: 0.0)
    )
    let second = SelectionMeasurementPoint(
        selection: selectionMeasurementResultReference("distance:second"),
        point: Point3D(x: 0.003, y: 0.004, z: 0.0)
    )
    let rawDistance = try SelectionDistanceMeasurement(first: first, second: second)

    let result = SelectionMeasurementResult(
        rawValue: .distance(rawDistance),
        displayUnit: .millimeter
    )

    guard case .distance(let distance) = result else {
        Issue.record("Expected distance measurement result.")
        return
    }
    #expect(abs(distance.distance - 0.005) <= 1.0e-12)
    #expect(distance.displayUnit == .millimeter)
    #expect(distance.displayUnitSymbol == "mm")
    #expect(distance.displayVector == Vector3D(x: 3.0, y: 4.0, z: 0.0))
    #expect(abs(distance.displayDistance - 5.0) <= 1.0e-12)
}

@Test func selectionMeasurementResultExposesAngleDisplayValues() throws {
    let first = SelectionMeasurementPoint(
        selection: selectionMeasurementResultReference("angle:first"),
        point: Point3D.origin,
        tangent: .unitX
    )
    let second = SelectionMeasurementPoint(
        selection: selectionMeasurementResultReference("angle:second"),
        point: Point3D.origin,
        tangent: .unitY
    )
    let rawAngle = try SelectionAngleMeasurement(first: first, second: second)

    let result = SelectionMeasurementResult(
        rawValue: .angle(rawAngle),
        displayUnit: .millimeter
    )

    guard case .angle(let angle) = result else {
        Issue.record("Expected angle measurement result.")
        return
    }
    #expect(abs(angle.angleRadians - (Double.pi / 2.0)) <= 1.0e-12)
    #expect(abs(angle.angleDegrees - 90.0) <= 1.0e-12)
    #expect(abs(angle.displayAngleValue - 90.0) <= 1.0e-12)
    #expect(angle.displayUnitSymbol == "deg")
}

@Test func selectionMeasurementResultDecodesMissingDisplayValues() throws {
    let first = SelectionMeasurementPoint(
        selection: selectionMeasurementResultReference("legacy:first"),
        point: Point3D(x: 0.0, y: 0.0, z: 0.0)
    )
    let second = SelectionMeasurementPoint(
        selection: selectionMeasurementResultReference("legacy:second"),
        point: Point3D(x: 0.003, y: 0.004, z: 0.0)
    )
    let rawDistance = try SelectionDistanceMeasurement(first: first, second: second)
    let encodedRaw = try JSONEncoder().encode(CADAgentMeasurementQueryResult.distance(rawDistance))

    let decoded = try JSONDecoder().decode(
        SelectionMeasurementResult.self,
        from: encodedRaw
    )

    guard case .distance(let distance) = decoded else {
        Issue.record("Expected distance measurement result.")
        return
    }
    #expect(distance.displayUnit == .meter)
    #expect(distance.displayUnitSymbol == "m")
    #expect(distance.displayVector == rawDistance.vector)
    #expect(distance.displayDistance == rawDistance.distance)
}

private func selectionMeasurementResultReference(_ suffix: String) -> SelectionReference {
    .topology(PersistentName(components: [
        .feature(FeatureID(UUID())),
        .generated("selectionMeasurementResult"),
        .subshape(suffix),
    ]))
}
