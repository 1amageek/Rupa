import ArgumentParser
import Foundation
import RupaAgentProtocol
import RupaCoreTypes
import RupaDomainFoundation

/// Common access arguments for semantic CAD commands.
public struct CADSemanticAccessOptions: ParsableArguments, Sendable {
    @Option(name: .customLong("session-id"), help: "Open project session UUID.")
    public var sessionID: String?

    @Flag(help: "Validate and plan without committing the operation.")
    public var dryRun: Bool = false

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func target(file: String?) throws -> CLIDocumentTarget {
        let parsedSessionID = try CLISelectionInputParser.optionalSessionID(sessionID)
        guard !(file != nil && parsedSessionID != nil) else {
            throw ValidationError("A CAD command accepts either a project path or --session-id, not both.")
        }
        guard file != nil || parsedSessionID != nil else {
            throw ValidationError("A CAD command requires a .rupa project path or --session-id.")
        }
        return CLIDocumentTarget(
            fileURL: file.map(URL.init(fileURLWithPath:)),
            sessionID: parsedSessionID
        )
    }
}

enum CADSemanticInputError: Error, LocalizedError, Equatable, Sendable {
    case inputTooLarge(label: String, maximum: Int)
    case unreadable(label: String, reason: String)
    case malformed(label: String, reason: String)
    case invalidVersion(label: String, value: String)
    case invalidOperationID(String)
    case duplicateArgument(String)
    case conflictingArgumentSources
    case invalidInvocationShape(String)

    var errorDescription: String? {
        switch self {
        case .inputTooLarge(let label, let maximum):
            return "\(label) exceeds the \(maximum)-byte semantic input limit."
        case .unreadable(let label, let reason):
            return "Could not read \(label): \(reason)."
        case .malformed(let label, let reason):
            return "Could not decode \(label): \(reason)."
        case .invalidVersion(let label, let value):
            return "\(label) must be a dot-separated major.minor.patch version: \(value)."
        case .invalidOperationID(let value):
            return "Operation ID must be a qualified non-empty name: \(value)."
        case .duplicateArgument(let name):
            return "CAD argument names must be unique: \(name)."
        case .conflictingArgumentSources:
            return "Use either repeated --argument values or --arguments-file, not both."
        case .invalidInvocationShape(let message):
            return message
        }
    }
}

enum CADSemanticInputReader {
    static let maximumByteCount = AgentProtocolEncodingLimits.defaultMaximumByteCount

    static func decode<T: Decodable>(
        _ type: T.Type,
        source: String,
        label: String
    ) throws -> T {
        let data = try boundedData(source: source, label: label)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CADSemanticInputError.malformed(label: label, reason: String(describing: error))
        }
    }

    static func boundedData(source: String, label: String) throws -> Data {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{" || trimmed.first == "[" {
            guard let data = trimmed.data(using: .utf8) else {
                throw CADSemanticInputError.unreadable(label: label, reason: "the value is not valid UTF-8")
            }
            try enforceLimit(data.count, label: label)
            return data
        }

        let url = URL(fileURLWithPath: source)
        let byteCount: Int
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let number = attributes[.size] as? NSNumber else {
                throw CADSemanticInputError.unreadable(label: label, reason: "the file size is unavailable")
            }
            guard number.int64Value >= 0,
                  number.int64Value <= Int64(Int.max) else {
                throw CADSemanticInputError.inputTooLarge(
                    label: label,
                    maximum: maximumByteCount
                )
            }
            byteCount = Int(number.int64Value)
            try enforceLimit(byteCount, label: label)
        } catch let error as CADSemanticInputError {
            throw error
        } catch {
            throw CADSemanticInputError.unreadable(label: label, reason: String(describing: error))
        }

        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count == byteCount else {
                throw CADSemanticInputError.unreadable(label: label, reason: "the file changed while it was read")
            }
            try enforceLimit(data.count, label: label)
            return data
        } catch let error as CADSemanticInputError {
            throw error
        } catch {
            throw CADSemanticInputError.unreadable(label: label, reason: String(describing: error))
        }
    }

    static func parseVersion(
        _ rawValue: String,
        label: String
    ) throws -> (major: UInt32, minor: UInt32, patch: UInt32) {
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              let major = UInt32(components[0]),
              let minor = UInt32(components[1]),
              let patch = UInt32(components[2]) else {
            throw CADSemanticInputError.invalidVersion(label: label, value: rawValue)
        }
        return (major, minor, patch)
    }

    static func operationID(_ rawValue: String) throws -> DomainCapabilityID {
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2,
              components.allSatisfy({ !$0.isEmpty }) else {
            throw CADSemanticInputError.invalidOperationID(rawValue)
        }
        let value = DomainCapabilityID(rawValue: rawValue)
        do {
            try value.validate()
            return value
        } catch {
            throw CADSemanticInputError.invalidOperationID(rawValue)
        }
    }

    static func enforceLimit(_ byteCount: Int, label: String) throws {
        guard byteCount <= maximumByteCount else {
            throw CADSemanticInputError.inputTooLarge(
                label: label,
                maximum: maximumByteCount
            )
        }
    }
}
