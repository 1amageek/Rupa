import Foundation
import RupaCore

struct InvoluteGearDraft: Identifiable {
    let id = UUID()
    var featureID: FeatureID?
    var name = "Gear"
    var toothCount = "32"
    var maximumSegments = "4096"
    var doubleHelical = false
    var origin = Point3D.origin
    var text: [InvoluteGearFeature.Dimension: String]
    let unit: LengthDisplayUnit
    private let originalDimensions: [InvoluteGearFeature.Dimension: CADExpression]
    private let originalText: [InvoluteGearFeature.Dimension: String]

    init(feature: FeatureNode? = nil, parameters: ParameterTable, unit: LengthDisplayUnit) {
        self.unit = unit
        if let feature, case let .involuteGear(gear) = feature.operation {
            featureID = feature.id
            name = feature.name ?? "Gear"
            toothCount = String(gear.toothCount)
            maximumSegments = String(gear.maximumSegments)
            doubleHelical = gear.doubleHelical
            origin = gear.origin
            originalDimensions = gear.dimensions
            text = gear.dimensions.mapValues { ParameterExpressionFormatter().format($0, parameters: parameters) }
        } else {
            originalDimensions = [:]
            text = [.baseRadius: "32 mm * cos(20 deg)", .pitchRadius: "32 mm",
                .tipRadius: "34 mm", .rootRadius: "29.5 mm", .filletRadius: "0.76 mm",
                .pitchToothAngle: "5.625 deg", .width: "10 mm", .twistAngle: "0 deg",
                .profileError: "0.0001 mm", .sweepError: "0.001 mm"]
        }
        originalText = text
    }

    func command(parameters: ParameterTable, tolerance: ModelingTolerance) throws -> EditorCommand {
        guard let count = Int(toothCount), let budget = Int(maximumSegments) else {
            throw EditorError(code: .commandInvalid, message: "Tooth count and segment budget must be integers.")
        }
        var dimensions: [InvoluteGearFeature.Dimension: CADExpression] = [:]
        for field in InvoluteGearFeature.Dimension.allCases {
            guard let source = text[field] else {
                throw EditorError(code: .commandInvalid, message: "A required gear dimension is missing.")
            }
            if source == originalText[field], let original = originalDimensions[field] {
                dimensions[field] = original
            } else {
                dimensions[field] = try ParameterExpressionParser().parse(source, parameters: parameters,
                    targetKind: field.quantityKind, defaults: ParameterExpressionDefaults(lengthUnit: unit))
            }
        }
        let gear = InvoluteGearFeature(toothCount: count, dimensions: dimensions,
            doubleHelical: doubleHelical, maximumSegments: budget, origin: origin)
        try gear.validate(tolerance: tolerance)
        _ = try gear.resolvedDimensions { try parameters.resolvedValue(for: $0) }
        if let featureID { return .setInvoluteGear(featureID: featureID, gear: gear) }
        return .createInvoluteGear(name: name, gear: gear)
    }
}
