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
