import Foundation

public enum CADJSONBoundedCodec {
    static func encode(_ value: CADJSONRequestEnvelope) throws -> Data {
        try value.validate()
        return try encodeEnvelope(value)
    }

    static func encode(_ value: CADJSONCandidateResponseEnvelope) throws -> Data {
        try value.validate()
        return try encodeEnvelope(value)
    }

    static func encode(_ value: CADJSONEvaluationEnvelope) throws -> Data {
        try value.validate()
        return try encodeEnvelope(value)
    }

    public static func encode(_ value: CADJSONErrorEnvelope) throws -> Data {
        try value.validate()
        return try encodeEnvelope(value)
    }

    private static func encodeEnvelope<Value: Encodable>(_ value: Value) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(value)
            guard data.count <= CADJSONAdapterSchema.maximumDocumentBytes else {
                throw CADJSONAdapterError.outputOverflow
            }
            return data
        } catch let error as CADJSONAdapterError {
            throw error
        } catch {
            throw CADJSONAdapterError.infrastructureFailure
        }
    }

    public static func decode(
        _ type: CADJSONRequestEnvelope.Type,
        from data: Data
    ) throws -> CADJSONRequestEnvelope {
        try decodeEnvelope(type, from: data)
    }

    public static func decode(
        _ type: CADJSONCandidateResponseEnvelope.Type,
        from data: Data
    ) throws -> CADJSONCandidateResponseEnvelope {
        try decodeEnvelope(type, from: data)
    }

    public static func decode(
        _ type: CADJSONEvaluationEnvelope.Type,
        from data: Data
    ) throws -> CADJSONEvaluationEnvelope {
        try decodeEnvelope(type, from: data)
    }

    public static func decode(
        _ type: CADJSONErrorEnvelope.Type,
        from data: Data
    ) throws -> CADJSONErrorEnvelope {
        try decodeEnvelope(type, from: data)
    }

    private static func decodeEnvelope<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        guard data.count <= CADJSONAdapterSchema.maximumDocumentBytes else {
            throw CADJSONAdapterError.oversizedInput
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw CADJSONAdapterError.malformedUTF8
        }
        try validateFraming(data)

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as CADJSONAdapterError {
            throw error
        } catch {
            throw CADJSONAdapterError.malformedJSON
        }
    }

    public static func readStandardInput() throws -> Data {
        do {
            return try readStandardInput(from: FileHandle.standardInput)
        } catch let error as CADJSONAdapterError {
            throw error
        } catch {
            throw CADJSONAdapterError.inputFailure
        }
    }

    // This seam is used by tests with a Pipe and is the exact reader used by standard input.
    static func readStandardInput(from handle: FileHandle) throws -> Data {
        do {
            return try readChunks(from: handle)
        } catch let error as CADJSONAdapterError {
            throw error
        } catch {
            throw CADJSONAdapterError.inputFailure
        }
    }

    public static func readRegularFile(
        at path: String
    ) throws -> Data {
        guard path.isEmpty == false else {
            throw CADJSONAdapterError.unsupportedInputSource
        }
        guard path.hasPrefix("http://") == false,
              path.hasPrefix("https://") == false,
              path.hasPrefix("file://") == false else {
            throw CADJSONAdapterError.unsupportedInputSource
        }

        let manager = FileManager.default
        guard manager.fileExists(atPath: path) else {
            throw CADJSONAdapterError.inputFailure
        }
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try manager.attributesOfItem(atPath: path)
        } catch {
            throw CADJSONAdapterError.inputFailure
        }
        guard let type = attributes[.type] as? FileAttributeType else {
            throw CADJSONAdapterError.inputFailure
        }
        guard type == .typeRegular else {
            if type == .typeDirectory {
                throw CADJSONAdapterError.directoryInput
            }
            throw CADJSONAdapterError.unsupportedInputSource
        }

        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw CADJSONAdapterError.inputFailure
        }
        do {
            let data = try readChunks(from: handle)
            do {
                try handle.close()
            } catch {
                throw CADJSONAdapterError.inputFailure
            }
            return data
        } catch let error as CADJSONAdapterError {
            do {
                try handle.close()
            } catch {
                throw CADJSONAdapterError.inputFailure
            }
            throw error
        } catch {
            do {
                try handle.close()
            } catch {
                throw CADJSONAdapterError.inputFailure
            }
            throw CADJSONAdapterError.inputFailure
        }
    }

    private static func readChunks(from handle: FileHandle) throws -> Data {
        let maximumBytes = CADJSONAdapterSchema.maximumDocumentBytes
        var data = Data()
        data.reserveCapacity(min(maximumBytes, 8_192))
        let chunkSize = 8_192
        while true {
            let remaining = maximumBytes - data.count
            let readSize = remaining >= 0 ? min(chunkSize, remaining + 1) : 1
            guard let chunk = try handle.read(upToCount: readSize), chunk.isEmpty == false else {
                break
            }
            data.append(chunk)
            if data.count > maximumBytes {
                throw CADJSONAdapterError.oversizedInput
            }
        }
        return data
    }

    private static func validateFraming(_ data: Data) throws {
        let bytes = Array(data)
        var index = 0
        skipWhitespace(in: bytes, index: &index)
        guard index < bytes.count, bytes[index] == 0x7B else {
            throw CADJSONAdapterError.malformedJSON
        }

        var depth = 0
        var inString = false
        var escaped = false
        var endIndex: Int?
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                }
                index += 1
                continue
            }

            switch byte {
            case 0x22:
                inString = true
            case 0x7B:
                depth += 1
            case 0x7D:
                depth -= 1
                if depth == 0 {
                    endIndex = index + 1
                    index = bytes.count
                } else if depth < 0 {
                    throw CADJSONAdapterError.malformedJSON
                }
            default:
                break
            }
            index += 1
        }

        guard inString == false, escaped == false, depth == 0, let endIndex else {
            throw CADJSONAdapterError.malformedJSON
        }
        var trailingIndex = endIndex
        skipWhitespace(in: bytes, index: &trailingIndex)
        guard trailingIndex == bytes.count else {
            throw CADJSONAdapterError.trailingData
        }
    }

    private static func skipWhitespace(in bytes: [UInt8], index: inout Int) {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D:
                index += 1
            default:
                return
            }
        }
    }
}
