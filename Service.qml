import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs.Commons
import "Policy.js" as Policy

// Applies the active-source idle policy. Screensaver and lock stay with
// first-party omarchy.idle via shell.json; this service only adds screen-off
// and suspend, gated on AC vs battery and stay-awake.
Item {
    id: root

    property var shell: null
    property var policy: Policy.defaults()
    property bool stayAwake: false
    property bool screenOffByUs: false
    property bool patchPending: false
    property bool profileApplyPending: false
    property string lastProfileSource: ""

    readonly property bool batteryPresent: !!(UPower.displayDevice && UPower.displayDevice.isPresent)
    readonly property bool onBattery: !!(batteryPresent && UPower.onBattery)
    readonly property string activeSource: onBattery ? "battery" : "ac"
    readonly property var activeIdle: Policy.sourceIdle(policy, activeSource)
    readonly property int screenOffSeconds: Policy.isNever(activeIdle.screenOff) ? 0 : Number(activeIdle.screenOff)
    readonly property int suspendSeconds: Policy.isNever(activeIdle.suspend) ? 0 : Number(activeIdle.suspend)
    readonly property bool idleAllowed: !stayAwake

    function applyPolicyText(text) {
        root.policy = Policy.parsePolicyText(text)
        root.scheduleShellIdlePatch()
    }

    function refreshStayAwake() {
        if (!stayAwakeProbe.running) stayAwakeProbe.running = true
    }

    function scheduleShellIdlePatch() {
        patchTimer.restart()
    }

    function patchShellIdle() {
        if (patchProc.running) {
            root.patchPending = true
            return
        }
        var idle = root.activeIdle
        patchProc.command = Policy.patchShellIdleCommand(idle.screensaver, idle.lock)
        patchProc.running = true
    }

    function dpmsOff() {
        if (dpmsOffProc.running) return
        root.screenOffByUs = true
        dpmsOffProc.running = true
    }

    function dpmsOn() {
        if (!root.screenOffByUs) return
        if (dpmsOnProc.running) return
        root.screenOffByUs = false
        dpmsOnProc.running = true
    }

    function suspendNow() {
        if (suspendProc.running) return
        suspendProc.running = true
    }

    function applyActiveProfile() {
        if (profileApplyProc.running) {
            root.profileApplyPending = true
            return
        }
        var name = Policy.sourceProfile(root.policy, root.activeSource)
        profileApplyProc.command = Policy.setProfileCommand(root.activeSource, name)
        profileApplyProc.running = true
    }

    onActiveSourceChanged: {
        if (root.lastProfileSource === "") {
            root.lastProfileSource = root.activeSource
            return
        }
        if (root.lastProfileSource === root.activeSource) return
        root.lastProfileSource = root.activeSource
        root.applyActiveProfile()
        root.scheduleShellIdlePatch()
    }
    onStayAwakeChanged: if (stayAwake) root.dpmsOn()

    FileView {
        id: policyFile
        path: Quickshell.env("HOME") + "/.config/omarchy/power-idle.json"
        watchChanges: true
        printErrors: false
        onLoaded: root.applyPolicyText(text)
        onFileChanged: reload()
    }

    FileView {
        id: stayAwakeDir
        path: Quickshell.env("HOME") + "/.local/state/omarchy/indicators"
        watchChanges: true
        printErrors: false
        onFileChanged: root.refreshStayAwake()
    }

    Process {
        id: stayAwakeProbe
        command: ["bash", "-c", "if [[ -f \"$HOME/.local/state/omarchy/indicators/stay-awake\" ]]; then echo yes; else echo no; fi"]
        stdout: SplitParser {
            onRead: function(line) { root.stayAwake = String(line).trim() === "yes" }
        }
    }

    Process {
        id: patchProc
        onExited: {
            if (!reloadProc.running) reloadProc.running = true
            if (root.patchPending) {
                root.patchPending = false
                root.patchShellIdle()
            }
        }
    }

    Process {
        id: profileApplyProc
        onExited: {
            if (root.profileApplyPending) {
                root.profileApplyPending = false
                root.applyActiveProfile()
            }
        }
    }

    Process {
        id: reloadProc
        command: Policy.reloadConfigCommand()
    }

    Process {
        id: dpmsOffProc
        command: ["hyprctl", "dispatch", "dpms", "off"]
    }

    Process {
        id: dpmsOnProc
        command: ["bash", "-lc", "hyprctl dispatch dpms on >/dev/null 2>&1; omarchy-system-wake >/dev/null 2>&1 || true"]
    }

    Process {
        id: suspendProc
        command: ["systemctl", "suspend"]
    }

    Timer {
        id: patchTimer
        interval: 250
        repeat: false
        onTriggered: root.patchShellIdle()
    }

    IdleMonitor {
        id: screenOffMonitor
        enabled: root.idleAllowed && root.screenOffSeconds > 0
        timeout: Math.max(1, root.screenOffSeconds)
        respectInhibitors: true
        onIsIdleChanged: {
            if (!root.idleAllowed) return
            if (isIdle) root.dpmsOff()
            else root.dpmsOn()
        }
    }

    IdleMonitor {
        id: suspendMonitor
        enabled: root.idleAllowed && root.suspendSeconds > 0
        timeout: Math.max(1, root.suspendSeconds)
        respectInhibitors: true
        onIsIdleChanged: {
            if (!root.idleAllowed) return
            if (isIdle) root.suspendNow()
        }
    }

    Component.onCompleted: {
        root.refreshStayAwake()
        policyFile.reload()
    }
}
