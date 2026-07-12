import Foundation

public struct GeometryCopyTelemetry: Codable, Equatable, Sendable {
    public private(set) var events: [GeometryCopyEvent]

    public init(events: [GeometryCopyEvent] = []) {
        self.events = events
    }

    public var copiedBytes: Int {
        events.reduce(0) { $0 + $1.copiedBytes }
    }

    public var didCopy: Bool {
        copiedBytes > 0
    }

    public mutating func record(reason: GeometryCopyReason, copiedBytes: Int) {
        guard copiedBytes > 0 else {
            return
        }
        events.append(
            GeometryCopyEvent(
                reason: reason,
                copiedBytes: copiedBytes
            )
        )
    }
}
