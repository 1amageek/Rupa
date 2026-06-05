import Foundation

public struct ObjectPropertyDefinition: Codable, Hashable, Identifiable, Sendable {
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
        try defaultValue.validate(id: id)
    }
}
