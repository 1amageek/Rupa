import Foundation
import Testing
import SwiftCAD
@testable import RupaCore

@MainActor
@Suite("Body source section persistence", .timeLimit(.minutes(1)))
struct BodySourceSectionReferenceTests {
    @Test func sourceSectionMetadataRequiresAnExplicitValidRegion() throws {
        let source = BodySourceSectionReference.profile(ProfileReference(featureID: FeatureID(), profileIndex: 2))
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let bytes = try encoder.encode(source)
        #expect(try decoder.decode(BodySourceSectionReference.self, from: bytes) == source)
        var fields = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        fields["profileIndex"] = -1
        #expect(throws: (any Error).self) {
            try decoder.decode(BodySourceSectionReference.self, from: JSONSerialization.data(withJSONObject: fields))
        }
        fields.removeValue(forKey: "profileIndex")
        #expect(throws: (any Error).self) {
            try decoder.decode(BodySourceSectionReference.self, from: JSONSerialization.data(withJSONObject: fields))
        }
        #expect(throws: (any Error).self) {
            try encoder.encode(BodySourceSectionReference.profile(
                ProfileReference(featureID: FeatureID(), profileIndex: -1)))
        }
        let curve = BodySourceSectionReference.curve(FeatureID())
        #expect(try decoder.decode(BodySourceSectionReference.self, from: encoder.encode(curve)) == curve)
    }
}
