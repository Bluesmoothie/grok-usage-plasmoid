import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.extras 2.0 as PlasmaExtras

Item {
    id: root

    property bool loading: false
    property bool ok: false
    property var percent: null
    property var buildPercent: null
    property var products: []
    property string period: ""
    property string resetHuman: ""
    property string plan: ""
    property string message: ""
    property string fetchedAt: ""

    readonly property bool inPanel: [
        PlasmaCore.Types.TopEdge,
        PlasmaCore.Types.RightEdge,
        PlasmaCore.Types.BottomEdge,
        PlasmaCore.Types.LeftEdge
    ].indexOf(Plasmoid.location) !== -1

    readonly property int usedPercent: Math.round(Number(root.percent || 0))
    readonly property color usageColor: {
        if (!root.ok || root.percent === null || root.percent === undefined)
            return PlasmaCore.Theme.disabledTextColor
        if (root.percent >= 85)
            return "#e05d44"
        if (root.percent >= 60)
            return "#d89b1a"
        return "#3d9a5b"
    }

    Plasmoid.preferredRepresentation: Plasmoid.compactRepresentation
    Plasmoid.switchWidth: PlasmaCore.Units.gridUnit * 14
    Plasmoid.switchHeight: PlasmaCore.Units.gridUnit * 12
    Plasmoid.backgroundHints: PlasmaCore.Types.StandardBackground | PlasmaCore.Types.ConfigurableBackground
    Plasmoid.icon: "view-statistics"
    Plasmoid.toolTipMainText: root.ok
        ? i18n("Quota Grok · %1 %", root.usedPercent)
        : i18n("Quota Grok")
    Plasmoid.toolTipSubText: {
        if (root.loading)
            return i18n("Actualisation…")
        if (!root.ok)
            return root.message || i18n("Quota indisponible")
        var bits = []
        if (root.plan)
            bits.push(root.plan)
        if (root.buildPercent !== null && root.buildPercent !== undefined)
            bits.push(i18n("Build %1 %", Math.round(root.buildPercent)))
        if (root.resetHuman)
            bits.push(i18n("reset %1", root.resetHuman))
        return bits.join(" · ")
    }

    Component.onCompleted: {
        plasmoid.removeAction("configure")
        refresh()
    }

    function scriptPath() {
        var path = ""
        try {
            path = plasmoid.file("code", "grok-usage.py")
        } catch (e) {
            path = ""
        }
        if (!path) {
            path = Qt.resolvedUrl("../code/grok-usage.py").toString()
            if (path.indexOf("file://") === 0)
                path = path.substring(7)
        }
        return path
    }

    function refresh() {
        if (root.loading)
            return
        root.loading = true
        exec.connectSource("/usr/bin/python3 \"" + scriptPath() + "\"")
    }

    function applyPayload(payload) {
        root.ok = !!payload.ok
        root.percent = payload.percent === undefined ? null : payload.percent
        root.buildPercent = payload.build_percent === undefined ? null : payload.build_percent
        root.products = payload.products || []
        root.period = payload.period || ""
        root.resetHuman = payload.reset_human || ""
        root.plan = payload.plan || ""
        root.message = payload.message || ""
        root.fetchedAt = payload.fetched_at || ""
    }

    PlasmaCore.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: {
            var stdout = data["stdout"] || ""
            disconnectSource(sourceName)
            root.loading = false
            var text = stdout.trim()
            if (!text) {
                root.ok = false
                root.message = i18n("Aucune réponse du script quota.")
                return
            }
            try {
                root.applyPayload(JSON.parse(text))
            } catch (e) {
                root.ok = false
                root.message = i18n("Réponse quota illisible.")
            }
        }
    }

    Timer {
        interval: 300000
        repeat: true
        running: true
        onTriggered: refresh()
    }

    Plasmoid.compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        property bool wasExpanded: false

        Layout.minimumWidth: label.implicitWidth + PlasmaCore.Units.smallSpacing * 2
        Layout.minimumHeight: label.implicitHeight
        Layout.preferredWidth: label.implicitWidth + PlasmaCore.Units.smallSpacing * 2
        Layout.preferredHeight: Math.max(PlasmaCore.Units.iconSizes.small, label.implicitHeight)

        Accessible.role: Accessible.Button
        Accessible.name: Plasmoid.toolTipMainText
        Accessible.description: Plasmoid.toolTipSubText

        onPressed: wasExpanded = Plasmoid.expanded
        onClicked: {
            if (mouse.button === Qt.MiddleButton)
                refresh()
            else
                Plasmoid.expanded = !wasExpanded
        }

        PlasmaComponents3.Label {
            id: label
            anchors.centerIn: parent
            text: {
                if (root.loading && !root.ok)
                    return i18n("Grok …")
                if (!root.ok)
                    return i18n("Grok ?")
                return i18n("Grok %1%", root.usedPercent)
            }
            color: root.usageColor
            font.bold: root.ok && root.percent >= 85
            font.pointSize: Math.max(PlasmaCore.Theme.smallestFont.pointSize, 8)
        }
    }

    Plasmoid.fullRepresentation: PlasmaExtras.Representation {
        Layout.preferredWidth: PlasmaCore.Units.gridUnit * 18
        Layout.preferredHeight: PlasmaCore.Units.gridUnit * 16
        Layout.minimumWidth: PlasmaCore.Units.gridUnit * 14
        Layout.minimumHeight: PlasmaCore.Units.gridUnit * 12
        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            contentItem: RowLayout {
                spacing: PlasmaCore.Units.smallSpacing
                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: root.plan ? i18n("Quota %1", root.plan) : i18n("Quota Grok")
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "view-refresh"
                    text: i18n("Actualiser")
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    enabled: !root.loading
                    onClicked: refresh()
                    PlasmaComponents3.ToolTip.text: i18n("Actualiser")
                    PlasmaComponents3.ToolTip.visible: hovered
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: PlasmaCore.Units.smallSpacing
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaExtras.PlaceholderMessage {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                visible: !root.ok && !root.loading
                iconName: "dialog-warning"
                text: root.message || i18n("Quota indisponible")
                helpfulAction: QQC2.Action {
                    text: i18n("Réessayer")
                    icon.name: "view-refresh"
                    onTriggered: refresh()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: root.ok
                spacing: PlasmaCore.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents3.Label {
                        text: i18n("Global")
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents3.Label {
                        text: root.percent === null ? "—" : (root.usedPercent + " %")
                        font.bold: true
                        color: root.usageColor
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 8
                    radius: 4
                    color: PlasmaCore.Theme.backgroundColor
                    border.color: PlasmaCore.Theme.disabledTextColor
                    border.width: 1

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, Number(root.percent || 0) / 100))
                        height: parent.height
                        radius: parent.radius
                        color: root.usageColor
                    }
                }

                Repeater {
                    model: root.products
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: modelData.label
                            opacity: 0.9
                        }
                        PlasmaComponents3.Label {
                            text: modelData.percent === null || modelData.percent === undefined
                                  ? "—"
                                  : (Math.round(modelData.percent) + " %")
                            color: {
                                var value = Number(modelData.percent)
                                if (isNaN(value))
                                    return PlasmaCore.Theme.disabledTextColor
                                if (value >= 85)
                                    return "#e05d44"
                                if (value >= 60)
                                    return "#d89b1a"
                                return PlasmaCore.Theme.textColor
                            }
                        }
                    }
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.75
                    text: {
                        var bits = []
                        if (root.period)
                            bits.push(i18n("Période %1", root.period))
                        if (root.resetHuman)
                            bits.push(i18n("reset %1", root.resetHuman))
                        return bits.join(" · ")
                    }
                    visible: text.length > 0
                }
            }

            Item { Layout.fillHeight: true }

            PlasmaComponents3.Button {
                Layout.alignment: Qt.AlignRight
                text: i18n("Ouvrir /usage")
                icon.name: "internet-web-browser"
                onClicked: Qt.openUrlExternally("https://grok.com/?_s=usage")
            }
        }
    }
}
