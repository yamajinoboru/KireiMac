//
// DuplicateFinderView.swift
// MiniPulse
//
// 役割: SHA-256 ハッシュ比較で特定された「重複ファイルグループ」を一覧表示し、オリジナル1件を残して安全にゴミ箱へ移動する画面。
// 存在意義: 同じインストーラや動画、写真の重複コピーによる数GBの無駄をスマート選択で一括解消する。

import SwiftUI

public struct DuplicateFinderView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleHeaderView(
                section: .duplicateFinder,
                trailingContent: AnyView(
                    HStack(spacing: 12) {
                        PastelActionButton(
                            title: "重複ファイルをスキャン",
                            icon: "doc.on.doc.fill",
                            color: AppTheme.pastelLilac,
                            isLoading: appState.isScanningDuplicates
                        ) {
                            Task { await appState.scanDuplicates() }
                        }

                        if appState.totalDuplicatesReclaimableBytes > 0 {
                            PastelActionButton(
                                title: "選択コピーをゴミ箱へ (\(ByteFormatter.string(from: appState.totalDuplicatesReclaimableBytes)))",
                                icon: "trash.fill",
                                color: AppTheme.pastelRose
                            ) {
                                Task { await appState.trashSelectedDuplicates() }
                            }
                        }
                    }
                )
            )

            if let msg = appState.lastDuplicateMessage {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.pastelLilac)
                    Text(msg)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .glassCard(cornerRadius: 14, padding: 12, tint: AppTheme.pastelLilac)
            }

            if appState.isScanningDuplicates {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text("サイズ照合 → 先頭4KBハッシュ → SHA-256 完全照合で重複を高速検査中...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else if appState.duplicateGroups.isEmpty {
                emptyStateView
            } else {
                HStack {
                    Label(
                        "スマート選択済み: 各グループで最も古いオリジナル1件を保護し、重複コピーのみにチェックを入れています",
                        systemImage: "Wand.and.stars"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Text("全 \(appState.duplicateGroups.count) グループ")
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 4)

                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(appState.duplicateGroups) { group in
                            duplicateGroupCard(group)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(26)
        .onAppear {
            if appState.duplicateGroups.isEmpty && !appState.isScanningDuplicates {
                Task { await appState.scanDuplicates() }
            }
        }
    }

    private func duplicateGroupCard(_ group: DuplicateFileGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundStyle(AppTheme.pastelLilac)
                Text(group.fileNameSample)
                    .font(.headline)
                Text("SHA-256: \(group.hashSignature)...")
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("1件あたり \(ByteFormatter.string(from: group.eachFileSizeBytes)) × \(group.entries.count) 個")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.5)

            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 12) {
                    Button {
                        appState.toggleDuplicateEntry(groupId: group.id, entryId: entry.id)
                    } label: {
                        Image(systemName: entry.isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(entry.isSelected ? AppTheme.pastelLilac : .secondary)
                    }
                    .buttonStyle(.plain)

                    if index == 0 && !entry.isSelected {
                        Text("オリジナル保持")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppTheme.pastelMint.opacity(0.25)))
                    } else if entry.isSelected {
                        Text("削除対象")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppTheme.pastelRose.opacity(0.25)))
                    }

                    Text(entry.url.path)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Text(entry.modifiedDate, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button {
                        appState.revealInFinder(entry.url)
                    } label: {
                        Image(systemName: "folder")
                            .font(.caption)
                            .padding(6)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
        .glassCard(cornerRadius: 16, padding: 14, tint: AppTheme.pastelLilac)
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.pastelLilac)
            Text("1 MB 以上の重複ファイルは見つかりませんでした")
                .font(.title3.weight(.bold))
            Text("Downloads, Desktop, Documents, Pictures, Movies 内に無駄な重複コピーはありません。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
