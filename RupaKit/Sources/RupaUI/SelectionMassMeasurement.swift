import RupaCore

/// The selected objects' mass, measured off the main actor: the exact volume of a body of many
/// spline spans can take long, and the workspace must stay responsive while it is measured.
///
/// One measurement runs at a time. A request made while one runs waits, replacing any earlier
/// waiting request; a result is delivered only when no newer request (or cancellation) came
/// while it was measured, so a stale mass never reaches the inspector.
///
/// The delivery closure is held only until its result is delivered or superseded, and
/// `cancel()` drops it at once: the closure captures the workspace view, which holds this object,
/// so keeping it would keep a closed workspace alive. A measurement already running cannot be
/// stopped (`MeasurementService` has no cancellation point); until it finishes it holds only its
/// own request.
@MainActor
final class SelectionMassMeasurement {
    typealias Delivery = @MainActor (Result<SceneMass, any Error>) -> Void

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
    /// The newest request's delivery, until it is called or superseded.
    private var delivery: Delivery?

    /// Measures `request`, then hands the result to `deliver` unless it is superseded first.
    func measure(_ request: Request, deliver: @escaping Delivery) {
        revision += 1
        pending = request
        delivery = deliver
        guard !isRunning else { return }
        isRunning = true
        Task { await drain() }
    }

    /// Drops the waiting request, the result of the running one and the delivery closure.
    func cancel() {
        revision += 1
        pending = nil
        delivery = nil
    }

    private func drain() async {
        while let request = pending {
            pending = nil
            let measuredRevision = revision
            let result = await Task.detached(priority: .utility) {
                Self.mass(for: request)
            }.value
            if measuredRevision == revision, let delivery {
                self.delivery = nil
                delivery(result)
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
