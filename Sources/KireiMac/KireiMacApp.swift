//
// KireiMacApp.swift
// KireiMac
//
// 役割: アプリケーションのエントリーポイント。メインウィンドウ、macOS メニューバー常駐 (MenuBarExtra)、カスタムアイコン、およびGitHub公開用の匿名デモスクリーンショット出力機能を提供する。
// 存在意義: 常駐ユーティリティとしての即時アクセス性と、フル機能ダッシュボードウィンドウの両立を実現する。

import SwiftUI
import AppKit

@main
public struct KireiMacApp: App {
    @StateObject private var appState = AppState()

    public init() {
        NSApplication.shared.setActivationPolicy(.regular)
        Self.applyApplicationIcon()

        // --export-demo-screenshots <outputDir> が指定された場合は、個人情報ゼロのデモデータで各画面のPNGを出力して即終了する
        let args = CommandLine.arguments
        if let flagIdx = args.firstIndex(of: "--export-demo-screenshots"),
           flagIdx + 1 < args.count {
            let outputDir = args[flagIdx + 1]
            MainActor.assumeIsolated {
                Self.exportSanitizedScreenshots(to: outputDir)
            }
            exit(0)
        }
    }

    public var body: some Scene {
        WindowGroup("KireiMac — macOS システムケア", id: "main") {
            MainWindowView()
                .environmentObject(appState)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1060, height: 720)

        // メニューバー常駐ウィジェット (整数変化時のみ再描画される省電力ラベル)
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text(appState.menuBarLabelText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Sanitized Offscreen Screenshot Renderer

    @MainActor
    private static func exportSanitizedScreenshots(to directoryPath: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: directoryPath, withIntermediateDirectories: true)

        let demoState = AppState(isDemoMode: true)
        let scenes: [(NavigationSection, String)] = [
            (.smartCare, "01_smart_care.png"),
            (.junkCleaner, "02_junk_cleaner.png"),
            (.systemMonitor, "03_system_monitor.png"),
            (.duplicateFinder, "04_duplicate_finder.png"),
            (.dockerCleaner, "05_docker_cleaner.png")
        ]

        let size = NSSize(width: 1080, height: 720)

        for (section, filename) in scenes {
            demoState.selectedSection = section
            let rootView = MainWindowView()
                .environmentObject(demoState)
                .frame(width: size.width, height: size.height)
                .background(Color(red: 0.11, green: 0.11, blue: 0.13))
                .environment(\.colorScheme, .dark)

            let hostingView = NSHostingView(rootView: rootView)
            hostingView.frame = NSRect(origin: .zero, size: size)
            hostingView.appearance = NSAppearance(named: .darkAqua)
            hostingView.layoutSubtreeIfNeeded()

            guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
                continue
            }
            hostingView.cacheDisplay(in: hostingView.bounds, to: rep)

            if let pngData = rep.representation(using: .png, properties: [:]) {
                let fileURL = URL(fileURLWithPath: directoryPath).appendingPathComponent(filename)
                try? pngData.write(to: fileURL)
                print("Exported sanitized screenshot: \(fileURL.path)")
            }
        }
    }

    // MARK: - App Icon

    /// ダッシュボード左上の「パステルラベンダー×ミントの角丸グラデーション＋sparkles」アイコンを Dock/AppSwitcher に適用する
    private static func applyApplicationIcon() {
        if let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let bundleIcon = NSImage(contentsOf: icnsURL) {
            NSApplication.shared.applicationIconImage = bundleIcon
            return
        }
        if let pngURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let pngIcon = NSImage(contentsOf: pngURL) {
            NSApplication.shared.applicationIconImage = pngIcon
            return
        }

        let size = 512
        let cgSize = CGSize(width: size, height: size)
        let image = NSImage(size: cgSize)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            let rect = CGRect(origin: .zero, size: cgSize)
            let inset = CGFloat(size) * 0.08
            let cardRect = rect.insetBy(dx: inset, dy: inset)
            let cornerRadius = cardRect.width * 0.23

            let path = CGPath(roundedRect: cardRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                CGColor(red: 0.65, green: 0.58, blue: 0.98, alpha: 1.0),
                CGColor(red: 0.35, green: 0.85, blue: 0.68, alpha: 1.0)
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: cardRect.minX, y: cardRect.maxY),
                    end: CGPoint(x: cardRect.maxX, y: cardRect.minY),
                    options: []
                )
            }
            ctx.restoreGState()

            let config = NSImage.SymbolConfiguration(pointSize: cardRect.width * 0.48, weight: .bold)
            if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let symSize = symbol.size
                let symRect = CGRect(
                    x: rect.midX - symSize.width / 2.0,
                    y: rect.midY - symSize.height / 2.0,
                    width: symSize.width,
                    height: symSize.height
                )
                let tinted = NSImage(size: symSize)
                tinted.lockFocus()
                NSColor(calibratedWhite: 0.12, alpha: 0.88).set()
                let drawRect = CGRect(origin: .zero, size: symSize)
                symbol.draw(in: drawRect)
                drawRect.fill(using: .sourceIn)
                tinted.unlockFocus()
                tinted.draw(in: symRect)
            }
        }
        image.unlockFocus()
        NSApplication.shared.applicationIconImage = image
    }
}
