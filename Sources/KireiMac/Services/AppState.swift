//
// AppState.swift
// MiniPulse
//
// 役割: メインウィンドウとメニューバー常駐ウィジェットで共有されるアプリ全体の状態管理オブジェクト。
// 存在意義: 各機能モジュールのスキャン結果・システム負荷履歴・累計削減容量を一元管理しつつ、省CPU設計でリアクティブなUI更新を実現する。

import Foundation
import SwiftUI
import AppKit

@MainActor
public final class AppState: ObservableObject {
    // MARK: - Navigation
    @Published public var selectedSection: NavigationSection = .smartCare

    // MARK: - System Monitor State
    @Published public var metrics: SystemMetricsSnapshot = .empty
    @Published public var cpuHistory: [Double] = Array(repeating: 0.05, count: 30)
    @Published public var memoryHistory: [Double] = Array(repeating: 0.30, count: 30)
    /// メニューバーの再描画頻度を最小限に抑えるための整数文字列キャッシュ
    @Published public var menuBarLabelText: String = "CPU 0% | RAM 0%"

    // MARK: - Junk Cleaner State
    @Published public var junkItems: [JunkItem] = []
    @Published public var isScanningJunk: Bool = false
    @Published public var isCleaningJunk: Bool = false
    @Published public var lastJunkCleanMessage: String?

    // MARK: - Large Files State
    @Published public var largeFiles: [LargeFileItem] = []
    @Published public var isScanningLargeFiles: Bool = false
    @Published public var sizeFilter: FileSizeFilter = .over50MB
    @Published public var ageFilter: FileAgeFilter = .all
    @Published public var lastLargeFileMessage: String?

    // MARK: - Duplicate Finder State
    @Published public var duplicateGroups: [DuplicateFileGroup] = []
    @Published public var isScanningDuplicates: Bool = false
    @Published public var lastDuplicateMessage: String?

    // MARK: - App Uninstaller State
    @Published public var installedApps: [InstalledAppItem] = []
    @Published public var isScanningApps: Bool = false
    @Published public var appSearchText: String = ""
    @Published public var lastUninstallMessage: String?

    // MARK: - Startup Manager State
    @Published public var startupItems: [StartupLaunchItem] = []
    @Published public var isScanningStartup: Bool = false
    @Published public var lastStartupMessage: String?

    // MARK: - Docker Cleaner State
    @Published public var dockerStatus: DockerStatusSnapshot = .empty
    @Published public var isScanningDocker: Bool = false
    @Published public var isPruningDocker: Bool = false
    @Published public var lastDockerMessage: String?

    // MARK: - Maintenance State
    @Published public var maintenanceTasks: [MaintenanceTaskItem] = MaintenanceService.defaultTasks()
    @Published public var isRunningMaintenance: Bool = false
    @Published public var lastMaintenanceSummary: String?

    // MARK: - Smart Care (One-Click) State
    @Published public var isRunningSmartScan: Bool = false
    @Published public var isRunningSmartCareCleanup: Bool = false
    @Published public var hasCompletedSmartScan: Bool = false
    @Published public var totalSessionFreedBytes: UInt64 = 0
    @Published public var smartCareBannerMessage: String?

    // MARK: - Services
    private let monitorService = SystemMonitorService()
    private let junkService = JunkScannerService()
    private let largeFileService = LargeFileScannerService()
    private let duplicateService = DuplicateScannerService()
    private let uninstallerService = AppUninstallerService()
    private let startupService = StartupManagerService()
    private let dockerService = DockerCleanerService()
    private let maintenanceService = MaintenanceService()

    private var monitorTimer: Timer?

    public init() {
        refreshMetrics(animated: false)
        startMonitoring()
    }

    // MARK: - Computed Properties

