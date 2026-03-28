// iPadAir5DeviceTests.swift
// MeloNX Air5 Edition
//
// Unit tests for iPadAir5Device profile.

import XCTest
@testable import MeloNXCore

final class iPadAir5DeviceTests: XCTestCase {

    // MARK: - Display properties

    func testDisplayResolution() {
        XCTAssertEqual(iPadAir5Device.displayWidth,  2360)
        XCTAssertEqual(iPadAir5Device.displayHeight, 1640)
    }

    func testDisplayPPI() {
        XCTAssertEqual(iPadAir5Device.ppi, 264.0, accuracy: 0.1)
    }

    func testLogicalResolution() {
        XCTAssertEqual(iPadAir5Device.logicalWidth,  1180)
        XCTAssertEqual(iPadAir5Device.logicalHeight, 820)
    }

    // MARK: - Memory budget

    func testEmulatorRAMBudget() {
        let fourGB: UInt64 = 4 * 1024 * 1024 * 1024
        XCTAssertEqual(iPadAir5Device.emulatorRAMBudget, fourGB)
        XCTAssertLessThanOrEqual(iPadAir5Device.emulatorRAMBudget, iPadAir5Device.totalRAM)
    }

    // MARK: - Core counts

    func testCoreCount() {
        XCTAssertEqual(iPadAir5Device.performanceCoreCount + iPadAir5Device.efficiencyCoreCount, 8)
        XCTAssertEqual(iPadAir5Device.gpuCoreCount, 7)
    }

    // MARK: - Performance tiers

    func testUltraPerformanceTier() {
        let tier = iPadAir5Device.PerformanceTier.ultraPerformance
        XCTAssertEqual(tier.targetFPS, 60)
        XCTAssertEqual(tier.renderScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(tier.jitThreadCount, 4)
    }

    func testBatteryLifeTier() {
        let tier = iPadAir5Device.PerformanceTier.batteryLife
        XCTAssertEqual(tier.targetFPS, 30)
        XCTAssertEqual(tier.renderScale, 0.5, accuracy: 0.001)
    }

    func testAllTiersHavePositiveFPS() {
        for tier in iPadAir5Device.PerformanceTier.allCases {
            XCTAssertGreaterThan(tier.targetFPS, 0, "Tier \(tier.rawValue) must have positive FPS")
        }
    }

    func testAllTiersHaveValidRenderScale() {
        for tier in iPadAir5Device.PerformanceTier.allCases {
            XCTAssertGreaterThan(tier.renderScale, 0.0, "Render scale must be > 0")
            XCTAssertLessThanOrEqual(tier.renderScale, 1.0, "Render scale must be ≤ 1.0")
        }
    }
}
