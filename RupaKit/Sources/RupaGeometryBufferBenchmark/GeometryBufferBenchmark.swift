import Foundation
import RupaGeometry

@main
struct GeometryBufferBenchmark {
    static func main() throws {
        let options = try GeometryBufferBenchmarkOptions(
            arguments: Array(CommandLine.arguments.dropFirst())
        )
        let values = (0..<options.elementCount).map { index in
            GeometryPoint3D(
                x: Double(index),
                y: Double(index % 97),
                z: Double(index % 17)
            )
        }
        let candidates = try options.chunkByteCounts.map { chunkByteCount in
            try measureCandidate(
                values: values,
                chunkByteCount: chunkByteCount,
                warmupCount: options.warmupCount,
                iterationCount: options.iterationCount
            )
        }
        let eligibleCandidates = candidates.filter {
            $0.copiedBytesPerEdit
                <= GeometryBufferPerformanceContract.maximumCopiedBytesPerLocalEdit
                && $0.copiedBytesPerView == 0
        }
        let fastestScan = eligibleCandidates.map(\.scanMedianSeconds).min() ?? 0
        let maximumEligibleScan = fastestScan * 1.10
        let selected =
            eligibleCandidates
            .filter { $0.scanMedianSeconds <= maximumEligibleScan }
            .min { lhs, rhs in
                if lhs.editMedianSeconds == rhs.editMedianSeconds {
                    return lhs.chunkByteCount < rhs.chunkByteCount
                }
                return lhs.editMedianSeconds < rhs.editMedianSeconds
            }

        let report = GeometryBufferBenchmarkReport(
            schemaVersion: 1,
            elementCount: options.elementCount,
            iterationCount: options.iterationCount,
            maximumCopiedBytesPerLocalEdit:
                GeometryBufferPerformanceContract.maximumCopiedBytesPerLocalEdit,
            selectionRule:
                "minimum edit median among zero-copy views and local edits copying at most 64 KiB, with scan median within 10 percent of the fastest eligible candidate",
            selectedChunkByteCount: selected?.chunkByteCount,
            candidates: candidates
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        guard let output = String(data: data, encoding: .utf8) else {
            throw GeometryBufferBenchmarkError.outputEncodingFailed
        }
        print(output)
    }

    private static func measureCandidate(
        values: [GeometryPoint3D],
        chunkByteCount: Int,
        warmupCount: Int,
        iterationCount: Int
    ) throws -> GeometryBufferBenchmarkCandidate {
        let buffer = GeometryBuffer(
            values,
            preferredChunkByteCount: chunkByteCount
        )
        let editIndex = values.count / 2
        let replacement = GeometryPoint3D(x: -1, y: -2, z: -3)

        for _ in 0..<warmupCount {
            _ = try measureEdit(
                buffer: buffer,
                editIndex: editIndex,
                replacement: replacement
            )
            _ = measureScan(buffer: buffer)
        }

        var editSamples: [Double] = []
        var scanSamples: [Double] = []
        var copiedBytes: UInt64 = 0
        var viewCopiedBytes: UInt64 = 0
        editSamples.reserveCapacity(iterationCount)
        scanSamples.reserveCapacity(iterationCount)

        for _ in 0..<iterationCount {
            let edit = try measureEdit(
                buffer: buffer,
                editIndex: editIndex,
                replacement: replacement
            )
            editSamples.append(edit.seconds)
            copiedBytes = edit.copiedBytes

            let scan = measureScan(buffer: buffer)
            scanSamples.append(scan.seconds)
            viewCopiedBytes = scan.copiedBytes
        }

        return GeometryBufferBenchmarkCandidate(
            chunkByteCount: chunkByteCount,
            editMedianSeconds: median(editSamples),
            editP95Seconds: percentile(0.95, samples: editSamples),
            scanMedianSeconds: median(scanSamples),
            scanP95Seconds: percentile(0.95, samples: scanSamples),
            copiedBytesPerEdit: copiedBytes,
            copiedBytesPerView: viewCopiedBytes
        )
    }

    private static func measureEdit(
        buffer: GeometryBuffer<GeometryPoint3D>,
        editIndex: Int,
        replacement: GeometryPoint3D
    ) throws -> GeometryBufferTimedCopy {
        let start = ContinuousClock.now
        var builder = buffer.makeBuilder()
        try builder.replaceSubrange(
            editIndex..<(editIndex + 1),
            with: CollectionOfOne(replacement)
        )
        let edited = builder.build()
        let duration = start.duration(to: ContinuousClock.now)
        precondition(edited[editIndex] == replacement)
        return GeometryBufferTimedCopy(
            seconds: duration.seconds,
            copiedBytes: builder.telemetry.copiedBytes
        )
    }

    private static func measureScan(
        buffer: GeometryBuffer<GeometryPoint3D>
    ) -> GeometryBufferTimedCopy {
        var telemetry = GeometryCopyTelemetry()
        let start = ContinuousClock.now
        let lease = buffer.lease(telemetry: &telemetry)
        var checksum = 0.0
        lease.withContiguousChunks { span in
            span.withUnsafeBufferPointer { pointer in
                for element in pointer {
                    checksum += element.x + element.y + element.z
                }
            }
        }
        let duration = start.duration(to: ContinuousClock.now)
        precondition(checksum.isFinite)
        return GeometryBufferTimedCopy(
            seconds: duration.seconds,
            copiedBytes: telemetry.copiedBytes
        )
    }

    private static func median(_ samples: [Double]) -> Double {
        percentile(0.5, samples: samples)
    }

    private static func percentile(_ value: Double, samples: [Double]) -> Double {
        let sorted = samples.sorted()
        let rank = Int(ceil(value * Double(sorted.count))) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }
}

private struct GeometryBufferBenchmarkOptions {
    var elementCount = 1_000_000
    var iterationCount = 25
    var warmupCount = 5
    var chunkByteCounts = [4, 16, 64, 256].map { $0 * 1_024 }

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            guard index + 1 < arguments.count else {
                throw GeometryBufferBenchmarkError.invalidArguments
            }
            switch arguments[index] {
            case "--elements":
                elementCount = try Self.positiveInteger(arguments[index + 1])
            case "--iterations":
                iterationCount = try Self.positiveInteger(arguments[index + 1])
            case "--warmups":
                guard let value = Int(arguments[index + 1]), value >= 0 else {
                    throw GeometryBufferBenchmarkError.invalidArguments
                }
                warmupCount = value
            default:
                throw GeometryBufferBenchmarkError.invalidArguments
            }
            index += 2
        }
    }

    private static func positiveInteger(_ value: String) throws -> Int {
        guard let result = Int(value), result > 0 else {
            throw GeometryBufferBenchmarkError.invalidArguments
        }
        return result
    }
}

private struct GeometryBufferBenchmarkReport: Codable {
    let schemaVersion: Int
    let elementCount: Int
    let iterationCount: Int
    let maximumCopiedBytesPerLocalEdit: UInt64
    let selectionRule: String
    let selectedChunkByteCount: Int?
    let candidates: [GeometryBufferBenchmarkCandidate]
}

private struct GeometryBufferBenchmarkCandidate: Codable {
    let chunkByteCount: Int
    let editMedianSeconds: Double
    let editP95Seconds: Double
    let scanMedianSeconds: Double
    let scanP95Seconds: Double
    let copiedBytesPerEdit: UInt64
    let copiedBytesPerView: UInt64
}

private struct GeometryBufferTimedCopy {
    let seconds: Double
    let copiedBytes: UInt64
}

private enum GeometryBufferBenchmarkError: Error {
    case invalidArguments
    case outputEncodingFailed
}

extension Duration {
    fileprivate var seconds: Double {
        let value = components
        return Double(value.seconds) + Double(value.attoseconds) / 1.0e18
    }
}
