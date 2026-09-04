import Foundation
import OSLog

/// The signpost identities the responsiveness acceptance table is measured
/// against in a signed build.
///
/// The table charges two `MainActor` intervals to a frame: the presentation
/// plan publication the view body performs, and the Canvas consumption SwiftUI
/// drives. Both are emitted under one subsystem and category so a single
/// `xctrace` or Instruments filter selects them together.
///
/// The offline harness in `RupaResponsivenessBaseline` measures only the
/// presentation portion of a Canvas pass, so its Canvas figure is a lower bound
/// of the interval recorded here. A harness rejection therefore stays valid for
/// the application, while a harness acceptance does not.
enum ViewportResponsivenessSignposts {
    /// The subsystem an Instruments filter selects.
    static let subsystem = "RupaRendering"

    /// The category both intervals share.
    static let category = "Responsiveness"

    /// The interval covering one presentation plan publication.
    static let planPublicationName: StaticString = "PresentationPlanPublication"

    /// The interval covering one Canvas consumption of the published plan.
    static let canvasConsumptionName: StaticString = "ViewportCanvasConsumption"

    static let signposter = OSSignposter(subsystem: subsystem, category: category)

    /// Records the publication interval around `body` and returns its value
    /// unchanged, so instrumenting the call cannot alter what the view body
    /// publishes.
    static func withPlanPublicationInterval<Value>(_ body: () -> Value) -> Value {
        let state = signposter.beginInterval(
            planPublicationName,
            id: signposter.makeSignpostID()
        )
        defer { signposter.endInterval(planPublicationName, state) }
        return body()
    }

    /// Opens the Canvas consumption interval. The interval is opened and closed
    /// separately rather than wrapped, because the Canvas renderer receives an
    /// `inout GraphicsContext` that cannot cross a generic closure boundary.
    static func beginCanvasConsumption() -> OSSignpostIntervalState {
        signposter.beginInterval(
            canvasConsumptionName,
            id: signposter.makeSignpostID()
        )
    }

    static func endCanvasConsumption(_ state: OSSignpostIntervalState) {
        signposter.endInterval(canvasConsumptionName, state)
    }
}
