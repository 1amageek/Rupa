/// The bounded surface presentation modes supported by the viewport renderer.
///
/// This value changes only the native display pass. It does not change the
/// scene snapshot, source/evaluation authority, section clipping, or picking.
public enum ViewportDisplayMode: String, CaseIterable, Hashable, Sendable {
    case solid
    case solidWithEdges
    case wireframe
    case normals
}
