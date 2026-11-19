//
// MenuBarPopoverView.swift
// MiniPulse
//
// 役割: macOS メニューバー常駐アイコンをクリックした際に開くコンパクトなダッシュボードポップオーバー。
// 存在意義: メインウィンドウを開かなくても、いつでもワンクリックでCPU/メモリ確認やメモリ解放・クイック掃除ができるようにする。

import SwiftUI
import AppKit

public struct MenuBarPopoverView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ヘッダー
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(AppTheme.pastelLavender)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("KireiMac")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("Health Score: \(appState.healthScore) / 100")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(appState.metrics.thermalStateDescription)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppTheme.pastelMint.opacity(0.22)))
            }

            Divider()

            // 3連ミニゲージ
            HStack(spacing: 12) {
                PastelRingGauge(
                    progress: appState.metrics.cpuUsageRatio,
                    title: "CPU",
                    valueText: String(format: "%.0f%%", appState.metrics.cpuUsageRatio * 100),
                    subtitle: "負荷",
                    color: AppTheme.pastelSky,
                    size: 76,
                    lineWidth: 8
                )

                PastelRingGauge(
                    progress: appState.metrics.memoryUsageRatio,
                    title: "RAM",
                    valueText: String(format: "%.0f%%", appState.metrics.memoryUsageRatio * 100),
                    subtitle: ByteFormatter.string(from: appState.metrics.memoryUsedBytes),
                    color: AppTheme.pastelLavender,
                    size: 76,
                    lineWidth: 8
                )

                PastelRingGauge(
                    progress: appState.metrics.diskUsageRatio,
                    title: "SSD",
                    valueText: ByteFormatter.string(from: appState.metrics.diskAvailableBytes),
                    subtitle: "空き容量",
                    color: AppTheme.pastelPeach,
                    size: 76,
                    lineWidth: 8
                )
            }
            .frame(maxWidth: .infinity)

            // ネットワーク速度バー
            HStack {
                Label(
                    ByteFormatter.speedString(bytesPerSec: appState.metrics.networkDownloadBytesPerSec),
                    systemImage: "arrow.down.circle.fill"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.pastelMint)

                Spacer()

                Label(
                    ByteFormatter.speedString(bytesPerSec: appState.metrics.networkUploadBytesPerSec),
                    systemImage: "arrow.up.circle.fill"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.pastelPeach)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))

            // クイックアクションボタン
            VStack(spacing: 8) {
                Button {
                    Task {
                        await appState.runSingleMaintenanceTask(id: "purge_memory")
                        await appState.runSingleMaintenanceTask(id: "flush_dns")
                    }
                } label: {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text("クイック高速化 (RAM整理 & DNSフラッシュ)")
                            .font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.pastelLavender.opacity(0.25)))
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Button {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        openWindow(id: "main")
                    } label: {
                        HStack {
                            Image(systemName: "macwindow")
                            Text("ダッシュボードを開く")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                            .font(.caption.weight(.bold))
                            .padding(.vertical, 7)
                            .padding(.horizontal, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.pastelRose.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                    .help("KireiMac を終了")
                }
            }
        }
        .padding(16)
        .frame(width: 310)
    }
}
