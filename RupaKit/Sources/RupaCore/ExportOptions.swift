import Foundation

public struct ExportOptions: Codable, Equatable, Sendable {
    public var presetID: ExportPresetID?
    public var presetName: String?
    public var destinationPolicy: ExportPreset.DestinationPolicy?

    public init(
        presetID: ExportPresetID? = nil,
        presetName: String? = nil,
        destinationPolicy: ExportPreset.DestinationPolicy? = nil
    ) {
        self.presetID = presetID
        self.presetName = presetName
        self.destinationPolicy = destinationPolicy
    }
}
