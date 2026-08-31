import Foundation
import RupaAutomation
import RupaCore
import Testing
@testable import RupaCLIKit

@Test
func automationResponsePreservesAuthorityAndMutationJSONFields() throws {
    let result = stubAutomationResult(
        message: "Created source geometry.",
        effect: .sourceMutation,
        generation: DocumentGeneration(12),
        sourceDirty: true,
        workspaceRevision: WorkspaceRevision(5),
        didMutate: true,
        workspaceScale: stubWorkspaceScale(displayUnit: .centimeter)
    )
    let response = CLIResponse(
        result: result,
        dirty: false,
        saved: true
    )
    let data = try JSONEncoder().encode(response)
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let scale = try #require(object["workspaceScale"] as? [String: Any])

    #expect(object["message"] as? String == "Created source geometry.")
    #expect(object["effect"] as? String == "sourceMutation")
    #expect(object["generation"] as? UInt64 == 12)
    #expect(object["workspaceRevision"] as? UInt64 == 5)
    #expect(object["dirty"] as? Bool == false)
    #expect(object["saved"] as? Bool == true)
    #expect(scale["displayUnit"] as? String == "centimeter")
    #expect(try JSONDecoder().decode(CLIResponse.self, from: data) == response)
}
