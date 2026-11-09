import qs
import qs.components
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// App launcher with prefix modes:
//   =  calculator (qalc)      :  emoji picker        ?  web search
//   >  run a command          /  find files (fd)
// Enter runs the selected row; Shift+Enter is the alternative action where a
// mode has one (run in a terminal, open the containing folder).
BaseExpandPopup {
    id: launcher

    ipcTarget: "launcher"
    placeholder: "Search apps   ·   = calc   : emoji   ? web   > run   / files"

    implicitWidth: 480
    implicitHeight: Math.min(600, 74 + Math.max(1, results.length) * 50)

    searchHeight: 44
    columnSpacing: 8
    searchFontSize: 14
    searchIconSize: 16

    minIndex: appsList.minIndex
    maxIndex: appsList.maxIndex

    readonly property string terminal: Quickshell.env("TERMINAL") || "alacritty"
    readonly property string home: Quickshell.env("HOME")
    // %s is replaced by the URL-encoded query
    property string webSearchUrl: "https://duckduckgo.com/?q=%s"

    // ── MODE ───────────────────────────────────────────────────
    readonly property var modes: ({ "=": "calc", ":": "emoji", "?": "web", ">": "run", "/": "files" })
    readonly property string mode: modes[searchText.charAt(0)] ?? "apps"
    readonly property string arg: (mode === "apps" ? searchText : searchText.slice(1)).trim()

    // Derive the mode from the new text itself: inside this handler the `mode`
    // binding may not have re-evaluated yet
    onSearchEdited: (text) => {
        selectedIndex = 0
        const m = modes[text.charAt(0)] ?? "apps"
        if (m === "calc") calcDebounce.restart()
        else if (m === "files") filesDebounce.restart()
        else if (m === "emoji") emojiFile.wanted = true
    }

    // Row shape: { title, subtitle, icon?, glyph?, emoji?, run?, alt? }
    // Rows without `run` are informational (hints, errors) and ignore Enter.
    readonly property var results: {
        switch (mode) {
        case "calc": return calcRows()
        case "emoji": return emojiRows()
        case "web": return webRows()
        case "run": return runRows()
        case "files": return fileRows()
        default: return appRows()
        }
    }

    // Open straight into a mode, e.g. `qs -c bar ipc call launcherquery open ":"`
    IpcHandler {
        target: "launcherquery"
        function open(text: string): void {
            launcher.open()
            launcher.searchText = text
        }
    }

    onAccepted: (index) => launcher.activate(results[index], false)
    onPlayRequested: (index) => launcher.activate(results[index], true)

    function activate(row, alt) {
        if (!row) return
        const fn = alt && row.alt ? row.alt : row.run
        if (!fn) return
        fn()
        close()
    }

    function hint(title, subtitle) {
        return [{ title: title, subtitle: subtitle || "", glyph: "󰋽" }]
    }

    // Launched through `uwsm app` so each app gets its own systemd scope in the
    // uwsm session instead of running as a child of the shell
    function spawn(cmd, workingDirectory) {
        Quickshell.execDetached({
            command: ["uwsm", "app", "--"].concat(cmd),
            workingDirectory: workingDirectory || launcher.home
        })
    }

    function copy(text, what) {
        Quickshell.execDetached(["wl-copy", "--", text])
        Quickshell.execDetached(["notify-send", "--transient", "-a", "Launcher", "-t", "2000",
            "Copied " + (what || text)])
    }

    // ── TOOL AVAILABILITY ──────────────────────────────────────
    // Re-checked on every open, so tools installed mid-session show up
    property var tools: ({})
    onOpened: {
        toolCheck.running = true
        if (emojiFile.missing) {
            emojiFile.missing = false
            emojiFile.reload()
        }
    }
    Process {
        id: toolCheck
        command: ["sh", "-c", "for c in qalc fd; do command -v $c >/dev/null && echo $c; done"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const t = {}
                for (const c of text.split("\n")) if (c) t[c] = true
                launcher.tools = t
            }
        }
    }

    // ── APPS ───────────────────────────────────────────────────
    readonly property var allApps: DesktopEntries.applications.values

    function appRows() {
        const q = arg.toLowerCase()
        let apps = allApps.filter(app => app.name)
        if (q !== "") {
            const score = app => {
                const name = app.name.toLowerCase()
                if (name.startsWith(q)) return 0
                if (name.includes(q)) return 1
                const extra = [app.genericName || "", (app.keywords || []).join(" ")].join(" ").toLowerCase()
                return extra.includes(q) ? 2 : -1
            }
            apps = apps.map(a => ({ a: a, s: score(a) }))
                .filter(x => x.s >= 0)
                .sort((x, y) => x.s - y.s || x.a.name.localeCompare(y.a.name))
                .map(x => x.a)
        } else {
            apps = apps.slice().sort((a, b) => a.name.localeCompare(b.name))
        }
        return apps.map(app => ({
            title: app.name,
            subtitle: app.genericName || app.comment || "",
            icon: app.icon,
            run: () => launcher.spawn(app.runInTerminal
                ? [launcher.terminal, "-e"].concat(app.command)
                : app.command, app.workingDirectory)
        }))
    }

    // ── CALCULATOR ─────────────────────────────────────────────
    property string calcResult: ""

    Timer {
        id: calcDebounce
        interval: 120
        onTriggered: calc.request(launcher.arg)
    }

    Process {
        id: calc
        property string pending: ""
        property bool hasPending: false

        function request(expr) {
            if (expr === "" || !launcher.tools.qalc) { launcher.calcResult = ""; return }
            if (running) { pending = expr; hasPending = true; return }
            command = ["qalc", "-t", launcher.decimalUnits(expr)]
            running = true
        }

        onRunningChanged: if (!running && hasPending) {
            hasPending = false
            Qt.callLater(() => calc.request(pending))
        }

        stdout: StdioCollector {
            onStreamFinished: launcher.calcResult = text.trim()
        }
    }

    // "5 km to mi" -> "5 km to -mi": the leading "-" makes qalc answer
    // 3.106855961 mi instead of "3 mi + 188 yd + 2.39 in". Number-base and
    // other non-unit targets are left alone.
    readonly property var calcKeywords: ["bin", "binary", "oct", "octal", "dec", "decimal", "duo",
        "hex", "hexadecimal", "base", "optimal", "fraction", "fractions", "mixed", "sexa",
        "time", "utc", "roman", "bijective", "factors", "partial", "prefix", "calendars", "bases"]

    function decimalUnits(expr) {
        return expr.replace(/(\s(?:to|->)\s+)([A-Za-z][\w\/^*]*)/i, (m, sep, target) =>
            launcher.calcKeywords.includes(target.toLowerCase()) ? m : sep + "-" + target)
    }

    function calcRows() {
        if (!tools.qalc) return hint("Calculator needs qalc", "Install the libqalculate package")
        if (arg === "") return hint("Type an expression", "Units and conversions work too: 5 km to mi, 20% of 340")
        if (calcResult === "") return hint("…")
        const result = calcResult
        return [{
            title: result,
            subtitle: arg + "  ·  Enter to copy",
            glyph: "󰃬",
            run: () => launcher.copy(result)
        }]
    }

    // ── EMOJI ──────────────────────────────────────────────────
    property var emojis: []

    FileView {
        id: emojiFile
        // Only read the (large) list once the emoji mode is first used
        property bool wanted: false
        path: wanted ? "/usr/share/unicode/emoji/emoji-test.txt" : ""
        property bool missing: false
        onLoaded: launcher.emojis = launcher.parseEmoji(text())
        onLoadFailed: missing = true
    }

    function parseEmoji(text) {
        const out = []
        let group = ""
        const re = /^[0-9A-F ]+;\s*fully-qualified\s*#\s*(\S+)\s+E[\d.]+\s+(.+)$/
        for (const line of text.split("\n")) {
            if (line.startsWith("# subgroup:")) { group = line.slice(11).trim(); continue }
            const m = re.exec(line)
            if (m) out.push({ e: m[1], name: m[2], search: (m[2] + " " + group).toLowerCase() })
        }
        return out
    }

    function emojiRows() {
        if (emojiFile.missing)
            return hint("Emoji list not found", "Install the unicode-emoji package")
        if (emojis.length === 0) return hint("…")
        const q = arg.toLowerCase()
        const matches = q === "" ? emojis : emojis.filter(x => x.search.includes(q))
        return matches.slice(0, 80).map(x => ({
            title: x.name,
            subtitle: "Enter to copy",
            glyph: x.e,
            emoji: true,
            run: () => launcher.copy(x.e, x.e + " " + x.name)
        }))
    }

    // ── WEB ────────────────────────────────────────────────────
    function webRows() {
        if (arg === "") return hint("Search the web", "Type a query, then Enter")
        const q = arg
        return [{
            title: "Search for “" + q + "”",
            subtitle: launcher.webSearchUrl.split("/")[2],
            glyph: "󰖟",
            run: () => launcher.spawn(["xdg-open", launcher.webSearchUrl.replace("%s", encodeURIComponent(q))])
        }]
    }

    // ── RUN ────────────────────────────────────────────────────
    function runRows() {
        if (arg === "") return hint("Run a command", "Enter runs it in the background, Shift+Enter in a terminal")
        const cmd = arg
        return [{
            title: cmd,
            subtitle: "Enter: run  ·  Shift+Enter: run in terminal",
            glyph: "󰆍",
            run: () => launcher.spawn(["sh", "-c", cmd]),
            alt: () => launcher.spawn([launcher.terminal, "--hold", "-e", "sh", "-c", cmd])
        }]
    }

    // ── FILES ──────────────────────────────────────────────────
    property var fileResults: []

    Timer {
        id: filesDebounce
        interval: 200
        onTriggered: files.request(launcher.arg)
    }

    Process {
        id: files
        property string pending: ""
        property bool hasPending: false

        function request(q) {
            if (q.length < 2 || !launcher.tools.fd) { launcher.fileResults = []; return }
            if (running) { pending = q; hasPending = true; return }
            // fd skips hidden and gitignored files by default
            command = ["fd", "--max-results", "40", "--ignore-case", "--", q, launcher.home]
            running = true
        }

        onRunningChanged: if (!running && hasPending) {
            hasPending = false
            Qt.callLater(() => files.request(pending))
        }

        stdout: StdioCollector {
            onStreamFinished: launcher.fileResults = text.split("\n").filter(l => l !== "")
        }
    }

    function fileRows() {
        if (!tools.fd) return hint("File search needs fd", "Install the fd package")
        if (arg.length < 2) return hint("Find files in your home folder", "Enter opens, Shift+Enter opens the folder")
        if (fileResults.length === 0) return hint("No matches")
        return fileResults.map(path => {
            const isDir = path.endsWith("/")
            const clean = isDir ? path.slice(0, -1) : path
            const slash = clean.lastIndexOf("/")
            const dir = clean.slice(0, slash)
            return {
                title: clean.slice(slash + 1),
                subtitle: dir.replace(launcher.home, "~"),
                glyph: isDir ? "󰉋" : "󰈔",
                run: () => launcher.spawn(["xdg-open", clean]),
                alt: () => launcher.spawn(["xdg-open", dir])
            }
        })
    }

    function resolveIcon(name) {
        if (!name) return ""
        const primary = Quickshell.iconPath(name, true)
        if (primary !== "") return primary
        return Quickshell.iconPath("application-x-executable", true)
    }

    SelectableListView {
        id: appsList
        anchors.fill: parent
        model: launcher.results
        rowHeight: 48
        emptyText: launcher.mode === "apps" ? "No matching apps" : ""

        onSelectedIndexChanged: if (launcher.selectedIndex !== selectedIndex) launcher.selectedIndex = selectedIndex
        Connections {
            target: launcher
            function onSelectedIndexChanged() {
                if (appsList.selectedIndex !== launcher.selectedIndex) appsList.selectedIndex = launcher.selectedIndex
            }
        }

        delegate: Component {
            RowLayout {
                id: row
                property var modelData
                property int index
                property bool selected: false

                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                spacing: 12

                Item {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28

                    IconImage {
                        anchors.fill: parent
                        visible: !!row.modelData?.icon
                        source: launcher.resolveIcon(row.modelData?.icon)
                        implicitSize: 28
                        asynchronous: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !row.modelData?.icon
                        text: row.modelData?.glyph ?? ""
                        color: row.selected ? Theme.background : Theme.hexToRgba(Theme.foreground, 0.8)
                        font.pixelSize: row.modelData?.emoji ? 22 : 18
                        font.family: row.modelData?.emoji ? "Noto Color Emoji" : "Symbols Nerd Font"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: row.modelData?.title ?? ""
                        color: row.selected ? Theme.background : Theme.foreground
                        font.pixelSize: 13
                        font.bold: row.selected
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: row.modelData?.subtitle ?? ""
                        color: row.selected
                            ? Theme.hexToRgba(Theme.background, 0.7)
                            : Theme.hexToRgba(Theme.foreground, 0.5)
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                        visible: text !== ""
                    }
                }

                TapHandler {
                    onTapped: launcher.activate(row.modelData, false)
                }
            }
        }
    }
}
