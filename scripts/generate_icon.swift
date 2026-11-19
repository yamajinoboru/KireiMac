//
// generate_icon.swift
// MiniPulse
//
// 役割: ダッシュボード左上の「パステルラベンダー×ミントの角丸グラデーション＋macmini.fill」アイコンを正確なピクセルサイズで描画し、AppIcon.icnsを生成するスクリプト。

import AppKit
import CoreGraphics

let args = CommandLine.arguments
let outputDir = args.count > 1 ? args[1] : "."
let iconsetPath = "\(outputDir)/AppIcon.iconset"

let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func renderBitmap(pixelSize: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext

    let rect = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    let inset = CGFloat(pixelSize) * 0.08
    let cardRect = rect.insetBy(dx: inset, dy: inset)
    let cornerRadius = cardRect.width * 0.23

    ctx.saveGState()
    let path = CGPath(roundedRect: cardRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
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

    // 内側のハイライト枠
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
    ctx.setLineWidth(max(1.0, CGFloat(pixelSize) * 0.012))
    ctx.strokePath()
    ctx.restoreGState()

    // SF Symbol "sparkles" を中央に描画（全Mac共通の「綺麗・整う」象徴アイコン）
    let symbolPointSize = cardRect.width * 0.48
    let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .bold)
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

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconSpecs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, px) in iconSpecs {
    if let rep = renderBitmap(pixelSize: px),
       let png = rep.representation(using: .png, properties: [:]) {
        try png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(filename)"))
    }
}

let icnsPath = "\(outputDir)/AppIcon.icns"
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
try proc.run()
proc.waitUntilExit()

// もし iconutil がベータSDK環境等でスキップされた場合でも 512x512 PNG を AppIcon.png として残す
if let rep = renderBitmap(pixelSize: 512),
   let png = rep.representation(using: .png, properties: [:]) {
    try png.write(to: URL(fileURLWithPath: "\(outputDir)/AppIcon.png"))
}

try? fm.removeItem(atPath: iconsetPath)
print("Generated \(icnsPath)")
