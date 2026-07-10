import RupaCore

public struct ManufacturingPrintabilityOptions: Equatable, Sendable {
    public var processID: ManufacturingProcessID
    public var buildVolume: BuildVolume
    public var requireMaterialAssignment: Bool
    public var requireExportReadyMesh: Bool
    public var overhangLimitDegrees: Double
    public var minimumWallThicknessMeters: Double?
    public var minimumClearanceMeters: Double?

    public init(
        processID: ManufacturingProcessID = .materialExtrusion,
        buildVolume: BuildVolume = .defaultPrintVolume,
        requireMaterialAssignment: Bool = true,
        requireExportReadyMesh: Bool = true,
        overhangLimitDegrees: Double = 45.0,
        minimumWallThicknessMeters: Double? = 0.0008,
        minimumClearanceMeters: Double? = 0.0002
    ) {
        self.processID = processID
        self.buildVolume = buildVolume
        self.requireMaterialAssignment = requireMaterialAssignment
        self.requireExportReadyMesh = requireExportReadyMesh
        self.overhangLimitDegrees = overhangLimitDegrees
        self.minimumWallThicknessMeters = minimumWallThicknessMeters
        self.minimumClearanceMeters = minimumClearanceMeters
    }

    public init(
        payload: SemanticJSONValue,
        defaultProcessID: ManufacturingProcessID = .materialExtrusion
    ) throws {
        switch payload {
        case .null:
            self.init(processID: defaultProcessID)
        case .object(let object):
            try Self.validateKnownKeys(
                in: object,
                allowedKeys: [
                    "processID",
                    "buildVolume",
                    "requireMaterialAssignment",
                    "requireExportReadyMesh",
                    "overhangLimitDegrees",
                    "minimumWallThicknessMeters",
                    "minimumClearanceMeters",
                ],
                context: "Manufacturing printability validation payload"
            )
            self.init(
                processID: ManufacturingProcessID(rawValue: try Self.stringValue(
                    for: "processID",
                    in: object,
                    defaultValue: defaultProcessID.rawValue
                )),
                buildVolume: try BuildVolume(payload: object["buildVolume"]),
                requireMaterialAssignment: try Self.boolValue(
                    for: "requireMaterialAssignment",
                    in: object,
                    defaultValue: true
                ),
                requireExportReadyMesh: try Self.boolValue(
                    for: "requireExportReadyMesh",
                    in: object,
                    defaultValue: true
                ),
                overhangLimitDegrees: try Self.positiveAngleValue(
                    for: "overhangLimitDegrees",
                    in: object,
                    defaultValue: 45.0
                ),
                minimumWallThicknessMeters: try Self.optionalPositiveNumber(
                    for: "minimumWallThicknessMeters",
                    in: object,
                    defaultValue: 0.0008
                ),
                minimumClearanceMeters: try Self.optionalPositiveNumber(
                    for: "minimumClearanceMeters",
                    in: object,
                    defaultValue: 0.0002
                )
            )
        case .array, .string, .number, .bool:
            throw EditorError(
                code: .commandInvalid,
                message: "Manufacturing printability validation payload must be an object or null."
            )
        }
    }

    public struct BuildVolume: Equatable, Sendable {
        public var widthMeters: Double
        public var depthMeters: Double
        public var heightMeters: Double

        public init(
            widthMeters: Double,
            depthMeters: Double,
            heightMeters: Double
        ) {
            self.widthMeters = widthMeters
            self.depthMeters = depthMeters
            self.heightMeters = heightMeters
        }

        public static let defaultPrintVolume = BuildVolume(
            widthMeters: 0.256,
            depthMeters: 0.256,
            heightMeters: 0.256
        )

