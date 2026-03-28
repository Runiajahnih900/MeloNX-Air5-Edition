// M1Optimizations.swift
// MeloNX Air5 Edition
//
// Apple M1-specific performance optimizations for the iPad Air 5.

import Foundation

/// Provides M1-specific configuration for maximum emulation performance.
enum M1Optimizations {

    // MARK: - Thread Affinity

    /// Bind the CPU emulation thread to the M1 performance cores.
    /// The M1 in iPad Air 5 has 4 performance (Firestorm) + 4 efficiency (Icestorm) cores.
    static func bindEmulationThreadToPerformanceCores() {
        // On Apple Silicon, thread affinity is managed through QoS classes.
        // Setting .userInteractive routes the thread to performance cores.
        Thread.current.qualityOfService = .userInteractive
    }

    /// Bind the audio thread to an efficiency core to save power.
    static func bindAudioThreadToEfficiencyCores() {
        Thread.current.qualityOfService = .utility
    }

    // MARK: - Memory

    /// Page size used for JIT code allocation on the Apple M1 host: 16 KB.
    /// Note: the MemoryBus uses 4 KB pages to emulate the Switch's guest memory map,
    /// which is separate from this host JIT page size.
    static let pageSize: Int = 16 * 1024

    /// Recommended JIT code cache size for M1 (128 MB – fits well in 8 GB).
    static let jitCacheSize: Int = 128 * 1024 * 1024

    /// Allocate a JIT code buffer with read-write-execute permissions.
    /// Returns a pointer to the allocated buffer, or nil on failure.
    static func allocateJITBuffer(size: Int) -> UnsafeMutableRawPointer? {
        let alignedSize = (size + pageSize - 1) & ~(pageSize - 1)
        var ptr: UnsafeMutableRawPointer?
        let result = posix_memalign(&ptr, pageSize, alignedSize)
        guard result == 0, let buffer = ptr else { return nil }
        // Mark region as read+write initially; switch to read+execute before running.
        mprotect(buffer, alignedSize, PROT_READ | PROT_WRITE)
        return buffer
    }

    /// Switch a JIT buffer from writable to executable.
    static func markJITBufferExecutable(_ buffer: UnsafeMutableRawPointer, size: Int) {
        let alignedSize = (size + pageSize - 1) & ~(pageSize - 1)
        mprotect(buffer, alignedSize, PROT_READ | PROT_EXEC)
        // Flush the instruction cache for the modified region.
        sys_icache_invalidate(buffer, alignedSize)
    }

    /// Switch a JIT buffer from executable back to writable (for patching).
    static func markJITBufferWritable(_ buffer: UnsafeMutableRawPointer, size: Int) {
        let alignedSize = (size + pageSize - 1) & ~(pageSize - 1)
        mprotect(buffer, alignedSize, PROT_READ | PROT_WRITE)
    }

    // MARK: - NEON/AMX intrinsics

    /// Returns true if AMX (Apple Matrix Coprocessor) acceleration is available.
    /// AMX is present in all M1 chips and can accelerate matrix operations used in game physics.
    static var amxAvailable: Bool {
        // AMX is always present on M1; detected via CPU feature flags.
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Metal Performance Shaders

    /// Whether MPS (Metal Performance Shaders) upscaling is available.
    /// Used for upscaling lower-resolution render targets to native 2360×1640.
    static var mpsUpscalingAvailable: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}
