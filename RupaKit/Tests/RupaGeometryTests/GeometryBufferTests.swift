import Testing
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func geometryBufferViewsReadWithoutMaterializingCopies() throws {
    let buffer = GeometryBuffer([1, 2, 3, 4])
    let view = try buffer.view(1..<3)

    #expect(Array(view) == [2, 3])
    #expect(view.startIndex == 1)
    #expect(view.endIndex == 3)
}

@Test(.timeLimit(.minutes(1)))
func geometryBufferBuilderPreservesOriginalAndReportsSourceEditCopy() throws {
    let buffer = GeometryBuffer([1, 2, 3, 4])
    var builder = buffer.makeBuilder()
    #expect(builder.telemetry.copiedBytes == 0)
    try builder.replaceSubrange(1..<2, with: [20])
    let edited = builder.build()

    #expect(Array(buffer) == [1, 2, 3, 4])
    #expect(Array(edited) == [1, 20, 3, 4])
    #expect(builder.telemetry.didCopy)
    #expect(builder.telemetry.events.first?.reason == .sourceEdit)
    #expect(builder.telemetry.copiedBytes == 4 * MemoryLayout<Int>.stride)
}
