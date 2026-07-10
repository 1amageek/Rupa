public struct ValidationElementRange: Codable, Equatable, Sendable {
    public var startIndex: Int
    public var count: Int

    public init(startIndex: Int, count: Int) {
        self.startIndex = startIndex
        self.count = count
    }

    public var endIndex: Int? {
        let (endIndex, overflow) = startIndex.addingReportingOverflow(count)
        return overflow ? nil : endIndex
    }

    public func validate() throws {
        guard startIndex >= 0 else {
            throw ReferenceValidationError(
                code: .invalidShape,
                message: "Validation element range start indexes must not be negative."
            )
        }
        guard count > 0, endIndex != nil else {
            throw ReferenceValidationError(
                code: .invalidShape,
                message: "Validation element ranges must have a positive non-overflowing count."
            )
        }
    }
}
