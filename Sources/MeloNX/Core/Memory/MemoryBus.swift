// MemoryBus.swift
// MeloNX Air5 Edition
//
// Memory management and bus controller for Nintendo Switch memory map.

import Foundation

/// Memory map constants for the Nintendo Switch.
enum MemoryMap {
    static let ramBase: UInt64       = 0x0000_0000_8000_0000
    static let ramSize: UInt64       = 0x0000_0000_C000_0000  // 4 GB address space
    static let vramBase: UInt64      = 0x0000_0000_C800_0000
    static let vramSize: UInt64      = 0x0000_0000_0200_0000  // 32 MB VRAM
    static let mmioBase: UInt64      = 0x5000_0000_0000_0000
}

/// Errors that can be raised by memory operations.
enum MemoryError: Error {
    case unmappedRead(address: UInt64)
    case unmappedWrite(address: UInt64)
    case alignmentFault(address: UInt64, size: Int)
}

/// The central memory bus. All CPU, GPU, and DMA accesses go through this object.
final class MemoryBus {

    // MARK: - Storage

    /// Main RAM (up to 4 GB, lazily allocated in pages).
    private var ram: [UInt64: Data] = [:]
    private let pageSize: UInt64 = 0x1000  // 4 KB pages

    /// MMIO handler registry.
    private var mmioHandlers: [ClosedRange<UInt64>: MMIOHandler] = [:]

    // MARK: - Read

    func read8(address: UInt64) -> UInt8 {
        let page = pageForAddress(address)
        let offset = Int(address & (pageSize - 1))
        return page[offset]
    }

    func read16(address: UInt64) -> UInt16 {
        let lo = UInt16(read8(address: address))
        let hi = UInt16(read8(address: address &+ 1))
        return lo | (hi << 8)
    }

    func read32(address: UInt64) -> UInt32 {
        let lo = UInt32(read16(address: address))
        let hi = UInt32(read16(address: address &+ 2))
        return lo | (hi << 16)
    }

    func read64(address: UInt64) -> UInt64 {
        let lo = UInt64(read32(address: address))
        let hi = UInt64(read32(address: address &+ 4))
        return lo | (hi << 32)
    }

    // MARK: - Write

    func write8(address: UInt64, value: UInt8) {
        let pageBase = address & ~(pageSize - 1)
        let offset = Int(address & (pageSize - 1))
        if ram[pageBase] == nil {
            ram[pageBase] = Data(count: Int(pageSize))
        }
        ram[pageBase]![offset] = value
    }

    func write16(address: UInt64, value: UInt16) {
        write8(address: address,      value: UInt8(value & 0xFF))
        write8(address: address &+ 1, value: UInt8(value >> 8))
    }

    func write32(address: UInt64, value: UInt32) {
        write16(address: address,      value: UInt16(value & 0xFFFF))
        write16(address: address &+ 2, value: UInt16(value >> 16))
    }

    func write64(address: UInt64, value: UInt64) {
        write32(address: address,      value: UInt32(value & 0xFFFF_FFFF))
        write32(address: address &+ 4, value: UInt32(value >> 32))
    }

    // MARK: - Block operations

    /// Load a block of data into RAM at the given guest address.
    func loadData(_ data: Data, at address: UInt64) {
        for (index, byte) in data.enumerated() {
            write8(address: address &+ UInt64(index), value: byte)
        }
    }

    // MARK: - MMIO

    /// Register an MMIO handler for a given address range.
    func registerMMIO(range: ClosedRange<UInt64>, handler: MMIOHandler) {
        mmioHandlers[range] = handler
    }

    // MARK: - Private helpers

    private func pageForAddress(_ address: UInt64) -> Data {
        let pageBase = address & ~(pageSize - 1)
        if let page = ram[pageBase] {
            return page
        }
        // Return a zeroed page for unmapped reads (Switch behavior).
        return Data(count: Int(pageSize))
    }
}

// MARK: - MMIOHandler

/// Protocol for memory-mapped I/O device handlers.
protocol MMIOHandler: AnyObject {
    func read32(offset: UInt64) -> UInt32
    func write32(offset: UInt64, value: UInt32)
}
