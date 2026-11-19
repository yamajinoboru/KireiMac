# GEMINI.md — KireiMac プロジェクト・コンテキスト

## 1. プロジェクト概要
* **名称**: KireiMac（キレイ・マック / 旧称 MiniPulse）
* **目的**: CleanMyMac ライクなオールインワン macOS メンテナンス＆システムモニタリング機能を提供するオープンソース・ネイティブ SwiftUI アプリケーション。
* **ターゲット環境**: macOS 14+ (すべての Apple Silicon / Intel Mac 対応)

## 2. アーキテクチャと設計判断
* **UI フレームワーク**: SwiftUI (`NavigationSplitView` + `MenuBarExtra(.window)`)
* **デザインシステム (`AppTheme.swift`)**:
  * パステルカラー（Lavender, Mint, Sky, Peach, Rose, Amber）と `.ultraThinMaterial` によるグラスモーフィズムカード (`GlassCardModifier`)。
  * スプリングアニメーション (`response: 0.42, dampingFraction: 0.82`) に統一。
* **安全性への配慮**:
  * ファイル削除系アクション（ジャンク掃除・大容量ファイル・アプリアンインストール）は、誤消去を防ぐため原則 `FileManager.default.trashItem`（ゴミ箱への移動）を優先使用。
  * CloudKit (`com.apple.bird`) や Safari などのシステム必須領域はスキップする保護フィルタを実装。
* **低負荷テレメトリ (`SystemMonitorService.swift`)**:
  * CPU負荷・メモリ統計・ネットワークインターフェース統計は外部プロセスを起動せず、Darwin Mach API (`host_statistics`, `host_statistics64`, `getifaddrs`) を直接呼び出して低オーバーヘッド化。
  * **v2.0 省CPU最適化**:
    * `SmartCareView` の `.repeatForever` アニメーションを待機時は完全停止し、スキャン実行中のみ稼働。
    * ポーリング間隔を 4.0秒 (`tolerance: 1.0`) のバックグラウンドタスク (`Task.detached`) に変更し、定常更新時の `withAnimation` を廃止。
    * `/bin/ps` による上位プロセス取得は「システムモニター」タブを表示している時のみ実行。
    * メニューバー文字列は整数パーセントが変化した時のみ `@Published` を更新。
* **アプリアイコン (`scripts/generate_icon.swift`)**:
  * ダッシュボード左上のパステルラベンダー×ミント＋`macmini.fill` アイコンを `iconutil` で `AppIcon.icns` 化し、`Info.plist` と `NSApplication.shared.applicationIconImage` の双方に適用。
* **v2.0 追加モジュール**:
  * `DuplicateScannerService` / `DuplicateFinderView` (SHA-256 3段階重複ファイル検出)
  * `StartupManagerService` / `StartupManagerView` (LaunchAgents / Daemons 稼働管理)
  * `DockerCleanerService` / `DockerCleanerView` (Docker / OrbStack リソース可視化 & Prune)

## 3. ビルド・パッケージング手順
* テスト実行: `swift test --disable-sandbox`
* `.app` バンドル生成: `zsh scripts/bundle_app.sh` → `dist/KireiMac.app` に出力。
* 匿名デモスクリーンショット出力: `./dist/KireiMac.app/Contents/MacOS/KireiMac --export-demo-screenshots docs/screenshots`
