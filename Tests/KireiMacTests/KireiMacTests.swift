//
// KireiMacTests.swift
// KireiMacTests
//
// 役割: KireiMac のコアロジック（フォーマット変換、システムモニター計測、ファイル種別分類、重複ハッシュ計算、匿名デモデータ生成）の単体テスト。
// 存在意義: TDD原則に基づき、各サービスがクラッシュせず正確な値を返し、デモモードに個人情報が一切含まれないことを検証する。

import XCTest
@testable import KireiMac

final class KireiMacTests: XCTestCase {
    func testByteFormatterSpeedAndUptime() {
        XCTAssertEqual(ByteFormatter.speedString(bytesPerSec: 500), "500 B/s")
        XCTAssertEqual(ByteFormatter.speedString(bytesPerSec: 2048), "2.0 KB/s")
        XCTAssertEqual(ByteFormatter.uptimeString(seconds: 3665), "1時間 1分")
        XCTAssertEqual(ByteFormatter.uptimeString(seconds: 90000), "1日 1時間 0分")
    }

    func testFileExtensionClassification() {
        XCTAssertEqual(LargeFileScannerService.classifyFileExtension("mp4"), "動画・ムービー")
        XCTAssertEqual(LargeFileScannerService.classifyFileExtension("DMG"), "ディスクイメージ・インストーラ")
        XCTAssertEqual(LargeFileScannerService.classifyFileExtension("gguf"), "AIモデル・重みデータ")
        XCTAssertEqual(LargeFileScannerService.classifyFileExtension("zip"), "アーカイブ・圧縮ファイル")
    }

    func testSystemMonitorSnapshotValidity() {
        let monitor = SystemMonitorService()
        let first = monitor.sampleMetrics()
        let second = monitor.sampleMetrics()

        XCTAssertGreaterThan(second.memoryTotalBytes, 0)
        XCTAssertGreaterThan(second.diskTotalBytes, 0)
        XCTAssertGreaterThanOrEqual(second.cpuUsageRatio, 0.0)
        XCTAssertLessThanOrEqual(second.cpuUsageRatio, 1.0)
        XCTAssertGreaterThanOrEqual(second.memoryUsageRatio, 0.0)
        XCTAssertLessThanOrEqual(second.memoryUsageRatio, 1.0)
        XCTAssertNotNil(first.thermalStateDescription)
    }

    func testMaintenanceDefaultTasksNotEmpty() {
        let tasks = MaintenanceService.defaultTasks()
        XCTAssertEqual(tasks.count, 6)
        XCTAssertTrue(tasks.contains(where: { $0.id == "flush_dns" }))
        XCTAssertTrue(tasks.contains(where: { $0.id == "rebuild_launchservices" }))
    }

    func testNavigationSectionsIncludeAllProModules() {
        let all = NavigationSection.allCases
        XCTAssertEqual(all.count, 9)
        XCTAssertTrue(all.contains(.duplicateFinder))
        XCTAssertTrue(all.contains(.startupManager))
        XCTAssertTrue(all.contains(.dockerCleaner))
    }

    func testDuplicateFastSHA256Consistency() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileA = tmpDir.appendingPathComponent("kireimac_test_a.dat")
        let fileB = tmpDir.appendingPathComponent("kireimac_test_b.dat")
        defer {
            try? FileManager.default.removeItem(at: fileA)
            try? FileManager.default.removeItem(at: fileB)
        }

        let payload = Data(repeating: 0xAB, count: 8192)
        try payload.write(to: fileA)
        try payload.write(to: fileB)

        let hashA = DuplicateScannerService.computeFastContentSHA256(url: fileA, fileSize: 8192)
        let hashB = DuplicateScannerService.computeFastContentSHA256(url: fileB, fileSize: 8192)
        XCTAssertNotNil(hashA)
        XCTAssertEqual(hashA, hashB)
    }

    @MainActor
    func testSanitizedDemoStateContainsNoRealUserHome() {
        let demo = AppState(isDemoMode: true)
        let realUser = NSUserName()
        for item in demo.junkItems {
            XCTAssertFalse(item.url.path.contains(realUser), "Demo junk path must not contain real username")
            XCTAssertTrue(item.url.path.hasPrefix("/Users/demo/"))
        }
        for file in demo.largeFiles {
            XCTAssertFalse(file.url.path.contains(realUser), "Demo large file path must not contain real username")
            XCTAssertTrue(file.url.path.hasPrefix("/Users/demo/"))
        }
    }
}
