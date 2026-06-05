import SwiftCAD

public extension LengthDisplayUnit {
    var swiftCADLengthUnit: LengthUnit {
        switch self {
        case .micrometer:
            .millimeter
        case .millimeter:
            .millimeter
        case .centimeter:
            .centimeter
        case .meter:
            .meter
        case .inch:
            .inch
        case .foot:
            .foot
        }
    }
}

public extension LengthUnit {
    var rupaDisplayUnit: LengthDisplayUnit {
        switch self {
        case .millimeter:
            .millimeter
        case .centimeter:
            .centimeter
        case .meter:
            .meter
        case .inch:
            .inch
        case .foot:
            .foot
        }
    }
}
