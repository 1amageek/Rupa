import Foundation
import CoreGraphics
import RupaAgentProtocol
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaKit
import Testing
@testable import RupaRendering
@testable import Rupa

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationViewportSessionRejectsForeignSessionsAndChangesWithDocumentLifetime() async throws {
    let registrar = ViewportTestRegistrar()
    let coordinator = ApplicationProjectCoordinator(
        workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(),
        agentRegistrar: registrar
    )
    await coordinator.launch()
    let sessionID = try #require(registrar.sessionID)
    let initial = try coordinator.requireViewportDocumentLifetime(sessionID: sessionID)
    #expect(throws: EditorError.self) {
        try coordinator.requireViewportDocumentLifetime(sessionID: UUID())
    }

    await coordinator.newProject(named: "Viewport Replacement")

    let replacement = try coordinator.requireViewportDocumentLifetime(sessionID: sessionID)
    #expect(initial != replacement)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationViewportRouterForwardsOrdinaryRequestsWithoutChangingTheirEnvelope() async throws {
    let registrar = ViewportTestRegistrar()
    let coordinator = ApplicationProjectCoordinator(
        workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(),
        agentRegistrar: registrar
    )
    let registry = ApplicationViewportRegistry(coordinator: coordinator)
    let probe = ViewportDownstreamProbe()
    let router = ApplicationViewportRequestRouter(downstream: probe, viewports: registry)
    let envelope = AgentRequestEnvelope(id: "viewport-forwarding", params: .status)

    let response = await router.handle(envelope)

    #expect(await probe.requests == [envelope])
    guard case .ordinary(.status(let status)) = response else {
        Issue.record("The viewport adapter changed the downstream response.")
        return
    }
    #expect(status.running)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationViewportControlTargetsOneMountedWindowAndNeverPublishesProjectState() async throws {
    let registrar = ViewportTestRegistrar()
    let coordinator = ApplicationProjectCoordinator(
        workspace: try DefaultProjectWorkspaceFactory().makeWorkspace(),
        agentRegistrar: registrar
    )
    await coordinator.launch()
    let sessionID = try #require(registrar.sessionID)
    let before = try #require(coordinator.snapshot)
    let registry = ApplicationViewportRegistry(coordinator: coordinator)
    let first = try mountedViewportControl()
    let second = try mountedViewportControl()
    registry.mount(lifetime: before.documentLifetimeID, control: first)
    registry.mount(lifetime: before.documentLifetimeID, control: second)
    #expect(try registry.list(sessionID: sessionID).count == 2)

    let probe = ViewportDownstreamProbe()
    let router = ApplicationViewportRequestRouter(downstream: probe, viewports: registry)
    let response = await router.handle(AgentRequestEnvelope(
        id: "viewport-execute", params: .executeViewport(
            sessionID: sessionID, viewportID: first.id.rawValue,
            expectedViewportRevision: first.revision, operation: .zoom(factor: 2)
        )
    ))
    guard case .ordinary(.viewportExecution(let applied)) = response else {
        Issue.record("The viewport request did not reach the mounted control.")
        return
    }
    #expect(await probe.requests.isEmpty)
    #expect(applied.zoomFactor == 2)
    #expect(try second.snapshot().camera.zoom == 1)
    #expect(throws: ViewportControlError.self) {
        try registry.execute(
            sessionID: sessionID, viewportID: first.id.rawValue,
            expectedRevision: applied.revision - 1, operation: .pan(deltaXPoints: 25, deltaYPoints: 0)
        )
    }
    #expect(try registry.state(sessionID: sessionID, viewportID: first.id.rawValue) == applied)
    #expect(coordinator.snapshot?.authorityCoordinate == before.authorityCoordinate)
    #expect(coordinator.snapshot?.isDirty == before.isDirty)
    #expect(coordinator.snapshot?.canUndo == before.canUndo)
    #expect(coordinator.snapshot?.workspaceState.ruler == before.workspaceState.ruler)

    let cancelled = Task { @MainActor in
        try registry.execute(
            sessionID: sessionID, viewportID: first.id.rawValue,
            expectedRevision: nil, operation: .pan(deltaXPoints: 30, deltaYPoints: 0)
        )
    }
    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(try registry.state(sessionID: sessionID, viewportID: first.id.rawValue) == applied)

    let perspective = try registry.execute(
        sessionID: sessionID, viewportID: first.id.rawValue,
        expectedRevision: applied.revision, operation: .setProjection(.perspective)
    )
    #expect(perspective.projection == .perspective)
    #expect(perspective.fieldOfViewRadians != nil)
    #expect(perspective.zoomFactor == applied.zoomFactor)
    #expect(perspective.orientation == applied.orientation)
    #expect(try second.snapshot().camera.projection == .parallel)
    _ = try first.perform(.setProjection(.perspective(fieldOfViewRadians: 0.9)))
    let custom = try registry.state(sessionID: sessionID, viewportID: first.id.rawValue)
    #expect(try registry.execute(
        sessionID: sessionID, viewportID: first.id.rawValue,
        expectedRevision: custom.revision, operation: .setProjection(.perspective)
    ) == custom)
    #expect(custom.fieldOfViewRadians == 0.9)
    let parallel = try registry.execute(
        sessionID: sessionID, viewportID: first.id.rawValue,
        expectedRevision: custom.revision, operation: .setProjection(.parallel)
    )
    #expect(parallel.projection == .parallel)
    #expect(parallel.fieldOfViewRadians == nil)
    #expect(coordinator.snapshot?.authorityCoordinate == before.authorityCoordinate)
    #expect(coordinator.snapshot?.isDirty == before.isDirty)

    let panned = try registry.execute(sessionID: sessionID, viewportID: first.id.rawValue,
        expectedRevision: nil, operation: .pan(deltaXPoints: 80, deltaYPoints: -30))
    #expect(panned.focusXMeters != parallel.focusXMeters || panned.focusZMeters != parallel.focusZMeters)
    let turned = try registry.execute(sessionID: sessionID, viewportID: first.id.rawValue,
        expectedRevision: panned.revision, operation: .orbit(yawDeltaDegrees: 90, elevationDeltaDegrees: 0))
    #expect(turned.focusXMeters == panned.focusXMeters)
    #expect(turned.focusYMeters == panned.focusYMeters)
    #expect(turned.focusZMeters == panned.focusZMeters)
    #expect(coordinator.snapshot?.authorityCoordinate == before.authorityCoordinate)
    #expect(coordinator.snapshot?.isDirty == before.isDirty)
    registry.unmount(first.id)
    #expect(throws: EditorError.self) {
        try registry.state(sessionID: sessionID, viewportID: first.id.rawValue)
    }
    #expect(try registry.list(sessionID: sessionID).map(\.viewportID) == [second.id.rawValue])

    var extraWindows: [ViewportControlSession] = []
    for _ in 1..<AgentViewportState.maximumListCount {
        let window = try mountedViewportControl()
        extraWindows.append(window)
        registry.mount(lifetime: before.documentLifetimeID, control: window)
    }
    #expect(try registry.list(sessionID: sessionID).count == AgentViewportState.maximumListCount)
    let overflowWindow = try mountedViewportControl()
    registry.mount(lifetime: before.documentLifetimeID, control: overflowWindow)
    #expect(throws: EditorError.self) { try registry.list(sessionID: sessionID) }

    await coordinator.newProject(named: "New Viewport Lifetime")
    #expect(try registry.list(sessionID: sessionID).isEmpty)
    let replacement = try #require(coordinator.snapshot)
    let current = try mountedViewportControl()
    registry.mount(lifetime: replacement.documentLifetimeID, control: current)
    #expect(try registry.list(sessionID: sessionID).map(\.viewportID) == [current.id.rawValue])
    registry.unmount(overflowWindow.id)
    for window in extraWindows { registry.unmount(window.id) }
    #expect(try registry.list(sessionID: sessionID).map(\.viewportID) == [current.id.rawValue])
    #expect(throws: EditorError.self) {
        try registry.execute(
            sessionID: sessionID, viewportID: second.id.rawValue,
            expectedRevision: nil, operation: .fitVisible
        )
    }
}

