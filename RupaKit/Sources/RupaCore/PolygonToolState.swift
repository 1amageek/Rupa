import Foundation

public struct PolygonToolState: Codable, Equatable, Sendable {
    public enum Failure: Swift.Error, Equatable, Sendable {
        case invalidSideCount(Int)

        public var message: String {
            switch self {
            case .invalidSideCount:
                "Polygon side count must be between 3 and 256."
            }
        }
    }

    public static let minimumSideCount = 3
    public static let maximumSideCount = 256
    public static let defaultSideCount = CanvasSketchCurveDrafts.defaultPolygonSides

    public static let standard = PolygonToolState(
        uncheckedSideCount: defaultSideCount,
        sizingMode: .circumradius,
        inclinationMode: .vertical,
        cutsFaces: false
    )

    public private(set) var sideCount: Int
    public var sizingMode: PolygonSizingMode
    public var inclinationMode: PolygonInclinationMode
    public var cutsFaces: Bool

    public init(
        sideCount: Int,
        sizingMode: PolygonSizingMode = .circumradius,
        inclinationMode: PolygonInclinationMode = .vertical,
        cutsFaces: Bool = false
    ) throws {
        guard Self.isValidSideCount(sideCount) else {
            throw Failure.invalidSideCount(sideCount)
        }
        self.sideCount = sideCount
        self.sizingMode = sizingMode
        self.inclinationMode = inclinationMode
        self.cutsFaces = cutsFaces
    }

    private init(
        uncheckedSideCount sideCount: Int,
        sizingMode: PolygonSizingMode,
        inclinationMode: PolygonInclinationMode,
        cutsFaces: Bool
    ) {
        self.sideCount = sideCount
        self.sizingMode = sizingMode
        self.inclinationMode = inclinationMode
        self.cutsFaces = cutsFaces
    }

    public var canDecreaseSideCount: Bool {
        sideCount > Self.minimumSideCount
    }

    public var canIncreaseSideCount: Bool {
        sideCount < Self.maximumSideCount
    }

    public mutating func setSideCount(_ sideCount: Int) throws {
        guard Self.isValidSideCount(sideCount) else {
            throw Failure.invalidSideCount(sideCount)
        }
        self.sideCount = sideCount
    }

    public mutating func adjustSideCount(by delta: Int) throws {
        try setSideCount(sideCount + delta)
    }

    public mutating func setSizingMode(_ sizingMode: PolygonSizingMode) {
        self.sizingMode = sizingMode
    }

    public mutating func toggleSizingMode() {
        switch sizingMode {
        case .circumradius:
            sizingMode = .inradius
        case .inradius:
            sizingMode = .circumradius
        }
    }

    public mutating func setInclinationMode(_ inclinationMode: PolygonInclinationMode) {
        self.inclinationMode = inclinationMode
    }

    public mutating func toggleInclinationMode() {
        inclinationMode = inclinationMode.toggled()
    }

    public mutating func setCutsFaces(_ cutsFaces: Bool) {
        self.cutsFaces = cutsFaces
    }

    public mutating func toggleCutsFaces() {
        cutsFaces.toggle()
    }

    public static func isValidSideCount(_ sideCount: Int) -> Bool {
        sideCount >= minimumSideCount && sideCount <= maximumSideCount
    }
}
