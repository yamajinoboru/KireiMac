//
// StartupManagerView.swift
// MiniPulse
//
// 役割: LaunchAgents / LaunchDaemons を一覧表示し、稼働状態の確認・有効化/無効化・ゴミ箱移動を行う画面。
// 存在意義: Mac mini の起動時や裏で常駐してメモリ・CPUを消費する不要なバックグラウンドプロセスを整理する。

import SwiftUI

public struct StartupManagerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedScopeFilter: StartupItemScope? = nil

    public init() {}

    private var displayedItems: [StartupLaunchItem] {
        if let scope = selectedScopeFilter {
            return appState.startupItems.filter { $0.scope == scope }
        }
        return appState.startupItems
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleHeaderView(
                section: .startupManager,
                trailingContent: AnyView(
                    PastelActionButton(
                        title: "常駐エージェントを再スキャン",
                        icon: "arrow.clockwise",
                        color: AppTheme.pastelTeal,
                        isLoading: appState.isScanningStartup
                    ) {
                        Task { await appState.scanStartupItems() }
                    }
                )
            )

            if let msg = appState.lastStartupMessage {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(AppTheme.pastelTeal)
                    Text(msg)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .glassCard(cornerRadius: 14, padding: 12, tint: AppTheme.pastelTeal)
            }

            // スコープフィルターピル
            HStack(spacing: 10) {
                scopeFilterButton(title: "すべて (\(appState.startupItems.count))", scope: nil)
                ForEach(StartupItemScope.allCases, id: \.rawValue) { scope in
                    let count = appState.startupItems.filter { $0.scope == scope }.count
                    scopeFilterButton(title: "\(scope.rawValue) (\(count))", scope: scope)
                }
                Spacer()
            }

            if appState.isScanningStartup {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView("LaunchAgents / Daemons を検査中...")
                    Spacer()
                }
                Spacer()
            } else if displayedItems.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("該当する常駐エージェントはありません。")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(displayedItems) { item in
                            startupRow(item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(26)
        .onAppear {
            if appState.startupItems.isEmpty && !appState.isScanningStartup {
                Task { await appState.scanStartupItems() }
            }
        }
    }

    private func scopeFilterButton(title: String, scope: StartupItemScope?) -> some View {
        let isSelected = selectedScopeFilter == scope
        return Button {
            withAnimation(AppTheme.smoothSpring) {
                selectedScopeFilter = scope
            }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? AppTheme.pastelTeal.opacity(0.32) : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }

    private func startupRow(_ item: StartupLaunchItem) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(item.isDisabledFile ? Color.secondary.opacity(0.4) : (item.isLoadedInLaunchd ? AppTheme.pastelMint : AppTheme.pastelAmber))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(.subheadline.weight(.semibold))
                    Text(item.scope.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .foregroundStyle(.secondary)

                    if item.isDisabledFile {
                        Text("無効化済み")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    } else if item.isLoadedInLaunchd {
                        Text("稼働中 (Loaded)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.pastelMint)
                    }
                }
                Text("実行プログラム: \(item.programPath)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if item.scope == .userAgent {
                Button {
                    Task { await appState.toggleStartupItem(item) }
                } label: {
                    Text(item.isDisabledFile ? "有効化" : "停止・無効化")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(item.isDisabledFile ? AppTheme.pastelMint.opacity(0.25) : AppTheme.pastelAmber.opacity(0.25))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    Task { await appState.trashStartupItem(item) }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .padding(7)
                        .background(Circle().fill(AppTheme.pastelRose.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .help("設定 plist をゴミ箱へ移動")
            }

            Button {
                appState.revealInFinder(item.plistURL)
            } label: {
                Image(systemName: "folder")
                    .font(.caption)
                    .padding(7)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Finder で plist を表示")
        }
        .glassCard(cornerRadius: 14, padding: 12)
    }
}
