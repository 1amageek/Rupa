extension SemanticJSONValue {
    func appendCanonicalIdentity(to hasher: inout CanonicalIdentityHasher) {
        switch self {
        case .object(let object):
            hasher.appendString("object")
            let keys = object.keys.sorted()
            hasher.appendCount(keys.count)
            for key in keys {
                hasher.appendString(key)
                object[key]?.appendCanonicalIdentity(to: &hasher)
            }
        case .array(let values):
            hasher.appendString("array")
            hasher.appendCount(values.count)
            for value in values {
                value.appendCanonicalIdentity(to: &hasher)
            }
        case .string(let value):
            hasher.appendString("string")
            hasher.appendString(value)
        case .number(let value):
            hasher.appendString("number")
            hasher.appendDouble(value)
        case .bool(let value):
            hasher.appendString("bool")
            hasher.appendBool(value)
        case .null:
            hasher.appendString("null")
            hasher.appendNull()
        }
    }
}
