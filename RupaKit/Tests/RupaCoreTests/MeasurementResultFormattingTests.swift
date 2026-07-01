import Testing
@testable import RupaCore

@Test func measurementResultFormatsLargeBoundsWithGroupedValues() {
    let bounds = MeasurementResult.Bounds(
        minX: 0.0,
        minY: 0.0,
        minZ: 0.0,
        maxX: 100_000.0,
        maxY: 30_480.0,
        maxZ: 1_000.0
    )

    #expect(bounds.formattedSize(in: .meter) == "100,000 x 30,480 x 1,000 m")
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
    #expect(result.message.contains("100,000 x 30,480 x 1,000 m bounds"))
}
