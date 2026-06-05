import Foundation

public enum ObjectTypeCatalog {
    public static let builtInDefinitions: [ObjectTypeDefinition] = [
        definition(
            id: .line,
            title: "Line",
            systemImage: "line.diagonal",
            representation: .twoDimensional,
            category: .sketch,
            geometryRole: .curve,
            properties: lineProperties
        ),
        definition(
            id: .rectangle,
            title: "Rectangle",
            systemImage: "rectangle",
            representation: .twoDimensional,
            generatedRepresentationRule: extruded2DRule,
            category: .sketch,
            geometryRole: .sketchProfile,
            properties: rectangleProperties
        ),
        definition(
            id: .circle,
            title: "Circle",
            systemImage: "circle",
            representation: .twoDimensional,
            generatedRepresentationRule: extruded2DRule,
            category: .sketch,
            geometryRole: .sketchProfile,
            properties: circleProperties
        ),
        definition(
            id: .cube,
            title: "Cube",
            systemImage: "cube",
            representation: .threeDimensional,
            category: .body,
            geometryRole: .solid,
            properties: cubeProperties
        ),
        definition(
            id: .cylinder,
            title: "Cylinder",
            systemImage: "cylinder",
            representation: .threeDimensional,
            category: .body,
            geometryRole: .solid,
            properties: cylinderProperties
        ),
    ]

    public static func definition(for id: ObjectTypeID?) -> ObjectTypeDefinition? {
        guard let id else {
            return nil
        }
        return builtInDefinitions.first { $0.id == id }
    }

    public static func defaultProperties(for id: ObjectTypeID?) -> ObjectPropertySet {
        definition(for: id)?.defaultProperties ?? ObjectPropertySet()
    }

    public static func geometryRole(for id: ObjectTypeID?) -> ObjectDescriptor.GeometryRole? {
        definition(for: id)?.geometryRole
    }

    private static func definition(
        id: ObjectTypeID,
        title: String,
        systemImage: String,
        representation: ObjectRepresentationKind,
        generatedRepresentation: ObjectRepresentationKind? = nil,
        generatedRepresentationRule: ObjectTypeDefinition.GeneratedRepresentationRule? = nil,
        category: ObjectDescriptor.Category,
        geometryRole: ObjectDescriptor.GeometryRole?,
        properties: [ObjectPropertyDefinition]
    ) -> ObjectTypeDefinition {
        ObjectTypeDefinition(
            id: id,
            title: title,
            systemImage: systemImage,
            representation: representation,
            generatedRepresentation: generatedRepresentation,
            generatedRepresentationRule: generatedRepresentationRule,
            category: category,
            geometryRole: geometryRole,
            properties: properties
        )
    }

    private static let extruded2DRule = ObjectTypeDefinition.GeneratedRepresentationRule.lengthPropertyThreshold(
        propertyID: "extrusion",
        threshold: 1.0e-9,
        defaultRepresentation: .twoDimensional,
        activeRepresentation: .threeDimensional
    )

    private static let lineProperties: [ObjectPropertyDefinition] = [
        .length(id: "length", title: "Length", binding: .sizeX, defaultValue: 1.0),
        .angle(id: "angle", title: "Angle", binding: .angle, defaultValue: 0.0),
        .length(id: "stroke.width", title: "Stroke", binding: .strokeWidth, defaultValue: 0.001),
    ]

    private static let rectangleProperties: [ObjectPropertyDefinition] = [
        .length(id: "size.x", title: "Size X", binding: .sizeX, defaultValue: 1.0),
        .length(id: "size.y", title: "Size Y", binding: .sizeY, defaultValue: 1.0),
        .integer(id: "subdivisions", title: "Subdivisions", binding: .subdivisionSegments, defaultValue: 40),
        .length(id: "corner.radius", title: "Corner", binding: .cornerRadius, defaultValue: 0.0),
        .length(id: "extrusion", title: "Extrusion", binding: .extrusion, defaultValue: 0.0),
        .length(id: "bevel", title: "Bevel", binding: .bevel, defaultValue: 0.0),
        .integer(id: "corner.sides", title: "Corner Sides", binding: .cornerSideSegments, defaultValue: 8),
        .length(id: "stroke.width", title: "Stroke", binding: .strokeWidth, defaultValue: 0.001),
    ]

