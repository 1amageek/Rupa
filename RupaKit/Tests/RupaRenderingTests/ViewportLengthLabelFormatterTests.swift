import Testing
@testable import RupaRendering

@Test func viewportLengthLabelFormatterUsesReadableMetricUnits() {
    #expect(
        ViewportLengthLabelFormatter.string(
            fromMeters: 1.024,
            preferredUnit: .millimeter
        ) == "1.024 m"
    )
    #expect(
        ViewportLengthLabelFormatter.string(
            fromMeters: 1_000_000.0,
            preferredUnit: .millimeter
        ) == "1,000 km"
    )
    #expect(
        ViewportLengthLabelFormatter.string(
            fromMeters: 0.000_25,
            preferredUnit: .meter
        ) == "250 μm"
    )
}

@Test func viewportLengthLabelFormatterKeepsReadablePreferredUnitValues() {
    #expect(
        ViewportLengthLabelFormatter.string(
            fromMeters: 0.512,
            preferredUnit: .millimeter
        ) == "512 mm"
    )
    #expect(
        ViewportLengthLabelFormatter.string(
            fromMeters: -1_500.0,
            preferredUnit: .meter
        ) == "-1.5 km"
    )
}
