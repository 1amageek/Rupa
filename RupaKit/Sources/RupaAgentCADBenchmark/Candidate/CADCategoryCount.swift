public struct CADCategoryCount: Codable, Equatable, Hashable, Sendable {
    public let category: CADBenchmarkCategory
    public let count: Int

    public init(category: CADBenchmarkCategory, count: Int) {
        self.category = category
        self.count = count
    }
}