    private static let circleProperties: [ObjectPropertyDefinition] = [
        .length(id: "radius", title: "Radius", binding: .radius, defaultValue: 0.5),
        .integer(id: "sides.x", title: "Sides", binding: .sideSegments, defaultValue: 64),
        .length(id: "extrusion", title: "Extrusion", binding: .extrusion, defaultValue: 0.0),
        .length(id: "bevel", title: "Bevel", binding: .bevel, defaultValue: 0.0),
        .integer(id: "bevel.sides", title: "Bevel Sides", binding: .bevelSideSegments, defaultValue: 3),
        .length(id: "stroke.width", title: "Stroke", binding: .strokeWidth, defaultValue: 0.001),
    ]

    private static let cubeProperties: [ObjectPropertyDefinition] = [
        .length(id: "size.x", title: "Size X", binding: .sizeX, defaultValue: 1.0),
        .length(id: "size.y", title: "Size Y", binding: .sizeY, defaultValue: 1.0),
        .length(id: "size.z", title: "Size Z", binding: .sizeZ, defaultValue: 1.0),
        .length(id: "corner.radius", title: "Corner", binding: .cornerRadius, defaultValue: 0.0),
        .integer(id: "corner.sides", title: "Corner Sides", binding: .cornerSideSegments, defaultValue: 8),
    ]

    private static let cylinderProperties: [ObjectPropertyDefinition] = [
        .length(id: "size.x", title: "Size X", binding: .sizeX, defaultValue: 1.0),
        .length(id: "size.y", title: "Size Y", binding: .sizeY, defaultValue: 1.0),
        .length(id: "size.z", title: "Size Z", binding: .sizeZ, defaultValue: 1.0),
        .length(id: "radius", title: "Radius", binding: .radius, defaultValue: 0.5),
        .integer(id: "sides.x", title: "Sides X", binding: .sideSegments, defaultValue: 64),
        .integer(id: "sides.y", title: "Sides Y", binding: .verticalSegments, defaultValue: 1),
        .angle(id: "angle", title: "Angle", binding: .angle, defaultValue: 360.0),
        .boolean(id: "caps", title: "Caps", binding: .capVisibility, defaultValue: true),
        .length(id: "hollow", title: "Hollow", binding: .hollow, defaultValue: 0.0),
        .length(id: "corner.radius", title: "Corner", binding: .cornerRadius, defaultValue: 0.0),
        .integer(id: "corner.sides", title: "Corner Sides", binding: .cornerSideSegments, defaultValue: 8),
    ]
}

private extension ObjectPropertyDefinition {
    static func length(
        id: ObjectPropertyID,
        title: String,
        binding: RenderBinding?,
        defaultValue: Double
    ) -> ObjectPropertyDefinition {
        ObjectPropertyDefinition(
            id: id,
            title: title,
            group: "Shape",
            valueKind: .length,
            defaultValue: .length(defaultValue),
            inspectorControl: .textFieldAndSlider,
            renderBinding: binding,
            numericRange: NumericRange(lowerBound: 0.0, upperBound: 100.0)
        )
    }

    static func integer(
        id: ObjectPropertyID,
        title: String,
        binding: RenderBinding?,
        defaultValue: Int
    ) -> ObjectPropertyDefinition {
        ObjectPropertyDefinition(
            id: id,
            title: title,
            group: "Shape",
            valueKind: .integer,
            defaultValue: .integer(defaultValue),
            inspectorControl: .textFieldAndSlider,
            renderBinding: binding,
            numericRange: NumericRange(lowerBound: 1.0, upperBound: 256.0)
        )
    }

    static func angle(
        id: ObjectPropertyID,
        title: String,
        binding: RenderBinding?,
        defaultValue: Double
    ) -> ObjectPropertyDefinition {
        ObjectPropertyDefinition(
            id: id,
            title: title,
            group: "Shape",
            valueKind: .angle,
            defaultValue: .angle(defaultValue),
            inspectorControl: .textFieldAndSlider,
            renderBinding: binding,
            numericRange: NumericRange(lowerBound: 0.0, upperBound: 360.0)
        )
    }

    static func boolean(
        id: ObjectPropertyID,
        title: String,
        binding: RenderBinding?,
        defaultValue: Bool
    ) -> ObjectPropertyDefinition {
        ObjectPropertyDefinition(
            id: id,
            title: title,
            group: "Shape",
            valueKind: .boolean,
            defaultValue: .boolean(defaultValue),
            inspectorControl: .segmented,
            renderBinding: binding
        )
    }

}
