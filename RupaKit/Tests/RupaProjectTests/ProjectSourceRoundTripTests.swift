import Foundation
import RupaCore
import RupaProjectModel
import RupaProjectPackage
import SwiftCAD
import Testing
@testable import RupaProject

/// A candidate is published only when its package sources decode to an equal document, and
/// proving that validates, projects and hashes the candidate no more than once.
@Suite struct ProjectSourceRoundTripTests {
    /// Decodes a CAD source one second newer than it was written.
    private struct AlteringCADSourceCodec: ProjectCADSourceCoding {
        func encode(_ document: CADDocument) throws -> ProjectPackageCADSource {
            try JSONProjectCADSourceCodec().encode(document)
        }

        func decode(_ source: ProjectPackageCADSource) throws -> CADDocument {
            var document = try JSONProjectCADSourceCodec().decode(source)
            document.metadata.updatedAt = document.metadata.updatedAt.addingTimeInterval(1)
            return document
        }
    }

    private func box() throws -> DesignDocument {
        var document = DesignDocument.empty(named: "Round trip")
        _ = try document.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter), depth: .length(0.1, .meter),
            direction: .normal
        )
        return document
    }

    private func roundTrip(cadSourceCodec: any ProjectCADSourceCoding = JSONProjectCADSourceCodec()) -> ProjectSourceRoundTrip {
        ProjectSourceRoundTrip(
            projector: FixtureProjector(),
            productSourceCodec: JSONProjectProductSourceCodec(),
            cadSourceCodec: cadSourceCodec,
            packageValidator: ProjectPackageStore(),
            objectRegistry: .builtIn
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func aCodecThatAltersTheCADDocumentIsRefused() throws {
        let document = try box()
        #expect(document.hasAuthoritativeCADSource)
        do {
            _ = try roundTrip(cadSourceCodec: AlteringCADSourceCodec()).stage(
                document, validated: nil, into: nil, collectingGarbage: false, context: .initial
            )
            Issue.record("A CAD source that decodes to a different document must be refused.")
        } catch let error as ProjectControllerError {
            #expect(error.code == .sourceMismatch)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func anExactRoundTripValidatesOnlyWhatTheCallerDidNot() throws {
        let document = try box()
        let validated = try document.validate()

        let reused = DocumentWorkProbe()
        let staged = try DocumentWorkProbe.$current.withValue(reused) {
            try roundTrip().stage(document, validated: validated, into: nil, collectingGarbage: false, context: .edit)
        }
        #expect(reused.validationCount == 0)
        #expect(staged.document.cadDocument == document.cadDocument)
        #expect(staged.validatedDocument.validatedCADDocument.document == document.cadDocument)

        let fresh = DocumentWorkProbe()
        _ = try DocumentWorkProbe.$current.withValue(fresh) {
            try roundTrip().stage(document, validated: nil, into: nil, collectingGarbage: false, context: .initial)
        }
        #expect(fresh.validationCount == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func aReadPackageIsValidatedOnce() throws {
        let staged = try roundTrip().stage(
            try box(), validated: nil, into: nil, collectingGarbage: false, context: .initial
        )
        let probe = DocumentWorkProbe()
        let read = try DocumentWorkProbe.$current.withValue(probe) {
            try roundTrip().read(staged.package)
        }
        #expect(probe.validationCount == 1)
        #expect(read.document.cadDocument == staged.document.cadDocument)
        #expect(read.retiredObjectProperties.isEmpty)
    }
}
