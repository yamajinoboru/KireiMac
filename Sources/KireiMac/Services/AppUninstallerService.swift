//
// AppUninstallerService.swift
// MiniPulse
//
// 役割: /Applications および ~/Applications のアプリを走査し、~/Library 内の関連残骸ファイルを特定・一括アンインストールする。
// 存在意義: アプリ本体をゴミ箱に入れるだけでは残ってしまう数GBのキャッシュや設定ファイルを綺麗に一掃する。

import Foundation

public actor AppUninstallerService {
    public init() {}

    /// インストールされているアプリケーションと、その関連ファイルをスキャンする
    public func scanInstalledApps() async -> [InstalledAppItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications")
        ]

        var apps: [InstalledAppItem] = []

        for dir in appDirs {
            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isPackageKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for bundleURL in contents where bundleURL.pathExtension.lowercased() == "app" {
                // Apple純正のシステム必須アプリ（/System/Applications等へのシンボリックリンクやcom.apple.*）は誤削除防止のためスキップ可能にする
                guard let bundle = Bundle(url: bundleURL) else { continue }
                let bundleId = bundle.bundleIdentifier ?? bundleURL.deletingPathExtension().lastPathComponent
                if bundleId.hasPrefix("com.apple.Safari") { continue }

                let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? bundleURL.deletingPathExtension().lastPathComponent

                let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
                let values = try? bundleURL.resourceValues(forKeys: [.contentModificationDateKey])
                let modifiedDate = values?.contentModificationDate

                let appSize = JunkScannerService.directorySize(at: bundleURL, maxDepth: 4)
                let leftovers = findLeftovers(forAppName: displayName, bundleId: bundleId, home: home)

                apps.append(
                    InstalledAppItem(
                        name: displayName,
                        bundleIdentifier: bundleId,
                        version: version,
                        bundleURL: bundleURL,
                        appSizeBytes: appSize,
                        lastUsedDate: modifiedDate,
                        leftovers: leftovers
                    )
                )
            }
        }

        return apps.sorted { $0.totalSizeBytes > $1.totalSizeBytes }
    }

    /// 指定されたアプリ本体＋すべての関連ファイル（または関連残骸のみ）をゴミ箱へ移動する
    public func uninstallApp(_ app: InstalledAppItem, leftoversOnly: Bool = false) async -> (freedBytes: UInt64, errors: [String]) {
        let fm = FileManager.default
        var freed: UInt64 = 0
        var errors: [String] = []

        // 1. 関連残骸ファイルをゴミ箱へ移動
        for item in app.leftovers {
            guard fm.fileExists(atPath: item.url.path) else { continue }
            do {
                try fm.trashItem(at: item.url, resultingItemURL: nil)
                freed += item.sizeBytes
            } catch {
                errors.append("\(item.url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // 2. アプリ本体も削除する場合
        if !leftoversOnly, fm.fileExists(atPath: app.bundleURL.path) {
            do {
                try fm.trashItem(at: app.bundleURL, resultingItemURL: nil)
                freed += app.appSizeBytes
            } catch {
                errors.append("\(app.name).app: \(error.localizedDescription)")
            }
        }

        return (freed, errors)
    }

    // MARK: - Leftover Detection

    private func findLeftovers(forAppName appName: String, bundleId: String, home: URL) -> [AppLeftoverItem] {
        let fm = FileManager.default
        let library = home.appendingPathComponent("Library")
        var items: [AppLeftoverItem] = []

        let searchTargets: [(AppLeftoverKind, String, [String])] = [
            (.appSupport, "Application Support", [bundleId, appName]),
            (.caches, "Caches", [bundleId, appName]),
            (.preferences, "Preferences", ["\(bundleId).plist"]),
            (.containers, "Containers", [bundleId]),
            (.savedState, "Saved Application State", ["\(bundleId).savedState"]),
            (.logs, "Logs", [bundleId, appName])
        ]

        for (kind, subFolder, candidates) in searchTargets {
            let baseDir = library.appendingPathComponent(subFolder)
            for candidate in candidates where !candidate.isEmpty {
                let candidateURL = baseDir.appendingPathComponent(candidate)
                if fm.fileExists(atPath: candidateURL.path) {
                    let size = JunkScannerService.directorySize(at: candidateURL, maxDepth: 3)
                    if size > 0 {
                        items.append(AppLeftoverItem(kind: kind, url: candidateURL, sizeBytes: size))
                    }
                }
            }
        }

        return items
    }
}
