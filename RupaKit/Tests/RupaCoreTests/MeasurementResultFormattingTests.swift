import Foundation
import Testing
@testable import RupaCore

@Test func measurementResultFormatsLargeBoundsWithReadableMetricUnits() {
    let bounds = MeasurementResult.Bounds(
        minX: 0.0,
        minY: 0.0,
        minZ: 0.0,
        maxX: 100_000.0,
        maxY: 30_480.0,
        maxZ: 1_000.0
    )

    #expect(bounds.formattedSize(in: .meter) == "100 km x 30.48 km x 1 km")
    #expect(bounds.formattedSize(in: .millimeter) == "100 km x 30.48 km x 1 km")
}

@Test func measurementResultFormatsFootBoundsAsArchitecturalLengths() {
    let bounds = MeasurementResult.Bounds(
        minX: 0.0,
        minY: 0.0,
        minZ: 0.0,
        maxX: LengthDisplayUnit.foot.meters(from: 6.0)
            + LengthDisplayUnit.inch.meters(from: 4.5),
        maxY: LengthDisplayUnit.inch.meters(from: 10.0),
        maxZ: LengthDisplayUnit.inch.meters(from: 0.5)
    )

    #expect(bounds.formattedSize(in: .foot) == "6' 4 1/2\" x 10\" x 1/2\"")
}

@Test func measurementResultMessageFormatsLargeTotalsWithGroupedValues() {
    let result = MeasurementResult(
        displayUnit: .meter,
        counts: MeasurementResult.Counts(sourceFeatures: 1, solids: 1),
        bounds: MeasurementResult.Bounds(
            minX: 0.0,
            minY: 0.0,
            minZ: 0.0,
            maxX: 100_000.0,
            maxY: 30_480.0,
            maxZ: 1_000.0
        ),
        totals: MeasurementResult.Totals(
            profileAreaSquareMeters: 100_000_000.0,
            sheetAreaSquareMeters: 30_480_000.0,
            solidVolumeCubicMeters: 1_000_000_000.0
        )
    )

    #expect(result.message.contains("100,000,000 m^2 profile area"))
    #expect(result.message.contains("30,480,000 m^2 sheet area"))
    #expect(result.message.contains("1,000,000,000 m^3 solid volume"))
    #expect(result.message.contains("100 km x 30.48 km x 1 km bounds"))
}

@Test(.timeLimit(.minutes(1)))
func legacySolidMeasurementDecodingMarksMissingProvenance() throws {
    let data = Data("""
    {
      "featureID": "feature",
      "sourceFeatureID": "source",
      "linearDimensions": [],
      "volumeCubicMeters": 1.0,
      "surfaceAreaSquareMeters": 6.0,
      "bounds": {
        "minX": 0.0, "minY": 0.0, "minZ": 0.0,
        "maxX": 1.0, "maxY": 1.0, "maxZ": 1.0
      }
    }
    """.utf8)

    let solid = try JSONDecoder().decode(MeasurementResult.Solid.self, from: data)

    #expect(solid.volumeMethod == .legacyUnspecified)
    #expect(solid.surfaceAreaMethod == .legacyUnspecified)
    #expect(solid.boundsMethod == .legacyUnspecified)
    #expect(solid.volume == .init(value: 1.0, method: .legacyUnspecified))
    #expect(solid.surfaceArea == .init(value: 6.0, method: .legacyUnspecified))
}

@Test(.timeLimit(.minutes(1)))
func solidMeasurementRoundTripPreservesMethodProvenance() throws {
    let solid = MeasurementResult.Solid(
        featureID: "feature",
        featureName: "Solid",
        sourceFeatureID: "source",
        sourceFeatureName: "Profile",
        linearDimensions: [],
        volume: .init(value: 1.0, method: .exactBRep),
        surfaceArea: .init(value: 6.0, method: .tessellatedMesh),
        bounds: .init(
            value: MeasurementResult.Bounds(
                minX: 0.0,
                minY: 0.0,
                minZ: 0.0,
                maxX: 1.0,
                maxY: 1.0,
                maxZ: 1.0
            ),
            method: .tessellatedMesh
        )
    )

    let encoded = try JSONEncoder().encode(solid)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let decoded = try JSONDecoder().decode(MeasurementResult.Solid.self, from: encoded)

    #expect(decoded == solid)
    #expect(object["volume"] != nil)
    #expect(object["measuredBounds"] != nil)
    #expect(object["volumeMethod"] == nil)
    #expect(object["boundsMethod"] == nil)
}

@Test(.timeLimit(.minutes(1)))
func solidMeasurementRejectsMixedCanonicalAndLegacyProvenance() throws {
    let data = Data("""
    {
      "featureID": "feature",
      "sourceFeatureID": "source",
      "linearDimensions": [],
      "volume": { "value": 1.0, "method": "exactBRep" },
      "volumeMethod": "tessellatedMesh",
      "measuredBounds": {
        "value": {
          "minX": 0.0, "minY": 0.0, "minZ": 0.0,
          "maxX": 1.0, "maxY": 1.0, "maxZ": 1.0
        },
        "method": "exactBRep"
      }
    }
    """.utf8)

    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(MeasurementResult.Solid.self, from: data)
    }
}

@Test(.timeLimit(.minutes(1)))
func profileMeasurementRoundTripPreservesSampledCurveProvenance() throws {
    let bounds = MeasurementResult.Bounds(
        minX: 0.0,
        minY: 0.0,
        minZ: 0.0,
        maxX: 1.0,
        maxY: 1.0,
        maxZ: 0.0
    )
    let profile = MeasurementResult.Profile(
        featureID: "feature",
        featureName: "Profile",
        kind: .curveLoop,
        area: .init(value: 0.75, method: .sampledCurve),
        bounds: .init(value: bounds, method: .sampledCurve)
    )

    let encoded = try JSONEncoder().encode(profile)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let decoded = try JSONDecoder().decode(MeasurementResult.Profile.self, from: encoded)

    #expect(decoded == profile)
    #expect(decoded.areaMethod == .sampledCurve)
    #expect(object["area"] != nil)
    #expect(object["areaSquareMeters"] == nil)
}

@Test(.timeLimit(.minutes(1)))
func legacySheetMeasurementDecodingMarksMissingProvenance() throws {
    let data = Data("""
    {
      "featureID": "feature",
      "sourceFeatureID": "source",
      "linearDimensions": [],
      "surfaceAreaSquareMeters": 2.0,
      "bounds": {
        "minX": 0.0, "minY": 0.0, "minZ": 0.0,
        "maxX": 1.0, "maxY": 2.0, "maxZ": 0.0
      }
    }
    """.utf8)

    let sheet = try JSONDecoder().decode(MeasurementResult.Sheet.self, from: data)

    #expect(sheet.surfaceAreaMethod == .legacyUnspecified)
    #expect(sheet.boundsMethod == .legacyUnspecified)
    #expect(sheet.surfaceArea == .init(value: 2.0, method: .legacyUnspecified))
}
