import Foundation
import Testing

@Test(.timeLimit(.minutes(1)))
func packageSourceImportsRespectArchitectureBoundaries() throws {
    let packageRoot = try rupaKitPackageRoot()
    let sourcesRoot = packageRoot.appendingPathComponent("Sources")
    let forbiddenImportsByTarget: [String: Set<String>] = [
        "RupaCore": [
            "RupaAutomation",
            "RupaDomainFoundation",
            "RupaUI",
            "RupaAgent",
            "RupaAgentProtocol",
            "RupaAgentRuntime",
            "RupaAgentTransport",
            "RupaCLIKit",
            "RupaCLI",
        ],
        "RupaAutomation": [
            "RupaDomainFoundation",
            "RupaUI",
            "RupaAgent",
            "RupaAgentProtocol",
            "RupaAgentRuntime",
            "RupaAgentTransport",
            "RupaCLIKit",
            "RupaCLI",
        ],
        "RupaDomainFoundation": [
            "RupaUI",
            "RupaAgent",
            "RupaAgentProtocol",
            "RupaAgentRuntime",
            "RupaAgentTransport",
            "RupaCLIKit",
            "RupaCLI",
        ],
        "RupaAgentProtocol": [
            "RupaAgentRuntime",
            "RupaAgentTransport",
            "RupaCLIKit",
            "RupaCLI",
            "RupaUI",
        ],
        "RupaAgentRuntime": [
            "RupaCLIKit",
            "RupaCLI",
            "RupaUI",
        ],
        "RupaCLIKit": [
            "RupaUI",
        ],
    ]
    let concreteDomainImports: Set<String> = [
        "RupaArchitecture",
        "RupaTurbomachinery",
        "RupaCharacterDesign",
        "RupaManufacturing",
        "RupaSimulation",
    ]

    var violations: [String] = []
    for (target, targetForbiddenImports) in forbiddenImportsByTarget {
        let targetURL = sourcesRoot.appendingPathComponent(target)
        let observedImports = try swiftImports(in: targetURL)
        let forbiddenImports = observedImports
            .intersection(targetForbiddenImports.union(concreteDomainImports))
            .sorted()
        for forbiddenImport in forbiddenImports {
            violations.append("\(target) imports forbidden module \(forbiddenImport).")
        }
    }

    #expect(violations.isEmpty, Comment(rawValue: violations.joined(separator: "\n")))
}

@Test(.timeLimit(.minutes(1)))
func packageManifestProductionTargetDependenciesRespectArchitectureGraph() throws {
    let graph = try packageManifestProductionTargetDependencies()
    let expectedGraph: [String: Set<String>] = [
        "RupaKit": [
            "RupaCore",
            "RupaAutomation",
            "RupaDomainFoundation",
        ],
        "RupaCore": [
            "RupaCoreTypes",
        ],
        "RupaCoreTypes": [],
        "RupaUI": [
            "RupaCore",
            "RupaDomainFoundation",
            "RupaRendering",
            "RupaPreview",
        ],
        "RupaAgentUI": [
            "RupaAgentRuntime",
            "RupaAgentTransport",
            "RupaCore",
            "RupaDomainFoundation",
            "RupaUI",
        ],
        "RupaViewportScene": [
            "RupaCore",
        ],
        "RupaRendering": [
            "RupaCore",
            "RupaViewportScene",
        ],
        "RupaPreview": [
            "RupaCore",
        ],
        "RupaAutomation": [
            "RupaCore",
        ],
        "RupaDomainFoundation": [
            "RupaCore",
            "RupaAutomation",
        ],
        "RupaManufacturing": [
            "RupaDomainFoundation",
            "RupaAutomation",
            "RupaCore",
        ],
        "RupaAgentProtocol": [
            "RupaCore",
            "RupaAutomation",
            "RupaDomainFoundation",
        ],
        "RupaAgentRuntime": [
            "RupaCore",
            "RupaAutomation",
            "RupaDomainFoundation",
            "RupaAgentProtocol",
        ],
        "RupaAgentTransport": [
            "RupaCore",
            "RupaAgentProtocol",
            "RupaAgentRuntime",
        ],
        "RupaAgent": [
            "RupaAgentProtocol",
            "RupaAgentRuntime",
            "RupaAgentTransport",
        ],
        "RupaCLIKit": [
            "RupaCore",
            "RupaAutomation",
            "RupaDomainFoundation",
            "RupaAgentProtocol",
            "RupaAgentRuntime",
            "RupaAgentTransport",
        ],
        "RupaCLI": [
            "RupaCLIKit",
        ],
    ]

    var violations: [String] = []
    let observedTargets = Set(graph.keys)
    let expectedTargets = Set(expectedGraph.keys)
    for missingTarget in expectedTargets.subtracting(observedTargets).sorted() {
        violations.append("Package.swift is missing expected production target \(missingTarget).")
    }
    for unexpectedTarget in observedTargets.subtracting(expectedTargets).sorted() {
        violations.append("Package.swift has production target \(unexpectedTarget) without an architecture rule.")
    }

    for target in expectedTargets.intersection(observedTargets).sorted() {
        let observedDependencies = graph[target] ?? []
        let expectedDependencies = expectedGraph[target] ?? []
        if observedDependencies != expectedDependencies {
            violations.append(
                "\(target) internal dependencies are \(observedDependencies.sorted()), expected \(expectedDependencies.sorted())."
            )
        }
    }

    #expect(violations.isEmpty, Comment(rawValue: violations.joined(separator: "\n")))
}

