pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // ── LIVE VALUES ────────────────────────────────────────────
    property real cpuUsage: 0
    property real memUsage: 0

    property var perCore: []
    property real memUsedKb: 0
    property real memTotalKb: 0

    property real gpuUtil: 0
    property real gpuMemUsedMb: 0
    property real gpuMemTotalMb: 0
    property real gpuTempC: 0
    property real gpuPowerW: 0

    property real cpuTempC: 0
    property var fans: []

    property var disks: []

    property real netRxKBs: 0
    property real netTxKBs: 0

    property var processes: []

    // ── SETTINGS ───────────────────────────────────────────────
    FileView {
        id: settingsFile
        path: Quickshell.dataPath("sysmonitor-settings.json")
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        JsonAdapter {
            id: settings
            property bool fetchNvidia: true
        }
    }
    // The setting only matters when the NVIDIA driver is actually loaded
    property bool hasNvidia: false
    FileView {
        path: "/proc/driver/nvidia/version"
        printErrors: false
        onLoaded: root.hasNvidia = true
    }
    readonly property bool fetchNvidiaEnabled: settings.fetchNvidia && root.hasNvidia
    function setFetchNvidia(enabled) { settings.fetchNvidia = enabled }

    // ── POLLING REFCOUNTS ──────────────────────────────────────
    property int gpuRequests: 0
    property int sensorRequests: 0
    property int diskRequests: 0
    property int processRequests: 0

    readonly property bool gpuPollActive: gpuRequests > 0
    readonly property bool sensorPollActive: sensorRequests > 0
    readonly property bool diskPollActive: diskRequests > 0
    readonly property bool processPollActive: processRequests > 0

    function startGpuPolling() { root.gpuRequests++ }
    function stopGpuPolling() { root.gpuRequests = Math.max(0, root.gpuRequests - 1) }

    function startSensorPolling() { root.sensorRequests++ }
    function stopSensorPolling() { root.sensorRequests = Math.max(0, root.sensorRequests - 1) }

    function startDiskPolling() { root.diskRequests++ }
    function stopDiskPolling() { root.diskRequests = Math.max(0, root.diskRequests - 1) }

    function startProcessPolling() { root.processRequests++ }
    function stopProcessPolling() { root.processRequests = Math.max(0, root.processRequests - 1) }

    // ── /proc SAMPLING ─────────────────────────────────────────

    property var _prevCpu: []
    property var _prevNet: null

    FileView {
        id: statFile
        path: "/proc/stat"
        onLoaded: root._sampleCpu(text())
    }

    FileView {
        id: meminfoFile
        path: "/proc/meminfo"
        onLoaded: root._sampleMem(text())
    }

    FileView {
        id: netDevFile
        path: "/proc/net/dev"
        onLoaded: root._sampleNet(text())
    }

    Timer {
        interval: 1500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statFile.reload()
            meminfoFile.reload()
            netDevFile.reload()
        }
    }

    Timer {
        interval: 4000
        repeat: true
        triggeredOnStart: true
        running: (root.gpuPollActive && root.fetchNvidiaEnabled) || root.sensorPollActive
        onTriggered: {
            if (root.gpuPollActive && root.fetchNvidiaEnabled) gpuProc.running = true
            if (root.sensorPollActive) sensorsProc.running = true
        }
    }

    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: root.diskPollActive
        onTriggered: diskProc.running = true
    }

    Timer {
        id: processTimer
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.processPollActive
        onTriggered: processProc.running = true
    }

    function _sampleCpu(text) {
        if (!text) return

        const lines = text.split("\n")
        const samples = []

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            if (!line.startsWith("cpu")) break

            const parts = line.trim().split(/\s+/)
            const v = parts.slice(1).map(Number)
            if (v.length < 8) continue

            const idle = v[3] + v[4]
            let total = 0
            for (let f = 0; f < 8; f++) total += v[f]

            samples.push({ total: total, idle: idle })
        }

        if (samples.length === 0) return

        if (root._prevCpu.length !== samples.length) {
            root._prevCpu = samples
            return
        }

        const cores = []
        for (let c = 1; c < samples.length; c++) {
            cores.push({ usage: root._usageDelta(root._prevCpu[c], samples[c]) })
        }

        root.cpuUsage = root._usageDelta(root._prevCpu[0], samples[0])
        root.perCore = cores
        root._prevCpu = samples
    }

    function _usageDelta(prev, now) {
        const dTotal = now.total - prev.total
        const dIdle = now.idle - prev.idle
        return dTotal > 0 ? Math.max(0, Math.min(1, 1 - dIdle / dTotal)) : 0
    }

    function _sampleMem(text) {
        if (!text) return

        let total = 0
        let avail = 0
        const lines = text.split("\n")
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            if (line.startsWith("MemTotal:")) {
                total = Number(line.replace(/[^0-9]/g, ""))
            } else if (line.startsWith("MemAvailable:")) {
                avail = Number(line.replace(/[^0-9]/g, ""))
            }
            if (total > 0 && avail > 0) break
        }

        if (total <= 0) return
        root.memTotalKb = total
        root.memUsedKb = total - avail
        root.memUsage = Math.max(0, Math.min(1, (total - avail) / total))
    }

    function _sampleNet(text) {
        if (!text) return

        const lines = text.split("\n").slice(2)
        let rxTotal = 0
        let txTotal = 0

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim()
            if (!line) continue
            const colon = line.indexOf(":")
            if (colon < 0) continue
            const iface = line.slice(0, colon).trim()
            // Physical NICs only: VPN tunnels (tailscale, wg, tun), bridges and
            // veths re-carry the same bytes and would double-count throughput
            if (!/^(en|eth|wl|ww)/.test(iface)) continue

            const fields = line.slice(colon + 1).trim().split(/\s+/).map(Number)
            if (fields.length < 16) continue
            rxTotal += fields[0]
            txTotal += fields[8]
        }

        const now = { rx: rxTotal, tx: txTotal, time: Date.now() }
        if (root._prevNet) {
            const dt = (now.time - root._prevNet.time) / 1000
            if (dt > 0) {
                root.netRxKBs = Math.max(0, (now.rx - root._prevNet.rx) / dt / 1024)
                root.netTxKBs = Math.max(0, (now.tx - root._prevNet.tx) / dt / 1024)
            }
        }
        root._prevNet = now
    }

    // ── GPU ────────────────────────────────────────────────────
    Process {
        id: gpuProc
        command: [
            "nvidia-smi",
            "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw",
            "--format=csv,noheader,nounits"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = (this.text || "").trim().split("\n")[0]
                if (!line) return
                const f = line.split(",").map(s => Number(s.trim()))
                if (f.length < 5) return
                root.gpuUtil = (f[0] || 0) / 100
                root.gpuMemUsedMb = f[1] || 0
                root.gpuMemTotalMb = f[2] || 0
                root.gpuTempC = f[3] || 0
                root.gpuPowerW = f[4] || 0
            }
        }
    }

    // ── CPU TEMP / FANS ────────────────────────────────────────
    Process {
        id: sensorsProc
        command: ["sensors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root._sampleSensors(this.text)
        }
    }

    function _sampleSensors(jsonText) {
        if (!jsonText) return
        let data
        try {
            data = JSON.parse(jsonText)
        } catch (e) {
            return
        }

        let temp = null
        const fanList = []

        for (const chipName in data) {
            const chip = data[chipName]
            for (const featureName in chip) {
                const feature = chip[featureName]
                if (typeof feature !== "object" || feature === null) continue
                const lname = featureName.toLowerCase()

                if (temp === null && (lname.includes("tctl") || lname.includes("tdie") || lname.includes("package"))) {
                    for (const key in feature) {
                        if (key.includes("_input")) { temp = feature[key]; break }
                    }
                }

                if (lname.startsWith("fan")) {
                    for (const key in feature) {
                        if (key.includes("_input")) {
                            fanList.push({ name: featureName, rpm: feature[key] })
                            break
                        }
                    }
                }
            }
        }

        if (temp !== null) root.cpuTempC = temp
        root.fans = fanList
    }

    // ── DISKS ──────────────────────────────────────────────────
    Process {
        id: diskProc
        // -x filters out the pseudo-filesystems by type, which is more robust
        // than prefix matching alone.
        command: ["bash", "-c",
            "df -B1 -x tmpfs -x devtmpfs -x efivarfs --output=target,size,used | tail -n +2"]
        stdout: StdioCollector {
            onStreamFinished: root._sampleDisks(this.text)
        }
    }

    function _sampleDisks(text) {
        if (!text) return
        const skipPrefixes = ["/dev", "/proc", "/sys", "/run", "/boot"]
        const list = []

        for (const rawLine of text.trim().split("\n")) {
            const parts = rawLine.trim().split(/\s+/)
            if (parts.length < 3) continue
            const target = parts[0]
            const size = Number(parts[1])
            const used = Number(parts[2])
            if (!size || skipPrefixes.some(p => target.startsWith(p))) continue

            list.push({
                mount: target,
                sizeBytes: size,
                usedBytes: used,
                usage: size > 0 ? used / size : 0
            })
        }

        root.disks = list
    }

    // ── PROCESSES ──────────────────────────────────────────────
    property var _prevProcCpu: ({})
    property real _prevProcTotal: 0

    readonly property int _pageSizeBytes: 4096

    Process {
        id: processProc
        command: ["bash", "-c",
            "head -n1 /proc/stat | awk '{s=0; for(i=2;i<=8;i++) s+=$i; print \"T\", s}'; " +
            "awk '{ n=split($0, a, \")\"); split(a[n], b, \" \"); " +
            "name=$0; sub(/^[0-9]+ \\(/, \"\", name); sub(/\\)[^)]*$/, \"\", name); " +
            "print $1, b[12]+b[13], b[22], name }' /proc/[0-9]*/stat 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root._sampleProcesses(this.text)
        }
    }

    function _sampleProcesses(text) {
        if (!text) return

        const lines = text.trim().split("\n")
        if (lines.length < 2) return

        // First line is the total jiffies across all CPUs.
        const totalParts = lines[0].trim().split(/\s+/)
        if (totalParts[0] !== "T") return
        const total = Number(totalParts[1])

        const cur = {}
        const raw = []

        for (let i = 1; i < lines.length; i++) {
            const parts = lines[i].trim().split(/\s+/)
            if (parts.length < 4) continue

            const pid = Number(parts[0])
            const jiffies = Number(parts[1])
            const rssPages = Number(parts[2])
            const name = parts.slice(3).join(" ")
            if (!pid) continue

            cur[pid] = jiffies
            raw.push({ pid: pid, name: name, jiffies: jiffies, rssPages: rssPages })
        }

        const totalDelta = total - root._prevProcTotal
        root._prevProcTotal = total

        // First sample has nothing to diff against; wait one tick.
        if (totalDelta <= 0 || Object.keys(root._prevProcCpu).length === 0) {
            root._prevProcCpu = cur
            return
        }

        const cores = Math.max(1, root.perCore.length)
        const memTotalBytes = root.memTotalKb * 1024
        const list = []

        for (const p of raw) {
            const prev = root._prevProcCpu[p.pid]
            // A pid seen for the first time (or reused) has no baseline.
            const delta = (prev === undefined) ? 0 : Math.max(0, p.jiffies - prev)

            list.push({
                pid: p.pid,
                name: p.name,
                cpu: (delta / totalDelta) * cores * 100,
                mem: memTotalBytes > 0
                    ? (p.rssPages * root._pageSizeBytes / memTotalBytes) * 100
                    : 0
            })
        }

        list.sort((a, b) => b.cpu - a.cpu)

        root._prevProcCpu = cur
        root.processes = list.slice(0, 60)
    }

    // ── ACTIONS ────────────────────────────────────────────────
    signal killFailed(int pid, string message)

    property int _killPid: 0

    function killProcess(pid) {
        root._killPid = pid
        killProc.command = ["kill", String(pid)]
        killProc.running = true
        refreshAfterKillTimer.restart()
    }

    Process {
        id: killProc
        command: []
        stderr: StdioCollector {
            onStreamFinished: {
                const msg = (this.text || "").trim()
                if (msg !== "") root.killFailed(root._killPid, msg)
            }
        }
    }

    Timer {
        id: refreshAfterKillTimer
        interval: 300
        onTriggered: if (root.processPollActive) processProc.running = true
    }
}
