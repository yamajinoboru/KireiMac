//
// DockerCleanerService.swift
// MiniPulse
//
// 役割: Docker / OrbStack / Colima 環境のディスク占有状況 (`docker system df`) を取得し、停止コンテナ・未使用イメージ・BuildKitキャッシュを安全に整理する。
// 存在意義: Mac mini で開発していると数十GBに肥大化しがちな Docker 領域をワンクリックで可視化・クリーンアップする。

import Foundation

public actor DockerCleanerService {
    private let candidateBinaryPaths = [
        "/opt/homebrew/bin/docker",
        "/usr/local/bin/docker",
        "/usr/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
        "/Applications/OrbStack.app/Contents/MacOS/xbin/docker"
    ]

    public init() {}

    private func resolveDockerExecutable() -> String? {
        let fm = FileManager.default
        for path in candidateBinaryPaths {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Docker の稼働状態と `docker system df` の結果をスキャンする
    public func inspectDockerStatus() async -> DockerStatusSnapshot {
        guard let dockerBin = resolveDockerExecutable() else {
            return DockerStatusSnapshot(
                isDockerInstalled: false,
                isDaemonRunning: false,
                resources: [],
                statusMessage: "Docker CLI が見つかりません（Docker Desktop / OrbStack 未導入）"
            )
        }

        let formatArg = "{{.Type}}\t{{.TotalCount}}\t{{.Active}}\t{{.Size}}\t{{.Reclaimable}}"
        let result = runCommand(dockerBin, arguments: ["system", "df", "--format", formatArg])

        guard result.exitCode == 0 else {
            return DockerStatusSnapshot(
                isDockerInstalled: true,
                isDaemonRunning: false,
                resources: [],
                statusMessage: "Docker デーモンが停止中です。Docker Desktop または OrbStack を起動するとスキャンできます。"
            )
        }

        var resources: [DockerResourceSummary] = []
        let lines = result.stdout.split(separator: "\n")
        for line in lines {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if cols.count >= 5 {
                let localizedType: String
                switch cols[0] {
                case "Images": localizedType = "Docker イメージ (Images)"
                case "Containers": localizedType = "コンテナ (Containers)"
                case "Local Volumes": localizedType = "ローカルボリューム (Volumes)"
                case "Build Cache": localizedType = "ビルドキャッシュ (BuildKit)"
                default: localizedType = cols[0]
                }
                resources.append(
                    DockerResourceSummary(
                        id: cols[0],
                        typeName: localizedType,
                        totalCount: cols[1],
                        activeCount: cols[2],
                        sizeText: cols[3],
                        reclaimableText: cols[4]
                    )
                )
            }
        }

        return DockerStatusSnapshot(
            isDockerInstalled: true,
            isDaemonRunning: true,
            resources: resources,
            statusMessage: "Docker エンジン稼働中"
        )
    }

    /// 未使用のコンテナ・ネットワーク・Danglingイメージ・ビルドキャッシュを安全に prune する（ボリュームは保護またはオプション指定）
    public func pruneDocker(includeVolumes: Bool = false) async -> (succeeded: Bool, outputMessage: String) {
        guard let dockerBin = resolveDockerExecutable() else {
            return (false, "Docker CLI が見つかりません。")
        }

        var args = ["system", "prune", "-f"]
        if includeVolumes {
            args.append("--volumes")
        }

        let res = runCommand(dockerBin, arguments: args)
        if res.exitCode == 0 {
            let summaryLine = res.stdout
                .split(separator: "\n")
                .last(where: { $0.contains("Total reclaimed space") })
                .map(String.init) ?? "不要な Docker リソースをクリーンアップしました。"
            return (true, summaryLine)
        } else {
            return (false, res.stderr.isEmpty ? "Docker prune に失敗しました" : res.stderr)
        }
    }

    /// BuildKit キャッシュのみをクリーンアップする (`docker builder prune -f`)
    public func pruneBuildCacheOnly() async -> (succeeded: Bool, outputMessage: String) {
        guard let dockerBin = resolveDockerExecutable() else {
            return (false, "Docker CLI が見つかりません。")
        }
        let res = runCommand(dockerBin, arguments: ["builder", "prune", "-f"])
        if res.exitCode == 0 {
            let summaryLine = res.stdout
                .split(separator: "\n")
                .last(where: { $0.contains("Total") })
                .map(String.init) ?? "BuildKit キャッシュを解放しました。"
            return (true, summaryLine)
        } else {
            return (false, res.stderr)
        }
    }

    private func runCommand(_ path: String, arguments: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (
                process.terminationStatus,
                String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        } catch {
            return (-1, "", error.localizedDescription)
        }
    }
}
