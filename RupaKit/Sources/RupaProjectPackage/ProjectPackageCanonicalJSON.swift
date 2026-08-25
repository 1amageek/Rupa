import Foundation

enum ProjectPackageCanonicalJSON {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(value)
        } catch {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Project package canonical JSON encoding failed: \(error)."
            )
        }
    }

    static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as ProjectPackageError {
            throw error
        } catch {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Project package canonical JSON decoding failed: \(error)."
            )
        }
    }
}