    public var totalJunkSelectedBytes: UInt64 {
        junkItems.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalJunkDetectedBytes: UInt64 {
        junkItems.reduce(0) { $0 + $1.sizeBytes }
    }

    public var filteredLargeFiles: [LargeFileItem] {
        let now = Date()
        return largeFiles.filter { item in
            guard item.sizeBytes >= sizeFilter.minBytes else { return false }
            if ageFilter != .all {
                let days = Calendar.current.dateComponents([.day], from: item.modifiedDate, to: now).day ?? 0
                if days < ageFilter.minAgeDays { return false }
            }
            return true
        }
    }

    public var selectedLargeFilesBytes: UInt64 {
        filteredLargeFiles.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalDuplicatesReclaimableBytes: UInt64 {
        duplicateGroups.reduce(0) { $0 + $1.reclaimableBytes }
    }

    public var filteredApps: [InstalledAppItem] {
        if appSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return installedApps
        }
        let query = appSearchText.lowercased()
        return installedApps.filter {
            $0.name.lowercased().contains(query) || $0.bundleIdentifier.lowercased().contains(query)
        }
    }

    /// Mac mini の総合ヘルススコア（0〜100）
    public var healthScore: Int {
        var score = 100
        if metrics.cpuUsageRatio > 0.85 { score -= 15 }
        else if metrics.cpuUsageRatio > 0.60 { score -= 6 }

        if metrics.memoryUsageRatio > 0.88 { score -= 15 }
        else if metrics.memoryUsageRatio > 0.75 { score -= 6 }

        if metrics.diskUsageRatio > 0.90 { score -= 20 }
        else if metrics.diskUsageRatio > 0.80 { score -= 8 }

        if totalJunkDetectedBytes > 2 * 1024 * 1024 * 1024 { score -= 12 }
        else if totalJunkDetectedBytes > 500 * 1024 * 1024 { score -= 5 }

        return max(40, min(100, score))
    }

    // MARK: - Low-CPU Real-time System Monitoring

    public func startMonitoring() {
        monitorTimer?.invalidate()
        // CPU負荷を抑えるため4秒間隔＋許容誤差(tolerance: 1.0秒)で省電力タイマー駆動
        let timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMetrics(animated: false)
            }
        }
        timer.tolerance = 1.0
        monitorTimer = timer
    }

    /// システムメトリクスを更新する。
    /// - Parameter animated: 定期ポーリング時は false にして不要な60fps補間描画を防ぎ、CPU負荷を1%未満に保つ。
    public func refreshMetrics(animated: Bool = false) {
        let shouldSampleProcesses = (selectedSection == .systemMonitor)
        let service = self.monitorService

        Task.detached(priority: .utility) {
            let snapshot = service.sampleMetrics(includeTopProcesses: shouldSampleProcesses)
            await MainActor.run { [weak self] in
                guard let self else { return }
                let applyUpdate = {
                    self.metrics = snapshot
                    self.cpuHistory.append(snapshot.cpuUsageRatio)
                    if self.cpuHistory.count > 30 {
                        self.cpuHistory.removeFirst()
                    }
                    self.memoryHistory.append(snapshot.memoryUsageRatio)
                    if self.memoryHistory.count > 30 {
                        self.memoryHistory.removeFirst()
                    }
                    let newLabel = String(
                        format: "CPU %.0f%% | RAM %.0f%%",
                        snapshot.cpuUsageRatio * 100,
                        snapshot.memoryUsageRatio * 100
                    )
                    if self.menuBarLabelText != newLabel {
                        self.menuBarLabelText = newLabel
                    }
                }

                if animated {
                    withAnimation(AppTheme.smoothSpring, applyUpdate)
                } else {
                    applyUpdate()
                }
            }
        }
    }

    // MARK: - Smart Care Actions

    public func runSmartScan() async {
        guard !isRunningSmartScan else { return }
        isRunningSmartScan = true
        smartCareBannerMessage = nil

        refreshMetrics(animated: false)
        let scannedJunk = await junkService.scanAllJunk()
        let scannedLarge = await largeFileService.scanLargeFiles(minSizeBytes: FileSizeFilter.over50MB.minBytes)

        withAnimation(AppTheme.smoothSpring) {
            self.junkItems = scannedJunk
            self.largeFiles = scannedLarge
            self.hasCompletedSmartScan = true
            self.isRunningSmartScan = false
        }
    }

    public func executeSmartCareCleanup() async {
        guard !isRunningSmartCareCleanup else { return }
        isRunningSmartCareCleanup = true

        let cleanResult = await junkService.cleanItems(junkItems)
        _ = await maintenanceService.runTask(id: "flush_dns")
        _ = await maintenanceService.runTask(id: "purge_memory")

        let remainingJunk = await junkService.scanAllJunk()
        refreshMetrics(animated: false)

        withAnimation(AppTheme.smoothSpring) {
            self.junkItems = remainingJunk
            self.totalSessionFreedBytes += cleanResult.freedBytes
            self.smartCareBannerMessage = "スマートケア完了：\(ByteFormatter.string(from: cleanResult.freedBytes)) を解放し、DNSとメモリキャッシュを最適化しました！"
            self.isRunningSmartCareCleanup = false
        }
    }

    // MARK: - Junk Cleaner Actions

    public func scanJunk() async {
        guard !isScanningJunk else { return }
        isScanningJunk = true
        lastJunkCleanMessage = nil
        let found = await junkService.scanAllJunk()
        withAnimation(AppTheme.smoothSpring) {
            self.junkItems = found
            self.isScanningJunk = false
        }
    }

    public func cleanSelectedJunk() async {
        guard !isCleaningJunk else { return }
        isCleaningJunk = true
        let result = await junkService.cleanItems(junkItems)
        let remaining = await junkService.scanAllJunk()
        refreshMetrics(animated: false)

        withAnimation(AppTheme.smoothSpring) {
            self.junkItems = remaining
            self.totalSessionFreedBytes += result.freedBytes
            self.lastJunkCleanMessage = "\(result.cleanedCount) 項目（合計 \(ByteFormatter.string(from: result.freedBytes))）をクリーンアップしました。"
            self.isCleaningJunk = false
        }
    }

    public func toggleJunkSelection(id: UUID) {
        if let idx = junkItems.firstIndex(where: { $0.id == id }) {
            junkItems[idx].isSelected.toggle()
        }
    }

    // MARK: - Large Files Actions

    public func scanLargeFiles() async {
        guard !isScanningLargeFiles else { return }
        isScanningLargeFiles = true
        lastLargeFileMessage = nil
        let found = await largeFileService.scanLargeFiles(minSizeBytes: FileSizeFilter.over20MB.minBytes)
        withAnimation(AppTheme.smoothSpring) {
            self.largeFiles = found
            self.isScanningLargeFiles = false
        }
    }

    public func toggleLargeFileSelection(id: UUID) {
        if let idx = largeFiles.firstIndex(where: { $0.id == id }) {
            largeFiles[idx].isSelected.toggle()
        }
    }

    public func trashSelectedLargeFiles() async {
        let targets = filteredLargeFiles.filter(\.isSelected)
        guard !targets.isEmpty else { return }
        let result = await largeFileService.moveFilesToTrash(targets)
        let removedURLs = Set(targets.map(\.url))
        refreshMetrics(animated: false)

        withAnimation(AppTheme.smoothSpring) {
            self.largeFiles.removeAll { removedURLs.contains($0.url) && !FileManager.default.fileExists(atPath: $0.url.path) }
            self.totalSessionFreedBytes += result.freedBytes
            self.lastLargeFileMessage = "\(result.removedCount) 件のファイルをゴミ箱へ移動しました（\(ByteFormatter.string(from: result.freedBytes)) 解放）。"
        }
    }

    // MARK: - Duplicate Finder Actions

    public func scanDuplicates() async {
        guard !isScanningDuplicates else { return }
        isScanningDuplicates = true
        lastDuplicateMessage = nil
        let groups = await duplicateService.scanDuplicates(minSizeBytes: 1024 * 1024)
        withAnimation(AppTheme.smoothSpring) {
            self.duplicateGroups = groups
            self.isScanningDuplicates = false
        }
    }

    public func toggleDuplicateEntry(groupId: UUID, entryId: UUID) {
        guard let gIdx = duplicateGroups.firstIndex(where: { $0.id == groupId }),
              let eIdx = duplicateGroups[gIdx].entries.firstIndex(where: { $0.id == entryId }) else {
            return
        }
        duplicateGroups[gIdx].entries[eIdx].isSelected.toggle()
    }

    public func trashSelectedDuplicates() async {
        let result = await duplicateService.trashSelectedDuplicates(in: duplicateGroups)
        let refreshedGroups = await duplicateService.scanDuplicates(minSizeBytes: 1024 * 1024)
        refreshMetrics(animated: false)

        withAnimation(AppTheme.smoothSpring) {
            self.duplicateGroups = refreshedGroups
            self.totalSessionFreedBytes += result.freedBytes
            self.lastDuplicateMessage = "\(result.removedCount) 個の重複コピーをゴミ箱へ移動しました（\(ByteFormatter.string(from: result.freedBytes)) 解放）。"
        }
    }

    // MARK: - App Uninstaller Actions

    public func scanApps() async {
        guard !isScanningApps else { return }
        isScanningApps = true
        lastUninstallMessage = nil
        let apps = await uninstallerService.scanInstalledApps()
        withAnimation(AppTheme.smoothSpring) {
            self.installedApps = apps
            self.isScanningApps = false
        }
    }

    public func uninstallApp(_ app: InstalledAppItem, leftoversOnly: Bool) async {
        let result = await uninstallerService.uninstallApp(app, leftoversOnly: leftoversOnly)
        let updatedApps = await uninstallerService.scanInstalledApps()
        refreshMetrics(animated: false)

        withAnimation(AppTheme.smoothSpring) {
            self.installedApps = updatedApps
            self.totalSessionFreedBytes += result.freedBytes
            if leftoversOnly {
                self.lastUninstallMessage = "「\(app.name)」の関連キャッシュ・残骸（\(ByteFormatter.string(from: result.freedBytes))）をゴミ箱へ移動しました。"
            } else {
                self.lastUninstallMessage = "「\(app.name)」本体と関連ファイル（\(ByteFormatter.string(from: result.freedBytes))）をゴミ箱へ移動しました。"
            }
        }
    }

    // MARK: - Startup Manager Actions

    public func scanStartupItems() async {
        guard !isScanningStartup else { return }
        isScanningStartup = true
        lastStartupMessage = nil
        let items = await startupService.scanStartupItems()
        withAnimation(AppTheme.smoothSpring) {
            self.startupItems = items
            self.isScanningStartup = false
        }
    }

    public func toggleStartupItem(_ item: StartupLaunchItem) async {
        let result = await startupService.toggleUserLaunchAgent(item)
        let refreshed = await startupService.scanStartupItems()
        withAnimation(AppTheme.smoothSpring) {
            self.startupItems = refreshed
            self.lastStartupMessage = result.message
        }
    }

    public func trashStartupItem(_ item: StartupLaunchItem) async {
        let result = await startupService.movePlistToTrash(item)
        let refreshed = await startupService.scanStartupItems()
        withAnimation(AppTheme.smoothSpring) {
            self.startupItems = refreshed
            self.lastStartupMessage = result.message
        }
    }

    // MARK: - Docker Cleaner Actions

    public func scanDocker() async {
        guard !isScanningDocker else { return }
        isScanningDocker = true
        lastDockerMessage = nil
        let status = await dockerService.inspectDockerStatus()
        withAnimation(AppTheme.smoothSpring) {
            self.dockerStatus = status
            self.isScanningDocker = false
        }
    }

    public func pruneDockerResources(includeVolumes: Bool = false) async {
        guard !isPruningDocker else { return }
        isPruningDocker = true
        let result = await dockerService.pruneDocker(includeVolumes: includeVolumes)
        let refreshed = await dockerService.inspectDockerStatus()
        refreshMetrics(animated: false)

        withAnimation(AppTheme.smoothSpring) {
            self.dockerStatus = refreshed
            self.lastDockerMessage = result.outputMessage
            self.isPruningDocker = false
        }
    }

    public func pruneDockerBuildCache() async {
        guard !isPruningDocker else { return }
        isPruningDocker = true
        let result = await dockerService.pruneBuildCacheOnly()
        let refreshed = await dockerService.inspectDockerStatus()
        refreshMetrics(animated: false)

        withAnimation(AppTheme.smoothSpring) {
            self.dockerStatus = refreshed
            self.lastDockerMessage = result.outputMessage
            self.isPruningDocker = false
        }
    }

    // MARK: - Maintenance Actions

    public func toggleMaintenanceTask(id: String) {
        if let idx = maintenanceTasks.firstIndex(where: { $0.id == id }) {
            maintenanceTasks[idx].isSelected.toggle()
        }
    }

    public func runSingleMaintenanceTask(id: String) async {
        guard let idx = maintenanceTasks.firstIndex(where: { $0.id == id }) else { return }
        isRunningMaintenance = true
        let outcome = await maintenanceService.runTask(id: id)
        withAnimation(AppTheme.smoothSpring) {
            maintenanceTasks[idx].lastRunDate = Date()
            maintenanceTasks[idx].lastRunSucceeded = outcome.succeeded
            maintenanceTasks[idx].lastResultMessage = outcome.message
            lastMaintenanceSummary = "「\(maintenanceTasks[idx].title)」を実行しました: \(outcome.message)"
            isRunningMaintenance = false
        }
        refreshMetrics(animated: false)
    }

    public func runSelectedMaintenanceTasks() async {
        guard !isRunningMaintenance else { return }
        isRunningMaintenance = true
        var successCount = 0

        for idx in maintenanceTasks.indices where maintenanceTasks[idx].isSelected {
            let taskId = maintenanceTasks[idx].id
            let outcome = await maintenanceService.runTask(id: taskId)
            maintenanceTasks[idx].lastRunDate = Date()
            maintenanceTasks[idx].lastRunSucceeded = outcome.succeeded
            maintenanceTasks[idx].lastResultMessage = outcome.message
            if outcome.succeeded { successCount += 1 }
        }

        withAnimation(AppTheme.smoothSpring) {
            lastMaintenanceSummary = "選択された \(successCount) 件のメンテナンスタスクが完了しました。"
            isRunningMaintenance = false
        }
        refreshMetrics(animated: false)
    }

    // MARK: - Finder Integration

    public func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Sanitized Demo Data for Generic Public Screenshots (No Personal Info)

    public init(isDemoMode: Bool) {
        if isDemoMode {
            populateSanitizedDemoData()
        } else {
            refreshMetrics(animated: false)
            startMonitoring()
        }
    }

    /// ユーザーの個人環境（ユーザー名、実ファイル名、実アプリ一覧）を一切含まない、GitHub公開スクリーンショット用の匿名サンプルデータを構築する
    public func populateSanitizedDemoData() {
        self.hasCompletedSmartScan = true
        self.totalSessionFreedBytes = 4_820_000_000 // 4.82 GB
        self.smartCareBannerMessage = "スマートケア診断完了：14.6 GB の不要キャッシュ・開発ファイルが安全に解放可能です。"

        self.metrics = SystemMetricsSnapshot(
            timestamp: Date(),
            cpuUsageRatio: 0.14,
            cpuUserRatio: 0.09,
            cpuSystemRatio: 0.05,
            memoryUsedBytes: 11_200_000_000,
            memoryTotalBytes: 24_000_000_000,
            memoryWiredBytes: 2_800_000_000,
            memoryActiveBytes: 6_400_000_000,
            memoryCompressedBytes: 980_000_000,
            diskUsedBytes: 268_000_000_000,
            diskTotalBytes: 512_000_000_000,
            diskAvailableBytes: 244_000_000_000,
            networkUploadBytesPerSec: 185 * 1024,
            networkDownloadBytesPerSec: 4.2 * 1024 * 1024,
            uptimeSeconds: 5 * 86400 + 14 * 3600 + 22 * 60,
            thermalStateDescription: "快適・低温 (Nominal)",
            topProcesses: [
                ProcessMetricItem(id: 412, name: "WindowServer", cpuPercent: 6.4, memoryMB: 412.5),
                ProcessMetricItem(id: 890, name: "Safari WebContent", cpuPercent: 4.1, memoryMB: 620.0),
                ProcessMetricItem(id: 1024, name: "Xcode", cpuPercent: 2.8, memoryMB: 1480.2),
                ProcessMetricItem(id: 518, name: "Spotlight (mds_stores)", cpuPercent: 1.2, memoryMB: 215.8),
                ProcessMetricItem(id: 301, name: "coreaudiod", cpuPercent: 0.5, memoryMB: 48.0),
                ProcessMetricItem(id: 1205, name: "KireiMac", cpuPercent: 0.2, memoryMB: 64.0)
            ]
        )

        self.cpuHistory = [
            0.12, 0.15, 0.18, 0.14, 0.11, 0.22, 0.28, 0.19, 0.15, 0.13,
            0.14, 0.16, 0.21, 0.25, 0.18, 0.14, 0.12, 0.15, 0.17, 0.13,
            0.11, 0.14, 0.19, 0.16, 0.13, 0.12, 0.15, 0.14, 0.13, 0.14
        ]
        self.memoryHistory = [
            0.44, 0.45, 0.45, 0.46, 0.46, 0.48, 0.49, 0.48, 0.47, 0.47,
            0.46, 0.46, 0.47, 0.48, 0.47, 0.46, 0.46, 0.45, 0.46, 0.46,
            0.47, 0.47, 0.48, 0.47, 0.46, 0.46, 0.47, 0.46, 0.46, 0.47
        ]

        self.junkItems = [
            JunkItem(
                category: .xcodeJunk,
                name: "Xcode DerivedData (ビルド中間生成物)",
                url: URL(fileURLWithPath: "/Users/demo/Library/Developer/Xcode/DerivedData"),
                sizeBytes: 8_420_000_000,
                isSelected: true
            ),
            JunkItem(
                category: .packageManagerCache,
                name: "Homebrew ダウンロードキャッシュ",
                url: URL(fileURLWithPath: "/Users/demo/Library/Caches/Homebrew"),
                sizeBytes: 3_150_000_000,
                isSelected: true
            ),
            JunkItem(
                category: .packageManagerCache,
                name: "npm キャッシュ (~/.npm/_cacache)",
                url: URL(fileURLWithPath: "/Users/demo/.npm/_cacache"),
                sizeBytes: 1_840_000_000,
                isSelected: true
            ),
            JunkItem(
                category: .userCaches,
                name: "com.apple.Safari.SafeBrowsing",
                url: URL(fileURLWithPath: "/Users/demo/Library/Caches/com.apple.Safari"),
                sizeBytes: 680_000_000,
                isSelected: true
            ),
            JunkItem(
                category: .userLogs,
                name: "DiagnosticReports & System Logs",
                url: URL(fileURLWithPath: "/Users/demo/Library/Logs/DiagnosticReports"),
                sizeBytes: 510_000_000,
                isSelected: true
            )
        ]

        self.largeFiles = [
            LargeFileItem(
                name: "iOS_18.2_Simulator_Runtime.dmg",
                url: URL(fileURLWithPath: "/Users/demo/Downloads/iOS_18.2_Simulator_Runtime.dmg"),
                sizeBytes: 7_850_000_000,
                modifiedDate: Date().addingTimeInterval(-45 * 86400),
                fileTypeCategory: "ディスクイメージ・インストーラ",
                isSelected: true
            ),
            LargeFileItem(
                name: "Keynote_Product_Demo_4K_Raw.mov",
                url: URL(fileURLWithPath: "/Users/demo/Movies/Keynote_Product_Demo_4K_Raw.mov"),
                sizeBytes: 4_320_000_000,
                modifiedDate: Date().addingTimeInterval(-120 * 86400),
                fileTypeCategory: "動画・ムービー",
                isSelected: false
            ),
            LargeFileItem(
                name: "Project_Archive_2025_Backup.zip",
                url: URL(fileURLWithPath: "/Users/demo/Desktop/Project_Archive_2025_Backup.zip"),
                sizeBytes: 2_140_000_000,
                modifiedDate: Date().addingTimeInterval(-95 * 86400),
                fileTypeCategory: "アーカイブ・圧縮ファイル",
                isSelected: true
            ),
            LargeFileItem(
                name: "Llama-3-8B-Instruct-Q4_K_M.gguf",
                url: URL(fileURLWithPath: "/Users/demo/Documents/Models/Llama-3-8B-Instruct-Q4_K_M.gguf"),
                sizeBytes: 4_920_000_000,
                modifiedDate: Date().addingTimeInterval(-60 * 86400),
                fileTypeCategory: "AIモデル・重みデータ",
                isSelected: false
            )
        ]

        self.duplicateGroups = [
            DuplicateFileGroup(
                hashSignature: "a94f8c2d10e7",
                fileNameSample: "macOS_Design_Resources_v2.zip",
                eachFileSizeBytes: 1_250_000_000,
                entries: [
                    DuplicateFileEntry(
                        url: URL(fileURLWithPath: "/Users/demo/Documents/Design/macOS_Design_Resources_v2.zip"),
                        modifiedDate: Date().addingTimeInterval(-30 * 86400),
                        isSelected: false
                    ),
                    DuplicateFileEntry(
                        url: URL(fileURLWithPath: "/Users/demo/Downloads/macOS_Design_Resources_v2 (1).zip"),
                        modifiedDate: Date().addingTimeInterval(-12 * 86400),
                        isSelected: true
                    ),
                    DuplicateFileEntry(
                        url: URL(fileURLWithPath: "/Users/demo/Desktop/macOS_Design_Resources_v2_copy.zip"),
                        modifiedDate: Date().addingTimeInterval(-4 * 86400),
                        isSelected: true
                    )
                ]
            ),
            DuplicateFileGroup(
                hashSignature: "e3b0c44298fc",
                fileNameSample: "Universal_Installer_v4.2.dmg",
                eachFileSizeBytes: 640_000_000,
                entries: [
                    DuplicateFileEntry(
                        url: URL(fileURLWithPath: "/Users/demo/Downloads/Universal_Installer_v4.2.dmg"),
                        modifiedDate: Date().addingTimeInterval(-20 * 86400),
                        isSelected: false
                    ),
                    DuplicateFileEntry(
                        url: URL(fileURLWithPath: "/Users/demo/Downloads/Archive/Universal_Installer_v4.2.dmg"),
                        modifiedDate: Date().addingTimeInterval(-19 * 86400),
                        isSelected: true
                    )
                ]
            )
        ]

        self.dockerStatus = DockerStatusSnapshot(
            isDockerInstalled: true,
            isDaemonRunning: true,
            resources: [
                DockerResourceSummary(id: "Images", typeName: "Docker イメージ (Images)", totalCount: "18", activeCount: "4", sizeText: "21.4 GB", reclaimableText: "15.8 GB (73%)"),
                DockerResourceSummary(id: "Containers", typeName: "コンテナ (Containers)", totalCount: "9", activeCount: "3", sizeText: "1.2 GB", reclaimableText: "840 MB (70%)"),
                DockerResourceSummary(id: "Local Volumes", typeName: "ローカルボリューム (Volumes)", totalCount: "12", activeCount: "5", sizeText: "6.8 GB", reclaimableText: "3.4 GB (50%)"),
                DockerResourceSummary(id: "Build Cache", typeName: "ビルドキャッシュ (BuildKit)", totalCount: "64", activeCount: "0", sizeText: "12.6 GB", reclaimableText: "12.6 GB (100%)")
            ],
            statusMessage: "Docker エンジン稼働中"
        )
    }
}
