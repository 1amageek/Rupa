import RupaCore
import RupaRendering
import SwiftUI

struct WorkspaceSurfaceAnalysisControl: View {
    @Binding var options: ViewportSurfaceAnalysisOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                optionButton(.curvatureCombs)
                optionButton(.principalDirections)
                optionButton(.trimBoundaries)
            }

            HStack(spacing: 6) {
                ForEach(SurfaceAnalysisSampleDensity.allCases, id: \.self) { density in
                    densityButton(density)
                }
            }
        }
    }

    private func optionButton(_ option: SurfaceAnalysisOption) -> some View {
        let isSelected = option.isSelected(in: options)
        return Button {
            option.toggle(in: &options)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(option.shortTitle)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.72))
            .frame(maxWidth: .infinity, minHeight: 42)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.10),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .help(option.help)
        .accessibilityLabel(option.title)
        .accessibilityValue(isSelected ? "On" : "Off")
        .accessibilityIdentifier("WorkspaceSurfaceAnalysis.\(option.rawValue)")
    }

    private func densityButton(_ density: SurfaceAnalysisSampleDensity) -> some View {
        let isSelected = options.sampleDensity == density
        return Button {
            options.sampleDensity = density
        } label: {
            VStack(spacing: 4) {
                Image(systemName: density.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(density.shortTitle)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.72))
            .frame(maxWidth: .infinity, minHeight: 38)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.10),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .help(density.help)
        .accessibilityLabel(density.title)
        .accessibilityValue(isSelected ? "Selected" : "Available")
        .accessibilityIdentifier("WorkspaceSurfaceAnalysis.density.\(density.rawValue)")
    }
}

private enum SurfaceAnalysisOption: String {
    case curvatureCombs
    case principalDirections
    case trimBoundaries

    var title: String {
        switch self {
        case .curvatureCombs:
            return "Curvature Combs"
        case .principalDirections:
            return "Principal Directions"
        case .trimBoundaries:
            return "Trim Boundaries"
        }
    }

    var shortTitle: String {
        switch self {
        case .curvatureCombs:
            return "Comb"
        case .principalDirections:
            return "Dir"
        case .trimBoundaries:
            return "Trim"
        }
    }

    var systemImage: String {
        switch self {
        case .curvatureCombs:
            return "waveform.path.ecg"
        case .principalDirections:
            return "arrow.up.left.and.arrow.down.right"
        case .trimBoundaries:
            return "rectangle.dashed"
        }
    }

    var help: String {
        switch self {
        case .curvatureCombs:
            return "Show Surface Curvature Combs"
        case .principalDirections:
            return "Show Principal Curvature Directions"
        case .trimBoundaries:
            return "Show Surface Trim Boundaries"
        }
    }

    func isSelected(in options: ViewportSurfaceAnalysisOptions) -> Bool {
        switch self {
        case .curvatureCombs:
            return options.showsCurvatureCombs
        case .principalDirections:
            return options.showsPrincipalDirections
        case .trimBoundaries:
            return options.showsTrimBoundaries
        }
    }

    func toggle(in options: inout ViewportSurfaceAnalysisOptions) {
        switch self {
        case .curvatureCombs:
            options.showsCurvatureCombs.toggle()
        case .principalDirections:
            options.showsPrincipalDirections.toggle()
        case .trimBoundaries:
            options.showsTrimBoundaries.toggle()
        }
    }
}

private extension SurfaceAnalysisSampleDensity {
    var title: String {
        switch self {
        case .low:
            return "Low Density"
        case .standard:
            return "Standard Density"
        case .high:
            return "High Density"
        }
    }

    var shortTitle: String {
        switch self {
        case .low:
            return "Low"
        case .standard:
            return "Std"
        case .high:
            return "High"
        }
    }

    var systemImage: String {
        switch self {
        case .low:
            return "square.grid.2x2"
        case .standard:
            return "square.grid.3x3"
        case .high:
            return "square.grid.4x3.fill"
        }
    }

    var help: String {
        "\(title) Surface Analysis"
    }
}
