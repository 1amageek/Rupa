import Foundation

public struct ObjectPropertyDefinition: Codable, Hashable, Identifiable, Sendable {
    public enum WorkspaceScaleDefault: String, Codable, Hashable, Sendable {
        case sketchWidth
        case sketchHeight
        case sketchDepth
        case cylinderDepth
        case placedSolidSide
        case curveRadius
        case curveDiameter
        case narrowProfileWidth
        case narrowProfileRadius

        public func meters(from defaults: WorkspaceScaleDefaults) -> Double {
            switch self {
            case .sketchWidth:
                defaults.sketchWidthMeters
            case .sketchHeight:
                defaults.sketchHeightMeters
            case .sketchDepth:
                defaults.sketchDepthMeters
            case .cylinderDepth:
                defaults.cylinderDepthMeters
            case .placedSolidSide:
                defaults.placedSolidSideMeters
            case .curveRadius:
                defaults.curveRadiusMeters
            case .curveDiameter:
                defaults.curveRadiusMeters * 2.0
            case .narrowProfileWidth:
                defaults.baseFeatureMeters * 0.1
            case .narrowProfileRadius:
                defaults.baseFeatureMeters * 0.05
            }
        }
    }

    public enum InspectorControl: String, Codable, Hashable, Sendable {
        case textField
        case textFieldAndSlider
        case toggle
        case segmented
        case menu
        case materialPicker
        case readOnly
    }

    public struct RenderBinding: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
        public var rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.rawValue = value
        }

        public static let sizeX: RenderBinding = "size.x"
        public static let sizeY: RenderBinding = "size.y"
        public static let sizeZ: RenderBinding = "size.z"
        public static let radius: RenderBinding = "radius"
        public static let topRadius: RenderBinding = "top.radius"
        public static let bottomRadius: RenderBinding = "bottom.radius"
        public static let sideSegments: RenderBinding = "segments.side"
        public static let verticalSegments: RenderBinding = "segments.vertical"
        public static let angle: RenderBinding = "angle"
        public static let capVisibility: RenderBinding = "caps.visible"
        public static let hollow: RenderBinding = "hollow"
        public static let cornerRadius: RenderBinding = "corner.radius"
        public static let cornerSideSegments: RenderBinding = "corner.segments"
        public static let subdivisionSegments: RenderBinding = "subdivision.segments"
        public static let extrusion: RenderBinding = "extrusion"
        public static let bevel: RenderBinding = "bevel"
        public static let bevelSideSegments: RenderBinding = "bevel.segments"
        public static let material: RenderBinding = "material"
        public static let strokeWidth: RenderBinding = "stroke.width"
        public static let textContent: RenderBinding = "text.content"
        public static let textSize: RenderBinding = "text.size"
        public static let fontFamily: RenderBinding = "font.family"
    }

    public struct NumericRange: Codable, Hashable, Sendable {
        public var lowerBound: Double
        public var upperBound: Double

        public init(lowerBound: Double, upperBound: Double) {
            self.lowerBound = lowerBound
            self.upperBound = upperBound
        }
    }

    public var id: ObjectPropertyID
    public var title: String
    public var group: String
    public var valueKind: ObjectPropertyValue.ValueKind
    public var defaultValue: ObjectPropertyValue
    public var inspectorControl: InspectorControl
    public var renderBinding: RenderBinding?
    public var workspaceScaleDefault: WorkspaceScaleDefault?
    public var numericRange: NumericRange?
    public var isEditable: Bool

    public init(
        id: ObjectPropertyID,
        title: String,
        group: String,
        valueKind: ObjectPropertyValue.ValueKind,
        defaultValue: ObjectPropertyValue,
        inspectorControl: InspectorControl,
        renderBinding: RenderBinding? = nil,
        workspaceScaleDefault: WorkspaceScaleDefault? = nil,
        numericRange: NumericRange? = nil,
        isEditable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.group = group
        self.valueKind = valueKind
        self.defaultValue = defaultValue
        self.inspectorControl = inspectorControl
        self.renderBinding = renderBinding
        self.workspaceScaleDefault = workspaceScaleDefault
        self.numericRange = numericRange
        self.isEditable = isEditable
    }

    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentValidationError.invalidProductMetadata("Object property titles must not be empty.")
        }
        guard !group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentValidationError.invalidProductMetadata("Object property groups must not be empty.")
        }
        guard defaultValue.valueKind == valueKind else {
            throw DocumentValidationError.invalidProductMetadata(
                "Object property \(id.rawValue) default value must match its declared value kind."
            )
        }
        if let numericRange {
            guard numericRange.lowerBound.isFinite,
                  numericRange.upperBound.isFinite,
                  numericRange.lowerBound < numericRange.upperBound else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Object property \(id.rawValue) numeric range must be finite and ordered."
                )
            }
        }
        if workspaceScaleDefault != nil, valueKind != .length {
            throw DocumentValidationError.invalidProductMetadata(
                "Object property \(id.rawValue) workspace scale defaults can only be applied to length values."
            )
        }
        try defaultValue.validate(id: id)
    }
}
