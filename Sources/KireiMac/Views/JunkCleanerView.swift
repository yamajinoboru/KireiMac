//
// JunkCleanerView.swift
// MiniPulse
//
// 役割: システムキャッシュ、Xcode/npm/Homebrew 開発キャッシュ、ログ、ゴミ箱などをカテゴリ別にスキャン・選択・削除する画面。
// 存在意義: ユーザーが「何を消すのか」を透明性高く確認でき、Finderで場所を開くことも可能な安心設計のクリーナーUIを提供する。

import SwiftUI

public struct JunkCleanerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedCategoryFilter: JunkCategory? = nil

    public init() {}

    private var displayedItems: [JunkItem] {
        if let filter = selectedCategoryFilter {
            return appState.junkItems.filter { $0.category == filter }
        }
        return appState.junkItems
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleHeaderView(
                section: .junkCleaner,
                trailingContent: AnyView(
                    HStack(spacing: 12) {
                        PastelActionButton(
                            title: "ジャンクをスキャン",
                            icon: "magnifyingglass",
                            color: AppTheme.pastelMint,
                            isLoading: appState.isScanningJunk
                        ) {
                            Task { await appState.scanJunk() }
                        }

                        if !appState.junkItems.isEmpty {
                            PastelActionButton(
                                title: "選択項目をクリーン (\(ByteFormatter.string(from: appState.totalJunkSelectedBytes)))",
                                icon: "sparkles",
                                color: AppTheme.pastelLavender,
                                isLoading: appState.isCleaningJunk,
                                isDisabled: appState.totalJunkSelectedBytes == 0
                            ) {
                                Task { await appState.cleanSelectedJunk() }
                            }
                        }
                    }
                )
            )

            if let message = appState.lastJunkCleanMessage {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.pastelMint)
                    Text(message)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .glassCard(cornerRadius: 14, padding: 12, tint: AppTheme.pastelMint)
            }

            // カテゴリ別サマリーピル
            categoryChipsBar

            // メインリスト
            if appState.isScanningJunk {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("~/Library/Caches, Logs, Xcode, npm/Homebrew 等を解析中...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else if appState.junkItems.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(displayedItems) { item in
                            junkRow(item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(26)
        .onAppear {
            if appState.junkItems.isEmpty && !appState.isScanningJunk {
                Task { await appState.scanJunk() }
            }
        }
    }

    // MARK: - Subviews

    private var categoryChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                categoryFilterButton(title: "すべて (\(ByteFormatter.string(from: appState.totalJunkDetectedBytes)))", category: nil)

                ForEach(JunkCategory.allCases) { category in
                    let catBytes = appState.junkItems
                        .filter { $0.category == category }
                        .reduce(0) { $0 + $1.sizeBytes }
                    if catBytes > 0 {
                        categoryFilterButton(
                            title: "\(category.rawValue) (\(ByteFormatter.string(from: catBytes)))",
                            category: category
                        )
                    }
                }
            }
        }
    }

    private func categoryFilterButton(title: String, category: JunkCategory?) -> some View {
        let isSelected = selectedCategoryFilter == category
        return Button {
            withAnimation(AppTheme.smoothSpring) {
                selectedCategoryFilter = category
            }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? AppTheme.pastelMint.opacity(0.32) : Color.primary.opacity(0.06))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? AppTheme.pastelMint : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func junkRow(_ item: JunkItem) -> some View {
        HStack(spacing: 14) {
            Button {
                appState.toggleJunkSelection(id: item.id)
            } label: {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isSelected ? AppTheme.pastelMint : .secondary)
            }
            .buttonStyle(.plain)

            Image(systemName: item.category.iconName)
                .font(.title3)
                .foregroundStyle(AppTheme.pastelMint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                    Text(item.category.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .foregroundStyle(.secondary)
                }
                Text(item.url.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteFormatter.string(from: item.sizeBytes))
                .font(.system(.subheadline, design: .rounded).weight(.bold))

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
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.pastelMint)
            Text("ジャンクファイルは見つかりませんでした")
                .font(.title3.weight(.bold))
            Text("「ジャンクをスキャン」を押すと、キャッシュや開発用一時ファイルを再検査します。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
