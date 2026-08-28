import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Policy.js" as Policy

Panel {
    id: root
    moduleName: Policy.PLUGIN_ID
    ipcTarget: "io.github.rustyoz.power-idle"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root

    property var policy: Policy.defaults()
    property var profiles: Policy.PROFILE_FALLBACK.slice()
    property string acProfile: Policy.defaults().profiles.ac
    property string batteryProfile: Policy.defaults().profiles.battery
    property bool stayAwake: false
    property bool policyLoaded: false
    property bool pendingWrite: false
    property var pendingProfileCommand: null
    property var pendingRememberCommand: null
    property int ignorePolicyReloads: 0
    property string savedJson: ""

    readonly property bool dirty: Policy.idleDirty(root.policy, root.savedJson)

    readonly property color contentForeground: bar ? bar.foreground : Color.foreground
    readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property bool batteryPresent: !!(UPower.displayDevice && UPower.displayDevice.isPresent)
    readonly property bool onBattery: !!(batteryPresent && UPower.onBattery)
    readonly property string activeSource: onBattery ? "battery" : "ac"
    readonly property real batteryFraction: {
        var device = UPower.displayDevice
        if (!device || !device.isPresent) return 0
        var pct = device.percentage
        if (pct === undefined || pct === null) return 0
        return pct > 1 ? Math.min(1, pct / 100) : Math.max(0, Math.min(1, pct))
    }
    readonly property string batteryPercentLabel: batteryPresent ? (Math.round(batteryFraction * 100) + "%") : "AC"
    readonly property string sourceLabel: onBattery ? "On battery" : "Plugged in"
    readonly property string activeProfileLabel: Policy.profileLabel(root.activeSource === "battery" ? root.batteryProfile : root.acProfile)

    function open() {
        root.controller.show()
    }

    function close() {
        root.controller.hide()
    }

    function toggle() {
        if (root.opened) root.close()
        else root.open()
    }

    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.barIdentity, direction)
        return false
    }

    function applyPolicyText(text) {
        if (root.ignorePolicyReloads > 0) return
        applyPolicyObject(Policy.parsePolicyText(text))
        root.savedJson = Policy.policyJson(root.policy)
        root.policyLoaded = true
    }

    function applyPolicyObject(next) {
        root.policy = Policy.merge(next)
        root.acProfile = root.policy.profiles.ac
        root.batteryProfile = root.policy.profiles.battery
    }

    function startPolicyWrite() {
        root.ignorePolicyReloads += 1
        writePolicyProc.command = Policy.writePolicyCommand(root.policy)
        writePolicyProc.running = true
    }

    function setTimeoutValue(source, field, seconds) {
        applyPolicyObject(Policy.withTimeout(root.policy, source, field, seconds))
    }

    function selectProfile(source, profile) {
        applyPolicyObject(Policy.withProfile(root.policy, source, profile))
        if (root.dirty) applySavedProfiles()
        else saveSettings()
    }

    function setSourceProfile(source, profile) {
        selectProfile(source, profile)
        saveSettings()
    }

    function saveSettings() {
        root.savedJson = Policy.policyJson(root.policy)
        if (writePolicyProc.running) root.pendingWrite = true
        else startPolicyWrite()
        applySavedProfiles()
    }

    function applySavedProfiles() {
        var activeName = root.activeSource === "battery" ? root.batteryProfile : root.acProfile
        var cmd = Policy.setProfileCommand(root.activeSource, activeName)
        if (root.batteryPresent) {
            var other = root.activeSource === "battery" ? "ac" : "battery"
            var otherName = other === "battery" ? root.batteryProfile : root.acProfile
            root.pendingRememberCommand = Policy.rememberProfileCommand(other, otherName)
        } else {
            root.pendingRememberCommand = null
        }
        if (profileProc.running) {
            root.pendingProfileCommand = cmd
            return
        }
        profileProc.command = cmd
        profileProc.running = true
    }

    function notifyPowerWidget() {
        if (!root.bar || typeof root.bar.moduleWidgets !== "function") return
        var items = root.bar.moduleWidgets("omarchy.power")
        for (var i = 0; i < items.length; i++) {
            if (items[i] && typeof items[i].refresh === "function") items[i].refresh()
        }
    }

    function refreshStayAwake() {
        if (!stayAwakeProbe.running) stayAwakeProbe.running = true
    }

    function toggleStayAwake() {
        if (!stayAwakeToggle.running) stayAwakeToggle.running = true
    }

    function refreshProfiles() {
        if (!profilesListProc.running) profilesListProc.running = true
    }

    onOpenedChanged: {
        if (opened) {
            refreshStayAwake()
            refreshProfiles()
        }
    }

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
        id: stayAwakeToggle
        command: ["omarchy", "toggle", "idle"]
        onExited: root.refreshStayAwake()
    }

    Process {
        id: writePolicyProc
        onExited: {
            Qt.callLater(function() {
                if (root.pendingWrite) {
                    root.pendingWrite = false
                    writePolicyProc.command = Policy.writePolicyCommand(root.policy)
                    writePolicyProc.running = true
                    return
                }
                root.ignorePolicyReloads = Math.max(0, root.ignorePolicyReloads - 1)
            })
        }
    }

    Process {
        id: profileProc
        onExited: {
            root.notifyPowerWidget()
            root.refreshProfiles()
            if (root.pendingProfileCommand) {
                profileProc.command = root.pendingProfileCommand
                root.pendingProfileCommand = null
                profileProc.running = true
                return
            }
            if (root.pendingRememberCommand && !rememberProc.running) {
                rememberProc.command = root.pendingRememberCommand
                root.pendingRememberCommand = null
                rememberProc.running = true
            }
        }
    }

    Process {
        id: rememberProc
    }

    Process {
        id: profilesListProc
        command: ["omarchy-powerprofiles-list", "--active-state"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var next = Policy.parseProfiles(text)
                if (next.profiles && next.profiles.length > 0) root.profiles = next.profiles
            }
        }
    }

    Component.onCompleted: {
        refreshStayAwake()
        refreshProfiles()
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(root.batteryPresent ? 620 : 320))
        contentHeight: panel.fittedContentHeight(column.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function(direction) { root.switchPanel(direction) }

            Column {
                id: column
                width: parent.width
                spacing: Style.space(14)

                Row {
                    width: parent.width
                    spacing: Style.space(12)

                    Column {
                        width: parent.width - stayAwakeButton.width - saveButton.width - parent.spacing * 2
                        spacing: Style.space(2)

                        Text {
                            text: "Power settings"
                            color: root.contentForeground
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.title
                            font.bold: true
                        }

                        Text {
                            text: root.batteryPresent
                                ? (root.sourceLabel + " · " + root.batteryPercentLabel + " · " + root.activeProfileLabel)
                                : ("Plugged in · " + root.activeProfileLabel)
                            color: Qt.darker(root.contentForeground, 1.4)
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            width: parent.width
                            elide: Text.ElideRight
                        }
                    }

                    Button {
                        id: saveButton
                        text: "Save"
                        fontSize: Style.font.bodySmall
                        foreground: root.contentForeground
                        fontFamily: root.contentFontFamily
                        horizontalPadding: Style.spacing.controlPaddingX
                        verticalPadding: Style.spacing.controlPaddingY
                        bordered: true
                        active: root.dirty
                        opacity: root.dirty ? 1 : 0.55
                        onClicked: if (root.dirty) root.saveSettings()
                    }

                    Button {
                        id: stayAwakeButton
                        text: root.stayAwake ? "Stay awake" : "Stay awake"
                        iconText: "\u2615"
                        iconSize: Style.font.title
                        fontSize: Style.font.bodySmall
                        foreground: root.contentForeground
                        fontFamily: root.contentFontFamily
                        horizontalPadding: Style.spacing.controlPaddingX
                        verticalPadding: Style.spacing.controlPaddingY
                        bordered: true
                        active: root.stayAwake
                        onClicked: root.toggleStayAwake()
                    }
                }

                PanelSeparator {
                    foreground: root.contentForeground
                }

                Row {
                    width: parent.width
                    spacing: Style.space(16)

                    Column {
                        id: acCol
                        clip: true
                        width: root.batteryPresent ? (parent.width - parent.spacing) / 2 : parent.width
                        spacing: Style.space(10)

                        PanelSectionHeader {
                            text: (root.batteryPresent ? "Plugged in" : "This machine").toUpperCase()
                                + (root.activeSource === "ac" ? "  ·  NOW" : "")
                            foreground: root.contentForeground
                            fontFamily: root.contentFontFamily
                        }

                        Row {
                            id: acProfileRow
                            width: parent.width
                            spacing: Style.space(6)
                            readonly property real cellWidth: root.profiles.length > 0
                                ? Math.max(1, (width - spacing * (root.profiles.length - 1)) / root.profiles.length)
                                : 0

                            Repeater {
                                model: root.profiles
                                Button {
                                    required property var modelData
                                    width: acProfileRow.cellWidth
                                    text: Policy.profileLabel(String(modelData))
                                    fontSize: Style.font.bodySmall
                                    foreground: root.contentForeground
                                    fontFamily: root.contentFontFamily
                                    horizontalPadding: Style.spacing.controlPaddingX
                                    verticalPadding: Style.spacing.controlPaddingY
                                    bordered: true
                                    active: root.acProfile === String(modelData)
                                    onClicked: root.selectProfile("ac", String(modelData))
                                }
                            }
                        }

                        TimeoutRow {
                            label: "Screensaver after"
                            seconds: Policy.idleField(root.policy, "ac", root.acProfile, "screensaver")
                            onPicked: function(value) { root.setTimeoutValue("ac", "screensaver", value) }
                        }
                        TimeoutRow {
                            label: "Turn off screen after"
                            seconds: Policy.idleField(root.policy, "ac", root.acProfile, "screenOff")
                            onPicked: function(value) { root.setTimeoutValue("ac", "screenOff", value) }
                        }
                        TimeoutRow {
                            label: "Lock after"
                            seconds: Policy.idleField(root.policy, "ac", root.acProfile, "lock")
                            onPicked: function(value) { root.setTimeoutValue("ac", "lock", value) }
                        }
                        TimeoutRow {
                            label: "Suspend after"
                            seconds: Policy.idleField(root.policy, "ac", root.acProfile, "suspend")
                            onPicked: function(value) { root.setTimeoutValue("ac", "suspend", value) }
                        }
                    }

                    Column {
                        id: batteryCol
                        clip: true
                        visible: root.batteryPresent
                        width: visible ? (parent.width - parent.spacing) / 2 : 0
                        spacing: Style.space(10)

                        PanelSectionHeader {
                            text: "ON BATTERY" + (root.activeSource === "battery" ? "  ·  NOW" : "")
                            foreground: root.contentForeground
                            fontFamily: root.contentFontFamily
                        }

                        Row {
                            id: batteryProfileRow
                            width: parent.width
                            spacing: Style.space(6)
                            readonly property real cellWidth: root.profiles.length > 0
                                ? Math.max(1, (width - spacing * (root.profiles.length - 1)) / root.profiles.length)
                                : 0

                            Repeater {
                                model: root.profiles
                                Button {
                                    required property var modelData
                                    width: batteryProfileRow.cellWidth
                                    text: Policy.profileLabel(String(modelData))
                                    fontSize: Style.font.bodySmall
                                    foreground: root.contentForeground
                                    fontFamily: root.contentFontFamily
                                    horizontalPadding: Style.spacing.controlPaddingX
                                    verticalPadding: Style.spacing.controlPaddingY
                                    bordered: true
                                    active: root.batteryProfile === String(modelData)
                                    onClicked: root.selectProfile("battery", String(modelData))
                                }
                            }
                        }

                        TimeoutRow {
                            label: "Screensaver after"
                            seconds: Policy.idleField(root.policy, "battery", root.batteryProfile, "screensaver")
                            onPicked: function(value) { root.setTimeoutValue("battery", "screensaver", value) }
                        }
                        TimeoutRow {
                            label: "Turn off screen after"
                            seconds: Policy.idleField(root.policy, "battery", root.batteryProfile, "screenOff")
                            onPicked: function(value) { root.setTimeoutValue("battery", "screenOff", value) }
                        }
                        TimeoutRow {
                            label: "Lock after"
                            seconds: Policy.idleField(root.policy, "battery", root.batteryProfile, "lock")
                            onPicked: function(value) { root.setTimeoutValue("battery", "lock", value) }
                        }
                        TimeoutRow {
                            label: "Suspend after"
                            seconds: Policy.idleField(root.policy, "battery", root.batteryProfile, "suspend")
                            onPicked: function(value) { root.setTimeoutValue("battery", "suspend", value) }
                        }
                    }
                }
            }
        }
    }

    component TimeoutRow: Column {
        id: timeoutRow
        property string label: ""
        property var seconds: null
        signal picked(var seconds)

        width: parent.width
        spacing: Style.space(4)

        Text {
            text: label
            color: root.contentForeground
            opacity: 0.7
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
        }

        ComboBox {
            id: box
            width: parent.width
            model: Policy.timeoutLabels()
            displayText: Policy.labelForSeconds(timeoutRow.seconds)
            currentIndex: Policy.indexForSeconds(timeoutRow.seconds)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            onActivated: function(index) { timeoutRow.picked(Policy.secondsAt(index)) }
        }

        onSecondsChanged: box.currentIndex = Policy.indexForSeconds(seconds)
    }
}
