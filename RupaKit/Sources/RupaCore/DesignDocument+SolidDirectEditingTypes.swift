import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    enum EditableBodyFace: Equatable {
        case front
        case back
        case top
        case bottom
        case left
        case right
        case side
    }

    enum EditableBodyEdge: Equatable, Hashable {
        case leftBottom
        case rightBottom
        case rightTop
        case leftTop
    }

    enum EditableBodyVertex: Equatable, Hashable {
        case bottomLeft
        case bottomRight
        case topRight
        case topLeft
    }
}
