// gta2 home: native Qt Quick Metro UI (Windows Phone 7/8 style). Talks to gta2-dash (127.0.0.1:8088):
//   GET /api every 10 s, GET /live every 2 s, POST /ctl {"a":..,"v":..} for tablet actions.
// Drawn by the Qt Quick scene graph on the GPU: holds 60 fps on the Mali T830 where WebKit could not.
// HOME key: gta2-keys writes /tmp/gta2-home.cmd; a 400 ms timer reads it (QML_XHR_ALLOW_FILE_READ=1).
import QtQuick
import QtQuick.Window
import QtQml.Models

Window {
    id: win
    visible: true
    visibility: Window.Windowed
    width: Screen.width; height: Screen.height
    title: "gta2-home"
    color: "black"

    // ---------- look
    readonly property string fnt: "Ubuntu"
    readonly property color mut: "#d0d0d0"
    readonly property color acc: "#2d89ef"
    readonly property int pad: 24
    readonly property int gap: 10
    readonly property int tileW: Math.floor((width - 2 * pad - 3 * gap) / 4)
    readonly property bool local: true
    readonly property string base: "http://127.0.0.1"
    property bool busy: pv.moving || pv.flicking || pHome.moving || pApps.moving || pScreen.moving || pSet.moving || detFlick.moving || subFlick.moving || (sub.tang > 0.5 && sub.tang < 81.5) || (det.slide > 0.001 && det.slide < 0.999) || launchT.running

    // ---------- Windows Phone turnstile: items swing around their LEFT edge with perspective (one 4x4 transform
    // per item, no offscreen layers). Staggered by row/column. turn(group, in): in = swing into view, else swing away.
    signal turn(string group, bool inn)
    function turnM(a, h) {
        if (a === 0) return Qt.matrix4x4();
        var r = a * Math.PI / 180, c = Math.cos(r), s = Math.sin(r), d = 900, cy = h / 2;
        return Qt.matrix4x4(c, 0, s, 0,  cy * s / d, 1, -cy * c / d, 0,  -s, 0, c, 0,  s / d, 0, -c / d, 1)
    }
    property var flipped: ({})          // groups currently swung away (an app was launched from them)
    function launch(group, fn) {         // WP app launch: tiles flip away, the app starts as the animation ends
        var f = flipped; f[group] = true; flipped = f; turn(group, false); launchFn = fn; launchT.restart()
    }
    property var launchFn: null
    Timer { id: launchT; interval: 300; onTriggered: { if (win.launchFn) win.launchFn(); win.launchFn = null } }
    function unflip() { var f = flipped; for (var g in f) if (f[g]) turn(g, true); flipped = ({}) }
    onActiveChanged: if (active) { unflip(); loadApps() }   // back from an app (HOME, closed, or switched): tiles swing back in
    component Turn: SequentialAnimation {   // attach inside an item that has "tang"
        id: ta
        property Item target2
        property int delay: 0
        property bool inn: true
        PauseAnimation { duration: ta.delay }
        NumberAnimation { target: ta.target2; property: "tang"; to: ta.inn ? 0 : -82; duration: ta.inn ? 300 : 220
                          easing.type: ta.inn ? Easing.OutExpo : Easing.InCubic }
    }

    // ---------- tiny HTTP helpers
    function req(method, url, body, cb) {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            var j = null; try { j = JSON.parse(x.responseText) } catch (e) {}
            if (cb) cb(x.status, j, x.responseText);
        };
        x.open(method, url); x.send(body === undefined ? null : body);
    }
    function ctl(a, v, cb) { req("POST", "http://127.0.0.1:8088/ctl", JSON.stringify({a: a, v: v}), function (s, j) { if (cb) cb(s === 200 ? j : null) }) }
    function sys(args, cb) {
        out.text = "working…";
        ctl("sys", args, function (j) { var o = j ? j.out : "failed"; out.text = o; toast((o || "done").split("\n")[0]); if (cb) cb(o) })
    }
    function toast(t) { toastT.text = t; toastBox.y = 0; toastTimer.restart() }
    function f(x, d) { if (x === null || x === undefined || isNaN(x)) return "–"; return Number(x).toFixed(d || 0) }
    function dur(s) { if (s == null) return "–"; var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60); return d ? d + "d " + h + "h" : h ? h + "h " + m + "m" : m + "m" }
    function gb(b) { if (b == null) return "–"; return b >= 1e12 ? (b / 1e12).toFixed(2) + " TB" : b >= 1e9 ? (b / 1e9).toFixed(1) + " GB" : (b / 1e6).toFixed(0) + " MB" }
    function ago(t) { var s = Date.now() / 1000 - t; return s < 90 ? Math.round(s) + " s ago" : s < 5400 ? Math.round(s / 60) + " min ago" : Math.round(s / 3600) + " h ago" }
    function lvl(v, a, b) { return v == null ? "#555555" : v < a ? "#1e7145" : v < b ? "#e3a21a" : "#b91d47" }

    // ---------- reusable bits
    component Tile: Rectangle {
        id: t
        property string val: ""
        property string unit: ""
        property string sub: ""
        property string name: ""
        property string icon: ""
        property real pct: -1
        property bool wide: false
        // numbers glide to their new value instead of jumping; colours fade (both GPU-cheap)
        readonly property bool numeric: /^-?[0-9]+(\.[0-9]+)?$/.test(val)
        readonly property int dec: numeric ? (val.split(".")[1] || "").length : 0
        property real shown: numeric ? parseFloat(val) : 0
        Behavior on shown { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 900; easing.type: Easing.InOutQuad } }
        signal clicked()
        property string tgroup: ""
        property real tang: 0
        readonly property int trow: Math.round(y / (win.tileW + win.gap))
        readonly property int tcol: Math.round(x / (win.tileW + win.gap))
        transform: Matrix4x4 { matrix: win.turnM(t.tang, t.height) }
        opacity: 1 - Math.min(1, Math.abs(t.tang) / 82)
        Turn { id: tTurn; target2: t; delay: (t.trow * 3 + t.tcol) * 24 }
        Connections { target: win; enabled: t.tgroup !== ""
            function onTurn(g, inn) { if (g !== t.tgroup) return; tTurn.stop(); if (inn && t.tang === 0) t.tang = 82; tTurn.inn = inn; tTurn.start() } }
        width: wide ? 2 * win.tileW + win.gap : win.tileW
        height: win.tileW
        scale: ma.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Text { x: 12; y: 6; visible: t.icon === ""; color: "#ffffff"; font.family: win.fnt; font.weight: Font.Light; font.pixelSize: 52
               text: t.numeric ? t.shown.toFixed(t.dec) : t.val; textFormat: Text.PlainText
               Text { anchors.left: parent.right; anchors.leftMargin: 4; anchors.baseline: parent.baseline; text: t.unit; color: "#ffffff"; font.family: win.fnt; font.pixelSize: 20 } }
        Text { x: 12; y: 12; visible: t.icon !== ""; text: t.icon; color: "#ffffff"; font.pixelSize: 48 }
        Text { x: 12; y: 70; width: t.width - 22; text: t.sub; color: "#ffffff"; font.family: win.fnt; font.pixelSize: 18; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.NoWrap; lineHeight: 1.08 }
        Text { x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 10; width: t.width - 22; text: t.name; color: "#ffffff"; font.family: win.fnt; font.pixelSize: 20; elide: Text.ElideRight }
        Rectangle { visible: t.pct >= 0; anchors.bottom: parent.bottom; height: 4; width: t.width * Math.max(0, Math.min(100, t.pct)) / 100; color: "#ccffffff"
                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } } }
        MouseArea { id: ma; anchors.fill: parent; onClicked: t.clicked() }
    }
    component Head: Text { color: "#d0d0d0"; font.family: win.fnt; font.weight: Font.Light; font.pixelSize: 31; topPadding: 22; bottomPadding: 8 }
    component Note: Text { color: "#d0d0d0"; font.family: win.fnt; font.pixelSize: 19; wrapMode: Text.Wrap; width: parent ? parent.width : 600; bottomPadding: 8 }
    component KV: Item {
        property string k: ""
        property string v: ""
        width: parent ? parent.width : 600; height: 46
        Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.42; elide: Text.ElideRight; text: parent.k; color: "#ffffff"; font.family: win.fnt; font.pixelSize: 19 }
        Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.57; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
               text: parent.v; color: "#e0e0e0"; font.family: win.fnt; font.pixelSize: 19 }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#262626" }
    }
    component Btn: Rectangle {
        id: b
        property string text: ""
        property bool primary: false
        property bool danger: false
        signal clicked()
        width: bt.implicitWidth + 40; height: 50
        color: primary ? win.acc : "transparent"
        border.width: primary ? 0 : 2; border.color: danger ? "#b91d47" : "white"
        scale: bm.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Text { id: bt; anchors.centerIn: parent; text: b.text; color: b.danger ? "#ff8a80" : "white"; font.family: win.fnt; font.pixelSize: 20 }
        MouseArea { id: bm; anchors.fill: parent; onClicked: b.clicked() }
    }
    component Toggle: Item {
        id: tg
        property string label: ""
        property string hint: ""
        property bool on: false
        signal toggled(bool v)
        width: parent ? parent.width : 600; height: 64
        Column { anchors.verticalCenter: parent.verticalCenter
            Text { text: tg.label; color: "#ffffff"; font.family: win.fnt; font.pixelSize: 24 }
            Text { text: tg.hint; visible: tg.hint !== ""; color: "#d0d0d0"; font.family: win.fnt; font.pixelSize: 17 } }
        Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 66; height: 30
            color: tg.on ? win.acc : "transparent"; border.width: tg.on ? 0 : 2; border.color: "white"
            Rectangle { width: 20; height: 20; y: 5; x: tg.on ? 41 : 5; color: "white"; Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } } } }
        MouseArea { anchors.fill: parent; onClicked: { tg.on = !tg.on; tg.toggled(tg.on) } }
    }
    component Field: Rectangle {
        id: fd
        property alias text: ti.text
        property string placeholder: ""
        property bool secret: false
        width: parent ? parent.width : 600; height: 52; color: "white"
        border.width: ti.activeFocus ? 3 : 0; border.color: win.acc
        TextInput { id: ti; anchors.fill: parent; anchors.margins: 12; color: "black"; font.family: win.fnt; font.pixelSize: 19; clip: true
                    echoMode: fd.secret ? TextInput.Password : TextInput.Normal; verticalAlignment: TextInput.AlignVCenter
                    onActiveFocusChanged: win.ctl(activeFocus ? "kbd_show" : "kbd_hide") }
        Text { anchors.fill: ti; visible: ti.text === "" && !ti.activeFocus; text: fd.placeholder; color: "#888"; font: ti.font; verticalAlignment: Text.AlignVCenter }
    }
    component Item2: Item {   // settings list entry: big lowercase title + small hint
        id: it
        property string title: ""
        property string hint: ""
        signal clicked()
        property string tgroup: ""
        property int trow: 0
        property real tang: 0
        transform: Matrix4x4 { matrix: win.turnM(it.tang, it.height) }
        opacity: 1 - Math.min(1, Math.abs(it.tang) / 82)
        Turn { id: iTurn; target2: it; delay: it.trow * 30 }
        Connections { target: win; enabled: it.tgroup !== ""
            function onTurn(g, inn) { if (g !== it.tgroup) return; iTurn.stop(); if (inn && it.tang === 0) it.tang = 82; iTurn.inn = inn; iTurn.start() } }
        width: parent ? parent.width : 600; height: 80
        transformOrigin: Item.Left
        scale: im.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Column { anchors.verticalCenter: parent.verticalCenter
            Text { text: it.title; color: "#ffffff"; font.family: win.fnt; font.weight: Font.Light; font.pixelSize: 40 }
            Text { text: it.hint; visible: it.hint !== ""; color: "#d0d0d0"; font.family: win.fnt; font.pixelSize: 18 } }
        MouseArea { id: im; anchors.fill: parent; onClicked: it.clicked() }
    }
    component Slider2: Item {   // flat Metro slider
        id: sl
        property real from: 0
        property real to: 100
        property real value: 50
        property real step: 1
        signal moved(real v)
        width: parent ? parent.width : 600; height: 52
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; color: "#333" }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; height: 6; width: knob.x + 10; color: win.acc }
        Rectangle { id: knob; width: 20; height: 40; anchors.verticalCenter: parent.verticalCenter; color: "white"
                    x: (sl.value - sl.from) / Math.max(1, sl.to - sl.from) * (sl.width - width) }
        MouseArea { anchors.fill: parent; preventStealing: true
            function upd(mx) { var v = sl.from + Math.max(0, Math.min(1, (mx - 10) / (sl.width - 20))) * (sl.to - sl.from); v = Math.round(v / sl.step) * sl.step; if (v !== sl.value) { sl.value = v; sl.moved(v) } }
            onPressed: (m) => upd(m.x); onPositionChanged: (m) => upd(m.x) }
    }
    component Chooser: Item {   // tap -> list of options
        id: ch
        property var options: []
        property string value: ""
        signal picked(string v)
        width: parent ? parent.width : 600; height: 52
        Rectangle { anchors.fill: parent; color: "white"
            Text { anchors.verticalCenter: parent.verticalCenter; x: 12; text: ch.value + "  ▾"; color: "black"; font.family: win.fnt; font.pixelSize: 19 } }
        MouseArea { anchors.fill: parent; onClicked: win.choose(ch.options, ch.value, function (v) { ch.value = v; ch.picked(v) }) }
    }

    // ---------- installed apps (gta2-dash GET /apps; launch / uninstall via /ctl) and home pins (/ctl pins)
    ListModel { id: appsM }   // {id, name, icon, col}
    ListModel { id: pinsM }   // same fields, pinned to the home grid
    readonly property var appCols: ["#2d89ef", "#2b5797", "#1e7145", "#603cba", "#9f00a7", "#7e3878", "#da532c", "#00aba9", "#e3a21a"]
    function appCol(id) { var h = 0; for (var i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) % 9973; return appCols[h % appCols.length] }
    function normApp(a) {   // tolerant of the backend's field names
        var id = "" + (a.id || a.name || ""), ic = a.icon || a.icon_url || "";
        if (ic && ic[0] === "/") ic = "http://127.0.0.1:8088" + ic;
        return {id: id, name: "" + (a.name || a.title || id), icon: "" + ic, col: appCol(id), removable: a.removable !== false}
    }
    function loadApps() {
        req("GET", "http://127.0.0.1:8088/apps", undefined, function (s, j) {
            if (s !== 200 || !j) return;
            var L = Array.isArray(j) ? j : (j.apps || j.installed || []);
            L = L.slice().sort(function (a, b) { return (b.installed || b.t || b.mtime || 0) - (a.installed || a.t || a.mtime || 0) });
            syncModel(appsM, L.map(normApp));
            // drop pins of apps that are gone
            var have = {}; for (var i = 0; i < appsM.count; i++) have[appsM.get(i).id] = appsM.get(i);
            var p = []; for (var k = 0; k < pinsM.count; k++) { var o = pinsM.get(k); if (have[o.id]) p.push(have[o.id]) }
            if (p.length !== pinsM.count) { syncModel(pinsM, p); savePins() }
        })
    }
    function loadPins() { ctl("pins", undefined, function (j) { if (j && j.pins) { syncModel(pinsM, j.pins.map(normApp)); loadApps() } else loadApps() }) }
    function savePins() { var p = []; for (var i = 0; i < pinsM.count; i++) { var o = pinsM.get(i); p.push({id: o.id, name: o.name, icon: o.icon}) } ctl("pins", p) }
    function pinApp(a) { for (var i = 0; i < pinsM.count; i++) if (pinsM.get(i).id === a.id) { toast("already on start"); return } pinsM.append(a); savePins(); toast("pinned to start") }
    function unpinApp(id) { for (var i = 0; i < pinsM.count; i++) if (pinsM.get(i).id === id) { pinsM.remove(i); savePins(); return } }
    function launchApp(group, a) { launch(group, function () { ctl("launch", {id: a.id}, function (j) { if (!j) toast("could not start " + a.name) }) }) }
    property var jobApp: null
    function uninstallApp(a) {
        confirm("Uninstall " + a.name + "?", function () {
            jobApp = a; jobText.text = "uninstalling " + a.name + "…"; jobBox.y = 0;
            ctl("uninstall", {id: a.id}, function (j) { if (!j || j.ok === false) { jobText.text = (j && j.error) ? j.error : "uninstall failed to start"; jobDone.restart() } else jobPoll.start() })
        })
    }
    Timer { id: jobPoll; interval: 1000; repeat: true
        onTriggered: win.req("GET", "http://127.0.0.1:8088/apps/job", undefined, function (s, j) {
            if (!j) return;
            var p = j.progress != null ? Math.round(j.progress) + "% · " : "", line = ("" + (j.log || j.line || j.what || "")).trim().split("\n").pop();
            win.jobText.text = (win.jobApp ? win.jobApp.name : "") + " · " + p + line;
            if (j.state === "done" || j.state === "failed" || j.state === "idle") {
                jobPoll.stop(); var ok = j.state !== "failed" && !j.code;
                win.jobText.text = (win.jobApp ? win.jobApp.name : "") + (ok ? " uninstalled" : " · uninstall failed");
                if (ok && win.jobApp) win.unpinApp(win.jobApp.id); win.loadApps(); jobDone.restart() } }) }
    Timer { id: jobDone; interval: 2500; onTriggered: win.jobBox.y = -win.jobBox.height }
    property alias jobText: jobT
    // long-press menu (Metro context menu)
    property var ctxApp: null
    property bool ctxPinned: false
    function openCtx(a, pinned) { ctxApp = a; ctxPinned = pinned; ctxBox.visible = true }
    component AppTile: Rectangle {
        id: at
        property string aid: ""
        property string aname: ""
        property string aicon: ""
        property bool pinned: false
        property string tgroup: ""
        property real tang: 0
        readonly property int trow: Math.round(y / (win.tileW + win.gap))
        readonly property int tcol: Math.round(x / (win.tileW + win.gap))
        transform: Matrix4x4 { matrix: win.turnM(at.tang, at.height) }
        opacity: 1 - Math.min(1, Math.abs(at.tang) / 82)
        Turn { id: aTurn; target2: at; delay: (at.trow * 3 + at.tcol) * 24 }
        Connections { target: win; enabled: at.tgroup !== ""
            function onTurn(g, inn) { if (g !== at.tgroup) return; aTurn.stop(); if (inn && at.tang === 0) at.tang = 82; aTurn.inn = inn; aTurn.start() } }
        width: win.tileW; height: win.tileW
        scale: am.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Image { anchors.centerIn: parent; anchors.verticalCenterOffset: -12; width: 76; height: 76; sourceSize.width: 76; sourceSize.height: 76
                source: at.aicon; asynchronous: true; cache: true; fillMode: Image.PreserveAspectFit; smooth: true
                Text { anchors.centerIn: parent; visible: parent.status !== Image.Ready; text: at.aname.slice(0, 1).toUpperCase(); color: "#ffffff"; font.family: win.fnt; font.weight: Font.Light; font.pixelSize: 56 } }
        Text { x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 10; width: at.width - 22; text: at.aname; color: "#ffffff"; font.family: win.fnt; font.pixelSize: 20; elide: Text.ElideRight }
        MouseArea { id: am; anchors.fill: parent; pressAndHoldInterval: 550
            onClicked: win.launchApp(at.tgroup, {id: at.aid, name: at.aname, icon: at.aicon, col: at.color + ""})
            onPressAndHold: { var r = true; for (var i = 0; i < appsM.count; i++) if (appsM.get(i).id === at.aid) r = appsM.get(i).removable; win.openCtx({id: at.aid, name: at.aname, icon: at.aicon, col: at.color + "", removable: r}, at.pinned) } }
    }

    // ---------- live data (ListModel updated in place: delegates are never re-created)
    ListModel { id: tiles }
    property var tileIdx: ({})
    Component.onCompleted: {
        var L = [["net", "#2d89ef", true], ["lat", "#1e7145"], ["sp", "#2b5797"], ["dev", "#603cba"], ["ph", "#9f00a7"], ["phq", "#7e3878"],
                 ["cpu", "#da532c"], ["mem", "#603cba"], ["bat", "#00aba9"], ["wifi", "#2d89ef", true], ["disk", "#2b5797"], ["today", "#e3a21a"],
                 ["up", "#1d1d1d"], ["ctr", "#1e7145"]];
        var idx = {};
        for (var i = 0; i < L.length; i++) { idx[L[i][0]] = i; tiles.append({key: L[i][0], col: L[i][1], wide: !!L[i][2], val: "–", unit: "", sub: "", name: "", pct: -1}) }
        tileIdx = idx; clock(); load(); live(); loadPins()
    }
    function setT(k, val, unit, sub, name, pct, col) {
        var i = tileIdx[k]; if (i === undefined) return;
        var o = tiles.get(i);
        if (o.val !== val) tiles.setProperty(i, "val", val);
        if (o.unit !== unit) tiles.setProperty(i, "unit", unit);
        if (o.sub !== sub) tiles.setProperty(i, "sub", sub);
        if (o.name !== name) tiles.setProperty(i, "name", name);
        var p = pct == null ? -1 : pct; if (o.pct !== p) tiles.setProperty(i, "pct", p);
        if (col && o.col !== col) tiles.setProperty(i, "col", col);
    }
    function clock() { var n = new Date(); setT("up", Qt.formatTime(n, "HH:mm"), "", Qt.formatDate(n, "dddd") + "\n" + Qt.formatDate(n, "d MMMM"), "", null) }
    property var liveRx: []
    property var liveTx: []
    function liveTiles(d) {
        var n = d.net || {}, L = n.lat || {}, r = d.router || {};
        var rx = r.ok ? r.rx_mbit : (n.rate ? n.rate.rx : null), tx = r.ok ? r.tx_mbit : (n.rate ? n.rate.tx : null);
        if (rx != null) { liveRx.push(rx); liveTx.push(tx || 0); if (liveRx.length > 150) { liveRx.shift(); liveTx.shift() } }
        var on = !!n.online, nm = on ? "internet · online" : "internet · OFFLINE", c = on ? "#2d89ef" : "#b91d47";
        if (r.ok) setT("net", f(r.rx_mbit, 1), "Mbit/s ↓", "↑ " + f(r.tx_mbit, 1) + " Mbit/s · whole home", nm, null, c);
        else if (n.rate) setT("net", f(n.rate.rx, 1), "Mbit/s ↓", "↑ " + f(n.rate.tx, 1) + " Mbit/s · tablet", nm, null, c);
        setT("lat", f(L["1.1.1.1"]), "ms", "router " + f(L.router) + " ms\n8.8.8.8 " + f(L["8.8.8.8"]) + " ms", "latency", null, lvl(L["1.1.1.1"], 30, 80));
    }
    property var netRows: []
    property var ctrRows: []
    property var aboutRows: []
    property var latPts: []
    function load() {
        if (busy) { retry.start(); return }
        req("GET", "http://127.0.0.1:8088/api", undefined, function (s, d) {
            if (!d) { setT("net", "–", "", "tablet service unreachable", "offline", null, "#b91d47"); return }
            if (win.busy) { win.pendApi = d; return }
            applyApi(d)
        });
    }
    function applyApi(d) {
            liveTiles(d);
            var n = d.net || {}, r = d.router || {}, sp = (n.speed || []).filter(function (x) { return x.down != null }), last = sp[sp.length - 1], p = d.pihole, m = d.mem || [0, 1], b = d.battery, ni = d.netinfo || {};
            setT("sp", last ? f(last.down) : "–", last ? "↓" : "", last ? "↑ " + f(last.up) + " Mbit/s\n" + ago(last.t) : "every 15 min\non Ethernet", "speed test · tap", null);
            setT("dev", r.ok ? f(r.clients) : "–", "", r.ok ? "router up " + dur(r.uptime) : "no router data", "devices", null);
            if (p) { setT("ph", f(p.percent, 1), "%", f(p.blocked) + " blocked", "pi-hole", p.percent); setT("phq", f(p.total), "", f(p.clients) + " clients", "dns queries", null) }
            setT("cpu", f(d.cpu_pct), "%", f(d.temp) + " °C · " + (d.cpu_mhz || []).map(function (x) { return (x / 1000).toFixed(1) }).join("/") + " GHz", "cpu", d.cpu_pct, d.temp >= 78 ? "#b91d47" : "#da532c");
            setT("mem", f(m[0] / 1024, 1), "GB", "of " + f(m[1] / 1024, 1) + " GB", "memory", 100 * m[0] / m[1]);
            if (b) setT("bat", "" + b.pct, "%", (b.plugged ? "plugged in\n" : "") + (b.status || "").toLowerCase(), "battery", b.pct, b.pct > 20 ? "#00aba9" : "#b91d47");
            var dk = d.disks || [], big = dk.filter(function (x) { return x.name === "Share drive" })[0] || dk.filter(function (x) { return x.name === "Data" })[0] || dk[0];
            if (big) setT("disk", f(big.total - big.used), "GB free", dk.map(function (x) { return x.name.toLowerCase() + " " + f(x.total - x.used) + "/" + f(x.total) }).join("\n"), "storage", 100 * big.used / big.total);
            var ifs = ni.ifs || [], w = ni.wifi, eth = ifs.filter(function (i) { return i.kind === "ethernet" && i.ip })[0], main = eth || ifs.filter(function (i) { return i.ip })[0];
            var ip = main ? main.ip.split("/")[0] : "";
            if (eth) setT("wifi", eth.speed ? (eth.speed >= 1000 ? f(eth.speed / 1000) : f(eth.speed)) : "", eth.speed ? (eth.speed >= 1000 ? "Gbit ethernet" : "Mbit ethernet") : "ethernet",
                          ip + (w ? " · " + w.ssid + " " + w.signal + "%" : "") + "\ngateway " + (ni.gw || "–"), "network", null);
            else setT("wifi", w ? "" + w.signal : "–", w ? "% wi-fi" : "no network", (ip ? ip + " · " : "") + (w ? w.ssid : "wi-fi off") + "\ngateway " + (ni.gw || "–"), "network", null);
            if (r.ok && (r.today_bytes != null || r.month_rx != null)) {
                var tb = r.today_bytes != null ? gb(r.today_bytes) : gb((r.month_rx || 0) + (r.month_tx || 0)), parts = tb.split(" ");
                setT("today", parts[0], parts[1] || "", r.line_down ? "line " + f(r.line_down / 1000) + "/" + f(r.line_up / 1000) + " Mbit" : "", "data " + (r.today_bytes != null ? "today" : "this month"), null);
            } else setT("today", "–", "", "", "data", null);
            var cs = d.containers || [];
            setT("ctr", "" + cs.length, d.docker_total != null ? "/ " + d.docker_total : "", cs.slice(0, 2).map(function (c) { return c.name }).join("\n"), "containers", null);
            clock();
            var rows = ifs.map(function (i) { return [i.name + " · " + i.kind + (i.speed ? " · " + i.speed + " Mbit" : ""), (i.ip || "no address") + " · ↓" + gb(i.rx) + " ↑" + gb(i.tx)] });
            if (w) rows.push(["wi-fi", w.ssid + " · " + w.signal + "% · " + w.freq + " · " + w.rate]);
            rows.push(["gateway", ni.gw || "–"]);
            if (r.ok) rows.push(["router", "WAN " + (r.wan_up === false ? "down" : "up") + " · up " + dur(r.uptime) + (r.fw ? " · fw " + r.fw : "")]);
            rows.push(["dashboard", "http://" + (ip || "tablet") + ":8088"]);
            if (JSON.stringify(rows) !== JSON.stringify(netRows)) netRows = rows;
            var cr = cs.map(function (c) { return [c.name, c.status] });
            if (JSON.stringify(cr) !== JSON.stringify(ctrRows)) ctrRows = cr;
            var ab = [["name", d.host], ["kernel", d.kernel || ""], ["uptime", dur(d.uptime)], ["load", (d.load || []).join(" ")]];
            if (JSON.stringify(ab) !== JSON.stringify(aboutRows)) aboutRows = ab;
            var h = (n.hist || []).map(function (x) { return x[1] }).filter(function (x) { return x != null });
            if (h.length > 1 && JSON.stringify(h) !== JSON.stringify(latPts)) { latPts = h; chart.requestPaint() }
    }
    function live() { if (busy) return; req("GET", "http://127.0.0.1:8088/live", undefined, function (s, d) { if (!d) return; if (win.busy) win.pendLive = d; else liveTiles(d) }) }
    property var pendLive: null
    property var pendApi: null
    Timer { interval: 150; repeat: true; running: win.pendLive !== null || win.pendApi !== null
        onTriggered: { if (win.busy) return; if (win.pendApi) { var a = win.pendApi; win.pendApi = null; win.applyApi(a) } else if (win.pendLive) { var l = win.pendLive; win.pendLive = null; win.liveTiles(l) } } }
    Timer { id: retry; interval: 500; onTriggered: win.load() }
    Timer { interval: 10000; running: true; repeat: true; onTriggered: win.load() }
    Timer { interval: 2000; running: true; repeat: true; onTriggered: win.live() }
    Timer { interval: 15000; running: true; repeat: true; onTriggered: win.clock() }

    // HOME key from gta2-keys: /tmp/gta2-home.cmd changes -> back to the home pivot, close sub pages
    property string lastCmd: ""
    Timer { interval: 400; running: true; repeat: true
        onTriggered: { var x = new XMLHttpRequest(); x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return; var c = (x.responseText || "").trim();
            if (c !== "" && c !== win.lastCmd) { var first = win.lastCmd === ""; win.lastCmd = c; if (!first) win.goHome() } };
            x.open("GET", "file:///tmp/gta2-home.cmd"); x.send() } }
    function goHome() { unflip(); loadApps(); closeDetail(); closeSub(); chooserBox.visible = false; pv.currentIndex = 0; pages.forEach(function (p) { p.contentY = 0 }); win.ctl("kbd_hide") }
    Shortcut { sequences: ["Esc", "Back"]; onActivated: { if (ctxBox.visible) ctxBox.visible = false; else if (chooserBox.visible) chooserBox.visible = false; else if (sub.open) win.closeSub(); else if (det.open) win.closeDetail(); else pv.currentIndex = 0 } }

    // ---------- panorama
    Text { // parallax title
        x: win.pad - pv.contentX * 0.18; y: 0; text: "gta2srv"; color: "#22ffffff"
        font.family: win.fnt; font.weight: Font.Light; font.pixelSize: 110
    }
    readonly property var pivotNames: ["home", "apps", "screen", "settings"]
    Row {
        id: pivots
        y: 76; spacing: 26
        property real pos: pv.width > 0 ? pv.contentX / pv.width : 0
        x: win.pad - offsetAt(pos)
        function offsetAt(p) { var i = Math.floor(p), fr = p - i, a = 0; for (var k = 0; k < i && k < rep.count; k++) a += rep.itemAt(k).width + spacing;
                               var nxt = i < rep.count ? rep.itemAt(i).width + spacing : 0; return a + nxt * fr }
        Repeater { id: rep; model: win.pivotNames
            Text { text: modelData; font.family: win.fnt; font.weight: Font.Light; font.pixelSize: 48
                   color: Math.abs(pivots.pos - index) < 0.5 ? "white" : "#3a3a3a"
                   MouseArea { anchors.fill: parent; onClicked: pv.currentIndex = index } } }
    }
    property var pages: [pHome, pApps, pScreen, pSet]
    ListView {
        id: pv
        y: 150; width: win.width; height: win.height - y
        orientation: ListView.Horizontal; snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange; highlightMoveDuration: 260; highlightMoveVelocity: -1
        boundsBehavior: Flickable.StopAtBounds; flickDeceleration: 4000; maximumFlickVelocity: 6000
        cacheBuffer: 10000
        onCurrentIndexChanged: { if (currentIndex === 1) win.turn("apps", true); else if (currentIndex === 3 && !sub.open) win.turn("set", true) }
        model: ObjectModel {
            // ---- HOME
            Flickable { id: pHome; width: pv.width; height: pv.height; contentHeight: homeCol.height + 60; flickableDirection: Flickable.VerticalFlick; clip: true; pressDelay: 0; flickDeceleration: 1500; maximumFlickVelocity: 4000
                Column { id: homeCol; x: win.pad; width: pv.width - 2 * win.pad; spacing: 0
                    Flow { width: parent.width; spacing: win.gap
                        Repeater { model: tiles
                            Tile { tgroup: "home"; color: model.col; wide: model.wide; val: model.val; unit: model.unit; sub: model.sub; name: model.name; pct: model.pct
                                   onClicked: win.openDetail(model.key) } }
                        Repeater { model: pinsM
                            AppTile { tgroup: "home"; pinned: true; color: model.col; aid: model.id; aname: model.name; aicon: model.icon } } }
                    Head { text: "network" }
                    Repeater { model: win.netRows; KV { k: modelData[0]; v: modelData[1] } }
                    Head { text: "latency · 3 h" }
                    Rectangle { width: parent.width; height: 150; color: "#1d1d1d"
                        Canvas { id: chart; anchors.fill: parent; anchors.margins: 10; renderStrategy: Canvas.Cooperative
                            onPaint: { var c = getContext("2d"); c.reset(); var h = win.latPts; if (h.length < 2) return; var mx = Math.max.apply(null, h.concat([1]));
                                c.strokeStyle = "#e3a21a"; c.lineWidth = 2; c.beginPath();
                                for (var i = 0; i < h.length; i++) { var X = i * width / (h.length - 1), Y = height - 4 - (height - 8) * h[i] / mx; if (i) c.lineTo(X, Y); else c.moveTo(X, Y) }
                                c.stroke() } } }
                } }
            // ---- APPS
            Flickable { id: pApps; width: pv.width; height: pv.height; contentHeight: appsCol.height + 60; flickableDirection: Flickable.VerticalFlick; clip: true; pressDelay: 0; flickDeceleration: 1500; maximumFlickVelocity: 4000
                Column { id: appsCol; x: win.pad; width: pv.width - 2 * win.pad
                    Flow { width: parent.width; spacing: win.gap
                        Repeater { model: [["files", "#1e7145", "▤", "/#/files"], ["app store", "#2d89ef", "⇣", "/#/"], ["casaos", "#2b5797", "⌂", "/"], ["pi-hole", "#9f00a7", "⛨", ":8083/admin/"],
                                           ["portainer", "#00aba9", "▣", ":9000/"], ["terminal", "#1d1d1d", "›_", "!terminal"], ["keyboard", "#555555", "⌨", "!keyboard"], ["classic panel", "#7e3878", "☰", ":8090/"],
                                           ["desktop", "#2b5797", "▭", "!desktop"], ["store", "#1e7145", "✚", "!store"]]
                            Tile { tgroup: "apps"; color: modelData[1]; icon: modelData[2]; name: modelData[0]
                                   onClicked: { var u = modelData[3];
                                       if (u === "!keyboard") { win.ctl("keyboard"); return }
                                       win.launch("apps", function () {
                                           if (u === "!desktop") win.ctl("desktop", "left", function (j) { if (!j) win.toast("desktop mode is not available yet") });
                                           else if (u === "!store") win.ctl("launch", {id: "pi-apps"}, function (j) { if (!j || j.ok === false) win.toast("Pi-Apps store is not installed yet") });
                                           else if (u[0] === "!") win.ctl(u.slice(1)); else win.ctl("open", win.base + u) }) } } } }
                    Head { text: "installed apps"; visible: appsM.count > 0 }
                    Flow { width: parent.width; spacing: win.gap; visible: appsM.count > 0
                        Repeater { model: appsM
                            AppTile { tgroup: "apps"; color: model.col; aid: model.id; aname: model.name; aicon: model.icon } } }
                    Note { visible: appsM.count === 0; topPadding: 16; text: "Apps you install from the store (Pi-Apps) appear here. Hold an app tile to pin it to start or uninstall it." }
                    Head { text: "containers" }
                    Repeater { model: win.ctrRows; KV { k: modelData[0]; v: modelData[1] } }
                    Note { visible: win.ctrRows.length === 0; text: "no containers running" }
                } }
            // ---- SCREEN
            Flickable { id: pScreen; width: pv.width; height: pv.height; contentHeight: scrCol.height + 60; flickableDirection: Flickable.VerticalFlick; clip: true; pressDelay: 0; flickDeceleration: 1500; maximumFlickVelocity: 4000
                property real tang: 0
                transform: Matrix4x4 { matrix: win.turnM(pScreen.tang, pScreen.height) }
                opacity: 1 - Math.min(1, Math.abs(pScreen.tang) / 82)
                Turn { id: sTurn; target2: pScreen }
                Connections { target: win; function onTurn(g, inn) { if (g !== "screen") return; sTurn.stop(); if (inn && pScreen.tang === 0) pScreen.tang = 82; sTurn.inn = inn; sTurn.start() } }
                Column { id: scrCol; x: win.pad; width: pv.width - 2 * win.pad; spacing: 6
                    Head { text: "vnc"; topPadding: 0 }
                    Note { text: "Connect to a VNC server on your PC (TightVNC, TigerVNC, RealVNC…)." }
                    Field { id: vncAddr; placeholder: "192.168.1.x:5900" }
                    Btn { text: "connect"; primary: true; onClicked: { if (vncAddr.text.trim() === "") win.toast("enter the PC address first"); else { win.ctl("kbd_hide"); var a = vncAddr.text.trim(); win.launch("screen", function () { win.ctl("vnc", a) }) } } }
                    Head { text: "moonlight" }
                    Note { text: "Stream your PC from Sunshine or NVIDIA GameStream. Pick 720p, 30–60 fps." }
                    Btn { text: "open moonlight"; primary: true; onClicked: win.launch("screen", function () { win.ctl("moonlight") }) }
                    Head { text: "extend windows" }
                    Note { text: "spacedesk discontinued its browser viewer, so it cannot run on Linux. Same result, smoother: on the PC install Sunshine and a free virtual display driver (\"Virtual Display Driver\" on GitHub). Windows then gets a real extra monitor: pick it in Sunshine, then open Moonlight here and choose Desktop." }
                } }
            // ---- SETTINGS
            Flickable { id: pSet; width: pv.width; height: pv.height; contentHeight: setCol.height + 60; flickableDirection: Flickable.VerticalFlick; clip: true; pressDelay: 0; flickDeceleration: 1500; maximumFlickVelocity: 4000
                Column { id: setCol; x: win.pad; width: pv.width - 2 * win.pad
                    Repeater { model: win.sections; Item2 { tgroup: "set"; trow: index; title: modelData[0]; hint: modelData[1]; onClicked: win.openSub(index) } }
                } }
        }
    }


    // ---------- detail pages: tap a home tile -> breakdown from GET /detail?k=<tile> (refreshed only while open)
    readonly property var detTitles: ({net: "internet", lat: "latency", sp: "speed test", dev: "devices", ph: "pi-hole", phq: "dns queries", cpu: "cpu",
                                       mem: "memory", bat: "battery", disk: "storage", wifi: "network", today: "data used", up: "system", ctr: "containers"})
    property string detKey: ""
    property var detCharts: []
    property var detActions: []
    ListModel { id: heroM }
    ListModel { id: rowM }      // flattened sections: {h: true, k: head} or {h: false, k, v}
    signal chartsChanged2()
    function openDetail(k) {
        detKey = k; detTitle.text = detTitles[k] || k; heroM.clear(); rowM.clear(); detCharts = []; detActions = []; detNote.visible = true;
        detFlick.contentY = 0; turn("home", false); detOpenT.restart(); detTimer.interval = (k === "cpu" || k === "net" || k === "lat") ? 2000 : 4000;
        detFirst.restart()
    }
    function closeDetail() { if (!det.open && !detOpenT.running) return; detOpenT.stop(); det.open = false; detKey = ""; detBackT.restart() }
    Timer { id: detOpenT; interval: 170; onTriggered: det.open = true }          // tiles swing away first (WP turnstile)
    Timer { id: detBackT; interval: 120; onTriggered: win.turn("home", true) }  // then swing back in behind the closing page
    function syncModel(m, arr) {   // update a ListModel in place (no delegate re-creation when only values change)
        for (var i = 0; i < arr.length; i++) {
            if (i < m.count) { var o = m.get(i); for (var p in arr[i]) if (o[p] !== arr[i][p]) m.setProperty(i, p, arr[i][p]) }
            else m.append(arr[i])
        }
        while (m.count > arr.length) m.remove(m.count - 1)
    }
    function detLoad() {
        if (!det.open || detKey === "") return;
        if (busy) { detRetry.start(); return }
        var k = detKey;
        req("GET", "http://127.0.0.1:8088/detail?k=" + k, undefined, function (s, d) {
            if (!d || k !== detKey) return;
            if (busy) { pendingD = d; detApplyT.start(); return }   // never build rows while the page slides
            detApply(d)
        })
    }
    property var pendingD: null
    Timer { id: detApplyT; interval: 120; repeat: true; onTriggered: { if (win.busy) return; stop(); if (win.pendingD) { var d = win.pendingD; win.pendingD = null; win.detApply(d) } } }
    function detApply(d) {
            detNote.visible = false;
            syncModel(heroM, (d.hero || []).map(function (h) { return {l: "" + h[0], v: "" + h[1], u: "" + h[2]} }));
            var rows = [];
            (d.sections || []).forEach(function (sct) { rows.push({h: true, k: sct.head, v: ""}); (sct.rows || []).forEach(function (r) { rows.push({h: false, k: "" + r[0], v: "" + r[1]}) }) });
            syncModel(rowM, rows);
            var ch = d.charts || [];
            ch.forEach(function (c) { if (c.live) c.series = [{c: "#2d89ef", pts: win.liveRx.slice()}, {c: "#e3a21a", pts: win.liveTx.slice()}] });
            detCharts = ch; detActions = d.actions || [];
            chartsChanged2();
    }
    Timer { id: detTimer; interval: 3000; repeat: true; running: det.open; onTriggered: win.detLoad() }
    Timer { id: detRetry; interval: 400; onTriggered: win.detLoad() }
    Timer { id: detFirst; interval: 300; onTriggered: win.detLoad() }
    component Hero: Item {
        id: hr
        property string l: ""
        property string v: ""
        property string u: ""
        readonly property bool numeric: /^-?[0-9]+(\.[0-9]+)?$/.test(v)
        readonly property int dec: numeric ? (v.split(".")[1] || "").length : 0
        property real shown: numeric ? parseFloat(v) : 0
        Behavior on shown { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
        width: Math.max(150, hv.width + hu.width + 16); height: 104
        Text { id: hv; y: 0; text: hr.numeric ? hr.shown.toFixed(hr.dec) : hr.v; color: "#ffffff"; font.family: win.fnt; font.weight: Font.Light; font.pixelSize: 64 }
        Text { id: hu; anchors.left: hv.right; anchors.leftMargin: 6; anchors.baseline: hv.baseline; text: hr.u; color: "#ffffff"; font.family: win.fnt; font.pixelSize: 22 }
        Text { y: 76; text: hr.l; color: "#d0d0d0"; font.family: win.fnt; font.pixelSize: 19 }
    }
    component Chart: Rectangle {
        id: cr
        property int idx: 0
        property var c: idx < win.detCharts.length ? win.detCharts[idx] : null
        width: parent ? parent.width : 600; height: 230; color: "#141414"
        Text { x: 12; y: 8; text: cr.c ? cr.c.name : ""; color: "#d0d0d0"; font.family: win.fnt; font.pixelSize: 17 }
        Text { id: mxT; anchors.right: parent.right; anchors.rightMargin: 12; y: 8; color: "#d0d0d0"; font.family: win.fnt; font.pixelSize: 15 }
        Canvas { id: cv; x: 10; y: 36; width: parent.width - 20; height: parent.height - 46; renderStrategy: Canvas.Cooperative
            onPaint: {
                var g = getContext("2d"); g.reset(); if (!cr.c) return;
                var mx = 1, ser = cr.c.series || [];
                ser.forEach(function (s) { (s.pts || []).forEach(function (p) { if (p != null && p > mx) mx = p }) });
                mxT.text = "max " + (mx >= 100 ? Math.round(mx) : mx.toFixed(1)) + " " + (cr.c.unit || "");
                g.strokeStyle = "#2a2a2a"; g.lineWidth = 1;
                for (var q = 1; q < 4; q++) { g.beginPath(); g.moveTo(0, height * q / 4); g.lineTo(width, height * q / 4); g.stroke() }
                ser.forEach(function (s) {
                    var p = s.pts || []; if (p.length < 2) return;
                    g.strokeStyle = s.c; g.lineWidth = 2.5; g.beginPath(); var pen = false;
                    for (var i = 0; i < p.length; i++) {
                        if (p[i] == null) { pen = false; continue }
                        var X = i * width / (p.length - 1), Y = height - 3 - (height - 6) * p[i] / mx;
                        if (pen) g.lineTo(X, Y); else { g.moveTo(X, Y); pen = true }
                    }
                    g.stroke()
                })
            } }
        Connections { target: win; function onChartsChanged2() { cv.requestPaint() } }
    }
    Rectangle {
        id: det
        property bool open: false
        width: win.width; height: win.height; color: "black"; z: 4
        property real slide: open ? 0 : 1     // 0 = shown; WP "continuum": short slide + fade, rows follow with a lag
        Behavior on slide { NumberAnimation { duration: det.open ? 260 : 170; easing.type: det.open ? Easing.OutCubic : Easing.InCubic } }
        opacity: 1 - slide
        transform: Translate { x: det.slide * 110 }
        visible: slide < 0.999
        MouseArea { anchors.fill: parent }
        Flickable { id: detFlick; anchors.fill: parent; contentHeight: detCol.height + 80; clip: true
            Column { id: detCol; x: win.pad; y: 20; width: win.width - 2 * win.pad; spacing: 8
                Rectangle { width: 50; height: 50; radius: 25; color: "transparent"; border.color: "white"; border.width: 2
                    Text { anchors.centerIn: parent; text: "←"; color: "white"; font.pixelSize: 24 }
                    MouseArea { anchors.fill: parent; onClicked: win.closeDetail() } }
                Text { text: "DETAILS"; color: "#d0d0d0"; font.family: win.fnt; font.pixelSize: 17; font.letterSpacing: 1 }
                Text { id: detTitle; color: "#ffffff"; font.family: win.fnt; font.weight: Font.Light; font.pixelSize: 60; bottomPadding: 6; transform: Translate { x: det.slide * 70 } }
                Note { id: detNote; text: "loading…" }
                Flow { width: parent.width; spacing: 18; transform: Translate { x: det.slide * 150 }
                       Repeater { model: heroM; Hero { l: model.l; v: model.v; u: model.u } } }
                Repeater { model: win.detCharts.length; Chart { idx: index } }
                Flow { width: parent.width; spacing: 10; visible: win.detActions.length > 0
                    Repeater { model: win.detActions
                        Btn { text: modelData[0]; primary: true
                              onClicked: { var a = modelData[1];
                                  if (a === "speedtest") win.req("POST", "http://127.0.0.1:8088/speedtest", "", function () { win.toast("speed test started… about a minute") });
                                  else if (a.indexOf("open:") === 0) { win.ctl("open", a.slice(5)); win.toast("opening…") } } } } }
                Repeater { model: rowM
                    Loader { width: detCol.width; transform: Translate { x: det.slide * Math.min(320, 170 + index * 14) }
                    sourceComponent: model.h ? detHeadC : detRowC
                             property string k: model.k; property string v: model.v } }
            } }
    }
    Component { id: detHeadC; Head { text: parent ? parent.k : "" } }
    Component { id: detRowC; KV { k: parent ? parent.k : ""; v: parent ? parent.v : "" } }

    // ---------- settings sub pages
    readonly property var sections: [["wi-fi", "networks, connect, forget"], ["hotspot & tether", "share the connection"], ["vpn", "tailscale, wireguard"],
        ["bluetooth", "devices, pairing"], ["display", "brightness, screen timeout"], ["battery", "charge limit for 24/7 use"], ["performance", "cpu governor, max clock, throttling"],
        ["file sharing", "SMB / SFTP for the NAS share"], ["remote access", "ssh"], ["date & time", "time zone, network time"], ["device", "name, login password"],
        ["updates", "ubuntu packages, free space"], ["interface", "home screen, classic launcher, restart"], ["storage", "external drive for apps"], ["power", "restart, shut down"], ["about", "credits, versions, thank you"]]
    property var st: ({})
    property int subIndex: -1
    function openSub(i) {
        subIndex = i; subTitle.text = sections[i][0]; out.text = ""; subLoader.sourceComponent = loadingC; turn("set", false); sub.open = true; subFlick.contentY = 0;
        ctl("status", undefined, function (j) { if (j) st = j; subLoader.sourceComponent = subComps[i] })
    }
    function closeSub() { if (!sub.open) return; sub.open = false; turn("set", true); ctl("kbd_hide") }
    Rectangle {
        id: sub
        property bool open: false
        width: win.width; height: win.height; color: "black"
        property real tang: open ? 0 : 82
        Behavior on tang { NumberAnimation { duration: 320; easing.type: sub.open ? Easing.OutExpo : Easing.InCubic } }
        transform: Matrix4x4 { matrix: win.turnM(sub.tang, sub.height) }
        opacity: 1 - Math.min(1, sub.tang / 82)
        visible: tang < 81.5
        MouseArea { anchors.fill: parent }  // swallow taps
        Flickable { id: subFlick; anchors.fill: parent; contentHeight: subCol.height + 80; clip: true
            Column { id: subCol; x: win.pad; y: 20; width: win.width - 2 * win.pad; spacing: 6
                Rectangle { width: 50; height: 50; radius: 25; color: "transparent"; border.color: "white"; border.width: 2
                    Text { anchors.centerIn: parent; text: "←"; color: "white"; font.pixelSize: 24 }
                    MouseArea { anchors.fill: parent; onClicked: win.closeSub() } }
                Text { text: "SETTINGS"; color: win.mut; font.family: win.fnt; font.pixelSize: 16; font.letterSpacing: 1 }
                Text { id: subTitle; color: "white"; font.family: win.fnt; font.weight: Font.Light; font.pixelSize: 58; bottomPadding: 10 }
                Loader { id: subLoader; width: parent.width }
                Text { id: out; width: parent.width; wrapMode: Text.Wrap; color: win.mut; font.family: "DejaVu Sans Mono"; font.pixelSize: 14; topPadding: 12 }
            } }
    }
    Component { id: loadingC; Note { text: "loading…" } }
    property var subComps: [wifiC, hotC, vpnC, btC, dispC, batC, perfC, shareC, sshC, timeC, devC, updC, uiC, storC, powC, aboutC]

    Component { id: wifiC
        Column { spacing: 6; width: parent ? parent.width : 600
            property var nets: []
            property int sel: -1
            Toggle { label: "Wi-Fi"; on: !!win.st.wifi_on; onToggled: (v) => win.ctl("wifi_radio", v ? "on" : "off", function (j) { win.toast(j ? j.out || "ok" : "failed") }) }
            Btn { text: "scan"; primary: true; onClicked: parent.scan() }
            function scan() { note.text = "scanning…"; nets = []; sel = -1; win.ctl("wifi_scan", undefined, function (j) { nets = (j && j.list) || []; note.text = nets.length ? "" : "nothing found" }) }
            Note { id: note; text: "tap scan" }
            Repeater { model: parent.nets
                Item2 { title: modelData.ssid; hint: (modelData.on ? "connected · " : modelData.saved ? "saved · " : "") + modelData.signal + "% · " + (modelData.sec || "open")
                        onClicked: parent.sel = index } }
            Column { visible: parent.sel >= 0; width: parent.width; spacing: 6
                property var w: parent.sel >= 0 ? parent.nets[parent.sel] : null
                Head { text: parent.w ? parent.w.ssid : "" }
                Field { id: wpw; secret: true; placeholder: "password"; visible: parent.w && parent.w.sec && !parent.w.saved }
                Row { spacing: 10
                    Btn { text: "connect"; primary: true; onClicked: { var w = parent.parent.w; out.text = "connecting…"; win.ctl("kbd_hide")
                        win.ctl("wifi_connect", {ssid: w.ssid, pw: wpw.text}, function (j) { var o = j ? j.out : "failed"; out.text = o; win.toast(o.indexOf("success") >= 0 ? "connected" : "see message") }) } }
                    Btn { text: "forget"; danger: true; visible: parent.parent.w && parent.parent.w.saved
                          onClicked: win.ctl("wifi_forget", parent.parent.w.ssid, function (j) { out.text = j ? j.out : "failed" }) } } }
            Component.onCompleted: scan()
        } }
    Component { id: hotC
        Column { spacing: 6; width: parent ? parent.width : 600
            Note { text: "The tablet becomes a Wi-Fi access point (its own Wi-Fi client is off meanwhile). Now: hotspot " + ((win.st.hotspot || {}).hotspot || "?") }
            Field { id: hs; text: (win.st.host || "gta2srv") + "-ap" }
            Field { id: hp; secret: true; placeholder: "password, 8+ characters" }
            Row { spacing: 10
                Btn { text: "start hotspot"; primary: true; onClicked: { win.ctl("kbd_hide"); win.sys(["hotspot", "on", hs.text, hp.text]) } }
                Btn { text: "stop"; onClicked: win.sys(["hotspot", "off"]) } }
            Toggle { label: "USB tether"; hint: "a laptop on the USB cable gets internet"; on: (win.st.hotspot || {}).tether === "on"; onToggled: (v) => win.sys(["hotspot", v ? "tether-on" : "tether-off"]) }
        } }
    Component { id: vpnC
        Column { spacing: 6; width: parent ? parent.width : 600
            Note { text: win.st.vpn || "" }
            Head { text: "tailscale" }
            Note { text: "\"sign in\" shows a link: open it on your phone." }
            Flow { width: parent.width; spacing: 10
                Btn { text: "install"; onClicked: win.sys(["vpn", "ts-install"]) }
                Btn { text: "sign in / up"; primary: true; onClicked: win.sys(["vpn", "ts-up"]) }
                Btn { text: "down"; onClicked: win.sys(["vpn", "ts-down"]) } }
            Head { text: "wireguard" }
            Note { text: "put wg0.conf in the Files share, then tap up." }
            Flow { width: parent.width; spacing: 10
                Btn { text: "install"; onClicked: win.sys(["vpn", "wg-install"]) }
                Btn { text: "up"; primary: true; onClicked: win.sys(["vpn", "wg-up"]) }
                Btn { text: "down"; onClicked: win.sys(["vpn", "wg-down"]) } }
        } }
    Component { id: btC
        Column { spacing: 6; width: parent ? parent.width : 600
            property var devs: []
            Toggle { label: "Bluetooth"; on: !!(win.st.bt || {}).on; onToggled: (v) => win.sys(["bt", "power", v ? "on" : "off"]) }
            Note { text: (win.st.bt || {}).text || "" }
            Btn { text: "scan 10 s"; primary: true; onClicked: { var c = parent; win.sys(["bt", "scan"], function (o) {
                c.devs = (o || "").split("\n").filter(function (l) { return l.indexOf("Device ") === 0 }).map(function (l) { var p = l.split(" "); return [p[1], p.slice(2).join(" ")] }) }) } }
            Repeater { model: parent.devs; Item2 { title: modelData[1] || modelData[0]; hint: modelData[0] + " · tap to pair"; onClicked: win.sys(["bt", "pair", modelData[0]]) } }
        } }
    Component { id: dispC
        Column { spacing: 6; width: parent ? parent.width : 600
            Head { text: "brightness"; topPadding: 0 }
            Slider2 { id: br; from: 5; to: 255; value: 128; onMoved: (v) => brT.restart() }
            Timer { id: brT; interval: 80; onTriggered: win.ctl("bright", Math.round(br.value)) }
            Head { text: "turn the screen off after" }
            Chooser { options: ["never", "1 min", "2 min", "5 min", "10 min", "15 min", "30 min", "60 min"]
                      value: { var m = (win.st.ui || {}).screen_off || 0; return m ? m + " min" : "never" }
                      onPicked: (v) => win.ctl("ui", v === "never" ? 0 : parseInt(v), function () { win.toast("saved") }) }
            Flow { width: parent.width; spacing: 10; topPadding: 10
                Btn { text: "screen off now"; onClicked: win.ctl("screenoff") }
                Btn { text: "keyboard"; onClicked: win.ctl("keyboard") } }
            Toggle { label: "On-screen buttons"; hint: "back · home · keyboard bar at the bottom"; on: win.st.navbar !== false
                     onToggled: (v) => win.ctl("navbar", v ? "on" : "off", function () { win.toast(v ? "buttons on" : "buttons hidden") }) }
            Note { text: "POWER screen off/on · VOL brightness · HOME this screen · BACK back · RECENTS keyboard" }
            Component.onCompleted: win.ctl("info", undefined, function (j) { try { if (j) { br.to = j.max; br.value = j.bright } } catch (e) {} })
        } }
    Component { id: batC
        Column { spacing: 6; width: parent ? parent.width : 600
            Note { text: win.st.battery || "" }
            Head { id: clh; text: "stop charging at " + Math.round(cl.value) + "%" }
            Slider2 { id: cl; from: 50; to: 100; step: 5; value: win.st.charge_limit || 100; onMoved: (v) => clT.restart() }
            Timer { id: clT; interval: 900; onTriggered: win.sys(["battery", "limit", "" + Math.round(cl.value)]) }
            Note { text: "Resumes 5% below. 80% is kind to a battery that is always plugged in." }
        } }
    Component { id: perfC
        Column { spacing: 6; width: parent ? parent.width : 600
            property var c: win.st.cpu || {}
            Note { text: "now: " + (parent.c.gov || "?") + " · max " + f((parent.c.max || 0) / 1000) + " MHz · throttle at " + (parent.c.trip || "?") + " °C" }
            Head { text: "governor" }
            Chooser { options: ["ondemand", "schedutil", "performance", "powersave"]; value: parent.c.gov || "ondemand"; onPicked: (v) => win.sys(["cpu", "gov", v]) }
            Head { text: "max clock" }
            Chooser { options: ["1794 MHz", "1690 MHz", "1586 MHz", "1482 MHz", "1248 MHz"]; value: f((parent.c.cap || 1794000) / 1000) + " MHz"; onPicked: (v) => win.sys(["cpu", "max", "" + parseInt(v) * 1000]) }
            Head { text: "throttle at (°C)" }
            Chooser { options: ["70", "75", "80", "85", "90", "95"]; value: "" + (parent.c.trip || 90); onPicked: (v) => win.sys(["cpu", "trip", v]) }
        } }
    Component { id: shareC
        Column { spacing: 6; width: parent ? parent.width : 600
            property var s: win.st.share || {}
            Note { text: "Windows: \\\\" + (win.st.host || "gta2srv") + "\\share · Mac/Linux: smb://" + (win.st.host || "gta2srv") + "/share or sftp://gta2@" + (win.st.host || "gta2srv") }
            Toggle { label: "Windows sharing (SMB)"; on: parent.s.smb === "on" || parent.s.smb === "active"; onToggled: (v) => win.ctl("share", ["smb", v ? "on" : "off"], function (j) { win.toast(j ? j.out || "ok" : "failed") }) }
            Toggle { label: "Guest access"; hint: "no password on the LAN"; on: parent.s.guest === "on"; onToggled: (v) => win.ctl("share", ["guest", v ? "on" : "off"], function (j) { win.toast(j ? j.out || "ok" : "failed") }) }
            Head { text: "smb password" }
            Field { id: spw; secret: true; placeholder: "new password" }
            Btn { text: "set"; primary: true; onClicked: { win.ctl("kbd_hide"); win.ctl("share", ["passwd", spw.text], function (j) { win.toast(j ? j.out || "set" : "failed"); spw.text = "" }) } }
        } }
    Component { id: sshC
        Column { spacing: 6; width: parent ? parent.width : 600
            property var s: win.st.ssh || {}
            Note { text: "ssh " + (parent.s.ssh || "?") + " · " + (parent.s.keys || 0) + " keys · ssh gta2@" + (win.st.host || "gta2srv") }
            Toggle { label: "Password login"; hint: "keys always work"; on: parent.s.password === "on"; onToggled: (v) => win.sys(["ssh", "password", v ? "on" : "off"]) }
            Note { text: "Put a public key into the Files share as authorized_keys.txt, then:" }
            Btn { text: "add key"; onClicked: win.sys(["ssh", "addkey"]) }
        } }
    Component { id: timeC
        Column { spacing: 6; width: parent ? parent.width : 600
            property var t: win.st.time || {}
            Note { text: (parent.t.now || "") + " · " + (parent.t.tz || "") }
            Head { text: "time zone" }
            Chooser { id: tzc; value: parent.t.tz || "UTC"; options: [value]; onPicked: (v) => win.sys(["time", "tz", v]) }
            Toggle { label: "Network time"; on: parent.t.ntp === "yes"; onToggled: (v) => win.sys(["time", "ntp", v ? "true" : "false"]) }
            Component.onCompleted: win.ctl("sys", ["time", "zones"], function (j) { try { if (j) tzc.options = j.out.split("\n").filter(function (z) { return z.indexOf("/") > 0 || z === "UTC" }) } catch (e) {} })
        } }
    Component { id: devC
        Column { spacing: 6; width: parent ? parent.width : 600
            Head { text: "name"; topPadding: 0 }
            Field { id: hn; text: win.st.host || "" }
            Btn { text: "rename"; primary: true; onClicked: { win.ctl("kbd_hide"); win.sys(["device", "hostname", hn.text.trim()]) } }
            Head { text: "login password (gta2)" }
            Field { id: p1; secret: true; placeholder: "new password" }
            Field { id: p2; secret: true; placeholder: "again" }
            Btn { text: "change"; primary: true; onClicked: { win.ctl("kbd_hide"); if (p1.text !== p2.text) win.toast("passwords differ"); else win.sys(["device", "passwd", p1.text]); p1.text = ""; p2.text = "" } }
        } }
    Component { id: updC
        Column { spacing: 6; width: parent ? parent.width : 600
            Note { text: win.st.space || "" }
            Flow { width: parent.width; spacing: 10
                Btn { text: "check"; onClicked: win.sys(["update", "check"]) }
                Btn { text: "install"; primary: true; onClicked: win.confirm("Install updates now? Keep the tablet plugged in.", function () { win.sys(["update", "run"]) }) }
                Btn { text: "clean up"; onClicked: win.sys(["update", "clean"]) } }
        } }
    Component { id: uiC
        Column { spacing: 6; width: parent ? parent.width : 600
            Note { text: "This Metro home is the default. The web version (same content, also used on your PC at :8088) and the old Tk launcher are still there." }
            Toggle { label: "Web home"; hint: "use the browser version on this screen"; on: false; onToggled: (v) => { if (v) win.confirm("Switch this screen to the web home?", function () { win.ctl("webhome", "on") }) } }
            Toggle { label: "Classic launcher"; hint: "old Tk home screen"; on: false; onToggled: (v) => { if (v) win.confirm("Switch to the classic launcher?", function () { win.ctl("classic", "on") }) } }
            Btn { text: "restart interface"; onClicked: win.ctl("restart-ui") }
        } }
    // ---- storage: external drive for apps (gta2store.py via /ctl)
    property var stor: ({})
    function loadStor() { ctl("storage", undefined, function (j) { if (j) stor = j }) }
    Component { id: storC
        Column { spacing: 6; width: parent ? parent.width : 600
            Component.onCompleted: win.loadStor()
            Note { text: win.stor.drive ? "External drive connected · " + win.gb(win.stor.free) + " free" : "External drive not connected. Plug the 500 GB drive into the dock to use these options." }
            Head { text: "docker / casaos apps" }
            Note { text: "Now stored " + (win.stor.docker_on_drive ? "on the external drive" : "on the tablet") + " (" + (win.stor.docker_root || "…") + "). Moving stops the apps for a few minutes; the old copy is kept until you delete it." }
            Btn { text: win.stor.docker_on_drive ? "move back to tablet" : "move to external drive"; primary: true; enabled: !!win.stor.drive; opacity: enabled ? 1 : 0.4
                  onClicked: win.confirm(text + "?", function () { win.ctl("docker_move", {to: win.stor.docker_on_drive ? "internal" : "drive"}, function (j) { win.toast(j && j.ok ? "moving Docker apps… keep the drive connected" : (j && j.error) || "failed"); win.storPoll.start() }) }) }
            Head { text: "desktop apps" }
            Note { text: "Hold an app tile › \"storage\" to move it. Works for apps that live in one folder (most Pi-Apps apps in /opt or your home folder). Ubuntu packages (apt) spread files over the system and must stay on the tablet." }
        } }
    property alias storPoll: storPollT
    Timer { id: storPollT; interval: 3000; repeat: true; property int n: 0
        onTriggered: { n++; win.ctl("store_job", undefined, function (j) { if (!j || j.state !== "running" || storPollT.n > 200) { storPollT.stop(); storPollT.n = 0; if (j && j.state === "done") win.toast(j.ok ? "move finished" : "move failed: " + (j.error || "")); win.loadStor() } }) } }
    function appStorage(a) {
        ctl("app_storage", {id: a.id}, function (j) {
            if (!j) { toast("not available"); return }
            if (!j.movable) { toast(j.reason || "this app cannot move"); return }
            if (!j.drive) { toast("connect the external drive first"); return }
            var to = j.on_drive ? "internal" : "drive";
            confirm((j.on_drive ? "Move " + a.name + " back to the tablet?" : "Move " + a.name + " to the external drive?"), function () {
                ctl("app_move", {id: a.id, to: to}, function (r) { toast(r && r.ok ? "moving " + a.name + "…" : (r && r.error) || "failed"); if (r && r.ok) storPollT.start() }) })
        })
    }
    // ---- about: credits + thank you; tap the version line 7 times for the popcorn
    property int eggTaps: 0
    Component { id: aboutC
        Column { spacing: 6; width: parent ? parent.width : 600
            Text { text: "gta2srv"; color: "white"; font.family: win.fnt; font.weight: Font.Light; font.pixelSize: 44 }
            Note { text: "Ubuntu Server Mini for the Samsung Galaxy Tab Active2 (SM-T395) on a mainline Linux kernel.\nCreated by ttabouch12 · github.com/ttabouch12" }
            Text { width: parent.width; color: "#d0d0d0"; font.family: win.fnt; font.pixelSize: 19; wrapMode: Text.Wrap; topPadding: 6; bottomPadding: 6
                   text: "version · kernel " + (win.aboutRows.length > 1 ? win.aboutRows[1][1] : "…") + (win.eggTaps > 2 && win.eggTaps < 7 ? "   (" + (7 - win.eggTaps) + " more…)" : "")
                   MouseArea { anchors.fill: parent; onClicked: { win.eggTaps++; if (win.eggTaps >= 7) { win.eggTaps = 0; win.popcorn() } } } }
            Repeater { model: win.aboutRows; KV { k: "" + (modelData[0] || ""); v: "" + (modelData[1] || "") } }
            Head { text: "thank you" }
            Note { text: "This tablet runs because of the work of thousands of people who share their code. Thank you to all of them:" }
            Repeater { model: [
                ["Linux kernel", "and everyone upstreaming Samsung Exynos support"], ["Samsung", "open-source Exynos 7870 kernel release"],
                ["U-Boot", "the bootloader that starts it all"], ["postmarketOS", "community knowledge for mainline phones and tablets"],
                ["Mesa · Panfrost", "open-source Mali GPU drivers"], ["Qt · Qt Quick", "this home screen"],
                ["Ubuntu · Canonical", "the operating system"], ["Debian", "the packages underneath"], ["systemd", "boot and services"],
                ["X.Org · matchbox · picom", "display, window manager, compositor"], ["LXQt · KDE Breeze", "the desktop mode and its look"],
                ["Pi-Apps", "Botspot and contributors: the app store"], ["CasaOS", "IceWhale: server apps and files"],
                ["Pi-hole · Docker · Portainer", "ad blocking and containers"], ["Moonlight · Sunshine", "game and desktop streaming"],
                ["FFmpeg · GStreamer", "video, now hardware accelerated"], ["TWRP", "the recovery safety net"],
                ["NetworkManager · BlueZ", "Wi-Fi and Bluetooth"], ["Claude (Anthropic)", "AI assistant that helped build and debug it"] ]
                KV { k: modelData[0]; v: modelData[1] } }
            Note { topPadding: 12; text: "Made with patience, a USB-C dock and a lot of reboots. Thank you!" }
        } }

    Component { id: powC
        Column { spacing: 6; width: parent ? parent.width : 600
            Flow { width: parent.width; spacing: 10
                Btn { text: "restart"; danger: true; onClicked: win.confirm("Restart the tablet?", function () { win.ctl("reboot") }) }
                Btn { text: "shut down"; danger: true; onClicked: win.confirm("Shut down? You need the power key to start it again.", function () { win.ctl("poweroff") }) } }
        } }

    // ---------- easter egg: the popcorn mascot (Settings › about, tap the version 7 times)
    function popcorn() { egg.visible = true; eggAnim.restart() }
    Rectangle { id: egg; visible: false; anchors.fill: parent; color: "#e6000000"; z: 9
        MouseArea { anchors.fill: parent; onClicked: egg.visible = false }
        Image { id: eggImg; source: "popcorn.png"; width: Math.min(win.width, win.height) * 0.62; height: width; anchors.centerIn: parent; anchors.verticalCenterOffset: -60; smooth: true; mipmap: true }
        Text { anchors.top: eggImg.bottom; anchors.topMargin: 24; anchors.horizontalCenter: parent.horizontalCenter; width: win.width - 2 * win.pad
               horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; color: "white"; font.family: win.fnt; font.weight: Font.Light; font.pixelSize: 30; opacity: eggImg.scale
               text: "thank you for building this!\n— ttabouch12 & everyone in about" }
        SequentialAnimation { id: eggAnim
            ParallelAnimation {
                NumberAnimation { target: eggImg; property: "scale"; from: 0.1; to: 1.0; duration: 650; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                NumberAnimation { target: eggImg; property: "rotation"; from: -25; to: 0; duration: 650; easing.type: Easing.OutBack } }
            SequentialAnimation { loops: 3
                NumberAnimation { target: eggImg; property: "rotation"; to: 6; duration: 140; easing.type: Easing.InOutSine }
                NumberAnimation { target: eggImg; property: "rotation"; to: -6; duration: 140; easing.type: Easing.InOutSine } }
            NumberAnimation { target: eggImg; property: "rotation"; to: 0; duration: 120 } } }

    // ---------- app context menu (long press) and uninstall progress bar
    Rectangle { id: ctxBox; visible: false; anchors.fill: parent; color: "#cc000000"; z: 8
        MouseArea { anchors.fill: parent; onClicked: ctxBox.visible = false }
        Rectangle { id: ctxPanel; width: parent.width; height: ctxCol.height + 40; y: parent.height - height - 56; color: "#1d1d1d"
            Column { id: ctxCol; x: win.pad; y: 20; width: parent.width - 2 * win.pad
                Text { text: win.ctxApp ? win.ctxApp.name : ""; color: "#d0d0d0"; font.family: win.fnt; font.pixelSize: 18; bottomPadding: 6 }
                Item2 { title: win.ctxPinned ? "unpin from start" : "pin to start"
                        onClicked: { ctxBox.visible = false; if (win.ctxPinned) win.unpinApp(win.ctxApp.id); else win.pinApp(win.ctxApp) } }
                Item2 { title: "storage (move to / from external drive)"; onClicked: { ctxBox.visible = false; win.appStorage(win.ctxApp) } }
                Item2 { title: "uninstall"; visible: !win.ctxApp || win.ctxApp.removable !== false; onClicked: { ctxBox.visible = false; win.uninstallApp(win.ctxApp) } } } } }
    Rectangle { id: jobBox; width: win.width; height: 54; y: -height; z: 10; color: "#1e7145"
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Text { id: jobT; anchors.verticalCenter: parent.verticalCenter; x: win.pad; color: "white"; font.family: win.fnt; font.pixelSize: 19; elide: Text.ElideRight; width: parent.width - 2 * win.pad } }

    // ---------- chooser + confirm overlays, toast
    property var chooseCb: null
    function choose(opts, cur, cb) { chooseCb = cb; chooserList.model = opts; chooserList.positionViewAtIndex(Math.max(0, opts.indexOf(cur)), ListView.Center); chooserBox.visible = true }
    Rectangle { id: chooserBox; visible: false; anchors.fill: parent; color: "#ee000000"; z: 8
        MouseArea { anchors.fill: parent; onClicked: chooserBox.visible = false }
        ListView { id: chooserList; x: win.pad; y: 80; width: parent.width - 2 * win.pad; height: parent.height - 160; clip: true
            delegate: Item2 { title: modelData; height: 64; onClicked: { chooserBox.visible = false; if (win.chooseCb) win.chooseCb(modelData) } } } }
    property var confirmCb: null
    function confirm(q, cb) { confirmCb = cb; confirmQ.text = q; confirmBox.visible = true }
    Rectangle { id: confirmBox; visible: false; anchors.fill: parent; color: "#dd000000"; z: 9
        MouseArea { anchors.fill: parent }
        Rectangle { width: parent.width; height: cc.height + 60; color: "#1d1d1d"
            Column { id: cc; x: win.pad; y: 30; width: parent.width - 2 * win.pad; spacing: 20
                Text { id: confirmQ; width: parent.width; wrapMode: Text.Wrap; color: "white"; font.family: win.fnt; font.pixelSize: 24 }
                Row { spacing: 12
                    Btn { text: "yes"; primary: true; onClicked: { confirmBox.visible = false; if (win.confirmCb) win.confirmCb() } }
                    Btn { text: "cancel"; onClicked: confirmBox.visible = false } } } } }
    Rectangle { id: toastBox; width: win.width; height: 54; y: -height; z: 10; color: win.acc
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Text { id: toastT; anchors.verticalCenter: parent.verticalCenter; x: win.pad; color: "white"; font.family: win.fnt; font.pixelSize: 19; elide: Text.ElideRight; width: parent.width - 2 * win.pad } }
    Timer { id: toastTimer; interval: 2400; onTriggered: toastBox.y = -toastBox.height }

    // ---------- autopage: page through the panorama every 0.7 s (frame-rate test without synthetic input)
    Timer { property int d: 1; interval: 700; repeat: true; running: Qt.application.arguments.indexOf("autopage") >= 0
        onTriggered: { if (pv.currentIndex === 3) d = -1; if (pv.currentIndex === 0) d = 1; pv.currentIndex += d } }

    // ---------- selftest: open every settings page once (qml Main.qml selftest), errors go to stderr
    Timer { property int i: 0; interval: 400; repeat: true; running: Qt.application.arguments.indexOf("selftest") >= 0
        onTriggered: { if (i >= win.sections.length) { console.log("SELFTEST DONE"); Qt.quit(); return } console.log("open", win.sections[i][0]); win.openSub(i); i++ } }

    // ---------- dettest: open every tile's detail page once (qml Main.qml dettest)
    Timer { property int i: 0; interval: 1200; repeat: true; running: Qt.application.arguments.indexOf("dettest") >= 0
        onTriggered: { var ks = Object.keys(win.detTitles); if (i >= ks.length) { console.log("DETTEST DONE", heroM.count, rowM.count); Qt.quit(); return }
                       console.log("detail", ks[i], heroM.count, rowM.count, win.detCharts.length); win.openDetail(ks[i]); i++ } }

    // ---------- ?fps probe: GTA2_FPS=1 -> frames swapped per second while something moves, to /ctl fpslog
    property int frames: 0      // frames drawn back-to-back (gap < 200 ms = something is moving)
    property real motionMs: 0
    property int jank: 0        // frames that took > 25 ms while moving
    property real lastSwap: 0
    onFrameSwapped: { var t = Date.now(), dt = t - lastSwap; lastSwap = t; if (dt > 0 && dt < 200) { frames++; motionMs += dt; if (dt > 25) jank++ } }
    Timer { interval: 1000; repeat: true; running: Qt.application.arguments.indexOf("fps") >= 0
        onTriggered: { if (win.frames > 5) win.ctl("fpslog", "?qmlhome FPS " + Math.round(1000 * win.frames / win.motionMs) + " jank " + win.jank + " n " + win.frames); win.frames = 0; win.motionMs = 0; win.jank = 0 } }
}
