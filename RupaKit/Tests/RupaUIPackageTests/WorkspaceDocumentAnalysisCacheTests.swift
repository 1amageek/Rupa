import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

/// A whole-document analysis is made once per input, however often the view reads it.
@Suite struct WorkspaceDocumentAnalysisCacheTests {
    private enum Failure: Error {
        case refused
    }

    @Test func aResultIsMadeOncePerKey() throws {
        let memo = MemoizedResults<Int, String>()
        var makes = 0
        func make() -> String { makes += 1; return "made \(makes)" }
        #expect(try memo.value(for: 1, make: make) == "made 1")
        #expect(try memo.value(for: 1, make: make) == "made 1")
        #expect(makes == 1)
        #expect(try memo.value(for: 2, make: make) == "made 2")
        #expect(try memo.value(for: 1, make: make) == "made 3", "one entry keeps only the latest key")
    }

    @Test func theRecentKeysAreKeptUpToTheCapacity() throws {
        let memo = MemoizedResults<Int, Int>(capacity: 2)
        var makes = 0
        func make() -> Int { makes += 1; return makes }
        _ = try memo.value(for: 1, make: make)
        _ = try memo.value(for: 2, make: make)
        _ = try memo.value(for: 1, make: make)
        #expect(makes == 2)
        _ = try memo.value(for: 3, make: make)   // evicts 2, the least recently read
        _ = try memo.value(for: 1, make: make)
        #expect(makes == 3)
        _ = try memo.value(for: 2, make: make)
        #expect(makes == 4)
    }

    @Test func aFailureIsKeptAndNotRetriedForTheSameKey() {
        let memo = MemoizedResults<Int, Int>()
        var makes = 0
        func make() throws -> Int { makes += 1; throw Failure.refused }
        #expect(throws: Failure.self) { try memo.value(for: 1, make: make) }
        #expect(throws: Failure.self) { try memo.value(for: 1, make: make) }
        #expect(makes == 1)
    }

    /// The view reads the surface analysis up to three times per render; through the cache the
    /// builder answers exactly what it answers without one.
    @Test func theCachedSurfaceAnalysisMatchesAFreshOne() throws {
        let fixture = try workspaceSurfaceInspectorFixture()
        func builder(_ cache: WorkspaceDocumentAnalysisCache?) -> WorkspaceSurfaceInspectorStateBuilder {
            WorkspaceSurfaceInspectorStateBuilder(
                document: fixture.document,
                selection: SelectionModel(selectedTargets: [SelectionTarget(sceneNodeID: fixture.sceneNode.id)]),
                currentEvaluation: nil,
                documentGeneration: DocumentGeneration(),
                objectRegistry: .builtIn,
                surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard),
                workspaceState: WorkspaceState(),
                analysisCache: cache
            )
        }
        let cache = WorkspaceDocumentAnalysisCache()
        // Each evaluation names its faces afresh, so two analyses made anew differ in those
        // names; two reads through the cache are the one analysis, identical to the last name.
        let fresh = try #require(try builder(nil).analysisResult(for: [fixture.sceneNode]).get())
        let first = try #require(try builder(cache).analysisResult(for: [fixture.sceneNode]).get())
        let second = try #require(try builder(cache).analysisResult(for: [fixture.sceneNode]).get())
        #expect(first == second)
        #expect(first.bSplineFaceCount == fresh.bSplineFaceCount)
        #expect(first.sampleCount == fresh.sampleCount)
        #expect(first.trimBoundaryEdgeCount == fresh.trimBoundaryEdgeCount)
        let continuity = try #require(try builder(cache).continuityResult(for: [fixture.sceneNode]).get())
        #expect(try builder(cache).continuityResult(for: [fixture.sceneNode]).get() == continuity)
        let freshContinuity = try #require(try builder(nil).continuityResult(for: [fixture.sceneNode]).get())
        #expect(continuity.sharedEdgeCount == freshContinuity.sharedEdgeCount)
        #expect(continuity.adjacencies.count == freshContinuity.adjacencies.count)
    }
}
