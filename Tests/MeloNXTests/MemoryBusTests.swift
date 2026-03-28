// MemoryBusTests.swift
// MeloNX Air5 Edition
//
// Unit tests for the MemoryBus implementation.

import XCTest
@testable import MeloNXCore

final class MemoryBusTests: XCTestCase {

    var bus: MemoryBus!

    override func setUp() {
        super.setUp()
        bus = MemoryBus()
    }

    // MARK: - Basic read/write

    func testReadWriteUInt8() {
        let addr: UInt64 = 0x8000_0000
        bus.write8(address: addr, value: 0xAB)
        XCTAssertEqual(bus.read8(address: addr), 0xAB)
    }

    func testReadWriteUInt16() {
        let addr: UInt64 = 0x8000_0010
        bus.write16(address: addr, value: 0xBEEF)
        XCTAssertEqual(bus.read16(address: addr), 0xBEEF)
    }

    func testReadWriteUInt32() {
        let addr: UInt64 = 0x8000_0020
        bus.write32(address: addr, value: 0xDEAD_BEEF)
        XCTAssertEqual(bus.read32(address: addr), 0xDEAD_BEEF)
    }

    func testReadWriteUInt64() {
        let addr: UInt64 = 0x8000_0040
        bus.write64(address: addr, value: 0xCAFE_BABE_DEAD_BEEF)
        XCTAssertEqual(bus.read64(address: addr), 0xCAFE_BABE_DEAD_BEEF)
    }

    // MARK: - Unmapped reads return zero

    func testUnmappedReadReturnsZero() {
        let addr: UInt64 = 0x9000_0000
        XCTAssertEqual(bus.read32(address: addr), 0x0000_0000)
    }

    // MARK: - Block load

    func testLoadDataBlock() {
        let payload = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let base: UInt64 = 0x8000_1000
        bus.loadData(payload, at: base)
        for (i, byte) in payload.enumerated() {
            XCTAssertEqual(bus.read8(address: base + UInt64(i)), byte)
        }
    }

    // MARK: - Cross-page access

    func testCrossPageWrite() {
        let pageSize: UInt64 = 0x1000
        // Write a 32-bit value spanning two pages.
        let addr = pageSize - 2  // offset 0xFFE in page 0
        bus.write32(address: addr, value: 0x1234_5678)
        XCTAssertEqual(bus.read32(address: addr), 0x1234_5678)
    }

    // MARK: - Overwrite

    func testOverwriteValue() {
        let addr: UInt64 = 0x8001_0000
        bus.write32(address: addr, value: 0xFFFF_FFFF)
        bus.write32(address: addr, value: 0x0000_0001)
        XCTAssertEqual(bus.read32(address: addr), 0x0000_0001)
    }
}
