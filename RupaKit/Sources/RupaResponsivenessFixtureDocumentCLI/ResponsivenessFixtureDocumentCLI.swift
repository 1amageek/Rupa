import ArgumentParser
import Foundation
import RupaResponsivenessBaseline
import RupaResponsivenessFixtureDocument

@main
struct ResponsivenessFixtureDocumentCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rupa-responsiveness-fixture-document",
        abstract: """
            Writes the responsiveness fixture as a project package so a signed \
            application measures the content the harness measured.
            """
    )

    @Option(name: .long, help: "Number of bodies in the fixture.")
    var bodies: Int?

    @Option(name: .long, help: "Lateral segment count per body.")
    var segments: Int?

    @Argument(help: "Destination path of the written project package.")
    var output: String

    func run() throws {
        var parameters = ResponsivenessFixture.Parameters.standard
        if let bodies {
            parameters.bodyCount = bodies
        }
        if let segments {
            parameters.segmentCount = segments
        }
        let fixture = try ResponsivenessFixture.build(parameters)
        let url = URL(fileURLWithPath: output)
        let result = try ResponsivenessFixtureDocumentWriter().write(fixture, to: url)
        print("Fixture: \(parameters.name) v\(parameters.version)")
        print("Content digest: \(result.fixtureContentDigest)")
        print("Bodies: \(result.bodyCount)")
        print("Vertices: \(result.vertexCount)")
        print("Faces: \(result.faceCount)")
        print("Bytes: \(result.byteCount)")
        print("Written: \(result.url.path)")
    }
}
