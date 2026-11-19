//
// MaintenanceView.swift
// MiniPulse
//
// 役割: DNSキャッシュフラッシュ、LaunchServices修復、フォントキャッシュクリア、メモリ解放等のメンテナンススクリプト実行画面。
// 存在意義: CleanMyMac の「メンテナンス」機能と同様、チェックボックスで一括または個別実行できる直感的なUIを提供する。

import SwiftUI

public struct MaintenanceView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModuleHeaderView(
                    section: .maintenance,
                    trailingContent: AnyView(
                        PastelActionButton(
                            title: "選択したメンテナンスを一括実行",
                            icon: "play.fill",
                            color: AppTheme.pastelAmber,
                            isLoading: appState.isRunningMaintenance,
                            isDisabled: !appState.maintenanceTasks.contains(where: \.isSelected)
                        ) {
                            Task { await appState.runSelectedMaintenanceTasks() }
                        }
                    )
                )

                if let summary = appState.lastMaintenanceSummary {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(AppTheme.pastelAmber)
                        Text(summary)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .glassCard(cornerRadius: 14, padding: 12, tint: AppTheme.pastelAmber)
                }

                VStack(spacing: 12) {
                    ForEach(appState.maintenanceTasks) { task in
                        maintenanceTaskCard(task)
                    }
                }
            }
            .padding(26)
        }
    }

    private func maintenanceTaskCard(_ task: MaintenanceTaskItem) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Button {
                appState.toggleMaintenanceTask(id: task.id)
            } label: {
                Image(systemName: task.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isSelected ? AppTheme.pastelAmber : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.pastelAmber.opacity(0.2))
                    .frame(width: 42, height: 42)
                Image(systemName: task.iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.pastelAmber)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.headline)
                    Text(task.commandDescription)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .foregroundStyle(.secondary)
                }

                Text(task.subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.85))

                Text(task.detailedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let message = task.lastResultMessage {
                    HStack(spacing: 6) {
                        Image(systemName: (task.lastRunSucceeded ?? true) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle((task.lastRunSucceeded ?? true) ? AppTheme.pastelMint : AppTheme.pastelRose)
                        Text(message)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.top, 3)
                }
            }

            Spacer()

            Button {
                Task { await appState.runSingleMaintenanceTask(id: task.id) }
            } label: {
                Label("単体実行", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(AppTheme.pastelAmber.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .disabled(appState.isRunningMaintenance)
        }
        .glassCard(cornerRadius: 18, padding: 16, tint: task.isSelected ? AppTheme.pastelAmber : nil)
    }
}
