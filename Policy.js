.pragma library

var PLUGIN_ID = "io.github.rustyoz.power-idle"
var NEVER_SHELL_SECONDS = 8640000
var PROFILE_FALLBACK = ["power-saver", "balanced", "performance"]

var TIMEOUTS = [
    { label: "Never", seconds: null },
    { label: "1 minute", seconds: 60 },
    { label: "2 minutes", seconds: 120 },
    { label: "5 minutes", seconds: 300 },
    { label: "10 minutes", seconds: 600 },
    { label: "15 minutes", seconds: 900 },
    { label: "20 minutes", seconds: 1200 },
    { label: "30 minutes", seconds: 1800 },
    { label: "1 hour", seconds: 3600 }
]

function defaults() {
    return {
        profiles: { ac: "performance", battery: "balanced" },
        idle: {
            ac: { screensaver: 3600, screenOff: null, lock: null, suspend: null },
            battery: { screensaver: 900, screenOff: 1200, lock: 900, suspend: 1800 }
        }
    }
}

function clone(value) {
    return JSON.parse(JSON.stringify(value))
}

function isNever(value) {
    return value === null || value === undefined
}

function timeoutLabels() {
    var labels = []
    for (var i = 0; i < TIMEOUTS.length; i++) labels.push(TIMEOUTS[i].label)
    return labels
}

function secondsAt(index) {
    if (index < 0 || index >= TIMEOUTS.length) return null
    return TIMEOUTS[index].seconds
}

function indexForSeconds(seconds) {
    if (isNever(seconds)) return 0
    var n = Number(seconds)
    for (var i = 1; i < TIMEOUTS.length; i++) {
        if (TIMEOUTS[i].seconds === n) return i
    }
    var best = 0
    var bestDelta = Infinity
    for (var j = 0; j < TIMEOUTS.length; j++) {
        if (isNever(TIMEOUTS[j].seconds)) continue
        var delta = Math.abs(TIMEOUTS[j].seconds - n)
        if (delta < bestDelta) {
            bestDelta = delta
            best = j
        }
    }
    return best
}

function labelForSeconds(seconds) {
    return TIMEOUTS[indexForSeconds(seconds)].label
}

function shellIdleSeconds(value) {
    if (isNever(value) || Number(value) <= 0) return NEVER_SHELL_SECONDS
    return Number(value)
}

function normalizeTimeout(value) {
    if (isNever(value)) return null
    var n = Number(value)
    if (!isFinite(n) || n <= 0) return null
    return Math.round(n)
}

function normalizeProfile(name) {
    var text = String(name || "").trim().toLowerCase()
    if (text === "power-saver" || text === "powersaver" || text === "power_saver") return "power-saver"
    if (text === "balanced") return "balanced"
    if (text === "performance") return "performance"
    return ""
}

function mergeSource(raw, fallback) {
    var src = (raw && typeof raw === "object") ? raw : {}
    return {
        screensaver: normalizeTimeout(src.screensaver !== undefined ? src.screensaver : fallback.screensaver),
        screenOff: normalizeTimeout(src.screenOff !== undefined ? src.screenOff : fallback.screenOff),
        lock: normalizeTimeout(src.lock !== undefined ? src.lock : fallback.lock),
        suspend: normalizeTimeout(src.suspend !== undefined ? src.suspend : fallback.suspend)
    }
}

function merge(raw) {
    var base = defaults()
    var data = (raw && typeof raw === "object") ? raw : {}
    var profiles = (data.profiles && typeof data.profiles === "object") ? data.profiles : {}
    var idle = (data.idle && typeof data.idle === "object") ? data.idle : {}
    var acProfile = normalizeProfile(profiles.ac) || base.profiles.ac
    var batteryProfile = normalizeProfile(profiles.battery) || base.profiles.battery
    return {
        profiles: { ac: acProfile, battery: batteryProfile },
        idle: {
            ac: mergeSource(idle.ac, base.idle.ac),
            battery: mergeSource(idle.battery, base.idle.battery)
        }
    }
}

function parsePolicyText(text) {
    var trimmed = String(text || "").trim()
    if (!trimmed) return defaults()
    try {
        return merge(JSON.parse(trimmed))
    } catch (e) {
        return defaults()
    }
}

function policyJson(policy) {
    return JSON.stringify(merge(policy), null, 2) + "\n"
}

