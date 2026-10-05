import SwiftCAD
import RupaCoreTypes

/// Required dimensions from one immutable original document/view/evaluation.
public struct DrawingGeometricAnnotations: Sendable {
    public let values: [DrawingProjectionResult.Annotation]
    public let radialMeasurements: [DrawingRadialDimensionMeasurement]
    public let savedViewID: SavedViewID
    private let sourceDocument: DesignDocument
    private let sourceCADDocument: CADDocument
    private let configuration: DocumentEvaluationConfiguration
    private let brep: BRepModel

    init(values: [DrawingProjectionResult.Annotation], savedViewID: SavedViewID,
         document: DesignDocument, evaluated: EvaluatedDocument,
         radialMeasurements: [DrawingRadialDimensionMeasurement] = []) {
        self.radialMeasurements = radialMeasurements
        self.values = values; self.savedViewID = savedViewID; sourceDocument = document
        sourceCADDocument = evaluated.document; configuration = evaluated.configuration; brep = evaluated.brep
    }

    public func validateCurrent(document: DesignDocument, evaluated: EvaluatedDocument) throws {
        guard sourceDocument == document, sourceCADDocument == evaluated.document,
              configuration == evaluated.configuration, brep == evaluated.brep else {
            throw EditorError(code: .referenceUnresolved, message: "Drawing dimensions belong to a different original source snapshot.")
        }
    }
}
