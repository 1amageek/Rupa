/// The interaction appearance one presentation occurrence is drawn in.
///
/// This is the batch key of a presentation draw pass. The number of batches a
/// pass can produce is the number of cases here, so it is a constant of the
/// module and not a function of the scene's occurrence or triangle count.
public enum MeshSourcePresentationVisualState: Equatable, CaseIterable, Sendable {
    case normal
    case hovered
    case selected
}
