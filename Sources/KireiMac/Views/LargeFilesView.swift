//
// LargeFilesView.swift
// MiniPulse
//
// 役割: ホームフォルダ配下の大容量ファイルおよび長期間更新されていない古いファイルを一覧・フィルタ・ゴミ箱移動する画面。
// 存在意義: 数百MB〜数GBのディスクイメージや動画・アーカイブ等を即座に見つけ出し、安全に整理できるようにする。

import SwiftUI

public struct LargeFilesView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleHeaderView(
                section: .largeFiles,
                trailingContent: AnyView(
                    HStack(spacing: 12) {
                        PastelActionButton(
                            title: "ホームフォルダをスキャン",
                            icon: "doc.viewfinder",
                            color: AppTheme.pastelPeach,
                            isLoading: appState.isScanningLargeFiles
                        ) {
                            Task { await appState.scanLargeFiles() }
                        }

                        if appState.selectedLargeFilesBytes > 0 {
                            PastelActionButton(
                                title: "ゴミ箱へ移動 (\(ByteFormatter.string(from: appState.selectedLargeFilesBytes)))",
                                icon: "trash.fill",
                                color: AppTheme.pastelRose
                            ) {
                                Task { await appState.trashSelectedLargeFiles() }
                            }
                        }
                    }
                )
            )

            if let msg = appState.lastLargeFileMessage {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.pastelPeach)
                    Text(msg)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .glassCard(cornerRadius: 14, padding: 12, tint: AppTheme.pastelPeach)
            }

            // フィルターバー（サイズ＆経過期間）
            filterControlBar

            // コンテンツリスト
            if appState.isScanningLargeFiles {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text("Downloads, Movies, Desktop, Documents 等から大容量ファイルを検索中...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else if appState.filteredLargeFiles.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(appState.filteredLargeFiles) { file in
                            largeFileRow(file)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(26)
        .onAppear {
            if appState.largeFiles.isEmpty && !appState.isScanningLargeFiles {
                Task { await appState.scanLargeFiles() }
            }
        }
    }

    // MARK: - Subviews

    private var filterControlBar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                Text("サイズ:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(FileSizeFilter.allCases) { filter in
                    let isSelected = appState.sizeFilter == filter
                    Button {
                        withAnimation(AppTheme.smoothSpring) {
                            appState.sizeFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(isSelected ? AppTheme.pastelPeach.opacity(0.32) : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().frame(height: 22)

            HStack(spacing: 8) {
                Text("最終更新:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("", selection: $appState.ageFilter) {
                    ForEach(FileAgeFilter.allCases) { age in
                        Text(age.rawValue).tag(age)
                    }
                }
                .labelsHidden()
                .frame(width: 135)
            }

            Spacer()

            Text("該当 \(appState.filteredLargeFiles.count) 件")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .glassCard(cornerRadius: 14, padding: 12)
    }

    private func largeFileRow(_ item: LargeFileItem) -> some View {
        HStack(spacing: 14) {
            Button {
                appState.toggleLargeFileSelection(id: item.id)
            } label: {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isSelected ? AppTheme.pastelPeach : .secondary)
            }
            .buttonStyle(.plain)

            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(item.fileTypeCategory)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppTheme.pastelPeach.opacity(0.18)))
                }
                Text(item.url.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormatter.string(from: item.sizeBytes))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                Text(item.modifiedDate, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                appState.revealInFinder(item.url)
            } label: {
                Image(systemName: "folder")
                    .font(.caption)
                    .padding(7)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Finder で表示")
        }
        .glassCard(cornerRadius: 14, padding: 12)
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.pastelPeach)
            Text("現在のフィルタ条件に一致する大容量ファイルはありません")
                .font(.title3.weight(.bold))
            Text("サイズしきい値（20 MB 以上など）を変更するか、再スキャンをお試しください。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
