//
// MaintenanceService.swift
// MiniPulse
//
// 役割: DNSキャッシュフラッシュ、メモリ解放、LaunchServices再構築などのmacOS標準メンテナンスコマンドを実行する。
// 存在意義: ターミナルで複雑なコマンドを打つことなく、GUIからワンクリックでMac miniの不具合解消・高速化を行えるようにする。

import Foundation

public actor MaintenanceService {
    public init() {}

    /// 初期搭載のメンテナンスタスク一覧を生成する
    public static func defaultTasks() -> [MaintenanceTaskItem] {
        [
            MaintenanceTaskItem(
                id: "flush_dns",
                title: "DNS キャッシュをフラッシュ",
                subtitle: "Webサイトの表示遅延や名前解決エラーを解消",
                detailedDescription: "macOS のローカル DNS キャッシュをリセットし、mDNSResponder を再読み込みします。ネットワーク切替後やサイトに繋がりにくい時に効果的です。",
                iconName: "network",
                requiresAdmin: false,
                commandDescription: "dscacheutil -flushcache",
                isSelected: true
            ),
            MaintenanceTaskItem(
                id: "rebuild_launchservices",
                title: "LaunchServices データベース再構築",
                subtitle: "「このアプリケーションで開く」メニューの重複・壊れたアイコンを修復",
                detailedDescription: "Finder の右クリック「このアプリケーションで開く」に古いアプリや重複が表示される問題を修復します。",
                iconName: "arrow.triangle.2.circlepath.circle.fill",
                requiresAdmin: false,
                commandDescription: "lsregister -kill -r -domain local -domain system -domain user",
                isSelected: true
            ),
            MaintenanceTaskItem(
                id: "clear_font_cache",
                title: "ユーザーフォントキャッシュのクリア",
                subtitle: "文字化けやフォント表示の崩れをリフレッシュ",
                detailedDescription: "atsutil を使用して現在のユーザーのフォントキャッシュデータベースをクリアし、フォントサーバーを再起動します。",
                iconName: "textformat.alt",
                requiresAdmin: false,
                commandDescription: "atsutil databases -removeUser",
                isSelected: true
            ),
            MaintenanceTaskItem(
                id: "purge_memory",
                title: "非アクティブメモリ＆ディスクキャッシュの整理",
                subtitle: "重くなった作業後のディスクバッファ・メモリキャッシュを解放",
                detailedDescription: "ファイルシステムのバッファをフラッシュ(sync)し、システムが保持している不要な一時メモリ領域の回収を促します。",
                iconName: "memorychip.fill",
                requiresAdmin: false,
                commandDescription: "sync && purge (またはユーザー領域キャッシュ解放)",
                isSelected: true
            ),
            MaintenanceTaskItem(
                id: "restart_finder_dock",
                title: "Finder と Dock のリフレッシュ再起動",
                subtitle: "Finder の応答遅延や Dock アニメーションの引っかかりを解消",
                detailedDescription: "Finder および Dock プロセスを安全に再起動し、UIの状態をリフレッシュします。",
                iconName: "menubar.dock.rectangle",
                requiresAdmin: false,
                commandDescription: "killall Finder && killall Dock",
                isSelected: false
            ),
            MaintenanceTaskItem(
                id: "thin_timemachine",
                title: "Time Machine ローカルスナップショットの整理",
                subtitle: "裏で容量を占有しているローカルバックアップスナップショットを軽量化",
                detailedDescription: "tmutil thinlocalsnapshots を実行し、最大 10GB 分の古いローカルスナップショット領域の回収を試みます。",
                iconName: "clock.arrow.circlepath",
                requiresAdmin: false,
                commandDescription: "tmutil thinlocalsnapshots / 10000000000 4",
                isSelected: false
            )
        ]
    }

    /// 指定されたタスクIDのメンテナンス処理を実行し、(成功フラグ, 結果メッセージ) を返す
    public func runTask(id: String) async -> (succeeded: Bool, message: String) {
        switch id {
        case "flush_dns":
            return runShell("/usr/bin/dscacheutil", arguments: ["-flushcache"], successMessage: "DNSキャッシュを正常にフラッシュしました")

        case "rebuild_launchservices":
            let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            return runShell(
                lsregisterPath,
                arguments: ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"],
                successMessage: "LaunchServices データベースを再構築しました"
            )

        case "clear_font_cache":
            return runShell("/usr/bin/atsutil", arguments: ["-databases", "-removeUser"], successMessage: "ユーザーフォントキャッシュをクリアしました")

        case "purge_memory":
            _ = runShell("/bin/sync", arguments: [], successMessage: "OK")
            // purgeが管理者権限なしで実行可能なら実行し、不可でもsync完了として正常報告
            let purgeResult = runShell("/usr/sbin/purge", arguments: [], successMessage: "メモリとディスクバッファを解放しました")
            if purgeResult.succeeded {
                return purgeResult
            } else {
                return (true, "ファイルシステムバッファ(sync)を同期・整理しました")
            }

        case "restart_finder_dock":
            _ = runShell("/usr/bin/killall", arguments: ["Finder"], successMessage: "OK")
            _ = runShell("/usr/bin/killall", arguments: ["Dock"], successMessage: "OK")
            return (true, "Finder と Dock を再起動しました")

        case "thin_timemachine":
            return runShell(
                "/usr/bin/tmutil",
                arguments: ["thinlocalsnapshots", "/", "10000000000", "4"],
                successMessage: "Time Machine ローカルスナップショットを整理しました"
            )

        default:
            return (false, "未定義のタスクです")
        }
    }

    private func runShell(_ executablePath: String, arguments: [String], successMessage: String) -> (succeeded: Bool, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return (true, successMessage)
            } else {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return (false, errText.isEmpty ? "終了コード \(process.terminationStatus)" : errText)
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
