//
// SystemMonitorService.swift
// MiniPulse
//
// 役割: macOS Mach カーネルAPIおよびBSDソケット統計を用いて、CPU・メモリ・ディスク・ネットワーク・プロセス負荷を取得する。
// 存在意義: 外部CLIに依存しすぎず、低オーバーヘッドでリアルタイムなMac miniのシステムテレメトリを提供する。

import Foundation
import Darwin

public final class SystemMonitorService: @unchecked Sendable {
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var previousNetSample: (timestamp: Date, ibytes: UInt64, obytes: UInt64)?
    private var processUpdateCounter: Int = 0
    private var cachedTopProcesses: [ProcessMetricItem] = []

    public init() {}

    /// 現在のシステムメトリクスを一括取得する
    /// - Parameter includeTopProcesses: `/bin/ps` を呼び出して上位プロセスを取得するか（システムモニター画面表示中のみ true にすることで待機時CPU負荷を0%に抑える）
    public func sampleMetrics(includeTopProcesses: Bool = false) -> SystemMetricsSnapshot {
        let now = Date()
        let cpu = readCPUUsage()
        let mem = readMemoryUsage()
        let disk = readDiskUsage()
        let net = readNetworkSpeed(now: now)
        let thermal = readThermalStateString()

        if includeTopProcesses {
            processUpdateCounter += 1
            if cachedTopProcesses.isEmpty || processUpdateCounter % 2 == 0 {
                cachedTopProcesses = readTopProcesses(limit: 6)
            }
        }

        return SystemMetricsSnapshot(
            timestamp: now,
            cpuUsageRatio: cpu.total,
            cpuUserRatio: cpu.user,
            cpuSystemRatio: cpu.system,
            memoryUsedBytes: mem.used,
            memoryTotalBytes: mem.total,
            memoryWiredBytes: mem.wired,
            memoryActiveBytes: mem.active,
            memoryCompressedBytes: mem.compressed,
            diskUsedBytes: disk.used,
            diskTotalBytes: disk.total,
            diskAvailableBytes: disk.available,
            networkUploadBytesPerSec: net.uploadPerSec,
            networkDownloadBytesPerSec: net.downloadPerSec,
            uptimeSeconds: ProcessInfo.processInfo.systemUptime,
            thermalStateDescription: thermal,
            topProcesses: cachedTopProcesses
        )
    }

    // MARK: - CPU Usage via host_statistics (HOST_CPU_LOAD_INFO)

    private func readCPUUsage() -> (total: Double, user: Double, system: Double) {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var cpuLoad = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }

        guard result == KERN_SUCCESS else {
            return (0, 0, 0)
        }

        let user = UInt64(cpuLoad.cpu_ticks.0)
        let system = UInt64(cpuLoad.cpu_ticks.1)
        let idle = UInt64(cpuLoad.cpu_ticks.2)
        let nice = UInt64(cpuLoad.cpu_ticks.3)

        defer {
            previousCPUTicks = (user, system, idle, nice)
        }

        guard let prev = previousCPUTicks else {
            return (0.08, 0.05, 0.03)
        }

        let userDiff = user >= prev.user ? user - prev.user : 0
        let sysDiff = system >= prev.system ? system - prev.system : 0
        let idleDiff = idle >= prev.idle ? idle - prev.idle : 0
        let niceDiff = nice >= prev.nice ? nice - prev.nice : 0

        let totalTicks = Double(userDiff + sysDiff + idleDiff + niceDiff)
        guard totalTicks > 0 else { return (0, 0, 0) }

