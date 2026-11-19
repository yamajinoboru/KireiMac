//
// LargeFileScannerService.swift
// MiniPulse
//
// 役割: ユーザーホーム配下（Downloads, Movies, Desktop, Documents等）から大容量ファイルや長期間放置されたファイルを検出する。
// 存在意義: CleanMyMac の「大容量＆古いファイル」機能と同様に、見落とされがちなギガバイト級の不要ファイルを可視化する。

import Foundation

public actor LargeFileScannerService {
    public init() {}

    /// ユーザーの主要フォルダを走査し、指定バイト数以上のファイルを検出する
    public func scanLargeFiles(minSizeBytes: UInt64 = 20 * 1024 * 1024) async -> [LargeFileItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let targetFolders = [
            "Downloads",
            "Desktop",
            "Documents",
            "Movies",
            "Music",
            "Pictures",
            "Public"
        ].map { home.appendingPathComponent($0) }

        var results: [LargeFileItem] = []
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .isPackageKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]

        for folderURL in targetFolders {
            guard fm.fileExists(atPath: folderURL.path),
                  let enumerator = fm.enumerator(
                    at: folderURL,
                    includingPropertiesForKeys: resourceKeys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else {
                continue
            }

            var countInFolder = 0
            while let fileURL = enumerator.nextObject() as? URL {
                if enumerator.level > 6 {
                    enumerator.skipDescendants()
                    continue
                }
                countInFolder += 1
                if countInFolder > 12000 {
                    break
                }

                guard let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                      values.isRegularFile == true else {
                    continue
                }

                let size = UInt64(max(0, values.totalFileAllocatedSize ?? values.fileSize ?? 0))
                guard size >= minSizeBytes else { continue }

                let modified = values.contentModificationDate ?? Date.distantPast
                let category = Self.classifyFileExtension(fileURL.pathExtension)

                results.append(
                    LargeFileItem(
                        name: fileURL.lastPathComponent,
                        url: fileURL,
                        sizeBytes: size,
                        modifiedDate: modified,
                        fileTypeCategory: category,
                        isSelected: false
                    )
                )
            }
        }

        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// 選択されたファイルをゴミ箱へ移動する
    public func moveFilesToTrash(_ items: [LargeFileItem]) async -> (removedCount: Int, freedBytes: UInt64, errors: [String]) {
        let fm = FileManager.default
        var removedCount = 0
        var freedBytes: UInt64 = 0
        var errors: [String] = []

        for item in items where item.isSelected {
            guard fm.fileExists(atPath: item.url.path) else { continue }
            do {
                try fm.trashItem(at: item.url, resultingItemURL: nil)
                removedCount += 1
                freedBytes += item.sizeBytes
            } catch {
                errors.append("\(item.name): \(error.localizedDescription)")
            }
        }

        return (removedCount, freedBytes, errors)
    }

    /// 拡張子から人間にとって分かりやすいファイル種別ラベルを返す
    public static func classifyFileExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mp4", "mov", "mkv", "avi", "webm", "m4v":
            return "動画・ムービー"
        case "dmg", "iso", "pkg", "ipsw":
            return "ディスクイメージ・インストーラ"
        case "zip", "tar", "gz", "7z", "rar", "tgz", "xz":
            return "アーカイブ・圧縮ファイル"
        case "wav", "mp3", "flac", "m4a", "aiff":
            return "オーディオ"
        case "psd", "ai", "fig", "sketch", "blend", "raw", "cr2", "png", "jpg", "heic":
            return "デザイン・画像"
        case "gguf", "safetensors", "bin", "pt", "onnx", "mlx":
            return "AIモデル・重みデータ"
        default:
            return "データ・その他"
        }
    }
}
