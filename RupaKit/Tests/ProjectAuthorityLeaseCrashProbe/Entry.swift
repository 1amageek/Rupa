import Darwin
import Foundation
import RupaProjectAccessComposition
import RupaProjectAccessPlatform

@main
struct ProjectAuthorityLeaseCrashProbe {
    static func main() async {
        let arguments = CommandLine.arguments
        guard let rootPath = value(after: "--root", in: arguments),
              let inputPath = value(after: "--input", in: arguments),
              let markerPath = value(after: "--marker", in: arguments) else {
            fputs("Missing lease probe arguments.\n", stderr)
            Darwin.exit(EXIT_FAILURE)
        }

        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let input = URL(fileURLWithPath: inputPath)
        let marker = URL(fileURLWithPath: markerPath)
        let store = ProjectFileAuthorityLeaseStore(rootDirectory: root)
        do {
            let lease = try await store.acquire(
                paths: [input],
                requiredPaths: [input],
                deadline: ContinuousClock.now.advanced(by: .seconds(10))
            )
            try await lease.validate()
            try Data("acquired\n".utf8).write(to: marker, options: .atomic)

            // Remain alive until the parent terminates this process. The
            // operating system must release every open-description lock when
            // this process is killed without calling release.
            while true {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
            }
        } catch {
            fputs("Lease probe failed: \(error)\n", stderr)
            Darwin.exit(EXIT_FAILURE)
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
