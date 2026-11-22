// gta2 task switcher (Windows Phone style): cards of the apps still running behind the home.
// Tap = switch, swipe a card up or tap × = close, "close all". Data: /tmp/gta2-recents.json (gta2-recentsd).
import QtQuick
import QtQuick.Window

Window {
    id: w
    title: "gta2-recents"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    x: 0; y: 0; width: Screen.width; height: Screen.height
    color: "black"; visible: false
    property real seq: -1
    ListModel { id: appsM }

    function cmd(s) { var x = new XMLHttpRequest(); x.open("PUT", "file:///tmp/gta2-recents.cmd"); x.send(s + " " + Date.now() + "\n") }
    function poll() {
        var x = new XMLHttpRequest(); x.open("GET", "file:///tmp/gta2-recents.json", false);
        try { x.send() } catch (e) { return }
        var j; try { j = JSON.parse(x.responseText) } catch (e) { return }
        if (!j || j.seq === w.seq) return; w.seq = j.seq;
        var a = j.apps || [];
        // update in place (no delegate re-creation while visible)
        while (appsM.count > a.length) appsM.remove(appsM.count - 1);
        for (var i = 0; i < a.length; i++) {
            var o = {wid: a[i].wid, name: a[i].name, thumb: a[i].thumb ? "file://" + a[i].thumb + "?" + a[i].tv : ""};
            if (i < appsM.count) appsM.set(i, o); else appsM.append(o);
        }
        if (j.show && !w.visible) { lv.positionViewAtBeginning(); w.visible = true; w.raise(); w.requestActivate(); intro.restart() }
        if (!j.show && w.visible) w.visible = false;
    }
    Timer { interval: 100; running: true; repeat: true; onTriggered: w.poll() }

    Text { x: 24; y: 40; text: "recent"; color: "white"; font.pixelSize: 56; font.weight: Font.Light }
    Text { anchors.centerIn: parent; visible: appsM.count === 0; text: "no recent apps"; color: "#a0a0a0"; font.pixelSize: 28; font.weight: Font.Light }
    MouseArea { anchors.fill: parent; onClicked: w.cmd("hide") }      // tap outside the cards: back to where you were

    ListView {
        id: lv; y: 160; width: parent.width; height: 680; orientation: ListView.Horizontal
        spacing: 24
        snapMode: ListView.SnapToItem; highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width - 360) / 2; preferredHighlightEnd: (width + 360) / 2
        model: appsM; cacheBuffer: 2000
        transform: Translate { id: introT; x: 0 }
        delegate: Item {
            id: card; width: 360; height: 680
            Item {
                id: body; width: parent.width; height: parent.height
                opacity: 1 - Math.min(1, Math.max(0, -body.y) / 420)
                Rectangle { y: 40; width: 360; height: 551; color: "#1d1d1d"
                    Image { anchors.fill: parent; source: model.thumb; asynchronous: true; cache: false; fillMode: Image.PreserveAspectCrop } }
                Text { y: 0; width: 300; text: model.name.toLowerCase(); color: "white"; font.pixelSize: 24; font.weight: Font.Light; elide: Text.ElideRight }
                Rectangle { x: 320; y: 0; width: 36; height: 36; radius: 18; color: "transparent"; border.color: "white"; border.width: 2
                    Text { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 24 }
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: closeAnim.start() } }
                MouseArea {
                    y: 40; width: 360; height: 551
                    drag.target: body; drag.axis: Drag.YAxis; drag.maximumY: 0; drag.minimumY: -700; drag.filterChildren: true
                    onClicked: w.cmd("switch " + model.wid)
                    onReleased: { if (body.y < -150) closeAnim.start(); else backAnim.start() }
                }
                NumberAnimation { id: backAnim; target: body; property: "y"; to: 0; duration: 200; easing.type: Easing.OutCubic }
                SequentialAnimation { id: closeAnim
                    NumberAnimation { target: body; property: "y"; to: -800; duration: 220; easing.type: Easing.InCubic }
                    ScriptAction { script: { w.cmd("close " + model.wid); body.y = 0 } } }
            }
        }
    }
    NumberAnimation { id: intro; target: introT; property: "x"; from: 160; to: 0; duration: 260; easing.type: Easing.OutCubic }
    Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 900; width: 220; height: 56; color: "transparent"; border.color: "white"; border.width: 2; visible: appsM.count > 0
        Text { anchors.centerIn: parent; text: "close all"; color: "white"; font.pixelSize: 22 }
        MouseArea { anchors.fill: parent; onClicked: w.cmd("closeall") } }
}