@Test(.timeLimit(.minutes(1)))
func uiAndRuntimeTargetsDoNotImportConcreteDomains() throws {
    let packageRoot = try rupaKitPackageRoot()
    let sourcesRoot = packageRoot.appendingPathComponent("Sources")
    let concreteDomainImports: Set<String> = [
        "RupaArchitecture",
        "RupaTurbomachinery",
        "RupaCharacterDesign",
        "RupaManufacturing",
        "RupaSimulation",
    ]
    let inspectedTargets = [
        "RupaUI",
        "RupaAgentRuntime",
        "RupaCLIKit",
    ]

    var violations: [String] = []
    for target in inspectedTargets {
        let observedImports = try swiftImports(
            in: sourcesRoot.appendingPathComponent(target)
        )
        let forbiddenImports = observedImports
            .intersection(concreteDomainImports)
            .sorted()
        for forbiddenImport in forbiddenImports {
            violations.append("\(target) imports concrete domain module \(forbiddenImport).")
        }
    }

    #expect(violations.isEmpty, Comment(rawValue: violations.joined(separator: "\n")))
}

private func rupaKitPackageRoot() throws -> URL {
    var url = URL(fileURLWithPath: #filePath)
    url.deleteLastPathComponent()
    url.deleteLastPathComponent()
    url.deleteLastPathComponent()
    guard FileManager.default.fileExists(
        atPath: url.appendingPathComponent("Package.swift").path
    ) else {
        throw TestArchitectureBoundaryError.packageRootNotFound(url.path)
    }
    return url
}

private func swiftImports(in targetURL: URL) throws -> Set<String> {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: targetURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        throw TestArchitectureBoundaryError.targetNotFound(targetURL.path)
    }

    var imports: Set<String> = []
    for case let fileURL as URL in enumerator {
        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard resourceValues.isRegularFile == true,
              fileURL.pathExtension == "swift" else {
            continue
        }
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("import ") else {
                continue
            }
            let importedModule = trimmed
                .dropFirst("import ".count)
                .split(separator: " ")
                .first
                .map(String.init)
            if let importedModule {
                imports.insert(importedModule)
            }
        }
    }
    return imports
}

private func packageManifestProductionTargetDependencies() throws -> [String: Set<String>] {
    let packageRoot = try rupaKitPackageRoot()
    let manifestURL = packageRoot.appendingPathComponent("Package.swift")
    let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
    let blocks = try packageTargetBlocks(in: manifest)
        .filter { !$0.isTestSupportTarget }
    let productionTargetNames = Set(blocks.map(\.name))
    var graph: [String: Set<String>] = [:]

    for block in blocks {
        graph[block.name] = block.dependencyNames
            .intersection(productionTargetNames)
    }
    return graph
}

private struct PackageTargetBlock: Equatable, Sendable {
    var kind: String
    var name: String
    var path: String?
    var dependencyNames: Set<String>

    var isTestSupportTarget: Bool {
        guard let path else {
            return false
        }
        return path == "Tests" || path.hasPrefix("Tests/")
    }
}

