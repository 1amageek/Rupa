import Testing
@testable import RupaRendering

@MainActor
@Test
func viewportAxisTriadProjectionButtonsPreserveLensSelection() {
    for projection in [ViewportCameraProjection.parallel, .standardPerspective, .perspective(fieldOfViewRadians: 0.9)] {
        var requests: [ViewportCameraProjection] = []
        let strip = ViewportAxisTriad(
            selectedAxis: nil, projection: projection,
            onResetView: {}, onSelectAxis: { _ in },
            onSelectProjection: { requests.append($0) }
        )
        strip.selectProjection(perspective: projection != .parallel)
        #expect(requests.isEmpty)
        strip.selectProjection(perspective: projection == .parallel)
        #expect(requests == [projection == .parallel ? .standardPerspective : .parallel])
    }
}