        init(payload: SemanticJSONValue?) throws {
            guard let payload else {
                self = .defaultPrintVolume
                return
            }
            guard case .object(let object) = payload else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Manufacturing buildVolume must be an object."
                )
            }
            try ManufacturingPrintabilityOptions.validateKnownKeys(
                in: object,
                allowedKeys: [
                    "widthMeters",
                    "depthMeters",
                    "heightMeters",
                ],
                context: "Manufacturing buildVolume"
            )
            self.init(
                widthMeters: try Self.requiredPositiveNumber(
                    "widthMeters",
                    in: object
                ),
                depthMeters: try Self.requiredPositiveNumber(
                    "depthMeters",
                    in: object
                ),
                heightMeters: try Self.requiredPositiveNumber(
                    "heightMeters",
                    in: object
                )
            )
        }

        var payload: SemanticJSONValue {
            .object([
                "widthMeters": .number(widthMeters),
                "depthMeters": .number(depthMeters),
                "heightMeters": .number(heightMeters),
            ])
        }

        func contains(_ bounds: MeasurementResult.Bounds) -> Bool {
            bounds.sizeX <= widthMeters
                && bounds.sizeY <= heightMeters
                && bounds.sizeZ <= depthMeters
        }

        private static func requiredPositiveNumber(
            _ key: String,
            in object: [String: SemanticJSONValue]
        ) throws -> Double {
            guard let value = object[key] else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Manufacturing buildVolume.\(key) is required."
                )
            }
            guard case .number(let number) = value,
                  number.isFinite,
                  number > 0.0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Manufacturing buildVolume.\(key) must be a positive finite number."
                )
            }
            return number
        }
    }

    var payload: SemanticJSONValue {
        var object: [String: SemanticJSONValue] = [
            "processID": .string(processID.rawValue),
            "buildVolume": buildVolume.payload,
            "requireMaterialAssignment": .bool(requireMaterialAssignment),
            "requireExportReadyMesh": .bool(requireExportReadyMesh),
            "overhangLimitDegrees": .number(overhangLimitDegrees),
        ]
        object["minimumWallThicknessMeters"] = minimumWallThicknessMeters.map(SemanticJSONValue.number) ?? .null
        object["minimumClearanceMeters"] = minimumClearanceMeters.map(SemanticJSONValue.number) ?? .null
        return .object(object)
    }

    private static func stringValue(
        for key: String,
        in object: [String: SemanticJSONValue],
        defaultValue: String
    ) throws -> String {
        guard let value = object[key] else {
            return defaultValue
        }
        guard case .string(let string) = value,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Manufacturing \(key) must be a non-empty string."
            )
        }
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func boolValue(
        for key: String,
        in object: [String: SemanticJSONValue],
        defaultValue: Bool
    ) throws -> Bool {
        guard let value = object[key] else {
            return defaultValue
        }
        guard case .bool(let bool) = value else {
            throw EditorError(
                code: .commandInvalid,
                message: "Manufacturing \(key) must be a Boolean."
            )
        }
        return bool
    }

    private static func positiveAngleValue(
        for key: String,
        in object: [String: SemanticJSONValue],
        defaultValue: Double
    ) throws -> Double {
        guard let value = object[key] else {
            return defaultValue
        }
        guard case .number(let number) = value,
              number.isFinite,
              number > 0.0,
              number <= 90.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Manufacturing \(key) must be a positive finite angle no greater than 90 degrees."
            )
        }
        return number
    }

    private static func optionalPositiveNumber(
        for key: String,
        in object: [String: SemanticJSONValue],
        defaultValue: Double?
    ) throws -> Double? {
        guard let value = object[key] else {
            return defaultValue
        }
        if case .null = value {
            return nil
        }
        guard case .number(let number) = value,
              number.isFinite,
              number > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Manufacturing \(key) must be null or a positive finite number."
            )
        }
        return number
    }

    private static func validateKnownKeys(
        in object: [String: SemanticJSONValue],
        allowedKeys: Set<String>,
        context: String
    ) throws {
        let unknownKeys = object.keys.filter { !allowedKeys.contains($0) }.sorted()
        guard unknownKeys.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(context) contains unsupported option(s): \(unknownKeys.joined(separator: ", "))."
            )
        }
    }
}
