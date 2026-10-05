import SwiftCAD

public protocol DocumentMassPropertyMeasuring: Sendable {
    func measure(_ components: [MassPropertyComponent], in evaluated: EvaluatedDocument,
                 options: BRepVolumeMomentOptions, reference: Point3D) throws -> MassPropertyMeasurement
}
