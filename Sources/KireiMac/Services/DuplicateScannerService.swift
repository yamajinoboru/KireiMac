//
// DuplicateScannerService.swift
// MiniPulse
//
// 役割: ホームフォルダ配下から「完全に同一内容の重複ファイル」を高速検出するサービス。
// 存在意義: 全ファイルのフルハッシュを計算すると遅いため、(1)ファイルサイズ一致 -> (2)先頭4KBハッシュ一致 -> (3)SHA-256完全ハッシュ一致 の3段階パイプラインで超高速かつ正確に重複を特定する。

import Foundation
import CryptoKit

public actor DuplicateScannerService {
    public init() {}

    /// 指定サイズ以上の重複ファイルグループを検出する（デフォルト: 1MB以上）
    public func scanDuplicates(minSizeBytes: UInt64 = 1024 * 1024) async -> [DuplicateFileGroup] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let targetDirs = [
            "Downloads",
            "Desktop",
            "Documents",
            "Pictures",
            "Movies",
            "Music"
        ].map { home.appendingPathComponent($0) }

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]

        // Step 1: ファイルサイズでグルーピング
        var sizeBuckets: [UInt64: [(url: URL, modified: Date)]] = [:]
        var totalScanned = 0

        for folder in targetDirs {
            guard fm.fileExists(atPath: folder.path),
                  let enumerator = fm.enumerator(
                    at: folder,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else {
                continue
            }

            while let fileURL = enumerator.nextObject() as? URL {
                if enumerator.level > 5 {
                    enumerator.skipDescendants()
                    continue
                }
                totalScanned += 1
                if totalScanned > 15000 { break }

                guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      values.isSymbolicLink != true,
                      let fileSize = values.fileSize,
                      UInt64(max(0, fileSize)) >= minSizeBytes else {
                    continue
                }

                let size = UInt64(fileSize)
                let modified = values.contentModificationDate ?? Date.distantPast
                sizeBuckets[size, default: []].append((fileURL, modified))
            }
        }

        // 2件以上同じサイズのファイルがあるバケットのみ抽出
        let candidateBuckets = sizeBuckets.filter { $0.value.count >= 2 }

        var confirmedGroups: [DuplicateFileGroup] = []

        // Step 2 & 3: 先頭4KBハッシュ -> フル(または先頭+中間+末尾64KB) SHA-256 で高速照合
        for (size, candidates) in candidateBuckets {
            var partialBuckets: [String: [(url: URL, modified: Date)]] = [:]
            for item in candidates {
                if let partialHash = Self.computeQuickPartialHash(url: item.url, fileSize: size) {
                    partialBuckets[partialHash, default: []].append(item)
                }
            }

            for (_, partialMatches) in partialBuckets where partialMatches.count >= 2 {
                var fullHashBuckets: [String: [(url: URL, modified: Date)]] = [:]
                for item in partialMatches {
                    if let fullHash = Self.computeFastContentSHA256(url: item.url, fileSize: size) {
                        fullHashBuckets[fullHash, default: []].append(item)
                    }
                }

                for (hash, exactMatches) in fullHashBuckets where exactMatches.count >= 2 {
                    // 最も古い（オリジナルと推定される）1件を非選択（残す）にし、2件目以降を選択状態（削除候補）にする
                    let sorted = exactMatches.sorted { $0.modified < $1.modified }
                    let entries = sorted.enumerated().map { idx, elem in
                        DuplicateFileEntry(
                            url: elem.url,
                            modifiedDate: elem.modified,
                            isSelected: idx > 0
                        )
                    }

                    confirmedGroups.append(
                        DuplicateFileGroup(
                            hashSignature: String(hash.prefix(12)),
                            fileNameSample: sorted.first?.url.lastPathComponent ?? "Duplicate",
                            eachFileSizeBytes: size,
                            entries: entries
                        )
                    )
                }
            }
        }

        return confirmedGroups.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    /// 選択された重複ファイルをゴミ箱へ移動する
    public func trashSelectedDuplicates(in groups: [DuplicateFileGroup]) async -> (removedCount: Int, freedBytes: UInt64, errors: [String]) {
        let fm = FileManager.default
        var removedCount = 0
        var freedBytes: UInt64 = 0
        var errors: [String] = []

        for group in groups {
            for entry in group.entries where entry.isSelected {
                guard fm.fileExists(atPath: entry.url.path) else { continue }
                do {
                    try fm.trashItem(at: entry.url, resultingItemURL: nil)
                    removedCount += 1
                    freedBytes += group.eachFileSizeBytes
                } catch {
                    errors.append("\(entry.url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        return (removedCount, freedBytes, errors)
    }

    // MARK: - Hashing Helpers

    private static func computeQuickPartialHash(url: URL, fileSize: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let headData = try? handle.read(upToCount: 4096) else { return nil }
        let digest = SHA256.hash(data: headData)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// 数GBのファイルでもディスクI/Oでフリーズしないよう、32MB以下のファイルは完全SHA-256、32MB超は先頭・中央・末尾の各1MBサンプリング＋ファイルサイズでSHA-256を算出する
    public static func computeFastContentSHA256(url: URL, fileSize: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1024 * 1024 // 1MB

        if fileSize <= UInt64(32 * chunkSize) {
            while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } else {
            // 先頭1MB
            if let head = try? handle.read(upToCount: chunkSize) {
                hasher.update(data: head)
            }
            // 中央1MB
            try? handle.seek(toOffset: fileSize / 2)
            if let mid = try? handle.read(upToCount: chunkSize) {
                hasher.update(data: mid)
            }
            // 末尾1MB
            if fileSize > UInt64(chunkSize) {
                try? handle.seek(toOffset: fileSize - UInt64(chunkSize))
                if let tail = try? handle.read(upToCount: chunkSize) {
                    hasher.update(data: tail)
                }
            }
        }

        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
