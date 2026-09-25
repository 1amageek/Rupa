import Foundation
import RupaCore

struct LoftSectionDraft: Equatable {
    var tangentScale = ""
    var startSampleIndex = ""
    var usesCurveInterval = false
    var lowerParameter = "0"
    var upperParameter = "1"
    var isReversed = false
    var tangentMode = LoftSectionSmoothTangentMode.automatic
    var profileDirection = LoftProfileDirection.automatic
    var profileIndex = "0"

    init(tangentScale: String = "", usesCurveInterval: Bool = false,
         lowerParameter: String = "0", upperParameter: String = "1", isReversed: Bool = false,
         tangentMode: LoftSectionSmoothTangentMode = .automatic) {
        self.tangentScale = tangentScale
        self.usesCurveInterval = usesCurveInterval
        self.lowerParameter = lowerParameter
        self.upperParameter = upperParameter
        self.isReversed = isReversed
        self.tangentMode = tangentMode
    }

    init(section: LoftSectionReference) {
        startSampleIndex = section.startSampleIndex.map { String($0) } ?? ""
        tangentScale = section.smoothTangentScale.map { String($0) } ?? ""
        tangentMode = section.smoothTangentMode
        profileDirection = section.profileDirection
        if case .profile(let reference) = section.section {
            profileIndex = String(reference.profileIndex)
        }
        if case .curve(let reference) = section.section {
            isReversed = reference.isReversed
            if case .closed(let lower, let upper) = reference.parameterDomain {
                usesCurveInterval = true
                lowerParameter = String(lower)
                upperParameter = String(upper)
            }
        }
    }

    func applying(to source: LoftSectionReference) throws -> LoftSectionReference {
        var result = source
        let start = startSampleIndex.trimmingCharacters(in: .whitespacesAndNewlines)
        if start.isEmpty {
            result.startSampleIndex = nil
        } else {
            guard let index = Int(start), index >= 0 else {
                throw invalid("Start sample index must be a nonnegative integer.")
            }
            result.startSampleIndex = index
        }
        result.smoothTangentMode = tangentMode
        result.profileDirection = profileDirection
        if case .curve(var curve) = result.section {
            curve.parameterDomain = nil
            if usesCurveInterval {
                let lower = try number(lowerParameter, label: "Curve interval start")
                let upper = try number(upperParameter, label: "Curve interval end")
                guard lower < upper else { throw invalid("Curve interval start must be less than its end.") }
                curve.parameterDomain = .closed(lower, upper)
            }
            curve.isReversed = isReversed
            result.section = .curve(curve)
        } else if usesCurveInterval || isReversed {
            throw invalid("Curve intervals and reversal require a curve section, not a closed profile.")
        }
        if case .profile(var profile) = result.section {
            guard let index = Int(profileIndex.trimmingCharacters(in: .whitespacesAndNewlines)), index >= 0 else {
                throw invalid("Profile index must be a nonnegative integer.")
            }
            profile.profileIndex = index
            result.section = .profile(profile)
        }
        if tangentScale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.smoothTangentScale = nil
        } else {
            let value = try number(tangentScale, label: "Section tension")
            guard value > 0 else { throw invalid("Section tension must be positive.") }
            result.smoothTangentScale = value
        }
        try result.validate()
        return result
    }

    private func number(_ text: String, label: String) throws -> Double {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else {
            throw invalid("\(label) must be a finite number.")
        }
        return value
    }

    private func invalid(_ message: String) -> EditorError {
        EditorError(code: .commandInvalid, message: message)
    }
}
