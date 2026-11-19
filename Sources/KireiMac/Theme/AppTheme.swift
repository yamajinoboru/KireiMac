//
// AppTheme.swift
// MiniPulse
//
// 役割: Apple / Linear ライクなパステルカラーパレット・角丸・グラスモーフィズムカード等の共通デザイン定義。
// 存在意義: 全画面で統一されたモダン・ミニマルな美学と滑らかなマイクロインタラクションを保証する。

import SwiftUI

public enum AppTheme {
    // MARK: - Pastel Palette

    /// スマートケア用 パステルラベンダー
    public static let pastelLavender = Color(red: 0.65, green: 0.58, blue: 0.98)
    /// ジャンク掃除用 パステルミント
    public static let pastelMint = Color(red: 0.35, green: 0.85, blue: 0.68)
    /// システムモニター用 パステルスカイブルー
    public static let pastelSky = Color(red: 0.42, green: 0.78, blue: 0.98)
    /// 大容量ファイル用 パステルピーチ
    public static let pastelPeach = Color(red: 0.98, green: 0.66, blue: 0.45)
    /// アプリ管理用 パステルローズ
    public static let pastelRose = Color(red: 0.96, green: 0.52, blue: 0.65)
    /// メンテナンス用 パステルアンバー
    public static let pastelAmber = Color(red: 0.96, green: 0.78, blue: 0.38)
    /// 重複ファイル用 パステルライラック
    public static let pastelLilac = Color(red: 0.82, green: 0.60, blue: 0.96)
    /// スタートアップ管理用 パステルティール
    public static let pastelTeal = Color(red: 0.36, green: 0.84, blue: 0.82)
    /// Docker掃除用 パステルインディゴブルー
    public static let pastelCyan = Color(red: 0.45, green: 0.72, blue: 0.99)

    /// セクションごとのテーマカラー
    public static func accentColor(for section: NavigationSection) -> Color {
        switch section {
        case .smartCare: return pastelLavender
        case .junkCleaner: return pastelMint
        case .systemMonitor: return pastelSky
        case .largeFiles: return pastelPeach
        case .duplicateFinder: return pastelLilac
        case .appUninstaller: return pastelRose
        case .startupManager: return pastelTeal
        case .dockerCleaner: return pastelCyan
        case .maintenance: return pastelAmber
        }
    }

    /// セクションごとのグラデーション
    public static func gradient(for section: NavigationSection) -> LinearGradient {
        let base = accentColor(for: section)
        return LinearGradient(
            colors: [base.opacity(0.85), base.opacity(0.45)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Animation Presets

    /// Linear / Apple ライクな心地よいスプリングアニメーション
    public static let smoothSpring = Animation.spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0.15)
}

// MARK: - Reusable Glass Card Modifier

public struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 18
    var tintColor: Color? = nil

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    if let tintColor {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tintColor.opacity(0.06))
                    }
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.primary.opacity(0.14),
                                    Color.primary.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
    }
}

extension View {
    public func glassCard(
        cornerRadius: CGFloat = 20,
        padding: CGFloat = 18,
        tint: Color? = nil
    ) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, padding: padding, tintColor: tint))
    }
}

// MARK: - Circular Ring Gauge View

/// 円形のパステルプログレスリング
public struct PastelRingGauge: View {
    public let progress: Double // 0.0 ... 1.0
    public let title: String
    public let valueText: String
    public let subtitle: String
    public let color: Color
    public var size: CGFloat = 110
    public var lineWidth: CGFloat = 11

    public init(
        progress: Double,
        title: String,
        valueText: String,
        subtitle: String,
        color: Color,
        size: CGFloat = 110,
        lineWidth: CGFloat = 11
    ) {
        self.progress = min(1.0, max(0.0, progress))
        self.title = title
        self.valueText = valueText
        self.subtitle = subtitle
        self.color = color
        self.size = size
        self.lineWidth = lineWidth
    }

    public var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.16), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.75), color, color.opacity(0.9)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(AppTheme.smoothSpring, value: progress)

                VStack(spacing: 2) {
                    Text(valueText)
                        .font(.system(size: size * 0.19, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(title)
                        .font(.system(size: size * 0.10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Pill Action Button

public struct PastelActionButton: View {
    public let title: String
    public let icon: String
    public let color: Color
    public var isLoading: Bool = false
    public var isDisabled: Bool = false
    public let action: () -> Void

    @State private var isHovering = false

    public init(
        title: String,
        icon: String,
        color: Color,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                color.opacity(isHovering ? 0.95 : 0.85),
                                color.opacity(isHovering ? 0.78 : 0.65)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .foregroundStyle(Color.black.opacity(0.85))
            .shadow(color: color.opacity(isHovering ? 0.35 : 0.18), radius: isHovering ? 10 : 5, y: 3)
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(AppTheme.smoothSpring, value: isHovering)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .opacity((isDisabled || isLoading) ? 0.55 : 1.0)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Section Header View

public struct ModuleHeaderView: View {
    public let section: NavigationSection
    public let trailingContent: AnyView?

    public init(section: NavigationSection, trailingContent: AnyView? = nil) {
        self.section = section
        self.trailingContent = trailingContent
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.gradient(for: section))
                    .frame(width: 46, height: 46)
                Image(systemName: section.iconName)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(section.rawValue)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(section.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let trailingContent {
                trailingContent
            }
        }
        .padding(.bottom, 6)
    }
}