        let userRatio = Double(userDiff + niceDiff) / totalTicks
        let sysRatio = Double(sysDiff) / totalTicks
        let totalRatio = min(1.0, max(0.0, userRatio + sysRatio))
        return (totalRatio, userRatio, sysRatio)
    }

    // MARK: - Memory Usage via host_statistics64 (HOST_VM_INFO64)

    private func readMemoryUsage() -> (used: UInt64, total: UInt64, wired: UInt64, active: UInt64, compressed: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var vmStats = vm_statistics64()

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }

        guard result == KERN_SUCCESS else {
            return (0, total, 0, 0, 0)
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let pageBytes = UInt64(pageSize)

        let active = UInt64(vmStats.active_count) * pageBytes
        let wired = UInt64(vmStats.wire_count) * pageBytes
        let compressed = UInt64(vmStats.compressor_page_count) * pageBytes
        // Activity Monitor に近い「App Memory + Wired + Compressed」相当の算出
        let appMemory = UInt64(vmStats.internal_page_count) * pageBytes
        let used = min(total, appMemory + wired + compressed)

        return (used, total, wired, active, compressed)
    }

    // MARK: - Disk Usage

    private func readDiskUsage() -> (used: UInt64, total: UInt64, available: UInt64) {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        do {
            let values = try homeURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
            let available: UInt64
            if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
                available = UInt64(important)
            } else {
                available = UInt64(max(0, values.volumeAvailableCapacity ?? 0))
            }
            let used = total > available ? (total - available) : 0
            return (used, total, available)
        } catch {
            return (0, 1, 1)
        }
    }

    // MARK: - Network Throughput via getifaddrs (AF_LINK / if_data)

    private func readNetworkSpeed(now: Date) -> (uploadPerSec: Double, downloadPerSec: Double) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
            return (0, 0)
        }
        defer { freeifaddrs(ifaddrPtr) }

        var totalIBytes: UInt64 = 0
        var totalOBytes: UInt64 = 0

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let ifa = cursor?.pointee {
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: ifa.ifa_name)
                // ループバック(lo0)を除いた物理・仮想インターフェースの累積バイト数を集計
                if !name.hasPrefix("lo"), let dataPtr = ifa.ifa_data {
                    let networkData = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                    totalIBytes &+= UInt64(networkData.ifi_ibytes)
                    totalOBytes &+= UInt64(networkData.ifi_obytes)
                }
            }
            cursor = ifa.ifa_next
        }

        defer {
            previousNetSample = (now, totalIBytes, totalOBytes)
        }

        guard let prev = previousNetSample else {
            return (0, 0)
        }

        let elapsed = now.timeIntervalSince(prev.timestamp)
        guard elapsed > 0.1 else { return (0, 0) }

        let diffIn = totalIBytes >= prev.ibytes ? Double(totalIBytes - prev.ibytes) : 0
        let diffOut = totalOBytes >= prev.obytes ? Double(totalOBytes - prev.obytes) : 0

        return (diffOut / elapsed, diffIn / elapsed)
    }

    // MARK: - Thermal State

    private func readThermalStateString() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "快適・低温 (Nominal)"
        case .fair: return "やや温かい (Fair)"
        case .serious: return "高温注意 (Serious)"
        case .critical: return "サーマルスロットリング中 (Critical)"
        @unknown default: return "正常"
        }
    }

    // MARK: - Top Processes

    private func readTopProcesses(limit: Int) -> [ProcessMetricItem] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aceo", "pid,%cpu,rss,comm", "-r"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            var items: [ProcessMetricItem] = []
            let lines = output.split(separator: "\n").dropFirst()
            for line in lines.prefix(limit) {
                let parts = line.split(whereSeparator: { $0.isWhitespace })
                guard parts.count >= 4,
                      let pid = Int32(parts[0]),
                      let cpu = Double(parts[1]),
                      let rssKB = Double(parts[2]) else {
                    continue
                }
                let name = parts.dropFirst(3).joined(separator: " ")
                items.append(
                    ProcessMetricItem(
                        id: pid,
                        name: name,
                        cpuPercent: cpu,
                        memoryMB: rssKB / 1024.0
                    )
                )
            }
            return items
        } catch {
            return []
        }
    }
}
