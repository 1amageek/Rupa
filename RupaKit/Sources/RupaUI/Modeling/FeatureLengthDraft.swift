import RupaCore

struct FeatureLengthDraft: Identifiable {
    let id: FeatureID
    let title: String
    let unit: LengthDisplayUnit
    var startText: String?
    var text: String

    init?(feature: FeatureNode, parameters: ParameterTable, unit: LengthDisplayUnit,
          using editor: any FeatureLengthEditing = NativeFeatureLengthEditor()) {
        guard let field = editor.length(in: feature.operation) else { return nil }
        id = feature.id
        title = field.title
        self.unit = unit
        text = ParameterExpressionFormatter().format(field.expression, parameters: parameters)
        if case .extrude(let extrusion) = feature.operation, extrusion.direction != .symmetric {
            startText = ParameterExpressionFormatter().format(
                extrusion.startDistance ?? .length(0, .meter), parameters: parameters)
        }
    }

    func command(parameters: ParameterTable) throws -> EditorCommand {
        let expression = try ParameterExpressionParser().parse(text, parameters: parameters,
            targetKind: .length, defaults: ParameterExpressionDefaults(lengthUnit: unit))
        if let startText {
            let start = try ParameterExpressionParser().parse(startText, parameters: parameters,
                targetKind: .length, defaults: ParameterExpressionDefaults(lengthUnit: unit))
            return .setExtrudeExtents(featureID: id, start: start, end: expression)
        }
        return .setFeatureLength(featureID: id, expression: expression)
    }
}
