import SwiftUI
import RupaCore

public struct PreviewSurface: View {
    private let document: DesignDocument
    private let evaluationStatus: EvaluationStatus
    private let evaluatedGeneration: DocumentGeneration?
    private let evaluatedBodyCount: Int
    private let diagnostics: [EditorDiagnostic]

    public init(
        document: DesignDocument,
        evaluationStatus: EvaluationStatus = .notEvaluated,
        evaluatedGeneration: DocumentGeneration? = nil,
        evaluatedBodyCount: Int = 0,
        diagnostics: [EditorDiagnostic]
    ) {
        self.document = document
        self.evaluationStatus = evaluationStatus
        self.evaluatedGeneration = evaluatedGeneration
        self.evaluatedBodyCount = evaluatedBodyCount
        self.diagnostics = diagnostics
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                metric(title: "Unit", value: document.displayUnit.symbol)
                metric(title: "Minor", value: formatted(document.ruler.minorTickMeters))
                metric(title: "Major", value: formatted(document.ruler.majorTickMeters))
                metric(title: "Eval", value: evaluationTitle)
                metric(title: "Bodies", value: "\(evaluatedBodyCount)")
                Spacer(minLength: 0)
            }

            Divider()

            if diagnostics.isEmpty {
                Label("No diagnostics", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diagnostics) { diagnostic in
                    Label(diagnostic.message, systemImage: icon(for: diagnostic.severity))
                        .foregroundStyle(color(for: diagnostic.severity))
                }
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }

    private func formatted(_ meters: Double) -> String {
        let value = document.displayUnit.value(fromMeters: meters)
        return "\(value.formatted(.number.precision(.fractionLength(0...4)))) \(document.displayUnit.symbol)"
    }

    private var evaluationTitle: String {
        switch evaluationStatus {
        case .notEvaluated:
            return "Pending"
        case .valid:
            if let evaluatedGeneration {
                return "Gen \(evaluatedGeneration.value)"
            }
            return "Valid"
        case .failed:
            return "Failed"
        }
    }

    private func icon(for severity: EditorDiagnostic.Severity) -> String {
        switch severity {
        case .info:
            "info.circle"
        case .warning:
            "exclamationmark.triangle"
        case .error:
            "xmark.octagon"
        }
    }

    private func color(for severity: EditorDiagnostic.Severity) -> Color {
        switch severity {
        case .info:
            .secondary
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}
