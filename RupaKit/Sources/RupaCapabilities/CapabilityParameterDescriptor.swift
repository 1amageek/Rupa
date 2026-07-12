import Foundation
import RupaCoreTypes

public struct CapabilityParameterDescriptor: Codable, Equatable, Sendable {
    public var id: String
    public var payloadPath: [String]
    public var label: String
    public var summary: String
    public var group: String
    public var kind: CapabilityParameterKind
    public var unit: CapabilityParameterUnit
    public var isRequired: Bool
    public var allowsNull: Bool
    public var defaultValue: CanonicalValue?
    public var minimumValue: Double?
    public var maximumValue: Double?
    public var choices: [CapabilityChoice]

    public init(
        id: String,
        payloadPath: [String],
        label: String,
        summary: String,
        group: String = "Options",
        kind: CapabilityParameterKind,
        unit: CapabilityParameterUnit = .unitless,
        isRequired: Bool = false,
        allowsNull: Bool = false,
        defaultValue: CanonicalValue? = nil,
        minimumValue: Double? = nil,
        maximumValue: Double? = nil,
        choices: [CapabilityChoice] = []
    ) {
        self.id = id
        self.payloadPath = payloadPath
        self.label = label
        self.summary = summary
        self.group = group
        self.kind = kind
        self.unit = unit
        self.isRequired = isRequired
        self.allowsNull = allowsNull
        self.defaultValue = defaultValue
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.choices = choices
    }

    public func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid("Capability parameter IDs must not be empty.")
        }
        guard !payloadPath.isEmpty,
              payloadPath.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw invalid("Capability parameter (id) must have a non-empty payload path.")
        }
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid("Capability parameter (id) must have a non-empty label.")
        }
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid("Capability parameter (id) must have a non-empty summary.")
        }
        guard !group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid("Capability parameter (id) must have a non-empty group.")
        }
        guard !isRequired || !allowsNull else {
            throw invalid("Required capability parameter (id) cannot allow null values.")
        }
        try validateUnit()
        try validateBounds()
        try validateChoices()
        if let defaultValue {
            try defaultValue.validate()
            try validateValue(defaultValue)
        }
    }

    public func validateValue(_ value: CanonicalValue) throws {
        if case .null = value {
            guard allowsNull else {
                throw invalid("Capability parameter (id) does not allow null values.")
            }
            return
        }

        switch (kind, value) {
        case (.text, .string(let text)):
            if isRequired, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw invalid("Required text parameter (id) must not be empty.")
            }
        case (.boolean, .bool):
            break
        case (.integer, .number(let number)):
            guard number.isFinite,
                  number.rounded() == number,
                  Int(exactly: number) != nil else {
                throw invalid("Parameter (id) must be an integer representable by the current platform.")
            }
            try validateNumericBounds(number)
        case (.number, .number(let number)),
             (.length, .number(let number)),
             (.angle, .number(let number)):
            guard number.isFinite else {
                throw invalid("Parameter (id) must be a finite number.")
            }
            try validateNumericBounds(number)
        case (.choice, .string(let selectedValue)):
            guard choices.contains(where: { $0.value == selectedValue }) else {
                throw invalid("Parameter (id) must use one of its registered choice values.")
            }
        default:
            throw invalid("Parameter (id) has a value that does not match (kind.rawValue).")
        }
    }

    private func validateBounds() throws {
        if let minimumValue, !minimumValue.isFinite {
            throw invalid("Capability parameter (id) minimumValue must be finite.")
        }
        if let maximumValue, !maximumValue.isFinite {
            throw invalid("Capability parameter (id) maximumValue must be finite.")
        }
        if kind == .integer {
            if let minimumValue, minimumValue.rounded() != minimumValue {
                throw invalid("Integer parameter (id) minimumValue must be an integer.")
            }
            if let maximumValue, maximumValue.rounded() != maximumValue {
                throw invalid("Integer parameter (id) maximumValue must be an integer.")
            }
        }
        if let minimumValue, let maximumValue, minimumValue > maximumValue {
            throw invalid("Capability parameter (id) minimumValue must not exceed maximumValue.")
        }
        if minimumValue != nil || maximumValue != nil {
            switch kind {
            case .integer, .number, .length, .angle:
                break
            case .text, .boolean, .choice:
                throw invalid("Capability parameter (id) can only define numeric bounds for numeric kinds.")
            }
        }
    }

    private func validateUnit() throws {
        let expectedUnit: CapabilityParameterUnit
        switch kind {
        case .length:
            expectedUnit = .meter
        case .angle:
            expectedUnit = .degree
        case .text, .boolean, .integer, .number, .choice:
            expectedUnit = .unitless
        }
        guard unit == expectedUnit else {
            throw invalid(
                "Capability parameter (id) must use the (expectedUnit.rawValue) payload unit for (kind.rawValue) values."
            )
        }
    }

    private func validateChoices() throws {
        switch kind {
        case .choice:
            guard !choices.isEmpty else {
                throw invalid("Choice parameter (id) must register at least one choice.")
            }
            for choice in choices {
                try choice.validate()
            }
            guard Set(choices.map(\.value)).count == choices.count else {
                throw invalid("Choice parameter (id) must not contain duplicate values.")
            }
        case .text, .boolean, .integer, .number, .length, .angle:
            guard choices.isEmpty else {
                throw invalid("Only choice parameters can register choices.")
            }
        }
    }

    private func validateNumericBounds(_ number: Double) throws {
        if let minimumValue, number < minimumValue {
            throw invalid("Parameter (id) must be at least (minimumValue).")
        }
        if let maximumValue, number > maximumValue {
            throw invalid("Parameter (id) must be no greater than (maximumValue).")
        }
    }

    private func invalid(_ message: String) -> CapabilityRegistryError {
        CapabilityRegistryError(code: .invalidDescriptor, message: message)
    }
}
