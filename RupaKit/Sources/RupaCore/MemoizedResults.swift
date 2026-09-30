/// The results made for the most recent distinct keys, failures included, so a failing input is
/// not retried on every read either. `Failure` is `Never` for a value that cannot fail.
///
/// It belongs to one owner on one isolation domain (a view's state) and is not synchronized.
public final class MemoizedResults<Key: Equatable, Value, Failure: Error> {
    private let capacity: Int
    private var entries: [(key: Key, result: Result<Value, Failure>)] = []

    public init(capacity: Int = 1) {
        precondition(capacity > 0, "A memo holds at least one result.")
        self.capacity = capacity
    }

    public func value(for key: Key, make: () throws(Failure) -> Value) throws(Failure) -> Value {
        if let index = entries.firstIndex(where: { $0.key == key }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            return try entry.result.get()
        }
        let result = Result<Value, Failure> { () throws(Failure) -> Value in try make() }
        entries.append((key, result))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        return try result.get()
    }
}
