import Foundation

/// A FIFO buffer with a fixed maximum size — appending past capacity drops
/// the oldest elements first.
///
/// The original code re-implemented "append then trim from front if over
/// capacity" by hand in three or four places with slightly different
/// off-by-one behavior each time. Centralizing it here means there's one
/// implementation to verify and reuse for traces, stress history, etc.
struct RollingBuffer<Element> {
    private(set) var elements: [Element] = []
    let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0, "RollingBuffer capacity must be positive")
        self.capacity = capacity
    }

    mutating func append(_ element: Element) {
        elements.append(element)
        trimIfNeeded()
    }

    mutating func append(contentsOf newElements: some Sequence<Element>) {
        elements.append(contentsOf: newElements)
        trimIfNeeded()
    }

    mutating func removeAll() {
        elements.removeAll()
    }

    private mutating func trimIfNeeded() {
        guard elements.count > capacity else { return }
        elements.removeFirst(elements.count - capacity)
    }
}

extension RollingBuffer where Element == Double {
    var latest: Double? { elements.last }
}
