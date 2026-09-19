import Foundation
import Testing
@testable import RupaUI

/// Audits the seven right-rail utilities the workspace presents.
///
/// A compact rail button expands the rail and then asks the scroll proxy to
/// reach the destination's section. `ScrollViewProxy.scrollTo` is a silent
/// no-op when no view carries that identifier, so a destination without an
/// anchor still expands the rail and leaves the user on whatever section
/// happened to be visible. These checks read the shipped sources so a new
/// destination cannot reach production with a button but no anchor, or with
/// an anchor but no button.
@Suite("Workspace utility rail destinations", .timeLimit(.minutes(1)))
struct WorkspaceUtilityRailDestinationTests {
    @Test func everyDestinationHasACompactRailButton() throws {
        let source = try WorkspaceUtilityRailDestinationTests.source(
            relativePath: "Sources/RupaUI/WorkspaceUtilityRailCompactView.swift"
        )
        let missing = WorkspaceUtilityRailDestination.allCases
            .filter { !source.contains("expand(.\($0.rawValue))") }
        #expect(missing.isEmpty, "Destinations with no compact rail button: \(missing)")
    }

    @Test func everyDestinationHasAnExpandedRailAnchor() throws {
        let source = try WorkspaceUtilityRailDestinationTests.source(
            relativePath: "Sources/RupaUI/MainView.swift"
        )
        let missing = WorkspaceUtilityRailDestination.allCases
            .filter { !source.contains(".id(WorkspaceUtilityRailDestination.\($0.rawValue))") }
        #expect(missing.isEmpty, "Destinations with no expanded rail anchor: \(missing)")
    }

    @Test func everyDestinationCarriesADistinctTitle() {
        let titles = WorkspaceUtilityRailDestination.allCases.map(\.title)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == titles.count)
    }

    private static func source(relativePath: String, filePath: String = #filePath) throws -> String {
        let url = try packageRoot(filePath: filePath)
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AuditError.sourceFileNotFound(relativePath)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func packageRoot(filePath: String) throws -> URL {
        var candidate = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let manifest = candidate.appendingPathComponent("Package.swift").path
            if FileManager.default.fileExists(atPath: manifest) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw AuditError.packageRootNotFound(filePath)
    }

    private enum AuditError: Error {
        case packageRootNotFound(String)
        case sourceFileNotFound(String)
    }
}
