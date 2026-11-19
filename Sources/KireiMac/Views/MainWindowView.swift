//
// MainWindowView.swift
// MiniPulse
//
// 役割: サイドバーナビゲーションと詳細画面を統合するメインウィンドウのルートビュー。
// 存在意義: Apple / Linear ライクな透過サイドバー、パステルカラーの選択インジケーター、下部ライブステータスバーを備える。

import SwiftUI

public struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 235, ideal: 250, max: 280)
        } detail: {
            ZStack {
                // 背景のベースウィンドウカラーと淡いパステルグラデーション装飾
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        AppTheme.accentColor(for: appState.selectedSection).opacity(0.10),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Group {
                    switch appState.selectedSection {
                    case .smartCare:
                        SmartCareView()
                    case .junkCleaner:
                        JunkCleanerView()
                    case .systemMonitor:
                        SystemMonitorView()
                    case .largeFiles:
                        LargeFilesView()
                    case .duplicateFinder:
                        DuplicateFinderView()
                    case .appUninstaller:
                        AppUninstallerView()
                    case .startupManager:
                        StartupManagerView()
                    case .dockerCleaner:
                        DockerCleanerView()
                    case .maintenance:
                        MaintenanceView()
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(minWidth: 960, minHeight: 640)
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // アプリブランディングヘッダー
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.pastelLavender, AppTheme.pastelMint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.82))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("KireiMac")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("macOS System Care")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            Divider().padding(.horizontal, 12)

            // ナビゲーションアイテムリスト
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(NavigationSection.allCases) { section in
                        sidebarButton(for: section)
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // 下部ライブミニテレメトリカード
            sidebarFooterCard
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    private func sidebarButton(for section: NavigationSection) -> some View {
        let isSelected = appState.selectedSection == section
        let color = AppTheme.accentColor(for: section)

        return Button {
            withAnimation(AppTheme.smoothSpring) {
                appState.selectedSection = section
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? color : .secondary)
                    .frame(width: 24)

                Text(section.rawValue)
                    .font(.system(size: 13.5, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()

                if isSelected {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? color.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var sidebarFooterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("システムステータス")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(AppTheme.pastelMint)
                    .frame(width: 7, height: 7)
            }

            HStack {
                Text("CPU")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", appState.metrics.cpuUsageRatio * 100))
                    .font(.caption2.monospacedDigit().weight(.bold))
            }
            ProgressView(value: appState.metrics.cpuUsageRatio)
                .tint(AppTheme.pastelSky)

            HStack {
                Text("メモリ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(ByteFormatter.string(from: appState.metrics.memoryUsedBytes))")
                    .font(.caption2.monospacedDigit().weight(.bold))
            }
            ProgressView(value: appState.metrics.memoryUsageRatio)
                .tint(AppTheme.pastelLavender)

            HStack {
                Text("空き容量")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteFormatter.string(from: appState.metrics.diskAvailableBytes))
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(AppTheme.pastelPeach)
            }
        }
        .glassCard(cornerRadius: 16, padding: 12)
    }
}
