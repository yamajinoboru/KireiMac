//
// AppUninstallerView.swift
// MiniPulse
//
// 役割: インストール済みアプリの一覧表示と、~/Library に散らばった関連残骸（Leftovers）の可視化・一括削除を行う画面。
// 存在意義: アプリ本体を残したままキャッシュ・残骸だけをリセットする機能と、アプリごとの完全アンインストールの両方を提供する。

import SwiftUI

public struct AppUninstallerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedApp: InstalledAppItem?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleHeaderView(
                section: .appUninstaller,
                trailingContent: AnyView(
                    HStack(spacing: 12) {
                        TextField("アプリ名または Bundle ID で検索...", text: $appState.appSearchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)

                        PastelActionButton(
                            title: "アプリ一覧を再スキャン",
                            icon: "arrow.clockwise",
                            color: AppTheme.pastelRose,
                            isLoading: appState.isScanningApps
                        ) {
                            Task { await appState.scanApps() }
                        }
                    }
                )
            )

            if let msg = appState.lastUninstallMessage {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.pastelRose)
                    Text(msg)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .glassCard(cornerRadius: 14, padding: 12, tint: AppTheme.pastelRose)
            }

            if appState.isScanningApps {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text("/Applications と ~/Library の関連データを照合しています...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 18) {
                    // 左側: アプリ一覧
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(appState.filteredApps) { app in
                                appRow(app)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // 右側: 選択中アプリの詳細＆残骸（Leftovers）内訳パネル
                    if let currentApp = selectedApp ?? appState.filteredApps.first {
                        appDetailInspector(currentApp)
                            .frame(width: 340)
                    }
                }
            }
        }
        .padding(26)
        .onAppear {
            if appState.installedApps.isEmpty && !appState.isScanningApps {
                Task { await appState.scanApps() }
            }
        }
    }

    // MARK: - Subviews

    private func appRow(_ app: InstalledAppItem) -> some View {
        let isSelected = (selectedApp?.id ?? appState.filteredApps.first?.id) == app.id
        return Button {
            withAnimation(AppTheme.smoothSpring) {
                selectedApp = app
            }
        } label: {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                    .resizable()
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(.subheadline.weight(.semibold))
                        Text("v\(app.version)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(app.bundleIdentifier)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(ByteFormatter.string(from: app.totalSizeBytes))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                    if app.leftoversSizeBytes > 0 {
                        Text("関連データ \(ByteFormatter.string(from: app.leftoversSizeBytes))")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.pastelRose)
                    }
                }
            }
            .glassCard(
                cornerRadius: 15,
                padding: 12,
                tint: isSelected ? AppTheme.pastelRose : nil
            )
        }
        .buttonStyle(.plain)
    }

    private func appDetailInspector(_ app: InstalledAppItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                    .resizable()
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.headline)
                    Text(app.bundleIdentifier)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("合計占有: \(ByteFormatter.string(from: app.totalSizeBytes))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.pastelRose)
                }
            }

            Divider()

            Text("内訳 (本体 + ~/Library 関連データ)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // 本体行
            HStack {
                Label("アプリケーション本体 (.app)", systemImage: "app.fill")
                    .font(.caption)
                Spacer()
                Text(ByteFormatter.string(from: app.appSizeBytes))
                    .font(.caption.weight(.semibold))
            }

            if app.leftovers.isEmpty {
                Text("~/Library 内に追加のキャッシュ・設定残骸は検出されませんでした。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(app.leftovers) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.kind.rawValue)
                                        .font(.caption.weight(.semibold))
                                    Text(item.url.lastPathComponent)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(ByteFormatter.string(from: item.sizeBytes))
                                    .font(.caption.monospacedDigit())
                                Button {
                                    appState.revealInFinder(item.url)
                                } label: {
                                    Image(systemName: "folder")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Spacer()

            VStack(spacing: 10) {
                if !app.leftovers.isEmpty {
                    PastelActionButton(
                        title: "関連残骸のみゴミ箱へ (\(ByteFormatter.string(from: app.leftoversSizeBytes)))",
                        icon: "paintbrush.fill",
                        color: AppTheme.pastelAmber
                    ) {
                        Task { await appState.uninstallApp(app, leftoversOnly: true) }
                    }
                }

                PastelActionButton(
                    title: "完全アンインストール (ゴミ箱へ移動)",
                    icon: "trash.fill",
                    color: AppTheme.pastelRose
                ) {
                    Task {
                        await appState.uninstallApp(app, leftoversOnly: false)
                        selectedApp = nil
                    }
                }
            }
        }
        .glassCard(cornerRadius: 20, padding: 18, tint: AppTheme.pastelRose)
    }
}
