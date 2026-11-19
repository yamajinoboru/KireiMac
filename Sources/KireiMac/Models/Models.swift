//
// Models.swift
// MiniPulse
//
// 役割: アプリ全体で使用するドメインモデルおよび状態表現の定義。
// 存在意義: UIレイヤーとサービスレイヤー間で型安全かつイミュータブル/明瞭なデータ受け渡しを実現する。

import Foundation
import AppKit

/// サイドバーのナビゲーション項目
public enum NavigationSection: String, CaseIterable, Identifiable, Sendable {
    case smartCare = "スマートケア"
    case junkCleaner = "ジャンク掃除"
    case systemMonitor = "システムモニター"
    case largeFiles = "大容量＆古いファイル"
    case duplicateFinder = "重複ファイル"
    case appUninstaller = "アプリ管理"
    case startupManager = "スタートアップ管理"
    case dockerCleaner = "Docker 掃除"
    case maintenance = "メンテナンス"

    public var id: String { rawValue }

    public var subtitle: String {
        switch self {
        case .smartCare: return "一括ヘルスチェック＆高速クリーン"
        case .junkCleaner: return "システム・開発キャッシュの安全な削除"
        case .systemMonitor: return "CPU・メモリ・ディスク・通信のリアルタイム監視"
        case .largeFiles: return "ストレージを圧迫する巨大ファイルの特定"
        case .duplicateFinder: return "SHA-256 ハッシュ比較で同一ファイルを高速特定・整理"
        case .appUninstaller: return "アプリ本体と関連残骸ファイルの完全削除"
        case .startupManager: return "LaunchAgents / 常駐プログラムの稼働管理"
        case .dockerCleaner: return "Docker コンテナ・イメージ・ビルドキャッシュの整理"
        case .maintenance: return "macOS 最適化スクリプト＆修復タスク"
        }
    }

    public var iconName: String {
        switch self {
        case .smartCare: return "sparkles"
        case .junkCleaner: return "trash.circle.fill"
        case .systemMonitor: return "gauge.with.dots.needle.33percent"
        case .largeFiles: return "externaldrive.fill.badge.timemachine"
        case .duplicateFinder: return "doc.on.doc.fill"
        case .appUninstaller: return "square.stack.3d.up.fill"
        case .startupManager: return "power.circle.fill"
        case .dockerCleaner: return "shippingbox.and.arrow.backward.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        }
    }
}

// MARK: - System Monitor Models

/// CPU・メモリ・ディスク・ネットワークのリアルタイムスナップショット
public struct SystemMetricsSnapshot: Sendable, Equatable {
    public var timestamp: Date
    public var cpuUsageRatio: Double        // 0.0 ... 1.0
    public var cpuUserRatio: Double         // 0.0 ... 1.0
    public var cpuSystemRatio: Double       // 0.0 ... 1.0
    public var memoryUsedBytes: UInt64
    public var memoryTotalBytes: UInt64
    public var memoryWiredBytes: UInt64
    public var memoryActiveBytes: UInt64
    public var memoryCompressedBytes: UInt64
    public var diskUsedBytes: UInt64
    public var diskTotalBytes: UInt64
    public var diskAvailableBytes: UInt64
    public var networkUploadBytesPerSec: Double
    public var networkDownloadBytesPerSec: Double
    public var uptimeSeconds: TimeInterval
    public var thermalStateDescription: String
    public var topProcesses: [ProcessMetricItem]

