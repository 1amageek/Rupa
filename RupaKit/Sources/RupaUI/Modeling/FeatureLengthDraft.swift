import RupaCore

struct FeatureLengthDraft: Identifiable {
    let id: FeatureID
    let title: String
    let unit: LengthDisplayUnit
    var text: String

    init?(feature: FeatureNode, parameters: ParameterTable, unit: LengthDisplayUnit,
          using editor: any FeatureLengthEditing = NativeFeatureLengthEditor()) {
        guard let field = editor.length(in: feature.operation) else { return nil }
        id = feature.id
        title = field.title
        self.unit = unit
        text = ParameterExpressionFormatter().format(field.expression, parameters: parameters)
    }

    func command(parameters: ParameterTable) throws -> EditorCommand {
        let expression = try ParameterExpressionParser().parse(text, parameters: parameters,
            targetKind: .length, defaults: ParameterExpressionDefaults(lengthUnit: unit))
        return .setFeatureLength(featureID: id, expression: expression)
    }
}
