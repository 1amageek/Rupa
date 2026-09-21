import Foundation
import RupaCoreTypes

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
            id: .arc,
            title: "Arc",
            systemImage: "circle.dashed",
            representation: .twoDimensional,
            category: .sketch,
            geometryRole: .curve,
            properties: arcProperties
        ),
        definition(
            id: .spline,
            title: "Spline",
            systemImage: "point.topleft.down.curvedto.point.bottomright.up",
            representation: .twoDimensional,
            category: .sketch,
            geometryRole: .curve,
            properties: splineProperties
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
            id: .polygon,
            title: "Polygon",
            systemImage: "hexagon",
            representation: .twoDimensional,
            generatedRepresentationRule: extruded2DRule,
            category: .sketch,
            geometryRole: .sketchProfile,
            properties: polygonProperties
        ),
        definition(
            id: .slot,
            title: "Slot",
            systemImage: "capsule",
            representation: .twoDimensional,
            generatedRepresentationRule: extruded2DRule,
            category: .sketch,
            geometryRole: .sketchProfile,
            properties: slotProperties
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
            // A cylinder is a solid while its caps are on and a surface while they are off, so the
            // role is the one its own extrusion declares rather than one this type forces on it.
            geometryRole: nil,
            properties: cylinderProperties
        ),
        definition(
            id: .sphere,
            title: "Sphere",
            systemImage: "sphere",
            representation: .threeDimensional,
            category: .body,
            geometryRole: .solid,
            properties: sphereProperties
        ),
        definition(
            id: .polySpline,
            title: "PolySpline",
            systemImage: "point.3.connected.trianglepath.dotted",
            representation: .threeDimensional,
            category: .body,
            geometryRole: .surface,
            properties: polySplineProperties
        ),
        definition(
            id: .bSplineSurface,
            title: "B-spline Surface",
            systemImage: "rectangle.grid.3x2",
            representation: .threeDimensional,
            category: .body,
            geometryRole: .surface,
            properties: bSplineSurfaceProperties
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
        .length(
            id: "length",
            title: "Length",
            binding: .sizeX,
            effect: .source,
            defaultValue: 1.0,
            workspaceScaleDefault: .sketchWidth
        ),
        .angle(id: "angle", title: "Angle", binding: .angle, effect: .source, defaultValue: 0.0),
    ]

    private static let arcProperties: [ObjectPropertyDefinition] = [
        .length(
            id: "radius",
            title: "Radius",
            binding: .radius,
            effect: .source,
            defaultValue: 0.5,
            workspaceScaleDefault: .curveRadius
        ),
        .angle(id: "start.angle", title: "Start", binding: .angle, effect: .source, defaultValue: 0.0),
        .angle(id: "end.angle", title: "End", binding: .angle, effect: .source, defaultValue: 90.0),
    ]

    private static let splineProperties: [ObjectPropertyDefinition] = [
        .derivedInteger(id: "control.point.count", title: "Control Points", defaultValue: 4),
    ]

    private static let rectangleProperties: [ObjectPropertyDefinition] = [
        .length(
            id: "size.x",
            title: "Size X",
            binding: .sizeX,
            effect: .source,
            defaultValue: 1.0,
            workspaceScaleDefault: .sketchWidth
        ),
        .length(
            id: "size.y",
            title: "Size Y",
            binding: .sizeY,
            effect: .source,
            defaultValue: 1.0,
            workspaceScaleDefault: .sketchHeight
        ),
        .length(id: "corner.radius", title: "Corner", binding: .cornerRadius, effect: .source, defaultValue: 0.0),
        .integer(
            id: "corner.sides",
            title: "Corner Sides",
            binding: .cornerSideSegments,
            effect: .tessellation,
            defaultValue: 8
        ),
        .length(
            id: "extrusion",
            title: "Extrusion",
            binding: .extrusion,
            effect: .source,
            defaultValue: 0.0
        ),
        .length(id: "bevel", title: "Bevel", binding: .bevel, effect: .source, defaultValue: 0.0),
    ]

    private static let circleProperties: [ObjectPropertyDefinition] = [
        .length(
            id: "radius",
            title: "Radius",
            binding: .radius,
            effect: .source,
            defaultValue: 0.5,
            workspaceScaleDefault: .curveRadius
        ),
        .integer(id: "sides.x", title: "Sides", binding: .sideSegments, effect: .tessellation, defaultValue: 64),
        .length(
            id: "extrusion",
            title: "Extrusion",
            binding: .extrusion,
            effect: .source,
            defaultValue: 0.0
        ),
        .length(id: "bevel", title: "Bevel", binding: .bevel, effect: .source, defaultValue: 0.0),
        .integer(
            id: "bevel.sides",
            title: "Bevel Sides",
            binding: .bevelSideSegments,
            effect: .tessellation,
            defaultValue: 3
        ),
    ]

    private static let polygonProperties: [ObjectPropertyDefinition] = [
        .length(
            id: "sizing.radius",
            title: "Sizing Radius",
            binding: nil,
            effect: .source,
            defaultValue: 0.5,
            workspaceScaleDefault: .curveRadius
        ),
        .boolean(
            id: "radius.is.inradius",
            title: "Use Inradius",
            binding: nil,
            effect: .source,
            defaultValue: false
        ),
        .integer(id: "sides.x", title: "Sides", binding: .sideSegments, effect: .source, defaultValue: 6),
        .angle(id: "angle", title: "Rotation", binding: .angle, effect: .source, defaultValue: 0.0),
        .length(
            id: "extrusion",
            title: "Extrusion",
            binding: .extrusion,
            effect: .source,
            defaultValue: 0.0
        ),
        .length(id: "bevel", title: "Bevel", binding: .bevel, effect: .source, defaultValue: 0.0),
        .integer(
            id: "bevel.sides",
            title: "Bevel Sides",
            binding: .bevelSideSegments,
            effect: .tessellation,
            defaultValue: 3
        ),
        .derivedLength(
            id: "radius",
            title: "Radius",
            binding: .radius,
            defaultValue: 0.5,
            workspaceScaleDefault: .curveRadius
        ),
        .derivedLength(
            id: "side.length",
            title: "Side Length",
            binding: nil,
            defaultValue: 0.5,
            workspaceScaleDefault: .curveRadius
        ),
        .text(id: "inclination.mode", title: "Inclination", defaultValue: PolygonInclinationMode.vertical.rawValue),
    ]

    private static let slotProperties: [ObjectPropertyDefinition] = [
        .integer(
            id: ProfileTessellationPolicy.arcSegmentsPropertyID,
            title: "Arc Segments",
            binding: .sideSegments,
            effect: .tessellation,
            defaultValue: 32
        ),
        .length(
            id: "extrusion",
            title: "Extrusion",
            binding: .extrusion,
            effect: .source,
            defaultValue: 0.0
        ),
        .length(id: "bevel", title: "Bevel", binding: .bevel, effect: .source, defaultValue: 0.0),
        .integer(
            id: "bevel.sides",
            title: "Bevel Sides",
            binding: .bevelSideSegments,
            effect: .tessellation,
            defaultValue: 3
        ),
        .derivedLength(
            id: "width",
            title: "Width",
            binding: nil,
            defaultValue: 0.1,
            workspaceScaleDefault: .narrowProfileWidth
        ),
        .derivedLength(
            id: "path.length",
            title: "Path",
            binding: nil,
            defaultValue: 1.0,
            workspaceScaleDefault: .sketchWidth
        ),
        .derivedLength(
            id: "radius",
            title: "Cap Radius",
            binding: .radius,
            defaultValue: 0.05,
            workspaceScaleDefault: .narrowProfileRadius
        ),
        .text(id: "source.kind", title: "Source", defaultValue: "curve"),
    ]

    private static let cubeProperties: [ObjectPropertyDefinition] = [
        .length(
            id: "size.x",
            title: "Size X",
            binding: .sizeX,
            effect: .source,
            defaultValue: 1.0,
            workspaceScaleDefault: .placedSolidSide
        ),
        .length(
            id: "size.y",
            title: "Size Y",
            binding: .sizeY,
            effect: .source,
            defaultValue: 1.0,
            workspaceScaleDefault: .placedSolidSide
        ),
        .length(
            id: "size.z",
            title: "Size Z",
            binding: .sizeZ,
            effect: .source,
            defaultValue: 1.0,
            workspaceScaleDefault: .placedSolidSide
        ),
        .length(id: "corner.radius", title: "Corner", binding: .cornerRadius, effect: .source, defaultValue: 0.0),
        .integer(
            id: "corner.sides",
            title: "Corner Sides",
            binding: .cornerSideSegments,
            effect: .tessellation,
            defaultValue: 8
        ),
    ]

    private static let cylinderProperties: [ObjectPropertyDefinition] = [
        .length(
            id: "size.x",
            title: "Size X",
            binding: .sizeX,
            effect: .source,
            defaultValue: 1.0,
            workspaceScaleDefault: .curveDiameter
        ),
        .length(
            id: "size.y",
            title: "Size Y",
            binding: .sizeY,
            effect: .source,
            defaultValue: 1.0,
            workspaceScaleDefault: .cylinderDepth
        ),
        .length(
            id: "size.z",
            title: "Size Z",
            binding: .sizeZ,
            effect: .source,
            defaultValue: 1.0,
            workspaceScaleDefault: .curveDiameter
        ),
        .length(
            id: "radius",
            title: "Radius",
            binding: .radius,
            effect: .source,
            defaultValue: 0.5,
            workspaceScaleDefault: .curveRadius
        ),
        .integer(id: "sides.x", title: "Sides", binding: .sideSegments, effect: .tessellation, defaultValue: 64),
        .angle(id: "angle", title: "Angle", binding: .angle, effect: .source, defaultValue: 360.0),
        .boolean(id: "caps", title: "Caps", binding: .capVisibility, effect: .source, defaultValue: true),
        .length(id: "hollow", title: "Hollow", binding: .hollow, effect: .source, defaultValue: 0.0),
        .length(id: "corner.radius", title: "Corner", binding: .cornerRadius, effect: .source, defaultValue: 0.0),
        .integer(
            id: "corner.sides",
            title: "Corner Sides",
            binding: .cornerSideSegments,
            effect: .tessellation,
            defaultValue: 8
        ),
    ]

    private static let sphereProperties: [ObjectPropertyDefinition] = [
        .derivedLength(id: "radius", title: "Radius", binding: .radius, defaultValue: 0.5),
    ]

    private static let polySplineProperties: [ObjectPropertyDefinition] = [
        .derivedInteger(id: "patch.count", title: "Patches", defaultValue: 1),
        .derivedInteger(id: "control.point.u", title: "U Control Points", defaultValue: 4),
        .derivedInteger(id: "control.point.v", title: "V Control Points", defaultValue: 4),
        .derivedBoolean(id: "merge.patches", title: "Merge Patches", defaultValue: true),
        .derivedBoolean(id: "interpolate.boundary", title: "Boundary Exact", defaultValue: true),
    ]

    private static let bSplineSurfaceProperties: [ObjectPropertyDefinition] = [
        .derivedInteger(id: "surface.degree.u", title: "U Degree", defaultValue: 3),
        .derivedInteger(id: "surface.degree.v", title: "V Degree", defaultValue: 3),
        .derivedInteger(id: "control.point.u", title: "U Control Points", defaultValue: 4),
        .derivedInteger(id: "control.point.v", title: "V Control Points", defaultValue: 4),
        .derivedBoolean(id: "surface.rational", title: "Rational", defaultValue: false),
    ]
}