    public var memoryUsageRatio: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(memoryUsedBytes) / Double(memoryTotalBytes)))
    }

    public var diskUsageRatio: Double {
        guard diskTotalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(diskUsedBytes) / Double(diskTotalBytes)))
    }

    public static let empty = SystemMetricsSnapshot(
        timestamp: Date(),
        cpuUsageRatio: 0,
        cpuUserRatio: 0,
        cpuSystemRatio: 0,
        memoryUsedBytes: 0,
        memoryTotalBytes: ProcessInfo.processInfo.physicalMemory,
        memoryWiredBytes: 0,
        memoryActiveBytes: 0,
        memoryCompressedBytes: 0,
        diskUsedBytes: 0,
        diskTotalBytes: 1,
        diskAvailableBytes: 1,
        networkUploadBytesPerSec: 0,
        networkDownloadBytesPerSec: 0,
        uptimeSeconds: ProcessInfo.processInfo.systemUptime,
        thermalStateDescription: "正常 (Nominal)",
        topProcesses: []
    )
}

/// CPUまたはメモリ消費上位のプロセス情報
public struct ProcessMetricItem: Identifiable, Sendable, Equatable {
    public let id: Int32 // PID
    public let name: String
    public let cpuPercent: Double
    public let memoryMB: Double

    public init(id: Int32, name: String, cpuPercent: Double, memoryMB: Double) {
        self.id = id
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryMB = memoryMB
    }
}

// MARK: - Junk Cleaner Models

/// ジャンクファイルのカテゴリ分類
public enum JunkCategory: String, CaseIterable, Identifiable, Sendable {
    case userCaches = "ユーザーアプリキャッシュ"
    case userLogs = "システム＆アプリログ"
    case xcodeJunk = "Xcode 開発キャッシュ (DerivedData等)"
    case packageManagerCache = "パッケージマネージャ (npm / Homebrew / pip)"
    case crashReports = "クラッシュレポート＆診断データ"
    case trashCan = "ゴミ箱内の未消去データ"
    case downloadsOld = "ダウンロードフォルダの一時インストーラ (.dmg/.pkg)"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .userCaches: return "archivebox.fill"
        case .userLogs: return "doc.text.magnifyingglass"
        case .xcodeJunk: return "hammer.fill"
        case .packageManagerCache: return "shippingbox.fill"
        case .crashReports: return "exclamationmark.triangle.fill"
        case .trashCan: return "trash.fill"
        case .downloadsOld: return "arrow.down.doc.fill"
        }
    }

    public var safetyNote: String {
        switch self {
        case .userCaches: return "次回アプリ起動時に必要なものだけ再生成されます（安全）"
        case .userLogs: return "過去の動作ログ・診断テキストを削除します（安全）"
        case .xcodeJunk: return "ビルド中間生成物を削除します。次回ビルド時に再生成されます"
        case .packageManagerCache: return "ダウンロード済みパッケージのアーカイブキャッシュを削除します"
        case .crashReports: return "過去のアプリクラッシュ履歴ファイルを削除します（安全）"
        case .trashCan: return "現在ゴミ箱に入っているファイルを完全に空にします"
        case .downloadsOld: return "ダウンロード済みのディスクイメージ(.dmg)やインストーラ(.pkg)"
        }
    }
}

/// スキャンで検出された個別ジャンク項目
public struct JunkItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let category: JunkCategory
    public let name: String
    public let url: URL
    public let sizeBytes: UInt64
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        category: JunkCategory,
        name: String,
        url: URL,
        sizeBytes: UInt64,
        isSelected: Bool = true
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.url = url
        self.sizeBytes = sizeBytes
        self.isSelected = isSelected
    }
}

// MARK: - Large & Old Files Models

/// 大容量ファイルのサイズしきい値フィルタ
public enum FileSizeFilter: String, CaseIterable, Identifiable, Sendable {
    case over20MB = "20 MB 以上"
    case over50MB = "50 MB 以上"
    case over100MB = "100 MB 以上"
    case over500MB = "500 MB 以上"
    case over1GB = "1 GB 以上"

    public var id: String { rawValue }

    public var minBytes: UInt64 {
        switch self {
        case .over20MB: return 20 * 1024 * 1024
        case .over50MB: return 50 * 1024 * 1024
        case .over100MB: return 100 * 1024 * 1024
        case .over500MB: return 500 * 1024 * 1024
        case .over1GB: return 1024 * 1024 * 1024
        }
    }
}

