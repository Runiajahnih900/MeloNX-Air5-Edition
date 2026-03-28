// AudioRingBufferTests.swift
// MeloNX Air5 Edition
//
// Unit tests for the lock-free audio ring buffer.

import XCTest
@testable import MeloNXCore

final class AudioRingBufferTests: XCTestCase {

    func testEmptyBufferReadsNothing() {
        let rb = AudioRingBuffer(capacity: 64)
        let result = rb.read(count: 10)
        XCTAssertTrue(result.isEmpty)
    }

    func testWriteThenRead() {
        let rb = AudioRingBuffer(capacity: 64)
        let samples = [AudioSample(left: 100, right: 200),
                       AudioSample(left: 300, right: 400)]
        rb.write(samples)
        let result = rb.read(count: 2)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].left,  100)
        XCTAssertEqual(result[0].right, 200)
        XCTAssertEqual(result[1].left,  300)
        XCTAssertEqual(result[1].right, 400)
    }

    func testPartialRead() {
        let rb = AudioRingBuffer(capacity: 64)
        let samples = (0..<10).map { AudioSample(left: Int16($0), right: Int16($0 + 100)) }
        rb.write(samples)
        let partial = rb.read(count: 5)
        XCTAssertEqual(partial.count, 5)
        let rest = rb.read(count: 10)
        XCTAssertEqual(rest.count, 5)
    }

    func testAvailableRead() {
        let rb = AudioRingBuffer(capacity: 64)
        XCTAssertEqual(rb.availableRead, 0)
        let samples = [AudioSample(left: 0, right: 0),
                       AudioSample(left: 1, right: 1),
                       AudioSample(left: 2, right: 2)]
        rb.write(samples)
        XCTAssertEqual(rb.availableRead, 3)
        _ = rb.read(count: 2)
        XCTAssertEqual(rb.availableRead, 1)
    }

    func testReadMoreThanAvailableReturnsAll() {
        let rb = AudioRingBuffer(capacity: 64)
        let samples = [AudioSample(left: 10, right: 20)]
        rb.write(samples)
        let result = rb.read(count: 100)
        XCTAssertEqual(result.count, 1)
    }
}
