import Foundation

/// Records element-payload copies performed by explicit geometry-buffer operations.
public struct GeometryCopyTelemetry: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case events
    }

    public private(set) var events: [GeometryCopyEvent]
    public private(set) var copiedBytes: UInt64

    public init() {
        events = []
        copiedBytes = 0
    }

    public init(events: [GeometryCopyEvent]) throws {
        var copiedBytes: UInt64 = 0
        for event in events {
            let addition = copiedBytes.addingReportingOverflow(event.copiedBytes)
            guard !addition.overflow else {
                throw GeometryBufferError(
                    code: .sizeOverflow,
                    message: "Geometry copy telemetry exceeds the supported byte-count range."
                )
            }
            copiedBytes = addition.partialValue
        }
        self.events = events
        self.copiedBytes = copiedBytes
    }

    public var didCopy: Bool {
        copiedBytes > 0
    }

    public mutating func record(
        reason: GeometryCopyReason,
        copiedBytes: UInt64
    ) throws {
        guard copiedBytes > 0 else {
            return
        }
        let addition = self.copiedBytes.addingReportingOverflow(copiedBytes)
        guard !addition.overflow else {
            throw GeometryBufferError(
                code: .sizeOverflow,
                message: "Geometry copy telemetry exceeds the supported byte-count range."
            )
        }
        events.append(
            GeometryCopyEvent(
                reason: reason,
                copiedBytes: copiedBytes
            )
        )
        self.copiedBytes = addition.partialValue
    }

    public mutating func record(contentsOf telemetry: GeometryCopyTelemetry) throws {
        let addition = copiedBytes.addingReportingOverflow(telemetry.copiedBytes)
        guard !addition.overflow else {
            throw GeometryBufferError(
                code: .sizeOverflow,
                message: "Geometry copy telemetry exceeds the supported byte-count range."
            )
        }
        events.append(contentsOf: telemetry.events)
        copiedBytes = addition.partialValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let events = try container.decode([GeometryCopyEvent].self, forKey: .events)
        do {
            try self.init(events: events)
        } catch let error as GeometryBufferError {
            throw DecodingError.dataCorruptedError(
                forKey: .events,
                in: container,
                debugDescription: error.message
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .events)
    }
}
