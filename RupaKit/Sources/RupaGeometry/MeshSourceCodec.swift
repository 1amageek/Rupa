import Foundation

public enum MeshSourceCodec {
    public static func encode(_ source: MeshSource) throws -> Data {
        try source.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(source)
    }

    public static func decode(_ data: Data) throws -> MeshSource {
        do {
            let source = try JSONDecoder().decode(MeshSource.self, from: data)
            try source.validate()
            return source
        } catch let error as MeshSourceError {
            throw error
        } catch {
            throw MeshSourceError(
                code: .malformedPayload,
                message: "Mesh source payload could not be decoded: \(error.localizedDescription)"
            )
        }
    }
}
