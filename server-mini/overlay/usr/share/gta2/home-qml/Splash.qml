// gta2 launch splash: Windows Phone style "app icon first, then the app".
// Persistent hidden window (no process start on launch). The home writes /tmp/gta2-splash.cmd
// ({"seq":ms,"show":true,"name","icon","glyph","col"}); gta2-splashd hides it when the app's window appears.
import QtQuick
import QtQuick.Window

Window {
    id: w
    title: "gta2-splash"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    x: 0; y: 0; width: Screen.width; height: Screen.height
    color: "black"
    visible: false
    property real seq: -1
    property string col: "#2d89ef"

    function poll() {
        var x = new XMLHttpRequest();
        x.open("GET", "file:///tmp/gta2-splash.cmd", false);
        try { x.send() } catch (e) { return }
        var j; try { j = JSON.parse(x.responseText) } catch (e) { return }
        if (!j || j.seq === w.seq) return;
        w.seq = j.seq;
        if (j.show) show(j); else hide(j.fail === true);
    }
    function show(j) {
        hideT.stop(); failT.stop(); fail.visible = false;
        w.col = j.col || "#2d89ef";
        name.text = (j.name || "").toLowerCase();
        glyph.text = j.glyph || "";
        icon.source = j.icon || "";
        bg.opacity = 1; dots.running = true;
        w.visible = true; w.raise();
    }
    function hide(failed) {
        if (!w.visible) return;
        if (failed) { fail.visible = true; failT.restart(); return }
        bg.opacity = 0; hideT.restart();
    }
    Timer { interval: 50; running: true; repeat: true; onTriggered: w.poll() }
    Timer { id: hideT; interval: 160; onTriggered: { w.visible = false; dots.running = false } }
    Timer { id: failT; interval: 1400; onTriggered: { bg.opacity = 0; hideT.restart() } }

    Rectangle {
        id: bg; anchors.fill: parent; color: w.col
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Item {
            anchors.centerIn: parent; anchors.verticalCenterOffset: -40; width: parent.width; height: 300
            Image { id: icon; anchors.horizontalCenter: parent.horizontalCenter; y: 0; width: 160; height: 160
                    sourceSize.width: 160; sourceSize.height: 160; fillMode: Image.PreserveAspectFit; smooth: true
                    visible: status === Image.Ready }
            Text { id: glyph; anchors.horizontalCenter: parent.horizontalCenter; y: 10; color: "white"
                   font.pixelSize: 120; visible: !icon.visible }
            Text { id: name; anchors.horizontalCenter: parent.horizontalCenter; y: 190; color: "white"
                   font.pixelSize: 40; font.weight: Font.Light }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter; y: 262; spacing: 10
                Repeater { model: 5; Rectangle { id: d; width: 6; height: 6; color: "white"; opacity: 0.25
                    SequentialAnimation on opacity { running: dots.running; loops: Animation.Infinite
                        PauseAnimation { duration: index * 120 }
                        NumberAnimation { to: 1; duration: 300 } NumberAnimation { to: 0.25; duration: 300 }
                        PauseAnimation { duration: (4 - index) * 120 } } } }
            }
            Text { id: fail; visible: false; anchors.horizontalCenter: parent.horizontalCenter; y: 262
                   color: "white"; font.pixelSize: 22; text: "app didn't start" }
        }
        QtObject { id: dots; property bool running: false }
    }
}
