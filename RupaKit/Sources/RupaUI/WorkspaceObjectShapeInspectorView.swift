import SwiftUI
import RupaCore

struct WorkspaceObjectShapeInspectorView: View {
    var shapes: [InspectorObjectShape]?
    var displayUnit: LengthDisplayUnit
    var positionSliderMetersRange: ClosedRange<Double>
    var sizeSliderMetersRange: ClosedRange<Double>
    var fallbackLengthSliderMetersRange: ClosedRange<Double>
    var onSetCenter: (InspectorObjectAxis, Double, [InspectorObjectShape]) -> Void
    var onSetSize: (InspectorObjectAxis, Double, [InspectorObjectShape]) -> Void
    var onSetProperty: (ObjectPropertyDefinition, ObjectPropertyValue, [InspectorObjectShape]) -> Void

    var body: some View {
        inspectorSection("Shape") {
            if let shapes {
                shapeRows(shapes)
            } else {
                workspaceInspectorValueRow("Object", "Mixed or Unsupported")
            }
        }
    }

    @ViewBuilder
    private func shapeRows(_ shapes: [InspectorObjectShape]) -> some View {
        workspaceInspectorValueRow("Object", valueSummary(shapes.map(objectShapeTitle)))
        workspaceInspectorValueRow(
            "Source",
            valueSummary(shapes.map { $0.definition?.sourceRepresentation.title ?? "Unknown" })
        )
        workspaceInspectorValueRow(
            "Generated",
            valueSummary(shapes.map {
                $0.definition?.generatedRepresentation(for: $0.properties).title ?? "Unknown"
            })
        )
        objectCenterControls(shapes)
        if shapes.allSatisfy({ $0.typeID == .cube || $0.typeID == .cylinder }) {
            objectSizeControls(shapes)
        }
        objectSchemaPropertyRows(shapes)
    }

    @ViewBuilder
    private func objectCenterControls(_ shapes: [InspectorObjectShape]) -> some View {
        workspaceLengthControl(
            "Center X",
            values: shapes.map(\.center.x),
            displayUnit: displayUnit,
            sliderMetersRange: positionSliderMetersRange
        ) { meters in
            onSetCenter(.x, meters, shapes)
        }
        workspaceLengthControl(
            "Center Y",
            values: shapes.map(\.center.y),
            displayUnit: displayUnit,
            sliderMetersRange: positionSliderMetersRange
        ) { meters in
            onSetCenter(.y, meters, shapes)
        }
        workspaceLengthControl(
            "Center Z",
            values: shapes.map(\.center.z),
            displayUnit: displayUnit,
            sliderMetersRange: positionSliderMetersRange
        ) { meters in
            onSetCenter(.z, meters, shapes)
        }
    }

    @ViewBuilder
    private func objectSizeControls(_ shapes: [InspectorObjectShape]) -> some View {
        workspaceLengthControl(
            "Size X",
            values: shapes.map(\.size.x),
            displayUnit: displayUnit,
            sliderMetersRange: sizeSliderMetersRange
        ) { meters in
            onSetSize(.x, meters, shapes)
        }
        workspaceLengthControl(
            "Size Y",
            values: shapes.map(\.size.y),
            displayUnit: displayUnit,
            sliderMetersRange: sizeSliderMetersRange
        ) { meters in
            onSetSize(.y, meters, shapes)
        }
        workspaceLengthControl(
            "Size Z",
            values: shapes.map(\.size.z),
            displayUnit: displayUnit,
            sliderMetersRange: sizeSliderMetersRange
        ) { meters in
            onSetSize(.z, meters, shapes)
        }
    }

    @ViewBuilder
    private func objectSchemaPropertyRows(_ shapes: [InspectorObjectShape]) -> some View {
        let definitions = sharedObjectPropertyDefinitions(for: shapes)
        if definitions.isEmpty == false {
            ForEach(definitions) { property in
                objectPropertyControl(property, shapes: shapes)
            }
        }
    }

    @ViewBuilder
    private func objectPropertyControl(
        _ property: ObjectPropertyDefinition,
        shapes: [InspectorObjectShape]
    ) -> some View {
        let values = shapes.map { $0.properties.value(for: property.id, default: property.defaultValue) }
        if !property.isEditable || property.inspectorControl == .readOnly {
            workspaceInspectorValueRow(property.title, valueSummary(values.map(formattedObjectProperty)))
        } else {
            switch property.valueKind {
            case .length:
                lengthObjectPropertyControl(property, values: values, shapes: shapes)
            case .number:
                numericObjectPropertyControl(property, values: values, shapes: shapes) { .number($0) }
            case .integer:
                numericObjectPropertyControl(property, values: values, shapes: shapes) { .integer(Int($0.rounded())) }
            case .angle:
                numericObjectPropertyControl(property, values: values, shapes: shapes) { .angle($0) }
            case .boolean:
                booleanObjectPropertyControl(property, values: values, shapes: shapes)
            case .text, .material:
                workspaceInspectorValueRow(property.title, valueSummary(values.map(formattedObjectProperty)))
            }
        }
    }

