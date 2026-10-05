/// Checked admission for retained original, candidate and staging resources.
enum OpticalVolumeStorageBudget {
    static func remaining(limit: Int, used: Int...) throws -> Int {
        guard limit > 0 else { throw exhausted() }
        var remaining = limit
        for count in used {
            guard count >= 0, count <= remaining else { throw exhausted() }
            remaining -= count
        }
        return remaining
    }

    static func bytes(count: Int, stride: Int) throws -> Int {
        let value = count.multipliedReportingOverflow(by: stride)
        guard count >= 0, stride > 0, !value.overflow else { throw exhausted() }
        return value.partialValue
    }

    private static func exhausted() -> MeshSourcePresentationRenderError {
        .init(code: .resourceExhausted, message: "Optical original and candidate storage exceeds the shared allowance.")
    }
}
