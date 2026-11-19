//
// StartupManagerService.swift
// MiniPulse
//
// 役割: ~/Library/LaunchAgents や /Library/LaunchAgents に登録された常駐エージェント(.plist)を検出し、稼働状態の確認・有効/無効の切り替えを行う。
// 存在意義: CleanMyMac の「最適化 > 起動エージェント」機能と同様、バックグラウンドで勝手に動いてCPUやメモリを消費する常駐プロセスを可視化・制御する。

import Foundation

public actor StartupManagerService {
    public init() {}

    /// システムおよびユーザーの LaunchAgents / Daemons を一覧取得する
    public func scanStartupItems() async -> [StartupLaunchItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let loadedLabels = fetchCurrentlyLoadedLaunchdLabels()

        let targets: [(StartupItemScope, URL)] = [
            (.userAgent, home.appendingPathComponent("Library/LaunchAgents")),
            (.globalAgent, URL(fileURLWithPath: "/Library/LaunchAgents")),
            (.globalDaemon, URL(fileURLWithPath: "/Library/LaunchDaemons"))
        ]

        var items: [StartupLaunchItem] = []

        for (scope, dirURL) in targets {
            guard let files = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for fileURL in files {
                let name = fileURL.lastPathComponent
                let isDisabled = name.hasSuffix(".plist.disabled")
                guard name.hasSuffix(".plist") || isDisabled else { continue }

                let plistDict = NSDictionary(contentsOf: fileURL) as? [String: Any]
                let label = (plistDict?["Label"] as? String)
                    ?? name.replacingOccurrences(of: ".plist.disabled", with: "")
                           .replacingOccurrences(of: ".plist", with: "")

                let program: String
                if let prog = plistDict?["Program"] as? String {
                    program = prog
                } else if let args = plistDict?["ProgramArguments"] as? [String], let first = args.first {
                    program = first
                } else {
                    program = "指定なし (Bundle サービス)"
                }

                let runAtLoad = (plistDict?["RunAtLoad"] as? Bool) ?? false
                let isLoaded = loadedLabels.contains(label)

                items.append(
                    StartupLaunchItem(
                        label: label,
                        programPath: program,
                        plistURL: fileURL,
                        scope: scope,
                        runAtLoad: runAtLoad,
                        isLoadedInLaunchd: isLoaded,
                        isDisabledFile: isDisabled
                    )
                )
            }
        }

        return items.sorted { lhs, rhs in
            if lhs.scope != rhs.scope {
                return lhs.scope == .userAgent
            }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    /// ユーザーの LaunchAgent を安全に load / unload（および .disabled リネーム）で切り替える
    public func toggleUserLaunchAgent(_ item: StartupLaunchItem) async -> (succeeded: Bool, message: String) {
        let fm = FileManager.default
        let path = item.plistURL.path

        if item.isDisabledFile {
            // 有効化: .plist.disabled -> .plist に戻して launchctl load
            let enabledPath = path.replacingOccurrences(of: ".plist.disabled", with: ".plist")
            let enabledURL = URL(fileURLWithPath: enabledPath)
            do {
                try fm.moveItem(at: item.plistURL, to: enabledURL)
                _ = runLaunchctl(arguments: ["load", "-w", enabledPath])
                return (true, "「\(item.label)」を有効化し、ロードしました。")
            } catch {
                return (false, "有効化に失敗しました: \(error.localizedDescription)")
            }
        } else {
            // 無効化: launchctl unload して、ユーザーエージェントの場合は .disabled を付与または unload 状態にする
            _ = runLaunchctl(arguments: ["unload", "-w", path])
            if item.scope == .userAgent {
                let disabledURL = URL(fileURLWithPath: path + ".disabled")
                try? fm.moveItem(at: item.plistURL, to: disabledURL)
                return (true, "「\(item.label)」を停止し、自動起動を無効化しました。")
            } else {
                return (true, "「\(item.label)」へ unload 要求を送信しました（システム領域のためファイル変更はスキップ）。")
            }
        }
    }

    /// 不要になった LaunchAgent plist をゴミ箱へ移動する
    public func movePlistToTrash(_ item: StartupLaunchItem) async -> (succeeded: Bool, message: String) {
        if !item.isDisabledFile {
            _ = runLaunchctl(arguments: ["unload", "-w", item.plistURL.path])
        }
        do {
            try FileManager.default.trashItem(at: item.plistURL, resultingItemURL: nil)
            return (true, "「\(item.label)」の設定ファイルをゴミ箱へ移動しました。")
        } catch {
            return (false, "削除できませんでした（管理者権限が必要な領域の可能性があります）: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func fetchCurrentlyLoadedLaunchdLabels() -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8) else { return [] }

            var labels: Set<String> = []
            for line in text.split(separator: "\n").dropFirst() {
                let cols = line.split(whereSeparator: { $0.isWhitespace })
                if let last = cols.last {
                    labels.insert(String(last))
                }
            }
            return labels
        } catch {
            return []
        }
    }

    private func runLaunchctl(arguments: [String]) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = arguments
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }
}
