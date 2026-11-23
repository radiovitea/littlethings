import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property string currentId: ""
    property var browsers: []          // [{ id, name, icon, iconFile }]
    property string errorText: ""
    property bool switching: false

    readonly property var current: findBrowser(currentId)
    readonly property string currentName: current ? current.name
                                        : (currentId !== "" ? currentId : "не задан")

    readonly property string scriptPath: decodeURIComponent(
        Qt.resolvedUrl("../code/browser-switch.sh").toString().replace(/^file:\/\//, ""))

    // Глобальный хоткей (настройки виджета → «Комбинации клавиш») — следующий браузер
    activationTogglesExpanded: false

    Plasmoid.icon: current && current.icon !== "" ? iconSource(current.icon) : "internet-web-browser"

    toolTipMainText: "Браузер по умолчанию: " + currentName
    toolTipSubText: errorText !== "" ? errorText
                                     : "Клик — выбрать браузер, колёсико — следующий"

    function findBrowser(id) {
        for (const b of browsers) {
            if (b.id === id) {
                return b
            }
        }
        return null
    }

    function iconSource(name) {
        return String(name).startsWith("/") ? "file://" + name : String(name)
    }

    function quote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    // action: status | set | next | prev
    function run(action, arg) {
        if (action !== "status") {
            switching = true
        }
        let command = "bash " + quote(scriptPath) + " " + action
        if (arg !== undefined) {
            command += " " + quote(arg)
        }
        executable.connectSource(command)
    }

    function applyStatus(stdout) {
        const list = []
        let cur = null
        let err = ""
        for (const line of stdout.split("\n")) {
            if (line.startsWith("browser=")) {
                const p = line.slice(8).split("\t")
                list.push({
                    id: p[0],
                    name: p[1] || p[0].replace(/\.desktop$/, ""),
                    icon: p[2] || "",
                    iconFile: p[3] || ""
                })
            } else if (line.startsWith("current=")) {
                cur = line.slice(8)
            } else if (line.startsWith("error=")) {
                err = line.slice(6)
            }
        }
        if (cur === null) {
            return false
        }
        browsers = list
        currentId = cur
        errorText = err
        return true
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            const isStatus = sourceName.endsWith(" status")
            // Пока идёт переключение, не даём старому статусу затереть новый
            if (isStatus && root.switching) {
                return
            }
            if (!isStatus) {
                root.switching = false
            }
            if (!root.applyStatus(data["stdout"] || "")) {
                root.errorText = (data["stderr"] || "").trim() || "Скрипт не ответил"
            }
        }
    }

    Connections {
        target: Plasmoid
        function onActivated() {
            root.run("next")
        }
    }

    // Открыли список — перечитываем, вдруг поставили новый браузер
    onExpandedChanged: {
        if (expanded && !switching) {
            run("status")
        }
    }

    // Подхватываем изменения, сделанные в «Параметрах системы»
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            if (!root.switching) {
                root.run("status")
            }
        }
    }

    Component.onCompleted: run("status")

    // Иконка браузера: сначала из темы значков, потом файл иконки,
    // в крайнем случае — своя иконка виджета
    component BrowserIcon: Item {
        id: browserIcon

        property string iconName: ""
        property string iconFile: ""
        property bool active: false

        Kirigami.Icon {
            id: themedIcon
            anchors.fill: parent
            source: browserIcon.iconName === "" ? ""
                  : browserIcon.iconName.startsWith("/") ? "file://" + browserIcon.iconName
                  : browserIcon.iconName
            fallback: ""
            active: browserIcon.active
            visible: valid
        }

        Kirigami.Icon {
            id: fileIcon
            anchors.fill: parent
            source: browserIcon.iconFile !== "" ? "file://" + browserIcon.iconFile : ""
            fallback: ""
            active: browserIcon.active
            visible: !themedIcon.valid && valid
        }

        Kirigami.Icon {
            anchors.fill: parent
            source: Qt.resolvedUrl("../icons/browser-switch.svg")
            active: browserIcon.active
            visible: !themedIcon.valid && !fileIcon.valid
        }
    }

    compactRepresentation: MouseArea {
        id: compact

        property bool wasExpanded: false
        property int wheelDelta: 0

        implicitWidth: Kirigami.Units.iconSizes.medium
        implicitHeight: Kirigami.Units.iconSizes.medium

        Layout.minimumWidth: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? height
                           : Plasmoid.formFactor === PlasmaCore.Types.Vertical ? 0
                           : Kirigami.Units.gridUnit * 3
        Layout.minimumHeight: Plasmoid.formFactor === PlasmaCore.Types.Vertical ? width
                            : Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? 0
                            : Kirigami.Units.gridUnit * 3

        hoverEnabled: true
        acceptedButtons: Qt.LeftButton

        onPressed: wasExpanded = root.expanded
        onClicked: root.expanded = !wasExpanded

        onWheel: wheel => {
            const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
            wheelDelta += delta
            // 120 — один «щелчок» колеса; тачпад набирает его постепенно
            if (Math.abs(wheelDelta) >= 120) {
                if (!root.switching) {
                    root.run(wheelDelta > 0 ? "prev" : "next")
                }
                wheelDelta = 0
            }
        }

        BrowserIcon {
            anchors.fill: parent
            iconName: root.current ? root.current.icon : ""
            iconFile: root.current ? root.current.iconFile : ""
            active: compact.containsMouse
            opacity: root.switching ? 0.4 : 1

            Behavior on opacity {
                NumberAnimation { duration: Kirigami.Units.shortDuration }
            }
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: implicitHeight
        Layout.preferredHeight: implicitHeight

        spacing: 0

        Kirigami.Heading {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            Layout.bottomMargin: Kirigami.Units.largeSpacing
            level: 4
            text: "Браузер по умолчанию"
            elide: Text.ElideRight
        }

        Repeater {
            model: root.browsers

            delegate: PlasmaComponents.ItemDelegate {
                id: item

                required property var modelData
                readonly property bool isCurrent: modelData.id === root.currentId

                Layout.fillWidth: true
                enabled: !root.switching

                onClicked: {
                    if (!isCurrent) {
                        root.run("set", modelData.id)
                    }
                    root.expanded = false
                }

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    BrowserIcon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                        iconName: item.modelData.icon
                        iconFile: item.modelData.iconFile
                        active: item.hovered
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: item.modelData.name
                        font.bold: item.isCurrent
                        elide: Text.ElideRight
                    }

                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        source: "checkmark"
                        visible: item.isCurrent
                    }
                }
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            visible: root.errorText !== "" || root.browsers.length === 0
            text: root.errorText !== "" ? root.errorText : "Браузеры не найдены"
            color: root.errorText !== "" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            wrapMode: Text.Wrap
        }
    }
}
