//
// SystemMonitorView.swift
// MiniPulse
//
// 役割: CPU・メモリ・ディスク・ネットワーク送受信速度・上位負荷プロセスをリアルタイム可視化するモニター画面。
// 存在意義: Mac mini のハードウェアリソース状況を直感的なパステルリングゲージと波形スパークラインで把握できるようにする。

import SwiftUI

public struct SystemMonitorView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModuleHeaderView(
                    section: .systemMonitor,
                    trailingContent: AnyView(
                        HStack(spacing: 10) {
                            Label(appState.metrics.thermalStateDescription, systemImage: "thermometer.medium")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(AppTheme.pastelSky.opacity(0.18)))

                            PastelActionButton(
                                title: "メモリキャッシュ解放",
                                icon: "memorychip",
                                color: AppTheme.pastelSky,
                                isLoading: appState.isRunningMaintenance
                            ) {
                                Task { await appState.runSingleMaintenanceTask(id: "purge_memory") }
                            }
                        }
                    )
                )

                // 上段: 3大リングゲージ (CPU / メモリ / ディスク)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    cpuGaugeCard
                    memoryGaugeCard
                    diskGaugeCard
                }

                // 中段: リアルタイム履歴波形 + ネットワーク速度
                HStack(spacing: 16) {
                    historySparklineCard
                    networkThroughputCard
                }

                // 下段: 上位リソース消費プロセス一覧
                topProcessesCard
            }
            .padding(26)
        }
        .onAppear {
            appState.refreshMetrics(animated: false)
        }
    }

    // MARK: - Cards

    private var cpuGaugeCard: some View {
        VStack(spacing: 14) {
            PastelRingGauge(
                progress: appState.metrics.cpuUsageRatio,
                title: "CPU Total",
                valueText: String(format: "%.1f%%", appState.metrics.cpuUsageRatio * 100),
                subtitle: String(
                    format: "User %.0f%% / Sys %.0f%%",
                    appState.metrics.cpuUserRatio * 100,
                    appState.metrics.cpuSystemRatio * 100
                ),
                color: AppTheme.pastelSky,
                size: 120
            )
        }
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 20, padding: 18, tint: AppTheme.pastelSky)
    }

    private var memoryGaugeCard: some View {
        VStack(spacing: 14) {
            PastelRingGauge(
                progress: appState.metrics.memoryUsageRatio,
                title: "Memory",
                valueText: String(format: "%.0f%%", appState.metrics.memoryUsageRatio * 100),
                subtitle: "\(ByteFormatter.string(from: appState.metrics.memoryUsedBytes)) / \(ByteFormatter.string(from: appState.metrics.memoryTotalBytes))",
                color: AppTheme.pastelLavender,
                size: 120
            )

            HStack(spacing: 10) {
                memoryMiniStat(label: "Wired", bytes: appState.metrics.memoryWiredBytes)
                memoryMiniStat(label: "Active", bytes: appState.metrics.memoryActiveBytes)
                memoryMiniStat(label: "Compressed", bytes: appState.metrics.memoryCompressedBytes)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 20, padding: 18, tint: AppTheme.pastelLavender)
    }

    private func memoryMiniStat(label: String, bytes: UInt64) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(ByteFormatter.string(from: bytes))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private var diskGaugeCard: some View {
        VStack(spacing: 14) {
            PastelRingGauge(
                progress: appState.metrics.diskUsageRatio,
                title: "Macintosh HD",
                valueText: ByteFormatter.string(from: appState.metrics.diskAvailableBytes),
                subtitle: "空き容量 (使用率 \(Int(appState.metrics.diskUsageRatio * 100))%)",
                color: AppTheme.pastelPeach,
                size: 120
            )
        }
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 20, padding: 18, tint: AppTheme.pastelPeach)
    }

    private var historySparklineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("CPU & メモリ リアルタイム推移 (直近60秒)", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Circle().fill(AppTheme.pastelSky).frame(width: 8, height: 8)
                        Text("CPU").font(.caption)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(AppTheme.pastelLavender).frame(width: 8, height: 8)
                        Text("Memory").font(.caption)
                    }
                }
            }

            ZStack {
                SparklineGraphView(values: appState.memoryHistory, color: AppTheme.pastelLavender)
                SparklineGraphView(values: appState.cpuHistory, color: AppTheme.pastelSky)
            }
            .frame(height: 110)
        }
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 20, padding: 18)
    }

    private var networkThroughputCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("ネットワーク通信速度", systemImage: "wifi")
                .font(.headline)

            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(AppTheme.pastelMint)
                        Text("ダウンロード")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(ByteFormatter.speedString(bytesPerSec: appState.metrics.networkDownloadBytesPerSec))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }

                Divider().frame(height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(AppTheme.pastelPeach)
                        Text("アップロード")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(ByteFormatter.speedString(bytesPerSec: appState.metrics.networkUploadBytesPerSec))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
            }

            Divider()

            HStack {
                Text("システム連続稼働時間:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteFormatter.uptimeString(seconds: appState.metrics.uptimeSeconds))
                    .font(.caption.weight(.semibold))
            }
        }
        .frame(width: 310)
        .glassCard(cornerRadius: 20, padding: 18)
    }

    private var topProcessesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("上位CPU消費プロセス", systemImage: "list.number")
                    .font(.headline)
                Spacer()
                Text("自動更新 (6秒周期)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appState.metrics.topProcesses.isEmpty {
                Text("プロセス情報を取得中...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(appState.metrics.topProcesses) { proc in
                    HStack {
                        Text(proc.name)
                            .font(.subheadline.weight(.medium))
                        Text("PID: \(proc.id)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f MB", proc.memoryMB))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .trailing)
                        Text(String(format: "%.1f %%", proc.cpuPercent))
                            .font(.subheadline.monospacedDigit().weight(.bold))
                            .foregroundStyle(proc.cpuPercent > 50 ? AppTheme.pastelRose : AppTheme.pastelSky)
                            .frame(width: 75, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.4)
                }
            }
        }
        .glassCard(cornerRadius: 20, padding: 18)
    }
}

/// 滑らかな折れ線＆グラデーション塗りつぶしスパークライン
public struct SparklineGraphView: View {
    public let values: [Double]
    public let color: Color

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let count = max(values.count, 2)
            let stepX = width / CGFloat(count - 1)

            ZStack {
                // 塗りつぶし領域
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height))
                    for (idx, val) in values.enumerated() {
                        let clamped = min(1.0, max(0.0, val))
                        let x = CGFloat(idx) * stepX
                        let y = height - (CGFloat(clamped) * (height - 8)) - 4
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.28), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // ライン
                Path { path in
                    for (idx, val) in values.enumerated() {
                        let clamped = min(1.0, max(0.0, val))
                        let x = CGFloat(idx) * stepX
                        let y = height - (CGFloat(clamped) * (height - 8)) - 4
                        if idx == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