/// 最終更新からの経過期間フィルタ
public enum FileAgeFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "すべての期間"
    case over30Days = "30日以上前"
    case over90Days = "3ヶ月以上前"
    case over180Days = "半年以上前"
    case over365Days = "1年以上前"

    public var id: String { rawValue }

    public var minAgeDays: Int {
        switch self {
        case .all: return 0
        case .over30Days: return 30
        case .over90Days: return 90
        case .over180Days: return 180
        case .over365Days: return 365
        }
    }
}

/// 大容量・古いファイル項目
public struct LargeFileItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let url: URL
    public let sizeBytes: UInt64
    public let modifiedDate: Date
    public let fileTypeCategory: String
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        sizeBytes: UInt64,
        modifiedDate: Date,
        fileTypeCategory: String,
        isSelected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.sizeBytes = sizeBytes
        self.modifiedDate = modifiedDate
        self.fileTypeCategory = fileTypeCategory
        self.isSelected = isSelected
    }
}

// MARK: - App Uninstaller Models

/// アプリに関連する残骸（Leftover）ファイル種別
public enum AppLeftoverKind: String, Sendable {
    case appSupport = "Application Support"
    case caches = "Caches"
    case preferences = "Preferences (.plist)"
    case containers = "Sandbox Container"
    case savedState = "Saved Application State"
    case logs = "Logs"
}

/// アプリの関連ファイル1件
public struct AppLeftoverItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let kind: AppLeftoverKind
    public let url: URL
    public let sizeBytes: UInt64

    public init(id: UUID = UUID(), kind: AppLeftoverKind, url: URL, sizeBytes: UInt64) {
        self.id = id
        self.kind = kind
        self.url = url
        self.sizeBytes = sizeBytes
    }
}

/// インストール済みアプリケーションと関連ファイルのまとめ
public struct InstalledAppItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let bundleIdentifier: String
    public let version: String
    public let bundleURL: URL
    public let appSizeBytes: UInt64
    public let lastUsedDate: Date?
    public let leftovers: [AppLeftoverItem]

    public var leftoversSizeBytes: UInt64 {
        leftovers.reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalSizeBytes: UInt64 {
        appSizeBytes + leftoversSizeBytes
    }

    public init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String,
        version: String,
        bundleURL: URL,
        appSizeBytes: UInt64,
        lastUsedDate: Date?,
        leftovers: [AppLeftoverItem]
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.bundleURL = bundleURL
        self.appSizeBytes = appSizeBytes
        self.lastUsedDate = lastUsedDate
        self.leftovers = leftovers
    }
}

// MARK: - Maintenance Task Models

/// メンテナンススクリプトの定義
public struct MaintenanceTaskItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let detailedDescription: String
    public let iconName: String
    public let requiresAdmin: Bool
    public let commandDescription: String
    public var isSelected: Bool
    public var lastRunDate: Date?
    public var lastResultMessage: String?
    public var lastRunSucceeded: Bool?

    public init(
        id: String,
        title: String,
        subtitle: String,
        detailedDescription: String,
        iconName: String,
        requiresAdmin: Bool,
        commandDescription: String,
        isSelected: Bool = true,
        lastRunDate: Date? = nil,
        lastResultMessage: String? = nil,
        lastRunSucceeded: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detailedDescription = detailedDescription
        self.iconName = iconName
        self.requiresAdmin = requiresAdmin
        self.commandDescription = commandDescription
        self.isSelected = isSelected
        self.lastRunDate = lastRunDate
        self.lastResultMessage = lastResultMessage
        self.lastRunSucceeded = lastRunSucceeded
    }
}

// MARK: - Formatting Utilities

