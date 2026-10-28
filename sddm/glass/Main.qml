import QtQuick
import QtQuick.Controls
import QtQuick.Effects

Rectangle {
    id: root
    color: "#000000"

    property bool dark: config.mode !== "light"
    property bool menuOpen: false

    readonly property color cText: dark ? "#f5f5f7" : "#1d1d1f"
    readonly property color cSub: dark ? "#c7c7cc" : "#48484a"
    readonly property color cGlass: dark ? "#26ffffff" : "#99ffffff"
    readonly property color cBorder: dark ? "#40ffffff" : "#33000000"
    readonly property color cAccent: dark ? "#0a84ff" : "#007aff"
    readonly property color cMenu: dark ? "#e61e1e22" : "#f2f6f6f8"
    readonly property string fam: config.font ? config.font : "Inter"
    readonly property string suffix: dark ? "dark" : "light"

    function doLogin() {
        if (userList.currentItem && password.text.length > 0)
            sddm.login(userList.currentItem.uname, password.text, sessionList.currentIndex)
    }

    Component.onCompleted: password.forceActiveFocus()

    Connections {
        target: sddm
        function onLoginFailed() {
            password.text = ""
            err.text = "Contraseña incorrecta"
            password.forceActiveFocus()
        }
    }

    // --- Fondo difuminado ---
    Image {
        id: bg
        anchors.fill: parent
        source: config.background
        fillMode: Image.PreserveAspectCrop
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: bg
        blurEnabled: true
        blurMax: 64
        blur: 1.0
        brightness: root.dark ? -0.15 : 0.05
    }

    // --- Reloj ---
    property date now: new Date()
    readonly property bool bigClock: config.clock === "big"

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: root.now = new Date()
    }

    // Estilo barra: píldora de cristal arriba a la derecha, como la de Waybar
    Rectangle {
        visible: !root.bigClock
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 24
        height: 34
        width: stamp.implicitWidth + 28
        radius: 17
        color: root.cGlass
        border.width: 1
        border.color: root.cBorder
        Text {
            id: stamp
            anchors.centerIn: parent
            text: Qt.formatDate(root.now, "ddd d MMM") + "  " + Qt.formatTime(root.now, "HH:mm")
            color: root.cText
            font.family: root.fam
            font.pixelSize: 14
            font.weight: Font.Medium
        }
    }

    // Estilo grande (opcional: clock=big en theme.conf)
    Column {
        visible: root.bigClock
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.10
        spacing: 2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "HH:mm")
            color: root.cText
            font.family: root.fam
            font.pixelSize: 120
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd, d 'de' MMMM")
            color: root.cSub
            font.family: root.fam
            font.pixelSize: 24
        }
    }

    // --- Cierra el menú al pulsar fuera ---
    MouseArea {
        anchors.fill: parent
        visible: root.menuOpen
        z: 5
        onClicked: root.menuOpen = false
    }

    // --- Usuario, contraseña y botón "?" ---
    Column {
        id: login
        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.bigClock ? parent.height - height - parent.height * 0.26 : (parent.height - height) / 2 - parent.height * 0.04
        spacing: 14

        ListView {
            id: userList
            width: 260
            height: 150
            anchors.horizontalCenter: parent.horizontalCenter
            model: userModel
            orientation: ListView.Horizontal
            snapMode: ListView.SnapOneItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            currentIndex: userModel.lastIndex
            interactive: userList.count > 1
            clip: true
            delegate: Item {
                width: userList.width
                height: userList.height
                property string uname: model.name
                property string ureal: model.realName
                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 92; height: 92; radius: 46
                        color: root.cGlass
                        border.width: 1
                        border.color: root.cBorder
                        Text {
                            anchors.centerIn: parent
                            text: (ureal !== "" ? ureal : uname).charAt(0).toUpperCase()
                            color: root.cText
                            font.family: root.fam
                            font.pixelSize: 42
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ureal !== "" ? ureal : uname
                        color: root.cText
                        font.family: root.fam
                        font.pixelSize: 20
                    }
                }
            }
        }

        Item {
            id: pwdArea
            z: 20
            width: 280
            height: 44
            anchors.horizontalCenter: parent.horizontalCenter

            TextField {
                id: password
                anchors.fill: parent
                echoMode: TextInput.Password
                placeholderText: "Contraseña"
                placeholderTextColor: root.cSub
                color: root.cText
                font.family: root.fam
                font.pixelSize: 16
                horizontalAlignment: TextInput.AlignHCenter
                background: Rectangle {
                    radius: 22
                    color: root.cGlass
                    border.width: 1
                    border.color: password.activeFocus ? root.cAccent : root.cBorder
                }
                Keys.onReturnPressed: root.doLogin()
                Keys.onEnterPressed: root.doLogin()
                Keys.onEscapePressed: root.menuOpen = false
            }

            // Botón "?"
            Rectangle {
                id: helpBtn
                anchors.left: parent.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 36; height: 36; radius: 18
                color: helpArea.containsMouse || root.menuOpen ? root.cBorder : root.cGlass
                border.width: 1
                border.color: root.cBorder
                Text {
                    anchors.centerIn: parent
                    text: "?"
                    color: root.cText
                    font.family: root.fam
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: helpArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.menuOpen = !root.menuOpen
                }
            }

            // Menú de apariencia
            Rectangle {
                id: themeMenu
                visible: root.menuOpen
                anchors.left: helpBtn.left
                anchors.top: helpBtn.bottom
                anchors.topMargin: 10
                width: 190
                height: menuCol.height + 16
                radius: 16
                color: root.cMenu
                border.width: 1
                border.color: root.cBorder

                Column {
                    id: menuCol
                    x: 8
                    y: 8
                    width: parent.width - 16
                    spacing: 2

                    Text {
                        text: "Apariencia"
                        color: root.cSub
                        font.family: root.fam
                        font.pixelSize: 12
                        leftPadding: 10
                        topPadding: 4
                        bottomPadding: 4
                    }

                    Repeater {
                        model: [ { key: "dark", label: "Oscuro" }, { key: "light", label: "Claro" } ]
                        delegate: Rectangle {
                            width: menuCol.width
                            height: 36
                            radius: 10
                            color: itemArea.containsMouse ? root.cBorder : "transparent"
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: root.cText
                                font.family: root.fam
                                font.pixelSize: 14
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: (root.dark ? "dark" : "light") === modelData.key ? "✓" : ""
                                color: root.cAccent
                                font.family: root.fam
                                font.pixelSize: 15
                            }
                            MouseArea {
                                id: itemArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.dark = (modelData.key === "dark")
                                    root.menuOpen = false
                                    password.forceActiveFocus()
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            id: err
            anchors.horizontalCenter: parent.horizontalCenter
            height: 18
            text: ""
            color: "#ff453a"
            font.family: root.fam
            font.pixelSize: 14
        }
    }

    // --- Selector de sesión (clic para cambiar) ---
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 32
        width: 240; height: 40; radius: 20
        color: root.cGlass
        border.width: 1
        border.color: root.cBorder

        ListView {
            id: sessionList
            anchors.fill: parent
            model: sessionModel
            orientation: ListView.Horizontal
            snapMode: ListView.SnapOneItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            currentIndex: sessionModel.lastIndex
            interactive: false
            clip: true
            delegate: Item {
                width: sessionList.width
                height: sessionList.height
                Text {
                    anchors.centerIn: parent
                    text: model.name
                    color: root.cText
                    font.family: root.fam
                    font.pixelSize: 14
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sessionList.currentIndex = (sessionList.currentIndex + 1) % sessionList.count
        }
    }

    // --- Botones de energía, centrados y con etiqueta ---
    Row {
        id: powerRow
        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 56
        spacing: 44

        Component.onCompleted: console.log("sddm caps:", sddm.canPowerOff, sddm.canReboot, sddm.canHibernate, sddm.canSuspend)

        Repeater {
            model: [
                { icon: "poweroff",  label: "Apagar",    ok: sddm.canPowerOff },
                { icon: "reboot",    label: "Reiniciar", ok: sddm.canReboot },
                { icon: "hibernate", label: "Hibernar",  ok: sddm.canHibernate }
            ]
            delegate: Column {
                spacing: 8
                opacity: modelData.ok ? 1.0 : 0.4

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 52; height: 52; radius: 26
                    color: area.containsMouse ? root.cBorder : root.cGlass
                    border.width: 1
                    border.color: root.cBorder
                    Image {
                        anchors.centerIn: parent
                        width: 24; height: 24
                        sourceSize: Qt.size(48, 48)
                        source: "icons/" + modelData.icon + "-" + root.suffix + ".svg"
                    }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.icon === "poweroff") sddm.powerOff()
                            else if (modelData.icon === "reboot") sddm.reboot()
                            else sddm.hibernate()
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.label
                    color: root.cText
                    font.family: root.fam
                    font.pixelSize: 13
                }
            }
        }
    }
}
