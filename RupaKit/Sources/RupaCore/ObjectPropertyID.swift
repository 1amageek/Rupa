import RupaCoreTypes

@available(
    *,
    deprecated,
    renamed: "PropertyID",
    message: "Use PropertyID as the universal property identity. Remove this alias after RupaCore callers migrate."
)
public typealias ObjectPropertyID = PropertyID
