import Foundation
import RupaCore

/// Compact applied state returned by the viewport control API.
public struct AgentViewportState: Codable, Equatable, Sendable {
    /// Admission ceiling for viewport discovery before collecting or sorting states.
    public static let maximumListCount = 64

    public static func validateListCount(_ count: Int) throws {
        guard count <= maximumListCount else {
            throw EditorError(
                code: .commandFailed,
                message: "Viewport discovery supports at most \(maximumListCount) mounted windows. Close unused windows and retry."
            )
        }
    }

    public let viewportID: UUID
    public let revision: UInt64
    public let projection: AgentViewportProjection
    public let fieldOfViewRadians: Double?
    public let viewportWidthPoints: Double
    public let viewportHeightPoints: Double
    public let canFitVisible: Bool
    public let canFitSelected: Bool
    public let orientation: AgentViewportOrientation
    public let yawDegrees: Double
    public let elevationDegrees: Double
    public let panXPoints: Double
    public let panYPoints: Double
    public let zoomFactor: Double
    public let xDirection: AgentViewportDirection2D
    public let yDirection: AgentViewportDirection2D
    public let zDirection: AgentViewportDirection2D
    public let displayMode: AgentViewportDisplayMode
    public let focusXMeters: Double
    public let focusYMeters: Double
    public let focusZMeters: Double

    private enum CodingKeys: String, CodingKey {
        case viewportID
        case revision
        case projection
        case fieldOfViewRadians
        case viewportWidthPoints
        case viewportHeightPoints
        case canFitVisible
        case canFitSelected
        case orientation
        case yawDegrees
        case elevationDegrees
        case panXPoints
        case panYPoints
        case zoomFactor
        case xDirection
        case yDirection
        case zDirection
        case displayMode
        case focusXMeters, focusYMeters, focusZMeters
    }

