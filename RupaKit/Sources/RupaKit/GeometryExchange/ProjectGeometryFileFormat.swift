import SwiftCAD

/// File geometry supported by the application's import and export controls.
public enum ProjectGeometryFileFormat: String, CaseIterable, Identifiable, Sendable {
    case step
    case stl
    case obj

    public var id: String { rawValue }
    public var title: String { rawValue.uppercased() }

    var nativeFormat: ExchangeFileFormat {
        switch self {
        case .step: .step
        case .stl: .stl
        case .obj: .obj
        }
    }
}