    @ViewBuilder
    private func lengthObjectPropertyControl(
        _ property: ObjectPropertyDefinition,
        values: [ObjectPropertyValue],
        shapes: [InspectorObjectShape]
    ) -> some View {
        let meters = values.compactMap { value -> Double? in
            if case .length(let meters) = value {
                return meters
            }
            return nil
        }
        if meters.count == values.count {
            let range = lengthSliderRange(for: property, values: meters)
            workspaceLengthControl(
                property.title,
                values: meters,
                displayUnit: displayUnit,
                sliderMetersRange: range
            ) { meters in
                onSetProperty(property, .length(meters), shapes)
            }
        } else {
            workspaceInspectorValueRow(property.title, "Mixed")
        }
    }

    @ViewBuilder
    private func numericObjectPropertyControl(
        _ property: ObjectPropertyDefinition,
        values: [ObjectPropertyValue],
        shapes: [InspectorObjectShape],
        makeValue: @escaping (Double) -> ObjectPropertyValue
    ) -> some View {
        let numbers = values.compactMap { value -> Double? in
            switch value {
            case .number(let number), .angle(let number):
                return number
            case .integer(let integer):
                return Double(integer)
            default:
                return nil
            }
        }
        if numbers.count == values.count {
            let range = property.numericRange.map { $0.lowerBound ... $0.upperBound } ?? 0.0 ... 100.0
            numericControl(
                property.title,
                values: numbers,
                sliderRange: range
            ) { value in
                onSetProperty(property, makeValue(value), shapes)
            }
        } else {
            workspaceInspectorValueRow(property.title, "Mixed")
        }
    }

    private func booleanObjectPropertyControl(
        _ property: ObjectPropertyDefinition,
        values: [ObjectPropertyValue],
        shapes: [InspectorObjectShape]
    ) -> some View {
        let commonValue = commonObjectBoolean(values)
        let binding = Binding<InspectorBoolChoice>(
            get: {
                guard let commonValue else {
                    return .mixed
                }
                return commonValue ? .on : .off
            },
            set: { choice in
                switch choice {
                case .mixed:
                    return
                case .on:
                    onSetProperty(property, .boolean(true), shapes)
                case .off:
                    onSetProperty(property, .boolean(false), shapes)
                }
            }
        )
        return inspectorControlRow(property.title) {
            Picker(property.title, selection: binding) {
                ForEach(InspectorBoolChoice.allCases) { choice in
                    Text(choice.rawValue)
                        .tag(choice)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: inspectorControlWidth)
        }
    }

    private func objectShapeTitle(_ shape: InspectorObjectShape) -> String {
        if let definition = shape.definition {
            return definition.title
        }
        return shape.typeID?.rawValue ?? "Object"
    }

    private func lengthSliderRange(
        for property: ObjectPropertyDefinition,
        values: [Double]
    ) -> ClosedRange<Double> {
        workspaceLengthInteractionSliderMetersRange(
            for: values,
            fallbackRange: fallbackLengthSliderMetersRange,
            validationRange: property.numericRange
        )
    }

    private func commonObjectBoolean(_ values: [ObjectPropertyValue]) -> Bool? {
        guard let first = values.first,
              case .boolean(let firstValue) = first else {
            return nil
        }
        for value in values {
            guard case .boolean(let boolValue) = value,
                  boolValue == firstValue else {
                return nil
            }
        }
        return firstValue
    }

    private func sharedObjectPropertyDefinitions(
        for shapes: [InspectorObjectShape]
    ) -> [ObjectPropertyDefinition] {
        guard let firstTypeID = shapes.first?.typeID,
              shapes.allSatisfy({ $0.typeID == firstTypeID }),
              let definition = shapes.first?.definition else {
            return []
        }
        var existingPropertyIDs: Set<ObjectPropertyID> = []
        if shapes.allSatisfy({ $0.typeID == .cube || $0.typeID == .cylinder }) {
            existingPropertyIDs.formUnion(["size.x", "size.y", "size.z"])
        }
        return definition.properties.filter { !existingPropertyIDs.contains($0.id) }
    }

    private func formattedObjectProperty(_ value: ObjectPropertyValue) -> String {
        switch value {
        case .length(let meters):
            return WorkspaceInspectorNumberText.readableLengthString(
                fromMeters: meters,
                preferredUnit: displayUnit
            )
        case .number(let number):
            return number.formatted(.number.precision(.fractionLength(0...4)))
        case .integer(let integer):
            return "\(integer)"
        case .boolean(let boolean):
            return boolean ? "Yes" : "No"
        case .angle(let degrees):
            return "\(degrees.formatted(.number.precision(.fractionLength(0...2)))) deg"
        case .text(let text):
            return text
        case .material(let materialID):
            return materialID.map { shortID($0) } ?? "None"
        }
    }

    private func valueSummary(_ values: [String]) -> String {
        var uniqueValues: [String] = []
        var seenValues: Set<String> = []
        for value in values {
            guard seenValues.insert(value).inserted else {
                continue
            }
            uniqueValues.append(value)
        }
        guard uniqueValues.isEmpty == false else {
            return "None"
        }
        if uniqueValues.count == 1 {
            return uniqueValues[0]
        }
        let visibleValues = uniqueValues.prefix(3).joined(separator: ", ")
        if uniqueValues.count > 3 {
            return "\(visibleValues), +\(uniqueValues.count - 3)"
        }
        return visibleValues
    }

    private func shortID<T: CustomStringConvertible>(_ id: T) -> String {
        String(id.description.prefix(8))
    }
}