private func packageTargetBlocks(in manifest: String) throws -> [PackageTargetBlock] {
    let markers = [
        (text: ".target(", kind: "target"),
        (text: ".executableTarget(", kind: "executableTarget"),
    ]
    var blocks: [PackageTargetBlock] = []
    var searchStart = manifest.startIndex

    while searchStart < manifest.endIndex {
        let nextMarker = markers
            .compactMap { marker -> (range: Range<String.Index>, kind: String)? in
                guard let range = manifest.range(
                    of: marker.text,
                    range: searchStart..<manifest.endIndex
                ) else {
                    return nil
                }
                return (range, marker.kind)
            }
            .min { lhs, rhs in lhs.range.lowerBound < rhs.range.lowerBound }

        guard let nextMarker else {
            break
        }

        let openParenthesis = manifest.index(before: nextMarker.range.upperBound)
        let closeParenthesis = try matchingDelimiter(
            in: manifest,
            open: openParenthesis,
            openCharacter: "(",
            closeCharacter: ")"
        )
        let bodyStart = manifest.index(after: openParenthesis)
        let body = String(manifest[bodyStart..<closeParenthesis])
        let name = try stringValue(after: "name:", in: body)
        let path = optionalStringValue(after: "path:", in: body)
        let dependencyNames = try packageDependencyNames(in: body)
        blocks.append(
            PackageTargetBlock(
                kind: nextMarker.kind,
                name: name,
                path: path,
                dependencyNames: dependencyNames
            )
        )
        searchStart = manifest.index(after: closeParenthesis)
    }

    return blocks
}

private func packageDependencyNames(in targetBody: String) throws -> Set<String> {
    guard let dependenciesLabel = targetBody.range(of: "dependencies:") else {
        return []
    }
    guard let arrayStart = targetBody[dependenciesLabel.upperBound...]
        .firstIndex(of: "[") else {
        throw TestArchitectureBoundaryError.invalidPackageManifest(
            "Target dependencies label is not followed by an array."
        )
    }
    let arrayEnd = try matchingDelimiter(
        in: targetBody,
        open: arrayStart,
        openCharacter: "[",
        closeCharacter: "]"
    )
    let bodyStart = targetBody.index(after: arrayStart)
    return Set(stringLiterals(in: String(targetBody[bodyStart..<arrayEnd])))
}

private func stringValue(after label: String, in body: String) throws -> String {
    guard let value = optionalStringValue(after: label, in: body) else {
        throw TestArchitectureBoundaryError.invalidPackageManifest(
            "Missing string value for \(label)"
        )
    }
    return value
}

private func optionalStringValue(after label: String, in body: String) -> String? {
    guard let labelRange = body.range(of: label),
          let quoteStart = body[labelRange.upperBound...].firstIndex(of: "\"") else {
        return nil
    }
    guard let quoteEnd = closingQuote(in: body, open: quoteStart) else {
        return nil
    }
    let valueStart = body.index(after: quoteStart)
    return String(body[valueStart..<quoteEnd])
}

private func stringLiterals(in body: String) -> [String] {
    var values: [String] = []
    var cursor = body.startIndex
    while cursor < body.endIndex {
        guard let quoteStart = body[cursor...].firstIndex(of: "\""),
              let quoteEnd = closingQuote(in: body, open: quoteStart) else {
            break
        }
        let valueStart = body.index(after: quoteStart)
        values.append(String(body[valueStart..<quoteEnd]))
        cursor = body.index(after: quoteEnd)
    }
    return values
}

private func closingQuote(in text: String, open: String.Index) -> String.Index? {
    var cursor = text.index(after: open)
    var isEscaped = false
    while cursor < text.endIndex {
        let character = text[cursor]
        if isEscaped {
            isEscaped = false
        } else if character == "\\" {
            isEscaped = true
        } else if character == "\"" {
            return cursor
        }
        cursor = text.index(after: cursor)
    }
    return nil
}

private func matchingDelimiter(
    in text: String,
    open: String.Index,
    openCharacter: Character,
    closeCharacter: Character
) throws -> String.Index {
    var depth = 0
    var cursor = open
    var isInsideString = false
    var isEscaped = false

    while cursor < text.endIndex {
        let character = text[cursor]
        if isInsideString {
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                isInsideString = false
            }
        } else if character == "\"" {
            isInsideString = true
        } else if character == openCharacter {
            depth += 1
        } else if character == closeCharacter {
            depth -= 1
            if depth == 0 {
                return cursor
            }
        }
        cursor = text.index(after: cursor)
    }

    throw TestArchitectureBoundaryError.invalidPackageManifest(
        "Could not find matching \(closeCharacter) for \(openCharacter)."
    )
}

private enum TestArchitectureBoundaryError: Error {
    case packageRootNotFound(String)
    case targetNotFound(String)
    case invalidPackageManifest(String)
}
