import SwiftCAD

public struct NativeDocumentMassPropertyMeasurer: DocumentMassPropertyMeasuring {
    private let evaluator: MassPropertyEvaluator
    public init(tolerance: ModelingTolerance) { evaluator = MassPropertyEvaluator(tolerance: tolerance) }
    public func measure(_ components: [MassPropertyComponent], in evaluated: EvaluatedDocument,
                        options: BRepVolumeMomentOptions, reference: Point3D) throws -> MassPropertyMeasurement {
        try evaluator.measure(components, in: evaluated, options: options, modelLengthUnit: .meter, reference: reference)
    }
}
