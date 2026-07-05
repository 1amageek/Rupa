import Foundation
import RupaCore

public struct ViewportCanvasScaleMenuState: Equatable, Sendable {
    public struct PresetOption: Equatable, Identifiable, Sendable {
        public var preset: WorkspaceScalePreset
        public var title: String
        public var visibleSpanTitle: String
        public var comfortTitle: String
        public var isSelected: Bool

        public var id: WorkspaceScalePreset {
            preset
        }

        public init(
            profile: WorkspaceScalePresetProfile,
            isSelected: Bool
        ) {
            self.preset = profile.preset
            self.title = profile.title
            self.visibleSpanTitle = profile.visibleSpanTitle
            self.comfortTitle = profile.comfortableModelSpanTitle
            self.isSelected = isSelected
        }

        public var menuTitle: String {
            "\(title) · \(visibleSpanTitle)"
        }

        public var accessibilityIdentifier: String {
            "CanvasScaleMenu.preset.\(preset.rawValue)"
        }
    }

    public struct Row: Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String
        public var value: String

        public init(id: String, title: String, value: String) {
            self.id = id
            self.title = title
            self.value = value
        }
    }

    public enum Action: String, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
        case fitToModel
        case smallerPreset
        case largerPreset

        public var id: String {
            rawValue
        }

        public var title: String {
            switch self {
            case .fitToModel:
                "Fit Scale to Model"
            case .smallerPreset:
                "Smaller Workspace Scale"
            case .largerPreset:
                "Larger Workspace Scale"
            }
        }

        public var systemImage: String {
            switch self {
            case .fitToModel:
                "scope"
            case .smallerPreset:
                "minus.magnifyingglass"
            case .largerPreset:
                "plus.magnifyingglass"
            }
        }

        public var accessibilityIdentifier: String {
            "CanvasScaleMenu.\(rawValue)"
        }
    }

    public var rows: [Row]
    public var presetOptions: [PresetOption]
    public var isVisualStepCapped: Bool
    public var availableActions: [Action]
    public var accessibilityText: String

    public init(
        scaleReadout: ViewportProjectedGrid.ScaleReadout,
        presetTitle: String? = nil,
        selectedPreset: WorkspaceScalePreset? = nil,
        presetProfiles: [WorkspaceScalePresetProfile] = [],
        canFitWorkspaceScaleToModel: Bool,
        canSelectSmallerWorkspaceScale: Bool,
        canSelectLargerWorkspaceScale: Bool
    ) {
        var rows: [Row] = []
        if let presetTitle, !presetTitle.isEmpty {
            rows.append(Row(
                id: "preset",
                title: "Preset",
                value: presetTitle
            ))
        }
        rows.append(contentsOf: [
            Row(
                id: "unit",
                title: "Unit",
                value: scaleReadout.minorStep.displayUnit.symbol
            ),
            Row(
                id: "mode",
                title: "Mode",
                value: scaleReadout.visualSpacingMode.title
            ),
            Row(
                id: "grid",
                title: "Grid",
                value: scaleReadout.minorStep.text
            ),
            Row(
                id: "snap",
                title: "Snap",
                value: scaleReadout.snapStep.text
            ),
            Row(
                id: "major",
                title: "Major",
                value: scaleReadout.majorStep.text
            ),
            Row(
                id: "visibleSpan",
                title: "Visible",
                value: scaleReadout.visibleSpan.text
            ),
            Row(
                id: "workspaceSpan",
                title: "Workspace",
                value: scaleReadout.workspaceSpan.text
            ),
        ])
        self.rows = rows
        self.presetOptions = presetProfiles.map { profile in
            PresetOption(
                profile: profile,
                isSelected: profile.preset == selectedPreset
            )
        }
        isVisualStepCapped = scaleReadout.isVisualStepCapped

        var actions: [Action] = []
        if canFitWorkspaceScaleToModel {
            actions.append(.fitToModel)
        }
        if canSelectSmallerWorkspaceScale {
            actions.append(.smallerPreset)
        }
        if canSelectLargerWorkspaceScale {
            actions.append(.largerPreset)
        }
        availableActions = actions

        var accessibilityComponents = rows.map { row in
            "\(row.title) \(row.value)"
        }
        if isVisualStepCapped {
            accessibilityComponents.append("visual grid capped by line budget")
        }
        if !actions.isEmpty {
            accessibilityComponents.append(
                "actions \(actions.map(\.title).joined(separator: ", "))"
            )
        }
        if !presetOptions.isEmpty {
            accessibilityComponents.append(
                "presets \(presetOptions.map(\.menuTitle).joined(separator: ", "))"
            )
        }
        accessibilityText = accessibilityComponents.joined(separator: ", ")
    }
}