function hexEncode(text) {
    var out = ""
    var str = String(text || "")
    for (var i = 0; i < str.length; i++) {
        var h = str.charCodeAt(i).toString(16)
        if (h.length < 2) h = "0" + h
        out += h
    }
    return out
}

function writePolicyCommand(policy) {
    return [
        "python3",
        "-c",
        "import pathlib,sys\n"
        + "p=pathlib.Path.home()/'.config/omarchy'\n"
        + "p.mkdir(parents=True, exist_ok=True)\n"
        + "(p/'power-idle.json').write_text(bytes.fromhex(sys.argv[1]).decode(), encoding='utf-8')\n",
        hexEncode(policyJson(policy))
    ]
}

function patchShellIdleCommand(screensaver, lock) {
    return [
        "python3",
        "-c",
        "import json,os,pathlib,sys\n"
        + "home=pathlib.Path.home()\n"
        + "cfg=home/'.config/omarchy'\n"
        + "cfg.mkdir(parents=True, exist_ok=True)\n"
        + "path=cfg/'shell.json'\n"
        + "screensaver=int(sys.argv[1]); lock=int(sys.argv[2])\n"
        + "candidates=[]\n"
        + "om=os.environ.get('OMARCHY_PATH')\n"
        + "if om: candidates.append(pathlib.Path(om)/'config/omarchy/shell.json')\n"
        + "candidates += [pathlib.Path('/usr/share/omarchy/config/omarchy/shell.json'), home/'.local/share/omarchy/config/omarchy/shell.json']\n"
        + "data={'version':1}\n"
        + "if path.exists():\n"
        + "    data=json.loads(path.read_text(encoding='utf-8'))\n"
        + "else:\n"
        + "    for c in candidates:\n"
        + "        if c.is_file():\n"
        + "            data=json.loads(c.read_text(encoding='utf-8'))\n"
        + "            break\n"
        + "if not isinstance(data, dict): data={'version':1}\n"
        + "data.setdefault('version', 1)\n"
        + "idle=data.get('idle') if isinstance(data.get('idle'), dict) else {}\n"
        + "idle['screensaver']=screensaver\n"
        + "idle['lock']=lock\n"
        + "data['idle']=idle\n"
        + "tmp=path.with_suffix('.json.tmp')\n"
        + "tmp.write_text(json.dumps(data, indent=2)+'\\n', encoding='utf-8')\n"
        + "tmp.replace(path)\n",
        String(shellIdleSeconds(screensaver)),
        String(shellIdleSeconds(lock))
    ]
}

function reloadConfigCommand() {
    return ["bash", "-lc", "omarchy-shell shell reloadConfig >/dev/null 2>&1 || true"]
}

function setProfileCommand(source, profile) {
    var src = source === "battery" ? "battery" : "ac"
    var name = normalizeProfile(profile) || "balanced"
    return [
        "bash",
        "-lc",
        "omarchy-powerprofiles-set " + src + " " + name
        + " 2>/dev/null || omarchy powerprofiles set " + src + " " + name
    ]
}

function parseProfiles(raw) {
    var text = String(raw || "")
    var found = []
    var seen = {}
    var lines = text.split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/^\s*\*\s*/, "").trim().toLowerCase()
        line = line.replace(/[:*,].*$/, "").trim()
        var name = normalizeProfile(line)
        if (!name || seen[name]) continue
        seen[name] = true
        found.push(name)
    }
    if (found.length === 0) found = PROFILE_FALLBACK.slice()
    return found
}

function profileLabel(name) {
    var n = normalizeProfile(name)
    if (n === "power-saver") return "Saver"
    if (n === "balanced") return "Balanced"
    if (n === "performance") return "Perf"
    return name
}

function sourceIdle(policy, source) {
    var merged = merge(policy)
    return source === "battery" ? merged.idle.battery : merged.idle.ac
}

function sourceProfile(policy, source) {
    var merged = merge(policy)
    return source === "battery" ? merged.profiles.battery : merged.profiles.ac
}

function withTimeout(policy, source, field, seconds) {
    var next = merge(policy)
    var key = source === "battery" ? "battery" : "ac"
    next.idle[key][field] = normalizeTimeout(seconds)
    return next
}

function withProfile(policy, source, profile) {
    var next = merge(policy)
    var key = source === "battery" ? "battery" : "ac"
    next.profiles[key] = normalizeProfile(profile) || next.profiles[key]
    return next
}
