import ArgumentParser
import Foundation
import RupaCore

public struct NewDocumentCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create a new empty Rupa document so headless agents can bootstrap without the app."
    )

    @Argument(help: "Path for the new .swcad document.")
    public var file: String

    @Option(help: "Document name stored in the package metadata.")
    public var name: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        try CLIExitCode.run {
            let url = URL(fileURLWithPath: file)
            guard FileManager.default.fileExists(atPath: url.path) == false else {
                throw EditorError(
                    code: .documentSaveFailed,
                    message: "A document already exists at \(url.path). Refusing to overwrite."
                )
            }
            let documentName = name ?? url.deletingPathExtension().lastPathComponent
            let document = DesignDocument.empty(named: documentName)
            try DocumentFileService().save(document, to: url)
            let response = CLIResponse(
                message: "Document \(documentName) created at \(url.path).",
                generation: 0,
                dirty: false,
                saved: true,
                diagnostics: []
            )
            try CLIOutput.write(response: response, asJSON: json)
        }
    }
}
