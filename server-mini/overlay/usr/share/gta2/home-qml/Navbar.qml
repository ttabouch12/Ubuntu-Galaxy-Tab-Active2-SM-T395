// gta2 on-screen navigation bar (Windows Phone style): back · home · keyboard, always at the bottom, over every app.
// Buttons write a command to /tmp/gta2-nav.cmd (QML_XHR_ALLOW_FILE_WRITE=1); gta2-keys picks it up within ~0.1 s
// and runs the same code as the hardware keys. gta2-navbar marks this window as a dock so matchbox keeps the space free.
import QtQuick
import QtQuick.Window

Window {
    id: bar
    visible: true
    title: "gta2-navbar"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    x: 0; y: Screen.height - height
    width: Screen.width; height: 56
    color: "black"

    function send(c) {
        var x = new XMLHttpRequest();
        x.open("PUT", "file:///tmp/gta2-nav.cmd"); x.send(c + " " + Date.now() + "\n");
    }
    component NavBtn: Item {
        id: nb
        property string cmd: ""
        default property alias content: holder.data
        width: bar.width / 3; height: bar.height
        Rectangle { anchors.centerIn: parent; width: 52; height: 52; radius: 26; color: "#ffffff"
                    opacity: m.pressed ? 0.22 : 0; Behavior on opacity { NumberAnimation { duration: 120 } } }
        Item { id: holder; anchors.centerIn: parent; width: 30; height: 30; scale: m.pressed ? 0.88 : 1
               Behavior on scale { NumberAnimation { duration: 90 } } }
        MouseArea { id: m; anchors.fill: parent; pressAndHoldInterval: 600; onClicked: bar.send(nb.cmd)
                    onPressAndHold: if (nb.cmd === "back") bar.send("recents") }   // hold back = recent apps
    }
    Row {
        anchors.fill: parent
        NavBtn { cmd: "back"      // ← in a circle, like WP
            Rectangle { anchors.fill: parent; radius: 15; color: "transparent"; border.color: "white"; border.width: 2
                Text { anchors.centerIn: parent; anchors.verticalCenterOffset: -1; text: "←"; color: "white"; font.pixelSize: 18 } } }
        NavBtn { cmd: "home"      // Ubuntu logo from the system icon theme (ubuntu-mono-dark)
            Image { anchors.centerIn: parent; source: "home-ubuntu.png"; width: 30; height: 30; smooth: true } }
        NavBtn { cmd: "keyboard"
            Rectangle { anchors.fill: parent; anchors.topMargin: 6; anchors.bottomMargin: 6; color: "transparent"; border.color: "white"; border.width: 2
                Grid { anchors.centerIn: parent; columns: 5; spacing: 2
                       Repeater { model: 10; Rectangle { width: 3; height: 3; color: "white" } } } } }
    }
    Rectangle { width: parent.width; height: 1; color: "#262626" }
}
