import SwiftUI

extension ViewportCoordinateAxis {
    var label: String {
        switch self {
        case .x:
            "X"
        case .y:
            "Y"
        case .z:
            "Z"
        }
    }

    var color: Color {
        switch self {
        case .x:
            Color(red: 1.0, green: 0.32, blue: 0.35)
        case .y:
            Color(red: 0.22, green: 0.82, blue: 0.60)
        case .z:
            Color(red: 0.25, green: 0.58, blue: 1.0)
        }
    }
}
