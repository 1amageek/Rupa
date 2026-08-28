import Foundation

enum CADBenchmarkCLIOutput {
    static func write(_ data: Data) throws {
        try FileHandle.standardOutput.write(contentsOf: data)
    }
}
