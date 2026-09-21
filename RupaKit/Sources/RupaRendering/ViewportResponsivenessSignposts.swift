import Foundation
import OSLog

/// The signpost identities the responsiveness acceptance table is measured
/// against in a signed build.
///
/// The table charges two `MainActor` intervals to a frame: the presentation
/// plan publication the cache performs when a completed plan reaches its
/// observable state, and the SDK-required `LowLevelMesh` construction and
/// scoped buffer copy the mounted frame performs for one native line payload.
/// Plan construction is not one of them, because it runs off `MainActor`. Both
/// are emitted under one subsystem and category so a single `xctrace` or
/// Instruments filter selects them together.
///
/// The offline measurement harness measures neither
/// interval as the application pays it: it cannot bring up a mounted frame, so
/// it performs no native upload at all, and its publication figure excludes the
/// observation invalidation a live SwiftUI scope adds. That figure is therefore
/// a lower bound of the interval recorded here. A harness rejection stays valid
/// for the application, while a harness acceptance does not.
enum ViewportResponsivenessSignposts {
    /// The subsystem an Instruments filter selects.
    static let subsystem = "RupaRendering"

    /// The category both intervals share.
    static let category = "Responsiveness"

    /// The interval covering one presentation plan publication.
    static let planPublicationName: StaticString = "PresentationPlanPublication"

    /// The interval covering the SDK-required `LowLevelMesh` construction and
    /// scoped buffer copy for one native line payload.
    static let nativeLineUploadName: StaticString = "NativeLineUpload"

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
}
