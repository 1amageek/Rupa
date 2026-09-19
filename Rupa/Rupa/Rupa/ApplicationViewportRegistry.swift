import CADCore
import Foundation
import RupaAgentProtocol
import RupaCoreTypes
import RupaKit
import RupaProject
import RupaRendering

/// Binds transient window controls to the existing project session authority.
@MainActor
final class ApplicationViewportRegistry {
    private let coordinator: ApplicationProjectCoordinator
    private var mountedLifetime: ProjectDocumentLifetimeID?
    private var entries: [UUID: ViewportControlSession] = [:]

    init(coordinator: ApplicationProjectCoordinator) {
        self.coordinator = coordinator
    }

    func mount(lifetime: ProjectDocumentLifetimeID, control: ViewportControlSession) {
        guard coordinator.snapshot?.documentLifetimeID == lifetime else { return }
        if mountedLifetime != lifetime {
            entries.removeAll()
            mountedLifetime = lifetime
        }
        entries[control.id.rawValue] = control
    }

    func unmount(_ id: ViewportInstanceID) {
        entries.removeValue(forKey: id.rawValue)
    }

    func list(sessionID: UUID) throws -> [AgentViewportState] {
        try Task.checkCancellation()
        let lifetime = try coordinator.requireViewportDocumentLifetime(sessionID: sessionID)
        guard mountedLifetime == lifetime else { return [] }
        try AgentViewportState.validateListCount(entries.count)
        return try entries.values
            .filter { $0.isReady }
            .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
            .map { try Self.wireState($0.snapshot()) }
    }

    func state(sessionID: UUID, viewportID: UUID) throws -> AgentViewportState {
        try Task.checkCancellation()
        return try Self.wireState(control(sessionID: sessionID, viewportID: viewportID).snapshot())
    }

    func execute(
        sessionID: UUID, viewportID: UUID, expectedRevision: UInt64?,
        operation: AgentViewportOperation
    ) throws -> AgentViewportState {
        try Task.checkCancellation()
        try operation.validate()
        let control = try control(sessionID: sessionID, viewportID: viewportID)
        let action = try Self.action(operation, control: control)
        // There is no suspension between identity validation and state application.
        return try Self.wireState(control.perform(action, expectedRevision: expectedRevision))
    }

    private func control(sessionID: UUID, viewportID: UUID) throws -> ViewportControlSession {
        let lifetime = try coordinator.requireViewportDocumentLifetime(sessionID: sessionID)
        guard mountedLifetime == lifetime, let control = entries[viewportID],
              control.isMounted else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Viewport \(viewportID.uuidString) is not mounted in this document. Refresh viewport.list."
            )
        }
        return control
    }

    private static func action(
        _ operation: AgentViewportOperation,
        control: ViewportControlSession
    ) throws -> ViewportControlAction {
        switch operation {
        case .fitVisible: .fitVisible
        case .fitSelected: .fitSelected
        case let .orbit(yaw, elevation):
            .orbit(yawDeltaDegrees: yaw, elevationDeltaDegrees: elevation)
        case let .pan(x, y): .pan(deltaXPoints: x, deltaYPoints: y)
        case .zoom(let factor): .zoom(factor: factor)
        case .resetCamera: .resetCamera
        case .setProjection(let projection):
            switch projection {
            case .parallel: .setProjection(.parallel)
            case .perspective:
                .setProjection(control.camera.projection == .parallel ? .standardPerspective : control.camera.projection)
            }
        case .setOrientation(let orientation):
            switch orientation {
            case .isometric: .setOrientation(.isometric)
            case .xFront: .setOrientation(.xFront)
            case .yFront: .setOrientation(.yFront)
            case .zFront: .setOrientation(.zFront)
            case .custom:
                throw EditorError(code: .commandInvalid, message: "Custom orientation is read-only.")
            }
        case .setDisplayMode(let mode):
            switch mode {
            case .solid: .setDisplayMode(.solid)
            case .solidWithEdges: .setDisplayMode(.solidWithEdges)
            case .wireframe: .setDisplayMode(.wireframe)
            case .normals: .setDisplayMode(.normals)
            }
        }
    }

    private static func wireState(_ state: ViewportControlSnapshot) throws -> AgentViewportState {
        let orientation: AgentViewportOrientation
        switch state.basis.mode {
        case .isometric: orientation = .isometric
        case .axisFront(.x): orientation = .xFront
        case .axisFront(.y): orientation = .yFront
        case .axisFront(.z): orientation = .zFront
        case .orbit: orientation = .custom
        }
        let mode: AgentViewportDisplayMode
        switch state.displayMode {
        case .solid: mode = .solid
        case .solidWithEdges: mode = .solidWithEdges
        case .wireframe: mode = .wireframe
        case .normals: mode = .normals
        }
        let projection: AgentViewportProjection
        let fieldOfViewRadians: Double?
        switch state.camera.projection {
        case .parallel:
            projection = .parallel
            fieldOfViewRadians = nil
        case .perspective(let value):
            projection = .perspective
            fieldOfViewRadians = value
        }
        guard let focus = state.camera.focus, focus.isFinite else {
            throw EditorError(code: .commandFailed, message: "Viewport camera focus is unavailable.")
        }
        let result = AgentViewportState(
            viewportID: state.id.rawValue, revision: state.revision,
            projection: projection, fieldOfViewRadians: fieldOfViewRadians,
            viewportWidthPoints: Double(state.viewportSize.width),
            viewportHeightPoints: Double(state.viewportSize.height),
            canFitVisible: state.canFitVisible, canFitSelected: state.canFitSelected,
            orientation: orientation,
            yawDegrees: Double(state.basis.orbitYawRadians) * 180 / .pi,
            elevationDegrees: Double(state.basis.orbitElevationRadians) * 180 / .pi,
            panXPoints: Double(state.camera.pan.width), panYPoints: Double(state.camera.pan.height),
            zoomFactor: Double(state.camera.zoom),
            xDirection: .init(dx: Double(state.basis.xDirection.dx), dy: Double(state.basis.xDirection.dy)),
            yDirection: .init(dx: Double(state.basis.yDirection.dx), dy: Double(state.basis.yDirection.dy)),
            zDirection: .init(dx: Double(state.basis.zDirection.dx), dy: Double(state.basis.zDirection.dy)),
            displayMode: mode,
            focusXMeters: focus.x, focusYMeters: focus.y, focusZMeters: focus.z
        )
        try result.validate()
        return result
    }
}
