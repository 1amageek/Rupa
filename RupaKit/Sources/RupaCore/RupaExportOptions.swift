import Foundation

public struct RupaExportOptions: Codable, Equatable, Sendable {
    public var presetID: RupaExportPresetID?
    public var presetName: String?
    public var destinationPolicy: RupaExportPreset.DestinationPolicy?

    public init(
        presetID: RupaExportPresetID? = nil,
        presetName: String? = nil,
        destinationPolicy: RupaExportPreset.DestinationPolicy? = nil
    ) {
        self.presetID = presetID
        self.presetName = presetName
        self.destinationPolicy = destinationPolicy
    }
}
