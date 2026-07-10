import Foundation
import RupaCore

public struct DomainCommandParameterDescriptor: Codable, Equatable, Sendable {
    public var id: String
    public var payloadPath: [String]
    public var label: String
    public var summary: String
    public var group: String
    public var kind: DomainCommandParameterKind
    public var unit: DomainCommandParameterUnit
    public var isRequired: Bool
    public var allowsNull: Bool
    public var defaultValue: SemanticJSONValue?
    public var minimumValue: Double?
    public var maximumValue: Double?
    public var choices: [DomainCommandParameterChoice]

    public init(
        id: String,
        payloadPath: [String],
        label: String,
        summary: String,
        group: String = "Options",
        kind: DomainCommandParameterKind,
        unit: DomainCommandParameterUnit = .unitless,
        isRequired: Bool = false,
        allowsNull: Bool = false,
        defaultValue: SemanticJSONValue? = nil,
        minimumValue: Double? = nil,
        maximumValue: Double? = nil,
        choices: [DomainCommandParameterChoice] = []
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
            throw invalidRegistration("Domain command parameter IDs must not be empty.")
        }
        guard !payloadPath.isEmpty,
              payloadPath.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw invalidRegistration(
                "Domain command parameter \(id) must have a non-empty payload path."
            )
        }
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalidRegistration(
                "Domain command parameter \(id) must have a non-empty label."
            )
        }
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalidRegistration(
                "Domain command parameter \(id) must have a non-empty summary."
            )
        }
        guard !group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalidRegistration(
                "Domain command parameter \(id) must have a non-empty group."
            )
        }
        guard !isRequired || !allowsNull else {
            throw invalidRegistration(
                "Required domain command parameter \(id) cannot allow null values."
            )
        }
        try validateUnit()
        try validateBounds()
        try validateChoices()
        if let defaultValue {
            do {
                try validateValue(defaultValue)
            } catch let error as DomainCommandPayloadError {
                throw invalidRegistration(
                    "Domain command parameter \(id) has an invalid default value: \(error.message)"
                )
            }
        }
    }

    public func validateValue(_ value: SemanticJSONValue) throws {
        if case .null = value {
            guard allowsNull else {
                throw payloadError("Parameter \(id) does not allow null values.")
            }
            return
        }

        switch (kind, value) {
        case (.text, .string(let text)):
            if isRequired, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw payloadError("Required text parameter \(id) must not be empty.")
            }
        case (.boolean, .bool):
            break
        case (.integer, .number(let number)):
            guard number.isFinite,
                  number.rounded() == number,
                  Int(exactly: number) != nil else {
                throw payloadError("Parameter \(id) must be an integer representable by the current platform.")
            }
            try validateNumericBounds(number)
        case (.number, .number(let number)),
             (.length, .number(let number)),
             (.angle, .number(let number)):
            guard number.isFinite else {
                throw payloadError("Parameter \(id) must be a finite number.")
            }
            try validateNumericBounds(number)
        case (.choice, .string(let selectedValue)):
            guard choices.contains(where: { $0.value == selectedValue }) else {
                throw payloadError(
                    "Parameter \(id) must use one of its registered choice values."
                )
            }
        default:
            throw payloadError("Parameter \(id) has a value that does not match \(kind.rawValue).")
        }
    }

    private func validateBounds() throws {
        if let minimumValue, !minimumValue.isFinite {
            throw invalidRegistration(
                "Domain command parameter \(id) minimumValue must be finite."
            )
        }
        if kind == .integer {
            if let minimumValue, minimumValue.rounded() != minimumValue {
                throw invalidRegistration(
                    "Integer parameter \(id) minimumValue must be an integer."
                )
            }
            if let maximumValue, maximumValue.rounded() != maximumValue {
                throw invalidRegistration(
                    "Integer parameter \(id) maximumValue must be an integer."
                )
            }
        }
        if let maximumValue, !maximumValue.isFinite {
            throw invalidRegistration(
                "Domain command parameter \(id) maximumValue must be finite."
            )
        }
        if let minimumValue, let maximumValue, minimumValue > maximumValue {
            throw invalidRegistration(
                "Domain command parameter \(id) minimumValue must not exceed maximumValue."
            )
        }
        if minimumValue != nil || maximumValue != nil {
            switch kind {
            case .integer, .number, .length, .angle:
                break
            case .text, .boolean, .choice:
                throw invalidRegistration(
                    "Domain command parameter \(id) can only define numeric bounds for numeric kinds."
                )
            }
        }
    }

    private func validateUnit() throws {
        let expectedUnit: DomainCommandParameterUnit
        switch kind {
        case .length:
            expectedUnit = .meter
        case .angle:
            expectedUnit = .degree
        case .text, .boolean, .integer, .number, .choice:
            expectedUnit = .unitless
        }
        guard unit == expectedUnit else {
            throw invalidRegistration(
                "Domain command parameter \(id) must use the \(expectedUnit.rawValue) payload unit for \(kind.rawValue) values."
            )
        }
    }

    private func validateChoices() throws {
        switch kind {
        case .choice:
            guard !choices.isEmpty else {
                throw invalidRegistration(
                    "Choice parameter \(id) must register at least one choice."
                )
            }
            for choice in choices {
                try choice.validate()
            }
            guard Set(choices.map(\.value)).count == choices.count else {
                throw invalidRegistration(
                    "Choice parameter \(id) must not contain duplicate values."
                )
            }
        case .text, .boolean, .integer, .number, .length, .angle:
            guard choices.isEmpty else {
                throw invalidRegistration(
                    "Only choice parameters can register choices."
                )
            }
        }
    }

    private func validateNumericBounds(_ number: Double) throws {
        if let minimumValue, number < minimumValue {
            throw payloadError("Parameter \(id) must be at least \(minimumValue).")
        }
        if let maximumValue, number > maximumValue {
            throw payloadError("Parameter \(id) must be no greater than \(maximumValue).")
        }
    }

    private func invalidRegistration(_ message: String) -> DomainRegistryError {
        DomainRegistryError(code: .invalidRegistration, message: message)
    }

    private func payloadError(_ message: String) -> DomainCommandPayloadError {
        DomainCommandPayloadError(code: .invalidValue, parameterID: id, message: message)
    }
}