    public init(
        viewportID: UUID,
        revision: UInt64,
        projection: AgentViewportProjection = .parallel,
        fieldOfViewRadians: Double? = nil,
        viewportWidthPoints: Double,
        viewportHeightPoints: Double,
        canFitVisible: Bool,
        canFitSelected: Bool,
        orientation: AgentViewportOrientation,
        yawDegrees: Double,
        elevationDegrees: Double,
        panXPoints: Double,
        panYPoints: Double,
        zoomFactor: Double,
        xDirection: AgentViewportDirection2D,
        yDirection: AgentViewportDirection2D,
        zDirection: AgentViewportDirection2D,
        displayMode: AgentViewportDisplayMode,
        focusXMeters: Double = 0,
        focusYMeters: Double = 0,
        focusZMeters: Double = 0
    ) {
        self.viewportID = viewportID
        self.revision = revision
        self.projection = projection
        self.fieldOfViewRadians = fieldOfViewRadians
        self.viewportWidthPoints = viewportWidthPoints
        self.viewportHeightPoints = viewportHeightPoints
        self.canFitVisible = canFitVisible
        self.canFitSelected = canFitSelected
        self.orientation = orientation
        self.yawDegrees = yawDegrees
        self.elevationDegrees = elevationDegrees
        self.panXPoints = panXPoints
        self.panYPoints = panYPoints
        self.zoomFactor = zoomFactor
        self.xDirection = xDirection
        self.yDirection = yDirection
        self.zDirection = zDirection
        self.displayMode = displayMode
        self.focusXMeters = focusXMeters
        self.focusYMeters = focusYMeters
        self.focusZMeters = focusZMeters
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: [
                "viewportID",
                "revision",
                "projection",
                "fieldOfViewRadians",
                "viewportWidthPoints",
                "viewportHeightPoints",
                "canFitVisible",
                "canFitSelected",
                "orientation",
                "yawDegrees",
                "elevationDegrees",
                "panXPoints",
                "panYPoints",
                "zoomFactor",
                "xDirection",
                "yDirection",
                "zDirection",
                "displayMode",
                "focusXMeters", "focusYMeters", "focusZMeters",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            viewportID: try container.decode(UUID.self, forKey: .viewportID),
            revision: try container.decode(UInt64.self, forKey: .revision),
            projection: try container.decode(AgentViewportProjection.self, forKey: .projection),
            fieldOfViewRadians: try container.decodeIfPresent(Double.self, forKey: .fieldOfViewRadians),
            viewportWidthPoints: try container.decode(Double.self, forKey: .viewportWidthPoints),
            viewportHeightPoints: try container.decode(Double.self, forKey: .viewportHeightPoints),
            canFitVisible: try container.decode(Bool.self, forKey: .canFitVisible),
            canFitSelected: try container.decode(Bool.self, forKey: .canFitSelected),
            orientation: try container.decode(AgentViewportOrientation.self, forKey: .orientation),
            yawDegrees: try container.decode(Double.self, forKey: .yawDegrees),
            elevationDegrees: try container.decode(Double.self, forKey: .elevationDegrees),
            panXPoints: try container.decode(Double.self, forKey: .panXPoints),
            panYPoints: try container.decode(Double.self, forKey: .panYPoints),
            zoomFactor: try container.decode(Double.self, forKey: .zoomFactor),
            xDirection: try container.decode(AgentViewportDirection2D.self, forKey: .xDirection),
            yDirection: try container.decode(AgentViewportDirection2D.self, forKey: .yDirection),
            zDirection: try container.decode(AgentViewportDirection2D.self, forKey: .zDirection),
            displayMode: try container.decode(AgentViewportDisplayMode.self, forKey: .displayMode),
            focusXMeters: try container.decode(Double.self, forKey: .focusXMeters),
            focusYMeters: try container.decode(Double.self, forKey: .focusYMeters),
            focusZMeters: try container.decode(Double.self, forKey: .focusZMeters)
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(viewportID, forKey: .viewportID)
        try container.encode(revision, forKey: .revision)
        try container.encode(projection, forKey: .projection)
        try container.encodeIfPresent(fieldOfViewRadians, forKey: .fieldOfViewRadians)
        try container.encode(viewportWidthPoints, forKey: .viewportWidthPoints)
        try container.encode(viewportHeightPoints, forKey: .viewportHeightPoints)
        try container.encode(canFitVisible, forKey: .canFitVisible)
        try container.encode(canFitSelected, forKey: .canFitSelected)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(yawDegrees, forKey: .yawDegrees)
        try container.encode(elevationDegrees, forKey: .elevationDegrees)
        try container.encode(panXPoints, forKey: .panXPoints)
        try container.encode(panYPoints, forKey: .panYPoints)
        try container.encode(zoomFactor, forKey: .zoomFactor)
        try container.encode(xDirection, forKey: .xDirection)
        try container.encode(yDirection, forKey: .yDirection)
        try container.encode(zDirection, forKey: .zDirection)
        try container.encode(displayMode, forKey: .displayMode)
        try container.encode(focusXMeters, forKey: .focusXMeters)
        try container.encode(focusYMeters, forKey: .focusYMeters)
        try container.encode(focusZMeters, forKey: .focusZMeters)
    }

    public func validate() throws {
        switch projection {
        case .parallel:
            guard fieldOfViewRadians == nil else {
                throw EditorError(code: .commandInvalid, message: "Parallel projection must not carry a field of view.")
            }
        case .perspective:
            guard let fieldOfViewRadians, fieldOfViewRadians.isFinite,
                  fieldOfViewRadians > 0, fieldOfViewRadians < .pi else {
                throw EditorError(code: .commandInvalid, message: "Perspective field of view must be finite and between zero and pi radians.")
            }
        }
        guard viewportWidthPoints.isFinite, viewportWidthPoints > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Viewport width must be finite and greater than zero."
            )
        }
        guard viewportHeightPoints.isFinite, viewportHeightPoints > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Viewport height must be finite and greater than zero."
            )
        }
        let cameraValues: [(String, Double)] = [
            ("yawDegrees", yawDegrees),
            ("elevationDegrees", elevationDegrees),
            ("panXPoints", panXPoints),
            ("panYPoints", panYPoints),
            ("focusXMeters", focusXMeters),
            ("focusYMeters", focusYMeters),
            ("focusZMeters", focusZMeters),
        ]
        for (name, value) in cameraValues where !value.isFinite {
            throw EditorError(
                code: .commandInvalid,
                message: "Viewport \(name) must be finite."
            )
        }
        guard zoomFactor.isFinite, zoomFactor > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Viewport zoom factor must be finite and greater than zero."
            )
        }
        try xDirection.validate(named: "xDirection")
        try yDirection.validate(named: "yDirection")
        try zDirection.validate(named: "zDirection")
    }
}
