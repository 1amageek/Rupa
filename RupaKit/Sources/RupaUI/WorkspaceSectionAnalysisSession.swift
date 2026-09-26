import RupaCore
import SwiftCAD

/// Section Analysis while its dialog is up: where the section plane comes from, how far it is
/// moved along its normal and which way it faces.
///
/// The section keeps what lies behind the plane and cuts away what its normal points toward, so
/// Flip shows the other side. Confirming turns the plane into a fixed slice that stays until the
/// command is run again.
struct WorkspaceSectionAnalysisSession: Equatable, Sendable {
    enum PlaneSource: String, CaseIterable, Identifiable, Sendable {
        /// The face selected when the command began.
        case selection
        /// The plane of the previous confirmed section.
        case previous
        /// The active construction plane.
        case constructionPlane

        var id: String { rawValue }

        var title: String {
            switch self {
            case .selection: "Selection"
            case .previous: "Previous"
            case .constructionPlane: "CPlane"
            }
        }
    }

    /// The planar face selected when the command began, if any.
    let selectedFace: SelectionTarget?
    /// The plane the previous confirmed section cut along, if any.
    let previousPlane: SketchPlane?
    private(set) var planeSource: PlaneSource
    /// How far the plane is moved along the source plane's normal.
    var distanceMeters: Double = 0
    var flipsNormal = false

    init(selectedFace: SelectionTarget?, previousPlane: SketchPlane?) {
        self.selectedFace = selectedFace
        self.previousPlane = previousPlane
        planeSource = selectedFace != nil ? .selection : .constructionPlane
    }

    func offers(_ source: PlaneSource) -> Bool {
        switch source {
        case .selection: selectedFace != nil
        case .previous: previousPlane != nil
        case .constructionPlane: true
        }
    }

    /// Chooses where the plane comes from; the distance and direction start over.
    mutating func choose(_ source: PlaneSource) throws {
        guard offers(source) else {
            throw EditorError(
                code: .commandInvalid,
                message: source == .selection
                    ? "Select a planar face before starting Section Analysis to section at it."
                    : "No section has been placed yet, so there is no previous plane."
            )
        }
        planeSource = source
        distanceMeters = 0
        flipsNormal = false
    }

    mutating func toggleFlip() {
        flipsNormal.toggle()
    }

    /// The analysis the session shows, sectioning at `constructionPlane` when that is the source.
    func query(constructionPlane: SketchPlane) -> SectionAnalysisQuery {
        let source: SectionAnalysisQuery.Source = switch planeSource {
        case .selection: selectedFace.map { .face($0) } ?? .sketchPlane(constructionPlane)
        case .previous: .sketchPlane(previousPlane ?? constructionPlane)
        case .constructionPlane: .sketchPlane(constructionPlane)
        }
        return SectionAnalysisQuery(
            source: source,
            offsetMeters: distanceMeters,
            flipsNormal: flipsNormal,
            clipping: SectionAnalysisClippingRequest(retainedSide: Self.retainedSide)
        )
    }

    /// A confirmed section is a fixed plane: it no longer follows the face or construction plane
    /// it was placed from.
    static func placedQuery(for result: SectionAnalysisResult) -> SectionAnalysisQuery {
        SectionAnalysisQuery(
            source: .sketchPlane(placedPlane(for: result)),
            clipping: SectionAnalysisClippingRequest(retainedSide: retainedSide)
        )
    }

    static func placedPlane(for result: SectionAnalysisResult) -> SketchPlane {
        .plane(Plane3D(origin: result.plane.origin, normal: result.plane.normal))
    }

    /// The section keeps the side behind the plane's normal.
    static let retainedSide = SectionAnalysisRetainedSide.behind

    var prompt: String {
        "Section Analysis: D sets the distance, F flips, Return or right-click places the slice, Esc cancels."
    }
}
