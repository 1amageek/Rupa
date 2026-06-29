import ArgumentParser
import RupaCore

public struct LoftModelCommand: ParsableCommand {
    public enum ResultKind: String, ExpressibleByArgument, Sendable {
        case solid
        case sheet

        var loftValue: LoftResultKind {
            switch self {
            case .solid:
                .solid
            case .sheet:
                .sheet
            }
        }
    }

    public enum SectionMatching: String, ExpressibleByArgument, Sendable {
        case byIndex

        var loftValue: LoftSectionMatching {
            switch self {
            case .byIndex:
                .byIndex
            }
        }
    }

    public static let configuration = CommandConfiguration(
        commandName: "loft",
        abstract: "Loft closed profile sections into a source-owned solid or sheet."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "Feature name.")
    public var name: String = "Loft"

    @Option(name: .customLong("section-feature-id"), help: "Closed profile sketch feature UUID used as a loft section. Repeatable.")
    public var sectionFeatureIDs: [String] = []

    @Option(name: .customLong("section-profile-index"), help: "Profile index for each section feature. Omit to use profile index 0 for every section.")
    public var sectionProfileIndexes: [Int] = []

    @Option(help: "Loft section matching policy.")
    public var sectionMatching: SectionMatching = .byIndex

    @Option(help: "Loft result kind: solid or sheet.")
    public var resultKind: ResultKind = .solid

    public init() {}

    public func run() throws {
        let sessionID = try document.resolvedSessionID()
        let input = try loftInput()

        try CLIExitCode.run {
            let response = try CLIService().createLoft(
                target: document.target(sessionID: sessionID),
                name: name,
                sections: input.sections,
                options: input.options,
                mode: document.mode,
                expectedGeneration: document.generation(),
                dryRun: document.dryRun,
                forceFileEdit: document.forceFileEdit,
                client: document.agentClient(sessionID: sessionID)
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }

    private func loftInput() throws -> (
        sections: [LoftSectionReference],
        options: LoftOptions
    ) {
        guard sectionFeatureIDs.count >= 2 else {
            throw ValidationError("Loft requires at least two section feature IDs.")
        }
        let profileIndexes: [Int]
        if sectionProfileIndexes.isEmpty {
            profileIndexes = Array(repeating: 0, count: sectionFeatureIDs.count)
        } else {
            guard sectionProfileIndexes.count == sectionFeatureIDs.count else {
                throw ValidationError("Section profile index count must match section feature ID count.")
            }
            profileIndexes = sectionProfileIndexes
        }
        guard profileIndexes.allSatisfy({ $0 >= 0 }) else {
            throw ValidationError("Section profile indexes must be zero or greater.")
        }

        let sections = try zip(sectionFeatureIDs, profileIndexes).map { featureIDValue, profileIndex in
            LoftSectionReference(profile: ProfileReference(
                featureID: try CLIFeatureReferenceParser.featureID(
                    featureIDValue,
                    valueName: "Section feature ID"
                ),
                profileIndex: profileIndex
            ))
        }
        return (
            sections: sections,
            options: LoftOptions(
                resultKind: resultKind.loftValue,
                sectionMatching: sectionMatching.loftValue
            )
        )
    }
}
