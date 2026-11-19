//
// DockerCleanerView.swift
// MiniPulse
//
// 役割: Docker / OrbStack のディスク使用状況（Images, Containers, Volumes, Build Cache）を一覧表示し、不要データを一括 prune する画面。
// 存在意義: 開発用 Mac mini で数十GBを占有しがちな Docker の未使用イメージやビルドキャッシュを安全に解放する。

import SwiftUI

public struct DockerCleanerView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModuleHeaderView(
                    section: .dockerCleaner,
                    trailingContent: AnyView(
                        HStack(spacing: 12) {
                            PastelActionButton(
                                title: "Docker 状態を更新",
                                icon: "arrow.clockwise",
                                color: AppTheme.pastelCyan,
                                isLoading: appState.isScanningDocker
                            ) {
                                Task { await appState.scanDocker() }
                            }

                            if appState.dockerStatus.isDaemonRunning {
                                PastelActionButton(
                                    title: "未使用イメージ・キャッシュを一括整理",
                                    icon: "sparkles",
                                    color: AppTheme.pastelMint,
                                    isLoading: appState.isPruningDocker
                                ) {
                                    Task { await appState.pruneDockerResources(includeVolumes: false) }
                                }
                            }
                        }
                    )
                )

                if let msg = appState.lastDockerMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(AppTheme.pastelCyan)
                        Text(msg)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .glassCard(cornerRadius: 14, padding: 12, tint: AppTheme.pastelCyan)
                }

                // ステータスカード
                HStack(spacing: 16) {
                    Circle()
                        .fill(appState.dockerStatus.isDaemonRunning ? AppTheme.pastelMint : AppTheme.pastelAmber)
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.dockerStatus.statusMessage)
                            .font(.headline)
                        Text("対応ランタイム: Docker Desktop / OrbStack / Colima (`docker system df`)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .glassCard(cornerRadius: 18, padding: 18, tint: AppTheme.pastelCyan)

                if appState.dockerStatus.isDaemonRunning {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(appState.dockerStatus.resources) { res in
                            dockerResourceCard(res)
                        }
                    }

                    // 個別アクションパネル
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BuildKit ビルドキャッシュのみをクリア")
                                .font(.subheadline.weight(.semibold))
                            Text("稼働中のコンテナやイメージを残したまま、肥大化したビルドキャッシュだけを削除します。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        PastelActionButton(
                            title: "Build Cache Prune",
                            icon: "hammer.fill",
                            color: AppTheme.pastelAmber,
                            isLoading: appState.isPruningDocker
                        ) {
                            Task { await appState.pruneDockerBuildCache() }
                        }
                    }
                    .glassCard(cornerRadius: 18, padding: 18)
                }
            }
            .padding(26)
        }
        .onAppear {
            if appState.dockerStatus.resources.isEmpty && !appState.isScanningDocker {
                Task { await appState.scanDocker() }
            }
        }
    }

    private func dockerResourceCard(_ res: DockerResourceSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(res.typeName)
                    .font(.headline)
                Spacer()
                Text("総数: \(res.totalCount) (稼働 \(res.activeCount))")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }

            Text(res.sizeText)
                .font(.system(size: 26, weight: .bold, design: .rounded))

            HStack {
                Text("回収可能 (Reclaimable):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(res.reclaimableText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.pastelCyan)
            }
        }
        .glassCard(cornerRadius: 18, padding: 18, tint: AppTheme.pastelCyan)
    }
}
