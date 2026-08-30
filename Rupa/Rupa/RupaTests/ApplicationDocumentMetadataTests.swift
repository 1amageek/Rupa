import Foundation
import Testing
@testable import Rupa

@Test(.timeLimit(.minutes(1)))
func applicationMetadataRegistersOnlyTheRupaProjectDocumentType() throws {
    let info = try #require(Bundle.main.infoDictionary)
    #expect(Bundle.main.bundleIdentifier == "team.stamp.Rupa")

    #expect(info["LSMultipleInstancesProhibited"] as? Bool == true)

    let exported = try #require(
        info["UTExportedTypeDeclarations"] as? [[String: Any]]
    )
    #expect(exported.count == 1)
    #expect(
        exported.first?["UTTypeIdentifier"] as? String
            == ApplicationProductConfiguration.projectTypeIdentifier
    )
    let tags = try #require(
        exported.first?["UTTypeTagSpecification"] as? [String: Any]
    )
    #expect(tags["public.filename-extension"] as? [String] == ["rupa"])

    let documents = try #require(
        info["CFBundleDocumentTypes"] as? [[String: Any]]
    )
    #expect(documents.count == 1)
    #expect(documents.first?["CFBundleTypeRole"] as? String == "Editor")
    #expect(
        documents.first?["LSItemContentTypes"] as? [String]
            == [ApplicationProductConfiguration.projectTypeIdentifier]
    )

    let data = try PropertyListSerialization.data(
        fromPropertyList: info,
        format: .xml,
        options: 0
    )
    let serialized = String(decoding: data, as: UTF8.self)
    #expect(!serialized.localizedCaseInsensitiveContains("swcad"))
}
