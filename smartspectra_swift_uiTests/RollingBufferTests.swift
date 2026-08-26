import XCTest
@testable import smartspectra_swift_ui

final class RollingBufferTests: XCTestCase {

    func test_append_addsElementsUnderCapacity() {
        var buffer = RollingBuffer<Int>(capacity: 5)
        buffer.append(1)
        buffer.append(2)
        XCTAssertEqual(buffer.elements, [1, 2])
    }

    func test_append_dropsOldestWhenOverCapacity() {
        var buffer = RollingBuffer<Int>(capacity: 3)
        for value in 1...5 {
            buffer.append(value)
        }
        // Capacity 3: only the most recent 3 of [1,2,3,4,5] should remain.
        XCTAssertEqual(buffer.elements, [3, 4, 5])
    }

    func test_appendContentsOf_addsAllUnderCapacity() {
        var buffer = RollingBuffer<Int>(capacity: 5)
        buffer.append(contentsOf: [1, 2, 3])
        XCTAssertEqual(buffer.elements, [1, 2, 3])
    }

    func test_appendContentsOf_dropsOldestWhenOverCapacity() {
        var buffer = RollingBuffer<Int>(capacity: 3)
        buffer.append(contentsOf: [1, 2])
        buffer.append(contentsOf: [3, 4, 5])
        XCTAssertEqual(buffer.elements, [3, 4, 5])
    }

    func test_appendContentsOf_whenBatchAloneExceedsCapacity_keepsOnlyMostRecentSuffix() {
        var buffer = RollingBuffer<Int>(capacity: 2)
        buffer.append(contentsOf: [1, 2, 3, 4, 5])
        XCTAssertEqual(buffer.elements, [4, 5])
    }

    func test_removeAll_clearsElements() {
        var buffer = RollingBuffer<Int>(capacity: 3)
        buffer.append(contentsOf: [1, 2, 3])
        buffer.removeAll()
        XCTAssertTrue(buffer.elements.isEmpty)
    }

    func test_removeAll_thenAppend_respectsCapacityAgain() {
        var buffer = RollingBuffer<Int>(capacity: 2)
        buffer.append(contentsOf: [1, 2])
        buffer.removeAll()
        buffer.append(contentsOf: [3, 4, 5])
        XCTAssertEqual(buffer.elements, [4, 5])
    }

    func test_latest_returnsNilForEmptyDoubleBuffer() {
        let buffer = RollingBuffer<Double>(capacity: 3)
        XCTAssertNil(buffer.latest)
    }

    func test_latest_returnsMostRecentDoubleElement() {
        var buffer = RollingBuffer<Double>(capacity: 3)
        buffer.append(1.0)
        buffer.append(2.5)
        XCTAssertEqual(buffer.latest, 2.5)
    }

    func test_capacityOne_alwaysHoldsOnlyMostRecentElement() {
        var buffer = RollingBuffer<Int>(capacity: 1)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        XCTAssertEqual(buffer.elements, [3])
    }
}