@MainActor
private func mountedViewportControl() throws -> ViewportControlSession {
    let control = ViewportControlSession()
    let mountID = ViewportInstanceID()
    control.mount(viewportID: mountID)
    control.updateContext(ViewportControlMountContext(
        viewportID: mountID,
        viewportSize: CGSize(width: 900, height: 700), fittingInsets: .zero,
        modelBounds: CGRect(x: -10, y: -10, width: 20, height: 20),
        verticalBounds: -1...1, ruler: .standard(for: .millimeter),
        sceneBounds: try GeometryBounds3D(
            minimum: .init(x: -1, y: -1, z: -1), maximum: .init(x: 1, y: 1, z: 1)
        ),
        selectedBounds: nil
    ))
    return control
}

@MainActor
private final class ViewportTestRegistrar: ApplicationAgentSessionRegistering {
    private(set) var sessionID: UUID?

    func register(workspace: ProjectWorkspace, path: URL?, id: UUID) async throws -> UUID {
        sessionID = id
        return id
    }

    func updatePath(id: UUID, path: URL?) async throws {
        guard sessionID == id else {
            throw EditorError(code: .sessionNotFound, message: "Test session does not exist.")
        }
    }

    func unregister(id: UUID) async {
        if sessionID == id { sessionID = nil }
    }
}

private actor ViewportDownstreamProbe: AgentRequestHandling {
    private(set) var requests: [AgentRequestEnvelope] = []

    func handle(_ envelope: AgentRequestEnvelope) async -> AgentHandledResponse {
        requests.append(envelope)
        return .ordinary(.status(AgentStatus(running: true, sessionCount: 0)))
    }
}
