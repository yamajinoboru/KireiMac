//
// SmartCareView.swift
// MiniPulse
//
// 役割: CleanMyMac の「スマートスキャン」に相当するホームダッシュボード画面。
// 存在意義: Mac mini の現在のヘルススコア、ジャンク削減可能容量、メモリ・ストレージ状態を一覧し、ワンクリックで最適化を実行できるようにする。

import SwiftUI

public struct SmartCareView: View {
    @EnvironmentObject private var appState: AppState
    @State private var pulseScale: CGFloat = 1.0

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ModuleHeaderView(
                    section: .smartCare,
                    trailingContent: AnyView(
                        HStack(spacing: 12) {
                            if appState.totalSessionFreedBytes > 0 {
                                Label(
                                    "今回解放済み: \(ByteFormatter.string(from: appState.totalSessionFreedBytes))",
                                    systemImage: "leaf.fill"
                                )
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(AppTheme.pastelMint.opacity(0.22)))
                            }

                            PastelActionButton(
                                title: appState.hasCompletedSmartScan ? "再スキャン" : "スマートスキャン開始",
                                icon: "sparkles",
                                color: AppTheme.pastelLavender,
                                isLoading: appState.isRunningSmartScan
                            ) {
                                Task { await appState.runSmartScan() }
                            }
                        }
                    )
                )

                // ヒーローカード: ヘルススコア＆ワンクリック最適化
                heroCard

                // 成功メッセージバナー
                if let banner = appState.smartCareBannerMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.pastelMint)
                        Text(banner)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .glassCard(cornerRadius: 16, padding: 14, tint: AppTheme.pastelMint)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // 3つの主要ピラー（ジャンク / パフォーマンス / ストレージ大容量）
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    junkSummaryCard
                    performanceSummaryCard
                    storageSummaryCard
                }

                // クイックナビゲーション
                quickJumpSection
            }
            .padding(26)
        }
    }

    // MARK: - Subviews

    private var heroCard: some View {
        HStack(spacing: 28) {
            // 円形ヘルススコア（待機中は完全静止してCPU使用率を0%に保つ）
            ZStack {
                Circle()
                    .fill(AppTheme.pastelLavender.opacity(0.14))
                    .frame(width: 140, height: 140)
                    .scaleEffect(appState.isRunningSmartScan ? pulseScale : 1.0)
                    .animation(
                        appState.isRunningSmartScan
                            ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                            : .default,
                        value: appState.isRunningSmartScan
                    )

                PastelRingGauge(
                    progress: Double(appState.healthScore) / 100.0,
                    title: "Health Score",
                    valueText: "\(appState.healthScore)",
                    subtitle: appState.metrics.thermalStateDescription,
                    color: AppTheme.pastelLavender,
                    size: 124,
                    lineWidth: 12
                )
            }
            .onChange(of: appState.isRunningSmartScan) { _, running in
                pulseScale = running ? 1.12 : 1.0
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("KireiMac スマート診断")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Apple Silicon / macOS 最適化")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppTheme.pastelLavender.opacity(0.25)))
                }

                if appState.isRunningSmartScan {
                    Text("システムキャッシュ・開発ゴミ・大容量ファイルを高速スキャンしています...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if appState.hasCompletedSmartScan {
                    Text("スキャン完了：不要ジャンク \(ByteFormatter.string(from: appState.totalJunkSelectedBytes)) がすぐに解放可能です。大容量ファイルも \(appState.filteredLargeFiles.count) 件検出されました。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("「スマートスキャン開始」を押すと、キャッシュ掃除・メモリ解放・大容量ファイルの診断を一度に実行します。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    if appState.hasCompletedSmartScan {
                        PastelActionButton(
                            title: "ワンクリック最適化を実行 (\(ByteFormatter.string(from: appState.totalJunkSelectedBytes)) 解放)",
                            icon: "bolt.shield.fill",
                            color: AppTheme.pastelMint,
                            isLoading: appState.isRunningSmartCareCleanup
                        ) {
                            Task { await appState.executeSmartCareCleanup() }
                        }
                    } else {
                        PastelActionButton(
                            title: "今すぐスマートスキャン",
                            icon: "play.fill",
                            color: AppTheme.pastelLavender,
                            isLoading: appState.isRunningSmartScan
                        ) {
                            Task { await appState.runSmartScan() }
                        }
                    }

                    Button {
                        withAnimation(AppTheme.smoothSpring) {
                            appState.selectedSection = .systemMonitor
                        }
                    } label: {
                        Label("詳細テレメトリを見る", systemImage: "waveform.path.ecg")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .glassCard(cornerRadius: 24, padding: 24, tint: AppTheme.pastelLavender)
    }

    private var junkSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trash.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.pastelMint)
                Text("ジャンク＆キャッシュ")
                    .font(.headline)
                Spacer()
            }

            Text(ByteFormatter.string(from: appState.totalJunkSelectedBytes))
                .font(.system(size: 26, weight: .bold, design: .rounded))

            Text(appState.junkItems.isEmpty ? "スキャン待ち・またはクリーンな状態" : "\(appState.junkItems.count) 個のキャッシュ項目を検出")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                withAnimation(AppTheme.smoothSpring) {
                    appState.selectedSection = .junkCleaner
                }
            } label: {
                HStack {
                    Text("内訳を確認")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .padding(.top, 6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.pastelMint)
        }
        .frame(minHeight: 165)
        .glassCard(cornerRadius: 20, padding: 18, tint: AppTheme.pastelMint)
    }

    private var performanceSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cpu.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.pastelSky)
                Text("CPU & メモリ負荷")
                    .font(.headline)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.0f%%", appState.metrics.cpuUsageRatio * 100))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("CPU 使用率")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.0f%%", appState.metrics.memoryUsageRatio * 100))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("メモリ (\(ByteFormatter.string(from: appState.metrics.memoryUsedBytes)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("稼働時間: \(ByteFormatter.uptimeString(seconds: appState.metrics.uptimeSeconds))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                withAnimation(AppTheme.smoothSpring) {
                    appState.selectedSection = .systemMonitor
                }
            } label: {
                HStack {
                    Text("リアルタイムモニターへ")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .padding(.top, 6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.pastelSky)
        }
        .frame(minHeight: 165)
        .glassCard(cornerRadius: 20, padding: 18, tint: AppTheme.pastelSky)
    }

    private var storageSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "internaldrive.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.pastelPeach)
                Text("ストレージ空き容量")
                    .font(.headline)
                Spacer()
            }

            Text(ByteFormatter.string(from: appState.metrics.diskAvailableBytes))
                .font(.system(size: 26, weight: .bold, design: .rounded))

            ProgressView(value: appState.metrics.diskUsageRatio)
                .tint(AppTheme.pastelPeach)

            Text("全体 \(ByteFormatter.string(from: appState.metrics.diskTotalBytes)) 中 \(ByteFormatter.string(from: appState.metrics.diskUsedBytes)) 使用")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                withAnimation(AppTheme.smoothSpring) {
                    appState.selectedSection = .largeFiles
                }
            } label: {
                HStack {
                    Text("大容量ファイルを探す")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .padding(.top, 6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.pastelPeach)
        }
        .frame(minHeight: 165)
        .glassCard(cornerRadius: 20, padding: 18, tint: AppTheme.pastelPeach)
    }

    private var quickJumpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("プロフェッショナル・ツールボックス")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                quickJumpTile(
                    title: "重複ファイルファインダー",
                    subtitle: "SHA-256 高速照合で同一コピーを検出し、1つを残して整理",
                    icon: "doc.on.doc.fill",
                    color: AppTheme.pastelLilac,
                    target: .duplicateFinder
                )

                quickJumpTile(
                    title: "スタートアップ・常駐管理",
                    subtitle: "LaunchAgents / バックグラウンド常駐の稼働確認・停止",
                    icon: "power.circle.fill",
                    color: AppTheme.pastelTeal,
                    target: .startupManager
                )

                quickJumpTile(
                    title: "Docker コンテナ＆キャッシュ掃除",
                    subtitle: "肥大化した Docker Images / BuildKit キャッシュを一掃",
                    icon: "shippingbox.and.arrow.backward.fill",
                    color: AppTheme.pastelCyan,
                    target: .dockerCleaner
                )

                quickJumpTile(
                    title: "アプリ完全アンインストール",
                    subtitle: "不要なアプリと ~/Library の残骸を一括削除",
                    icon: "square.stack.3d.up.fill",
                    color: AppTheme.pastelRose,
                    target: .appUninstaller
                )
            }
        }
    }

    private func quickJumpTile(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        target: NavigationSection
    ) -> some View {
        Button {
            withAnimation(AppTheme.smoothSpring) {
                appState.selectedSection = target
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.22))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(color.opacity(0.8))
            }
            .glassCard(cornerRadius: 18, padding: 16, tint: color)
        }
        .buttonStyle(.plain)
    }
}