private extension ObjectPropertyDefinition {
    static let maximumAuthoringLengthMeters = RulerConfiguration.visibleSpanMetersRange.upperBound * 10.0

    static func length(
        id: PropertyID,
        title: String,
        binding: RenderBinding?,
        effect: Effect,
        defaultValue: Double,
        workspaceScaleDefault: WorkspaceScaleDefault? = nil
    ) -> ObjectPropertyDefinition {
        ObjectPropertyDefinition(
            id: id,
            title: title,
            group: "Shape",
            valueKind: .length,
            defaultValue: .length(defaultValue),
            inspectorControl: .textFieldAndSlider,
            effect: effect,
            renderBinding: binding,
            workspaceScaleDefault: workspaceScaleDefault,
            numericRange: NumericRange(
                lowerBound: 0.0,
                upperBound: maximumAuthoringLengthMeters
            )
        )
    }

    static func integer(
        id: PropertyID,
        title: String,
        binding: RenderBinding?,
        effect: Effect,
        defaultValue: Int
    ) -> ObjectPropertyDefinition {
        ObjectPropertyDefinition(
            id: id,
            title: title,
            group: "Shape",
            valueKind: .integer,
            defaultValue: .integer(defaultValue),
            inspectorControl: .textFieldAndSlider,
            effect: effect,
            renderBinding: binding,
            numericRange: Self.subdivisionRange(binding: binding, effect: effect)
        )
    }

