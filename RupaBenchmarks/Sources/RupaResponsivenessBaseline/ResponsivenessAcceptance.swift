import Foundation

/// The acceptance-table environment inputs, recorded with the rule that
/// produced them when they were not supplied by the caller.
public struct ResponsivenessEnvironment: Equatable, Sendable, Codable {
    public var frameIntervalSeconds: Double
    public var frameIntervalIsDerived: Bool
    public var minimumMemoryBytes: UInt64
    public var minimumMemoryIsDerived: Bool

    /// The selection rule the derived defaults follow. It is recorded with every
    /// report so a later report can be compared only under the same rule.
    public static let derivationRule = """
        frameInterval is the lowest refresh rate of the release device matrix. \
        The application declares MACOSX_DEPLOYMENT_TARGET 26.0, and every Mac \
        that runs macOS 26 drives a display of at least 60 Hz, so the lowest \
        refresh rate is 60 Hz and frameInterval is 1/60 second. minimumMemory \
        is the physical memory of the lowest-memory supported device, and the \
        lowest-memory Mac that runs macOS 26 ships 8 GB, so minimumMemory is \
        8 GiB. Changing the deployment target or the supported device matrix \
        requires reselecting both values and re-recording every baseline that \
        is still cited as evidence.
        """

    public static let derivedFrameIntervalSeconds = 1.0 / 60.0
    public static let derivedMinimumMemoryBytes: UInt64 = 8 * 1024 * 1024 * 1024

    public init(
        frameIntervalSeconds: Double? = nil,
        minimumMemoryBytes: UInt64? = nil
    ) throws {
        if let frameIntervalSeconds {
            guard frameIntervalSeconds.isFinite, frameIntervalSeconds > 0.0 else {
                throw ResponsivenessBaselineError(
                    code: .invalidEnvironmentInput,
                    message: "frameInterval must be a positive finite number of seconds."
                )
            }
            self.frameIntervalSeconds = frameIntervalSeconds
            frameIntervalIsDerived = false
        } else {
            self.frameIntervalSeconds = Self.derivedFrameIntervalSeconds
            frameIntervalIsDerived = true
        }
        if let minimumMemoryBytes {
            guard minimumMemoryBytes > 0 else {
                throw ResponsivenessBaselineError(
                    code: .invalidEnvironmentInput,
                    message: "minimumMemory must be a positive number of bytes."
                )
            }
            self.minimumMemoryBytes = minimumMemoryBytes
            minimumMemoryIsDerived = false
        } else {
            self.minimumMemoryBytes = Self.derivedMinimumMemoryBytes
            minimumMemoryIsDerived = true
        }
    }

    /// The retained and working byte ceiling both memory rows compare against.
    public var planByteCeiling: Double {
        Double(minimumMemoryBytes) * 0.025
    }
}

/// One row of the RupaRendering performance acceptance table.
public enum ResponsivenessAcceptanceRow: String, Equatable, Sendable, Codable, CaseIterable {
    case mainActorStatePublication
    case canvasConsumption
    case planReadiness
    case cancellation
    case planRetainedBytes
    case planWorkingBytes

    public var title: String {
        switch self {
        case .mainActorStatePublication: "MainActor state publication"
        case .canvasConsumption: "Canvas consumption"
        case .planReadiness: "Plan readiness"
        case .cancellation: "Cancellation"
        case .planRetainedBytes: "Plan retained bytes"
        case .planWorkingBytes: "Plan working bytes"
        }
    }
}

public enum ResponsivenessVerdict: String, Equatable, Sendable, Codable {
    /// The measured value satisfies the row.
    case accepts
    /// The measured value violates the row.
    case rejects
    /// The current implementation cannot expose this measure. The reason is
    /// recorded; the row is never treated as satisfied.
    case notMeasured
}

public struct ResponsivenessRowResult: Equatable, Sendable, Codable {
    public let row: ResponsivenessAcceptanceRow
    public let verdict: ResponsivenessVerdict
    public let measured: String
    public let threshold: String
    public let detail: String

    public init(
        row: ResponsivenessAcceptanceRow,
        verdict: ResponsivenessVerdict,
        measured: String,
        threshold: String,
        detail: String
    ) {
        self.row = row
        self.verdict = verdict
        self.measured = measured
        self.threshold = threshold
        self.detail = detail
    }
}
