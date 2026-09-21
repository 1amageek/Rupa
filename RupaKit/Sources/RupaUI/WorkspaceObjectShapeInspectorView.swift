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
        if shapes.allSatisfy({ $0.center != nil }) {
            objectCenterControls(shapes)
        } else {
            workspaceInspectorValueRow("World Center", "No evaluated occurrence")
        }
        if shapes.allSatisfy({ $0.size != nil }) {
            objectSizeControls(shapes)
        }
        objectSchemaPropertyRows(shapes)
    }

    @ViewBuilder
    private func objectCenterControls(_ shapes: [InspectorObjectShape]) -> some View {
        InspectorVectorRow(title: "Center") {
            workspaceLengthControl(
                "X",
                values: shapes.compactMap(\.center?.x),
                displayUnit: displayUnit,
                sliderMetersRange: positionSliderMetersRange, axisField: true
            ) { meters in
                onSetCenter(.x, meters, shapes)
            }
            workspaceLengthControl(
                "Y",
                values: shapes.compactMap(\.center?.y),
                displayUnit: displayUnit,
                sliderMetersRange: positionSliderMetersRange, axisField: true
            ) { meters in
                onSetCenter(.y, meters, shapes)
            }
            workspaceLengthControl(
                "Z",
                values: shapes.compactMap(\.center?.z),
                displayUnit: displayUnit,
                sliderMetersRange: positionSliderMetersRange, axisField: true
            ) { meters in
                onSetCenter(.z, meters, shapes)
            }
        }
        .help("World center")
    }

    @ViewBuilder
    private func objectSizeControls(_ shapes: [InspectorObjectShape]) -> some View {
        InspectorVectorRow(title: "Size") {
            workspaceLengthControl(
                "X",
                values: shapes.compactMap(\.size?.x),
                displayUnit: displayUnit,
                sliderMetersRange: sizeSliderMetersRange, axisField: true
            ) { meters in
                onSetSize(.x, meters, shapes)
            }
            workspaceLengthControl(
                "Y",
                values: shapes.compactMap(\.size?.y),
                displayUnit: displayUnit,
                sliderMetersRange: sizeSliderMetersRange, axisField: true
            ) { meters in
                onSetSize(.y, meters, shapes)
            }
            workspaceLengthControl(
                "Z",
                values: shapes.compactMap(\.size?.z),
                displayUnit: displayUnit,
                sliderMetersRange: sizeSliderMetersRange, axisField: true
            ) { meters in
                onSetSize(.z, meters, shapes)
            }
        }
        .help("Source size")
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
                numericObjectPropertyControl(property, values: values, shapes: shapes) {
                    Int(exactly: $0.rounded()).map(ObjectPropertyValue.integer)
                }
            case .angle:
                numericObjectPropertyControl(property, values: values, shapes: shapes) { .angle($0) }
            case .boolean:
                booleanObjectPropertyControl(property, values: values, shapes: shapes)
            case .text, .material:
                workspaceInspectorValueRow(property.title, valueSummary(values.map(formattedObjectProperty)))
            }
        }
    }

    /// The bound the source publishes for a length the body's own geometry limits.
    ///
    /// A body's `corner.radius` and a profile's `bevel` are the same all-edge fillet seen from the
    /// two ends, so they take the same bound. A cylinder's `hollow` takes its own: the hole has to
    /// stay inside the wall the body is built to. Every other length keeps its declared range.
    private func sourceLengthLimit(
        _ binding: ObjectPropertyDefinition.RenderBinding?,
        shapes: [InspectorObjectShape]
    ) -> Double? {
        switch binding {
        case .cornerRadius, .bevel:
            return shapes.compactMap(\.cornerRadiusLimit).min()
        case .hollow:
            return shapes.compactMap(\.hollowLimit).min()
        default:
            return nil
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
            let sourceLimit = sourceLengthLimit(property.renderBinding, shapes: shapes)
            let range = sourceLimit.map { 0...$0 } ?? lengthSliderRange(for: property, values: meters)
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
        makeValue: @escaping (Double) -> ObjectPropertyValue?
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
            InspectorNumericInput(
                title: property.title,
                value: commonWorkspaceInspectorValue(numbers),
                mapping: property.valueKind == .integer
                    ? .integer(range: range, step: property.numericRange?.step ?? 1)
                    : .number(range: range)
            ) { value in
                if let propertyValue = makeValue(value) {
                    onSetProperty(property, propertyValue, shapes)
                }
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
        // The Size row above already edits the three size bindings, so the schema rows drop them
        // instead of offering a second control for the same value.
        guard shapes.allSatisfy({ $0.size != nil }) else {
            return definition.properties
        }
        return definition.properties.filter { property in
            switch property.renderBinding {
            case .sizeX, .sizeY, .sizeZ:
                return false
            default:
                return true
            }
        }
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
            return materialID.map { WorkspaceInspectorNumberText.shortID($0) } ?? "None"
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

}
