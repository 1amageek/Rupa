import RupaKit

struct ProjectAgentViewportSnapshotBudget: Sendable {
    let limits: ProjectAgentViewportSnapshotLimits
    private(set) var elementRecords = 0
    private(set) var auxiliaryRecords = 0
    private(set) var triangleCount: UInt64 = 0
    private(set) var stringUTF8Bytes = 0

    mutating func consumeElementRecords(_ count: Int) throws {
        elementRecords = try consume(
            count,
            current: elementRecords,
            maximum: limits.maxElementRecords,
            label: "source element"
        )
    }

    mutating func consumeAuxiliaryRecords(_ count: Int) throws {
        auxiliaryRecords = try consume(
            count,
            current: auxiliaryRecords,
            maximum: limits.maxAuxiliaryRecords,
            label: "diagnostic and telemetry"
        )
    }

    mutating func consumeString(_ value: String) throws {
        stringUTF8Bytes = try consume(
            value.utf8.count,
            current: stringUTF8Bytes,
            maximum: limits.maxStringUTF8Bytes,
            label: "UTF-8 string"
        )
    }

    mutating func consumeTriangles(_ count: UInt64) throws {
        let addition = triangleCount.addingReportingOverflow(count)
        guard !addition.overflow,
              addition.partialValue <= limits.maxTriangleCount else {
            throw ProjectMeshReadError(
                code: .limitExceeded,
                message: "The project viewport snapshot exceeds the triangle-count limit."
            )
        }
        triangleCount = addition.partialValue
    }

    private func consume(
        _ count: Int,
        current: Int,
        maximum: Int,
        label: String
    ) throws -> Int {
        guard count >= 0 else {
            throw ProjectMeshReadError(
                code: .invalidLimit,
                message: "The project viewport snapshot \(label) count cannot be negative."
            )
        }
        let addition = current.addingReportingOverflow(count)
        guard !addition.overflow,
              addition.partialValue <= maximum else {
            throw ProjectMeshReadError(
                code: .limitExceeded,
                message: "The project viewport snapshot exceeds the \(label) limit."
            )
        }
        return addition.partialValue
    }
}
