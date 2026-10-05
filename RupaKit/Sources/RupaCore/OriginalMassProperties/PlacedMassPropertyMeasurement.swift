import SwiftCAD
import RupaCoreTypes

public struct PlacedMassPropertyMeasurement: Sendable {
    public let occurrenceIDs: [SceneOccurrenceID]
    public let values: MassPropertyMeasurement
}
