extension EditorDiagnostic {
    /// Preserves source order while removing diagnostics with the same semantic identity.
    public static func stableMerged(
        _ groups: [[EditorDiagnostic]]
    ) -> [EditorDiagnostic] {
        var merged: [EditorDiagnostic] = []
        for diagnostic in groups.joined() where !merged.contains(where: { existing in
            existing.severity == diagnostic.severity
                && existing.code == diagnostic.code
                && existing.message == diagnostic.message
        }) {
            merged.append(diagnostic)
        }
        return merged
    }
}
