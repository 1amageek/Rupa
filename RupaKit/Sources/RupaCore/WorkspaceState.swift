import SwiftCAD
import RupaCoreTypes

public struct WorkspaceState: Sendable {
    public internal(set) var revision: WorkspaceRevision
    public internal(set) var ruler: RulerConfiguration
    public internal(set) var viewportGridSettings: ViewportGridSettings
    public internal(set) var activeConstructionPlaneID: ConstructionPlaneSourceID?
    public internal(set) var curveCurvatureDisplays: [SelectionComponentID: CurveCurvatureDisplay]
    public internal(set) var pointDisplays: [SelectionComponentID: PointDisplay]
    public internal(set) var surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay]
    public internal(set) var surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay]

    public var displayUnit: LengthDisplayUnit {
        ruler.displayUnit
    }

    public init(
        revision: WorkspaceRevision = WorkspaceRevision(),
        ruler: RulerConfiguration = .standard(for: .millimeter),
        viewportGridSettings: ViewportGridSettings = .standard,
        activeConstructionPlaneID: ConstructionPlaneSourceID? = nil,
        curveCurvatureDisplays: [SelectionComponentID: CurveCurvatureDisplay] = [:],
        pointDisplays: [SelectionComponentID: PointDisplay] = [:],
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay] = [:],
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay] = [:]
    ) {
        self.revision = revision
        self.ruler = ruler.normalizedForWorkspaceScale()
        self.viewportGridSettings = viewportGridSettings
        self.activeConstructionPlaneID = activeConstructionPlaneID
        self.curveCurvatureDisplays = curveCurvatureDisplays
        self.pointDisplays = pointDisplays
        self.surfaceControlPointDisplays = surfaceControlPointDisplays
        self.surfaceFrameDisplays = surfaceFrameDisplays
    }

    public mutating func apply(
        _ command: WorkspaceCommand,
        document: DesignDocument
    ) throws -> WorkspaceCommandResult {
        var updated = self
        try updated.applyWithoutRevision(command, document: document)
        try updated.validate(against: document)
        updated.revision = try revision.advanced()
        self = updated
        return WorkspaceCommandResult(
            commandName: command.name,
            revision: revision
        )
    }

    public func requireRevision(_ expectedRevision: WorkspaceRevision?) throws {
        guard let expectedRevision else {
            return
        }
        guard expectedRevision == revision else {
            throw EditorError(
                code: .workspaceRevisionMismatch,
                message: "Expected workspace revision \(expectedRevision.value), but current revision is \(revision.value)."
            )
        }
    }

    public mutating func pruneMissingReferences(in document: DesignDocument) {
        if let activeConstructionPlaneID,
           document.productMetadata.constructionPlanes[activeConstructionPlaneID] == nil {
            self.activeConstructionPlaneID = nil
        }
        curveCurvatureDisplays = curveCurvatureDisplays.filter { _, display in
            isValid { try display.validate(against: document.cadDocument) }
        }
        pointDisplays = pointDisplays.filter { _, display in
            isValid { try display.validate(against: document.cadDocument) }
        }
        surfaceControlPointDisplays = surfaceControlPointDisplays.filter { _, display in
            isValid { try display.validate(against: document.cadDocument) }
        }
        surfaceFrameDisplays = surfaceFrameDisplays.filter { _, display in
            isValid {
                try display.validate()
                _ = try SurfaceFrameService().resolveFrames(
                    document: document,
                    queries: [display.query]
                )
            }
        }
    }

    public func validate(against document: DesignDocument) throws {
        try ruler.validate()
        if let activeConstructionPlaneID,
           document.productMetadata.constructionPlanes[activeConstructionPlaneID] == nil {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Active construction plane requires an existing source plane."
            )
        }
        for display in curveCurvatureDisplays.values {
            try display.validate(against: document.cadDocument)
        }
        for display in pointDisplays.values {
            try display.validate(against: document.cadDocument)
        }
        for display in surfaceControlPointDisplays.values {
            try display.validate(against: document.cadDocument)
        }
        for display in surfaceFrameDisplays.values {
            try display.validate()
            _ = try SurfaceFrameService().resolveFrames(
                document: document,
                queries: [display.query]
            )
        }
    }

    private mutating func applyWithoutRevision(
        _ command: WorkspaceCommand,
        document: DesignDocument
    ) throws {
        switch command {
        case .setDisplayUnit(let unit):
            ruler = ruler.replacingDisplayUnit(unit)
        case .setRulerConfiguration(let configuration):
            try configuration.validate()
            ruler = configuration
        case .setViewportGridSettings(let settings):
            viewportGridSettings = settings
        case .setActiveConstructionPlane(let id):
            activeConstructionPlaneID = id
        case .setCurveCurvatureDisplay(let target, let isVisible, let combScale):
            try setCurveCurvatureDisplay(
                target: target,
                isVisible: isVisible,
                combScale: combScale,
                document: document
            )
        case .setPointDisplay(let target, let isVisible):
            try setPointDisplay(
                target: target,
                isVisible: isVisible,
                document: document
            )
        case .setSurfaceControlPointDisplay(let target, let isVisible):
            try setSurfaceControlPointDisplay(
                target: target,
                isVisible: isVisible,
                document: document
            )
        case .setSurfaceFrameDisplay(let query, let isVisible):
            try setSurfaceFrameDisplay(
                query: query,
                isVisible: isVisible,
                document: document
            )
        }
    }

    private func isValid(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            return true
        } catch {
            return false
        }
    }
}
