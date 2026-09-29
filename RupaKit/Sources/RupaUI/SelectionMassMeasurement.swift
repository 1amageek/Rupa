import RupaCore

/// The selected objects' mass, measured off the main actor: the exact volume of a body of many
/// spline spans can take long, and the workspace must stay responsive while it is measured.
///
/// One measurement runs at a time. A request made while one runs waits, replacing any earlier
/// waiting request; a result is delivered only when no newer request (or cancellation) came
/// while it was measured, so a stale mass never reaches the inspector.
@MainActor
final class SelectionMassMeasurement {
    struct Request: Sendable {
        var document: DesignDocument
        var selection: SelectionModel
        var ruler: RulerConfiguration
        var objectRegistry: ObjectTypeRegistry
        var evaluation: DocumentEvaluationContext?
        var generation: DocumentGeneration
    }

    private var pending: Request?
    private var isRunning = false
    /// Advances with every request and cancellation; a result measured under an older value is
    /// dropped.
    private var revision = 0
    private var deliver: (@MainActor (Result<SceneMass, any Error>) -> Void)?

    /// Measures `request`, then hands the result to `deliver` unless it is superseded first.
    func measure(_ request: Request, deliver: @escaping @MainActor (Result<SceneMass, any Error>) -> Void) {
        revision += 1
        pending = request
        self.deliver = deliver
        guard !isRunning else { return }
        isRunning = true
        Task { await drain() }
    }

    /// Drops the waiting request and the result of the running one.
    func cancel() {
        revision += 1
        pending = nil
    }

    private func drain() async {
        while let request = pending {
            pending = nil
            let measuredRevision = revision
            let result = await Task.detached(priority: .utility) {
                Self.mass(for: request)
            }.value
            if measuredRevision == revision {
                deliver?(result)
            }
        }
        isRunning = false
    }

    private nonisolated static func mass(for request: Request) -> Result<SceneMass, any Error> {
        Result {
            let measurement = try MeasurementService().measure(
                document: request.document,
                selection: request.selection,
                ruler: request.ruler,
                objectRegistry: request.objectRegistry,
                currentEvaluation: request.evaluation,
                currentGeneration: request.generation
            )
            return try request.document.mass(of: measurement)
        }
    }
}
