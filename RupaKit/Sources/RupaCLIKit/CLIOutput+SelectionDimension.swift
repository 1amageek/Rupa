public extension CLIOutput {
    static func write(
        response: CLISelectionDimensionAddResponse,
        asJSON: Bool
    ) throws {
        let dimensionID = response.selectionDimensionID?.description ?? "unknown"
        try write(
            response,
            fallback: "\(response.message) \(dimensionID)",
            asJSON: asJSON
        )
    }
}
