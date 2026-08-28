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

function profileIdleDefaults(source, profile) {
    var name = normalizeProfile(profile) || "balanced"
    var onBattery = source === "battery"
    if (name === "power-saver") {
        return onBattery
            ? { screensaver: 300, screenOff: 600, lock: 300, suspend: 900 }
            : { screensaver: 600, screenOff: 1200, lock: 600, suspend: null }
    }
    if (name === "performance") {
        return onBattery
            ? { screensaver: 1800, screenOff: null, lock: null, suspend: null }
            : { screensaver: 3600, screenOff: null, lock: null, suspend: null }
    }
    return onBattery
        ? { screensaver: 900, screenOff: 1200, lock: 900, suspend: 1800 }
        : { screensaver: 1800, screenOff: null, lock: null, suspend: null }
}

function defaults() {
    return {
        profiles: { ac: "performance", battery: "balanced" },
        idle: {
            ac: {
                "power-saver": profileIdleDefaults("ac", "power-saver"),
                balanced: profileIdleDefaults("ac", "balanced"),
                performance: profileIdleDefaults("ac", "performance")
            },
            battery: {
                "power-saver": profileIdleDefaults("battery", "power-saver"),
                balanced: profileIdleDefaults("battery", "balanced"),
                performance: profileIdleDefaults("battery", "performance")
            }
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

function isFlatIdle(src) {
    if (!src || typeof src !== "object") return false
    return src.screensaver !== undefined || src.screenOff !== undefined
        || src.lock !== undefined || src.suspend !== undefined
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

function mergeSourceProfiles(raw, source, selectedProfile) {
    var src = (raw && typeof raw === "object") ? raw : {}
    var selected = normalizeProfile(selectedProfile) || "balanced"
    var flat = isFlatIdle(src)
    var out = {}
    for (var i = 0; i < PROFILE_FALLBACK.length; i++) {
        var name = PROFILE_FALLBACK[i]
        var fallback = profileIdleDefaults(source, name)
        if (flat && name === selected) out[name] = mergeSource(src, fallback)
        else out[name] = mergeSource(flat ? {} : src[name], fallback)
    }
    return out
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
            ac: mergeSourceProfiles(idle.ac, "ac", acProfile),
            battery: mergeSourceProfiles(idle.battery, "battery", batteryProfile)
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

function idleJson(policy) {
    return JSON.stringify(merge(policy).idle)
}

function idleDirty(policy, savedJson) {
    return idleJson(policy) !== idleJson(parsePolicyText(savedJson))
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
        "import pathlib,sys;p=pathlib.Path.home()/'.config/omarchy';p.mkdir(parents=True,exist_ok=True);(p/'power-idle.json').write_text(bytes.fromhex(sys.argv[1]).decode(),encoding='utf-8')",
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
    return ["omarchy-powerprofiles-set", src, name]
}

function rememberProfileCommand(source, profile) {
    var src = source === "battery" ? "battery" : "ac"
    var name = normalizeProfile(profile) || "balanced"
    return [
        "python3",
        "-c",
        "import os, pathlib, sys\n"
        + "src=sys.argv[1]; name=sys.argv[2]\n"
        + "base=os.environ.get('XDG_STATE_HOME')\n"
        + "d=pathlib.Path(base) if base else pathlib.Path.home()/'.local'/'state'\n"
        + "d=d/'omarchy'/'powerprofiles'\n"
        + "d.mkdir(parents=True, exist_ok=True)\n"
        + "(d/src).write_text(name+'\\n', encoding='utf-8')\n",
        src,
        name
    ]
}

function parseProfiles(raw) {
    var text = String(raw || "")
    var found = []
    var seen = {}
    var active = ""
    var lines = text.split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
        var rawLine = String(lines[i] || "")
        var starred = /^\s*\*/.test(rawLine)
        var line = rawLine.replace(/^\s*\*\s*/, "").trim()
        if (!line) continue
        var parts = line.split(/\t+/)
        var head = String(parts[0] || "").replace(/[:*,].*$/, "").trim()
        var name = normalizeProfile(head)
        if (!name || seen[name]) continue
        seen[name] = true
        found.push(name)
        if (starred || String(parts[1] || "").trim() === "1") active = name
    }
    if (found.length === 0) found = PROFILE_FALLBACK.slice()
    return { profiles: found, activeProfile: active }
}

function profileLabel(name) {
    var n = normalizeProfile(name)
    if (n === "power-saver") return "Saver"
    if (n === "balanced") return "Balanced"
    if (n === "performance") return "Perf"
    return name
}

function idleFor(policy, source, profile) {
    var merged = merge(policy)
    var key = source === "battery" ? "battery" : "ac"
    var name = normalizeProfile(profile) || merged.profiles[key]
    return merged.idle[key][name]
}

function idleField(policy, source, profile, field) {
    var idle = idleFor(policy, source, profile)
    if (!idle) return null
    return idle[field]
}

function sourceIdle(policy, source) {
    return idleFor(policy, source, sourceProfile(policy, source))
}

function sourceProfile(policy, source) {
    var merged = merge(policy)
    return source === "battery" ? merged.profiles.battery : merged.profiles.ac
}

function withTimeout(policy, source, field, seconds) {
    var next = merge(policy)
    var key = source === "battery" ? "battery" : "ac"
    var profile = next.profiles[key]
    next.idle[key][profile][field] = normalizeTimeout(seconds)
    return next
}

function withProfile(policy, source, profile) {
    var next = merge(policy)
    var key = source === "battery" ? "battery" : "ac"
    next.profiles[key] = normalizeProfile(profile) || next.profiles[key]
    return next
}
