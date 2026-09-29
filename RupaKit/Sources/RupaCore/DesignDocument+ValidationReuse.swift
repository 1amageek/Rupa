import RupaCoreTypes

extension DesignDocument {
    /// Validates the document unless `evaluation` is a current evaluation of it at `generation`.
    ///
    /// A matching evaluation was made from this very document at this generation once it
    /// validated, so a read-only service handed one skips the whole-document check it would
    /// otherwise repeat on every call; without a matching one the document is validated as before.
    func validate(
        objectRegistry: ObjectTypeRegistry,
        unlessEvaluatedBy evaluation: DocumentEvaluationContext?,
        generation: DocumentGeneration?
    ) throws {
        if evaluation?.matches(document: self, generation: generation) == true {
            return
        }
        _ = try validate(objectRegistry: objectRegistry)
    }
}