    /// The counts an integer property offers.
    ///
    /// A tessellation count divides an arc, and `DisplayTessellationArc` owns which counts the
    /// canvas resolves that arc at, so the schema offers those and nothing between them. A count
    /// that changes the source names whole geometry instead, and every whole number is one.
    static func subdivisionRange(
        binding: RenderBinding?,
        effect: Effect
    ) -> NumericRange {
        guard effect == .tessellation,
              let arc = DisplayTessellationArc(dividedBy: binding) else {
            return NumericRange(lowerBound: 1.0, upperBound: 256.0, step: 1.0)
        }
        return NumericRange(
            lowerBound: Double(arc.lowestDrawableCount),
            upperBound: 256.0,
            step: Double(arc.drawableCountStep)
        )
    }

    static func angle(
        id: PropertyID,
        title: String,
        binding: RenderBinding?,
        effect: Effect,
        defaultValue: Double
    ) -> ObjectPropertyDefinition {
        ObjectPropertyDefinition(
            id: id,
            title: title,
            group: "Shape",
            valueKind: .angle,
            defaultValue: .angle(defaultValue),
            inspectorControl: .textFieldAndSlider,
            effect: effect,
            renderBinding: binding,
            numericRange: NumericRange(lowerBound: 0.0, upperBound: 360.0)
        )
    }