/// バイト数や時間を見やすい日本語フォーマットに変換するユーティリティ
public enum ByteFormatter {
    public static func string(from bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(clamping: bytes))
    }

    public static func speedString(bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 {
            return String(format: "%.0f B/s", max(0, bytesPerSec))
        } else if bytesPerSec < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSec / 1024.0)
        } else {
            return String(format: "%.2f MB/s", bytesPerSec / (1024.0 * 1024.0))
        }
    }

    public static func uptimeString(seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 {
            return "\(days)日 \(hours)時間 \(minutes)分"
        } else if hours > 0 {
            return "\(hours)時間 \(minutes)分"
        } else {
            return "\(minutes)分"
        }
    }
}

// MARK: - Duplicate Finder Models

/// 重複ファイルの個別エントリ
public struct DuplicateFileEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let modifiedDate: Date
    public var isSelected: Bool

    public init(id: UUID = UUID(), url: URL, modifiedDate: Date, isSelected: Bool) {
        self.id = id
        self.url = url
        self.modifiedDate = modifiedDate
        self.isSelected = isSelected
    }
}

/// 同一ハッシュ・同一サイズを持つ重複ファイルグループ
public struct DuplicateFileGroup: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let hashSignature: String
    public let fileNameSample: String
    public let eachFileSizeBytes: UInt64
    public var entries: [DuplicateFileEntry]

    /// グループ内で削除対象として選択されている合計サイズ
    public var reclaimableBytes: UInt64 {
        let selectedCount = UInt64(entries.filter(\.isSelected).count)
        return selectedCount * eachFileSizeBytes
    }

    public init(
        id: UUID = UUID(),
        hashSignature: String,
        fileNameSample: String,
        eachFileSizeBytes: UInt64,
        entries: [DuplicateFileEntry]
    ) {
        self.id = id
        self.hashSignature = hashSignature
        self.fileNameSample = fileNameSample
        self.eachFileSizeBytes = eachFileSizeBytes
        self.entries = entries
    }
}

// MARK: - Startup / LaunchAgents Models

public enum StartupItemScope: String, CaseIterable, Sendable {
    case userAgent = "ユーザー LaunchAgent"
    case globalAgent = "システム共通 LaunchAgent"
    case globalDaemon = "システム LaunchDaemon"
}

public struct StartupLaunchItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let label: String
    public let programPath: String
    public let plistURL: URL
    public let scope: StartupItemScope
    public let runAtLoad: Bool
    public var isLoadedInLaunchd: Bool
    public var isDisabledFile: Bool

    public init(
        id: UUID = UUID(),
        label: String,
        programPath: String,
        plistURL: URL,
        scope: StartupItemScope,
        runAtLoad: Bool,
        isLoadedInLaunchd: Bool,
        isDisabledFile: Bool
    ) {
        self.id = id
        self.label = label
        self.programPath = programPath
        self.plistURL = plistURL
        self.scope = scope
        self.runAtLoad = runAtLoad
        self.isLoadedInLaunchd = isLoadedInLaunchd
        self.isDisabledFile = isDisabledFile
    }
}

// MARK: - Docker Cleaner Models

public struct DockerResourceSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public let typeName: String
    public let totalCount: String
    public let activeCount: String
    public let sizeText: String
    public let reclaimableText: String

    public init(
        id: String,
        typeName: String,
        totalCount: String,
        activeCount: String,
        sizeText: String,
        reclaimableText: String
    ) {
        self.id = id
        self.typeName = typeName
        self.totalCount = totalCount
        self.activeCount = activeCount
        self.sizeText = sizeText
        self.reclaimableText = reclaimableText
    }
}

public struct DockerStatusSnapshot: Sendable, Equatable {
    public var isDockerInstalled: Bool
    public var isDaemonRunning: Bool
    public var resources: [DockerResourceSummary]
    public var statusMessage: String

    public static let empty = DockerStatusSnapshot(
        isDockerInstalled: false,
        isDaemonRunning: false,
        resources: [],
        statusMessage: "未スキャン"
    )
}

