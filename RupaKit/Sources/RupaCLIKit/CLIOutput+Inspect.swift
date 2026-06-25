public extension CLIOutput {
    static func write(
        response: CLISketchEntitySummaryResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    static func write(
        response: CLITopologySummaryResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    static func write(
        response: CLICurveAnalysisResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    static func write(
        response: CLISurfaceAnalysisResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    static func write(
        response: CLISurfaceContinuitySummaryResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }

    static func write(
        response: CLISurfaceFramesResponse,
        asJSON: Bool
    ) throws {
        try write(
            response,
            fallback: response.message,
            asJSON: asJSON
        )
    }
}
