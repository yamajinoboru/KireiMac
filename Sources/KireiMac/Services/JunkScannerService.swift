//
// JunkScannerService.swift
// MiniPulse
//
// 役割: システムキャッシュ、アプリログ、Xcode DerivedData、npm/Homebrew等の開発キャッシュ、ゴミ箱などをスキャン・削除する。
// 存在意義: Mac mini のストレージを圧迫する不要な一時ファイルを安全（原則ゴミ箱移動）かつ高速に整理する。

import Foundation

public actor JunkScannerService {
    public init() {}

    /// 対象カテゴリ群を非同期でスキャンし、検出されたジャンク項目を返す
    public func scanAllJunk() async -> [JunkItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var results: [JunkItem] = []

        // 1. ユーザーアプリキャッシュ (~/Library/Caches 直下のサブフォルダ)
        let cachesURL = home.appendingPathComponent("Library/Caches")
        results.append(contentsOf: scanSubdirectories(in: cachesURL, category: .userCaches, minBytes: 512 * 1024))

        // 2. ユーザーログ (~/Library/Logs 直下)
        let logsURL = home.appendingPathComponent("Library/Logs")
        results.append(contentsOf: scanSubdirectories(in: logsURL, category: .userLogs, minBytes: 128 * 1024))

        // 3. Xcode 開発キャッシュ (DerivedData, Archives, iOS DeviceSupport)
        let xcodeCandidates: [(String, String)] = [
            ("Xcode DerivedData (ビルド中間生成物)", "Library/Developer/Xcode/DerivedData"),
            ("Xcode Archives (過去アーカイブ)", "Library/Developer/Xcode/Archives"),
            ("Xcode CoreSimulator Caches", "Library/Developer/CoreSimulator/Caches"),
            ("Swift Package Manager Cache", "Library/Caches/org.swift.swiftpm")
        ]
        for (label, relPath) in xcodeCandidates {
            let url = home.appendingPathComponent(relPath)
            if fm.fileExists(atPath: url.path) {
                let size = Self.directorySize(at: url, maxDepth: 4)
                if size > 256 * 1024 {
                    results.append(JunkItem(category: .xcodeJunk, name: label, url: url, sizeBytes: size, isSelected: true))
                }
            }
        }

        // 4. パッケージマネージャキャッシュ (npm, pnpm, yarn, Homebrew, pip, CocoaPods)
        let pkgCandidates: [(String, String)] = [
            ("npm キャッシュ (~/.npm/_cacache)", ".npm/_cacache"),
            ("pnpm ストア (~/.local/share/pnpm/store)", ".local/share/pnpm/store"),
            ("Yarn キャッシュ (~/Library/Caches/Yarn)", "Library/Caches/Yarn"),
            ("Homebrew ダウンロードキャッシュ", "Library/Caches/Homebrew"),
            ("pip キャッシュ (~/Library/Caches/pip)", "Library/Caches/pip"),
            ("CocoaPods キャッシュ", "Library/Caches/CocoaPods")
        ]
        for (label, relPath) in pkgCandidates {
            let url = home.appendingPathComponent(relPath)
            if fm.fileExists(atPath: url.path) {
                let size = Self.directorySize(at: url, maxDepth: 4)
                if size > 256 * 1024 {
                    results.append(JunkItem(category: .packageManagerCache, name: label, url: url, sizeBytes: size, isSelected: true))
                }
            }
        }

        // 5. クラッシュレポート (~/Library/Logs/DiagnosticReports)
        let crashURL = home.appendingPathComponent("Library/Logs/DiagnosticReports")
        results.append(contentsOf: scanSubdirectories(in: crashURL, category: .crashReports, minBytes: 4 * 1024))

        // 6. ゴミ箱 (~/.Trash)
        let trashURL = home.appendingPathComponent(".Trash")
        if fm.fileExists(atPath: trashURL.path) {
            let trashItems = scanSubdirectories(in: trashURL, category: .trashCan, minBytes: 1024)
            results.append(contentsOf: trashItems)
        }

        // 7. ダウンロードフォルダの古いディスクイメージ・インストーラ (.dmg, .pkg, .iso)
        let downloadsURL = home.appendingPathComponent("Downloads")
        if let children = try? fm.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for fileURL in children {
                let ext = fileURL.pathExtension.lowercased()
                if ["dmg", "pkg", "iso"].contains(ext) {
                    let size = Self.directorySize(at: fileURL, maxDepth: 1)
                    if size > 0 {
                        results.append(
                            JunkItem(
                                category: .downloadsOld,
                                name: fileURL.lastPathComponent,
                                url: fileURL,
                                sizeBytes: size,
                                // ディスクイメージは念のため初期状態を非選択またはユーザー確認しやすくする
                                isSelected: false
                            )
                        )
                    }
                }
            }
        }

        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// 選択されたジャンク項目を安全にクリーンアップする
    /// ゴミ箱外のファイルは原則ゴミ箱へ移動し、ゴミ箱内のファイルまたはゴミ箱移動不可のキャッシュは直接削除する
    public func cleanItems(_ items: [JunkItem]) async -> (cleanedCount: Int, freedBytes: UInt64, errors: [String]) {
        let fm = FileManager.default
        var cleanedCount = 0
        var freedBytes: UInt64 = 0
        var errors: [String] = []

        for item in items where item.isSelected {
            guard fm.fileExists(atPath: item.url.path) else { continue }
            do {
                if item.category == .trashCan {
                    try fm.removeItem(at: item.url)
                } else {
                    do {
                        try fm.trashItem(at: item.url, resultingItemURL: nil)
                    } catch {
                        // キャッシュディレクトリ等でゴミ箱移動が拒否された場合は直接削除にフォールバック
                        try fm.removeItem(at: item.url)
                    }
                }
                cleanedCount += 1
                freedBytes += item.sizeBytes
            } catch {
                errors.append("\(item.name): \(error.localizedDescription)")
            }
        }

        return (cleanedCount, freedBytes, errors)
    }

    // MARK: - Helpers

    private func scanSubdirectories(in parentURL: URL, category: JunkCategory, minBytes: UInt64) -> [JunkItem] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [JunkItem] = []
        for url in children {
            // Apple純正システム保護対象(CloudKit等)のキャッシュはスキップして安全性を高める
            let lastComponent = url.lastPathComponent
            if lastComponent.hasPrefix("com.apple.bird") || lastComponent.hasPrefix("CloudKit") {
                continue
            }
            let size = Self.directorySize(at: url, maxDepth: 3)
            if size >= minBytes {
                items.append(
                    JunkItem(
                        category: category,
                        name: lastComponent,
                        url: url,
                        sizeBytes: size,
                        isSelected: true
                    )
                )
            }
        }
        return items
    }

    /// 指定されたURL（ファイルまたはディレクトリ）の合計バイト数を高速計算する
    public static func directorySize(at url: URL, maxDepth: Int = 4) -> UInt64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            return UInt64(max(0, values?.totalFileAllocatedSize ?? values?.fileSize ?? 0))
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: UInt64 = 0
        var scannedCount = 0
        for case let fileURL as URL in enumerator {
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            scannedCount += 1
            if scannedCount > 8000 {
                // 極端にファイル数が多いディレクトリでもUIをブロックしないよう上限を設定
                break
            }
            if let values = try? fileURL.resourceValues(forKeys: Set(keys)),
               values.isRegularFile == true {
                total += UInt64(max(0, values.totalFileAllocatedSize ?? values.fileSize ?? 0))
            }
        }
        return total
    }
}
