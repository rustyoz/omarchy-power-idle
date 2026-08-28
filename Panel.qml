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
    property bool stayAwake: false
    property bool policyLoaded: false

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
    readonly property string activeProfileLabel: Policy.profileLabel(Policy.sourceProfile(policy, activeSource))

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
        root.policy = Policy.parsePolicyText(text)
        root.policyLoaded = true
    }

    function persistPolicy(next) {
        root.policy = Policy.merge(next)
        if (!writePolicyProc.running) {
            writePolicyProc.command = Policy.writePolicyCommand(root.policy)
            writePolicyProc.running = true
        }
    }

    function setTimeoutValue(source, field, seconds) {
        persistPolicy(Policy.withTimeout(root.policy, source, field, seconds))
    }

    function setSourceProfile(source, profile) {
        persistPolicy(Policy.withProfile(root.policy, source, profile))
        if (!profileProc.running) {
            profileProc.command = Policy.setProfileCommand(source, profile)
            profileProc.running = true
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
            policyFile.reload()
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
    }

    Process {
        id: profileProc
        onExited: root.refreshProfiles()
    }

    Process {
        id: profilesListProc
        command: ["bash", "-lc", "omarchy-powerprofiles-list --active-state 2>/dev/null || omarchy powerprofiles list 2>/dev/null || true"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var next = Policy.parseProfiles(text)
                if (next.length > 0) root.profiles = next
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
                        width: parent.width - stayAwakeButton.width - parent.spacing
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

                    SourceColumn {
                        width: root.batteryPresent ? (parent.width - parent.spacing) / 2 : parent.width
                        sourceKey: "ac"
                        title: root.batteryPresent ? "Plugged in" : "This machine"
                        current: root.activeSource === "ac"
                    }

                    SourceColumn {
                        visible: root.batteryPresent
                        width: visible ? (parent.width - parent.spacing) / 2 : 0
                        sourceKey: "battery"
                        title: "On battery"
                        current: root.activeSource === "battery"
                    }
                }
            }
        }
    }

    component SourceColumn: Column {
        property string sourceKey
        property string title
        property bool current: false

        spacing: Style.space(10)
        width: parent.width

        readonly property var idle: Policy.sourceIdle(root.policy, sourceKey)
        readonly property string selectedProfile: Policy.sourceProfile(root.policy, sourceKey)

        PanelSectionHeader {
            text: title.toUpperCase() + (current ? "  ·  NOW" : "")
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
        }

        Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
                ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
                : 0

            Repeater {
                model: root.profiles

                Button {
                    required property var modelData
                    width: profileRow.cellWidth
                    text: Policy.profileLabel(String(modelData))
                    fontSize: Style.font.bodySmall
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    horizontalPadding: Style.spacing.controlPaddingX
                    verticalPadding: Style.spacing.controlPaddingY
                    bordered: true
                    active: selectedProfile === String(modelData)
                    onClicked: root.setSourceProfile(sourceKey, String(modelData))
                }
            }
        }

        TimeoutRow {
            label: "Screensaver after"
            seconds: idle.screensaver
            onPicked: function(value) { root.setTimeoutValue(sourceKey, "screensaver", value) }
        }

        TimeoutRow {
            label: "Turn off screen after"
            seconds: idle.screenOff
            onPicked: function(value) { root.setTimeoutValue(sourceKey, "screenOff", value) }
        }

        TimeoutRow {
            label: "Lock after"
            seconds: idle.lock
            onPicked: function(value) { root.setTimeoutValue(sourceKey, "lock", value) }
        }

        TimeoutRow {
            label: "Suspend after"
            seconds: idle.suspend
            onPicked: function(value) { root.setTimeoutValue(sourceKey, "suspend", value) }
        }
    }

    component TimeoutRow: Column {
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
            currentIndex: Policy.indexForSeconds(seconds)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            onActivated: function(index) { picked(Policy.secondsAt(index)) }

            Binding {
                target: box
                property: "currentIndex"
                value: Policy.indexForSeconds(seconds)
                when: !box.down
            }
        }
    }
}
