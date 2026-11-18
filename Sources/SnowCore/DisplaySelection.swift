/// Which displays get snow, kept as the hardware UUIDs the person switched off. Anything not
/// excluded is included, so a newly connected display (or one without a UUID) gets snow.
public struct DisplaySelection: Equatable, Sendable {
    public private(set) var excluded: Set<String>

    public init(stored: [String] = []) { excluded = Set(stored) }

    public func includes(_ uuid: String?) -> Bool {
        guard let uuid else { return true }
        return !excluded.contains(uuid)
    }

    public mutating func setIncluded(_ included: Bool, for uuid: String) {
        if included { excluded.remove(uuid) } else { excluded.insert(uuid) }
    }

    /// Sorted, for stable UserDefaults storage.
    public var stored: [String] { excluded.sorted() }
}