    static func boolean(
        id: PropertyID,
        title: String,
        binding: RenderBinding?,
        effect: Effect,
        defaultValue: Bool
    ) -> ObjectPropertyDefinition {
        ObjectPropertyDefinition(
            id: id,
            title: title,
            group: "Shape",
            valueKind: .boolean,
            defaultValue: .boolean(defaultValue),
            inspectorControl: .segmented,
            effect: effect,
            renderBinding: binding
        )
    }

    static func derivedLength(
        id: PropertyID,
        title: String,
        binding: RenderBinding?,
        defaultValue: Double,
        workspaceScaleDefault: WorkspaceScaleDefault? = nil
    ) -> ObjectPropertyDefinition {
        ObjectPropertyDefinition(
            id: id,
            title: title,
            group: "Shape",
            valueKind: .length,
            defaultValue: .length(defaultValue),
            inspectorControl: .readOnly,
            effect: .derived,
            renderBinding: binding,
            workspaceScaleDefault: workspaceScaleDefault,
            numericRange: NumericRange(
                lowerBound: 0.0,
                upperBound: maximumAuthoringLengthMeters
            ),
            isEditable: false
        )
    }

    static func derivedInteger(
        id: PropertyID,
        title: String,
        defaultValue: Int
    ) -> ObjectPropertyDefinition {
        ObjectPropertyDefinition(
            id: id,
            title: title,
            group: "Shape",
            valueKind: .integer,
            defaultValue: .integer(defaultValue),
            inspectorControl: .readOnly,
            effect: .derived,
            isEditable: false
        )
    }

    static func derivedBoolean(
        id: PropertyID,
        title: String,
        defaultValue: Bool
    ) -> ObjectPropertyDefinition {
        ObjectPropertyDefinition(
            id: id,
            title: title,
            group: "Shape",
            valueKind: .boolean,
            defaultValue: .boolean(defaultValue),
            inspectorControl: .readOnly,
            effect: .derived,
            isEditable: false
        )
    }

    static func text(
        id: PropertyID,
        title: String,
        defaultValue: String
    ) -> ObjectPropertyDefinition {
        ObjectPropertyDefinition(
            id: id,
            title: title,
            group: "Shape",
            valueKind: .text,
            defaultValue: .text(defaultValue),
            inspectorControl: .readOnly,
            effect: .derived,
            isEditable: false
        )
    }
}
