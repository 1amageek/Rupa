import Foundation
import Testing

/// A command that reads evaluated topology reads the store's current evaluation instead of
/// evaluating the whole document again, which an omitted argument silently did. Every RupaCore
/// read of evaluated topology states the evaluation it reuses (nil when it has none), and the
/// store passes its evaluation to every document operation that accepts one.
@Suite struct CurrentEvaluationPlumbingAuditTests {
    private static let topologyReads = try! NSRegularExpression(pattern: [
        #"TopologySnapshotService\(\)\.snapshot\("#,
        #"\b(?:topologyService|topologySnapshotService)\.snapshot\("#,
        #"DocumentEvaluationContextResolver\([^()]*\)\.(?:exactEvaluatedDocument|evaluatedDocument)\("#,
        #"(?<!func |class )\bTopologySnapshotMemo\("#,
    ].joined(separator: "|"))

    @Test(.timeLimit(.minutes(1)))
    func everyTopologyReadInCoreStatesItsEvaluation() throws {
        var omissions: [String] = []
        for file in try coreSourceFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for call in Self.calls(matching: Self.topologyReads, in: source)
            where !call.arguments.contains("currentEvaluation") {
                omissions.append("\(file.lastPathComponent):\(call.line)")
            }
        }
        #expect(omissions.isEmpty, "Topology reads without an evaluation: \(omissions)")
    }

    @Test(.timeLimit(.minutes(1)))
    func theStorePassesItsEvaluationToEveryOperationThatTakesOne() throws {
        // Operations keyed by name, each with the argument labels of an overload that accepts
        // the evaluation; a call matches an overload whose labels include all of its own.
        var accepting: [String: [Set<String>]] = [:]
        let declaration = try NSRegularExpression(pattern: #"func\s+(\w+)\s*\("#)
        for file in try coreSourceFiles() where file.lastPathComponent.hasPrefix("DesignDocument")
            || file.path.contains("/TopologyEditing/") {
            let source = try String(contentsOf: file, encoding: .utf8)
            for call in Self.calls(matching: declaration, in: source)
            where call.arguments.contains("currentEvaluation:") {
                accepting[call.name, default: []].append(Set(Self.labels(of: call.arguments, declaration: true)))
            }
        }
        #expect(accepting["deleteBodyFaces"] != nil)

        let storeURL = try coreSourceRoot().appendingPathComponent("CADDocumentStore.swift")
        let store = try String(contentsOf: storeURL, encoding: .utf8)
        let operation = try NSRegularExpression(pattern: #"\b(?:updatedDocument|updated|document)\.(\w+)\("#)
        var omissions: [String] = []
        for call in Self.calls(matching: operation, in: store) {
            guard let overloads = accepting[call.name], !call.arguments.contains("currentEvaluation:") else { continue }
            let labels = Set(Self.labels(of: call.arguments, declaration: false))
            if overloads.contains(where: { labels.isSubset(of: $0) }) {
                omissions.append("\(call.name) at line \(call.line)")
            }
        }
        #expect(omissions.isEmpty, "Store operations called without the current evaluation: \(omissions)")
    }

    /// The labels of a parameter list (the external name of each parameter) or of an argument
    /// list ("_" for an unlabeled argument), read from its top-level comma-separated parts.
    private static func labels(of list: Substring, declaration: Bool) -> [String] {
        var parts: [Substring] = []
        var depth = 0
        var start = list.startIndex
        for index in list.indices {
            switch list[index] {
            case "(", "[", "{": depth += 1
            case ")", "]", "}": depth -= 1
            case "," where depth == 0:
                parts.append(list[start..<index])
                start = list.index(after: index)
            default: break
            }
        }
        parts.append(list[start...])
        return parts.compactMap { part in
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard let colon = trimmed.firstIndex(of: ":") else { return declaration ? nil : "_" }
            let head = trimmed[..<colon].split(separator: " ")
            guard let first = head.first else { return nil }
            if declaration { return String(first) }
            return head.count == 1 && first.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) ? String(first) : "_"
        }
    }

    private struct Call {
        var name: String
        var line: Int
        var arguments: Substring
    }

    /// Each match of `pattern` that ends at an opening parenthesis, with its balanced argument
    /// text and the first capture group as its name.
    private static func calls(matching pattern: NSRegularExpression, in source: String) -> [Call] {
        let text = source as NSString
        return pattern.matches(in: source, range: NSRange(location: 0, length: text.length)).compactMap { match in
            guard let open = Range(match.range, in: source).map({ source.index(before: $0.upperBound) }),
                  source[open] == "(" else { return nil }
            var depth = 0
            var index = open
            while index < source.endIndex {
                switch source[index] {
                case "(": depth += 1
                case ")":
                    depth -= 1
                    if depth == 0 {
                        let name = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                            ? text.substring(with: match.range(at: 1)) : ""
                        let line = source[..<open].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
                        return Call(name: name, line: line, arguments: source[source.index(after: open)..<index])
                    }
                default: break
                }
                index = source.index(after: index)
            }
            return nil
        }
    }

    private func coreSourceRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url.appendingPathComponent("Sources/RupaCore")
    }

    private func coreSourceFiles() throws -> [URL] {
        let root = try coreSourceRoot()
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty, "RupaCore sources were not found at \(root.path).")
        return files
    }
}
