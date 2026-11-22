// gta2 on-screen keyboard, Windows Phone 8 style. Always running (gta2-kbd), so showing it is instant.
// Keys go to the focused X window through the gta2kbd.py helper (XTest) on 127.0.0.1:8097.
// The window is override-redirect + never takes focus, so the app you type into keeps its focus.
import QtQuick
import QtQuick.Window

Window {
    id: win
    title: "gta2-kbd"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus | Qt.X11BypassWindowManagerHint
    color: "#121212"
    visible: false
    readonly property int nav: navOn ? 56 : 0
    property bool navOn: true
    readonly property int keyH: Screen.width > Screen.height ? 54 : 62
    readonly property int gap: 6
    width: Screen.width
    height: 4 * keyH + 5 * gap + 2
    x: 0
    y: Screen.height - nav - height

    readonly property color accent: "#2d89ef"
    readonly property string font: "Segoe UI, Open Sans, Noto Sans, DejaVu Sans"

    // ---- helper link -------------------------------------------------------------------------------
    property int ver: -1
    function req(path, cb) {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function() { if (x.readyState === XMLHttpRequest.DONE && cb) cb(x.status, x.responseText) };
        x.open("GET", "http://127.0.0.1:8097" + path); x.send();
    }
    // keys go through a FIFO (synchronous local write, ~1 ms) instead of HTTP
    function fifo(line) { var x = new XMLHttpRequest(); x.open("PUT", "file:///tmp/gta2-kbd.fifo"); x.send(line + "\n") }
    function send(ch) { fifo("c " + encodeURIComponent(ch)) }
    function sendKey(k) { fifo("k " + k) }
    function poll() {
        req("/wait?v=" + ver, function(st, t) {
            if (st === 200) {
                var p = t.split(" "); ver = parseInt(p[0]);
                if (p[1] === "show") open(); else close();
            }
            pollTimer.start();   // re-arm (short delay also covers helper restarts)
        });
    }
    Timer { id: pollTimer; interval: 30; onTriggered: win.poll() }
    Component.onCompleted: {
        var f = new XMLHttpRequest();   // nav bar hidden? (Settings > display)
        f.onreadystatechange = function() { if (f.readyState === XMLHttpRequest.DONE) win.navOn = (f.status !== 200) };
        try { f.open("GET", "file:///home/gta2/.config/gta2/nonavbar"); f.send(); } catch (e) {}
        poll();
    }
    function open() { slide.stop(); visible = true; raise(); body.y = height; slideIn.start() }
    function close() { slideIn.stop(); slide.start() }
    NumberAnimation { id: slideIn; target: body; property: "y"; to: 0; duration: 180; easing.type: Easing.OutCubic }
    SequentialAnimation { id: slide
        NumberAnimation { target: body; property: "y"; to: win.height; duration: 140; easing.type: Easing.InCubic }
        ScriptAction { script: { win.visible = false; win.shift = 0 } }
    }

    // ---- layouts -----------------------------------------------------------------------------------
    // key: plain string = character; object {a: action, t: label, w: width units}
    property string page: "abc"       // abc | num | sym
    property bool tr: false           // Turkish Q layout
    property int shift: 0             // 0 off, 1 next letter, 2 caps lock
    property real lastShift: 0
    readonly property var en: [
        ["q","w","e","r","t","y","u","i","o","p"],
        [{sp:0.5},"a","s","d","f","g","h","j","k","l",{sp:0.5}],
        [{a:"shift",w:1.5},"z","x","c","v","b","n","m",{a:"bs",w:1.5}],
        [{a:"num",t:"&123",w:1.5},",",{a:"lang",t:"⌨",w:1},{a:"space",w:4},".",{a:"enter",w:1.5}]]
    readonly property var trq: [
        ["q","w","e","r","t","y","u","ı","o","p","ğ","ü"],
        ["a","s","d","f","g","h","j","k","l","ş","i"],
        [{a:"shift",w:1.5},"z","x","c","v","b","n","m","ö","ç",{a:"bs",w:1.5}],
        [{a:"num",t:"&123",w:1.5},",",{a:"lang",t:"TR",w:1},{a:"space",w:4},".",{a:"enter",w:1.5}]]
    readonly property var num: [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["-","/",":",";","(",")","$","&","@","\""],
        [{a:"sym",t:"=\\<",w:1.5},".",",","?","!","'","%","*",{a:"bs",w:1.5}],
        [{a:"abc",t:"abc",w:1.5},"_",{a:"lang",t:"⌨",w:1},{a:"space",w:4},"#",{a:"enter",w:1.5}]]
    readonly property var sym: [
        ["[","]","{","}","#","%","^","*","+","="],
        ["_","\\","|","~","<",">","€","£","¥","•"],
        [{a:"num",t:"123",w:1.5},".",",","?","!","'","`","°",{a:"bs",w:1.5}],
        [{a:"abc",t:"abc",w:1.5},"@",{a:"lang",t:"⌨",w:1},{a:"space",w:4},"/",{a:"enter",w:1.5}]]
    readonly property var rows: page === "num" ? num : page === "sym" ? sym : (tr ? trq : en)
    // long-press alternatives (WP shows them in a strip above the key)
    readonly property var alts: ({
        "a":"àáâäæå","c":"ç","e":"3éèêë€","g":"ğ","i":"8ıİíìîï","n":"ñ","o":"9öóòôøœ","s":"şß","u":"7üúùû",
        "y":"6ý","q":"1","w":"2","r":"4","t":"5","p":"0","ı":"8i","ş":"s","ğ":"g","ü":"u","ö":"o","ç":"c",
        ".":".,?!:;…","-":"–—","$":"€£¥₺","'":"‘’\"“”","?":"¿","!":"¡","0":"°" })

    function label(k) {
        if (typeof k === "string") return shift ? (k === "i" && tr ? "İ" : k.toUpperCase()) : k;
        if (k.a === "space") return tr ? "Türkçe" : "English";
        if (k.a === "bs") return "⌫";
        if (k.a === "enter") return "↵";
        if (k.a === "shift") return shift === 2 ? "⇪" : "⇧";
        return k.t || "";
    }
    function typeChar(c) {
        if (shift && c.length === 1) c = (c === "i" && tr) ? "İ" : c.toUpperCase();
        send(c);
        if (shift === 1) shift = 0;
    }
    function action(a) {
        if (a === "shift") {
            var now = Date.now();
            if (shift === 1 && now - lastShift < 400) shift = 2; else shift = shift ? 0 : 1;
            lastShift = now;
        } else if (a === "enter") sendKey("Return");
        else if (a === "num") page = "num";
        else if (a === "sym") page = "sym";
        else if (a === "abc") page = "abc";
        else if (a === "lang") { tr = !tr; page = "abc" }
    }

    // ---- UI ----------------------------------------------------------------------------------------
    Item {
        id: body
        width: win.width; height: win.height; y: win.height
        Rectangle { anchors.fill: parent; color: "#121212" }
        Column {
            id: col
            x: win.gap; y: win.gap; spacing: win.gap
            Repeater {
                model: win.rows
                Row {
                    id: row
                    required property var modelData
                    spacing: win.gap
                    readonly property real units: {
                        var u = 0; for (var i = 0; i < modelData.length; i++) {
                            var k = modelData[i]; u += typeof k === "string" ? 1 : (k.sp !== undefined ? k.sp : (k.w || 1)); }
                        return Math.max(10, u);
                    }
                    readonly property real unitW: (win.width - win.gap * (units + 1)) / units
                    Repeater {
                        model: row.modelData
                        Key { required property var modelData; k: modelData; unitW: row.unitW }
                    }
                }
            }
        }
        // key preview bubble (WP: the pressed key pops up above your finger)
        Rectangle {
            id: bubble; visible: false; color: win.accent; width: 64; height: win.keyH + 12; z: 10
            Text { id: bubbleT; anchors.centerIn: parent; color: "white"; font.family: win.font; font.pixelSize: 34 }
        }
        // long-press strip
        Rectangle {
            id: strip; visible: false; color: "#2b2b2b"; border.color: win.accent; border.width: 2; z: 11
            height: win.keyH; property var chars: []; property int sel: 0; property real cellW: 56
            width: chars.length * cellW + 4
            Row { x: 2; Repeater { model: strip.chars
                Rectangle { required property int index; required property string modelData
                    width: strip.cellW; height: win.keyH - 4; y: 2; color: index === strip.sel ? win.accent : "transparent"
                    Text { anchors.centerIn: parent; text: win.shift ? parent.modelData.toUpperCase() : parent.modelData
                           color: "white"; font.family: win.font; font.pixelSize: 26 } } } }
        }
    }

    component Key: Rectangle {
        id: key
        property var k
        property real unitW
        readonly property bool isStr: typeof k === "string"
        readonly property bool spacer: !isStr && k.sp !== undefined
        readonly property string act: isStr ? "" : (k.a || "")
        readonly property real units: isStr ? 1 : (spacer ? k.sp : (k.w || 1))
        width: Math.max(0, unitW * units + win.gap * (units - 1))
        height: win.keyH
        visible: true
        opacity: spacer ? 0 : 1
        color: spacer ? "transparent"
             : ma.pressed && act !== "" ? win.accent
             : act === "enter" || (act === "shift" && win.shift) ? win.accent
             : act !== "" ? "#3a3a3a" : "#2b2b2b"
        Text {
            anchors.centerIn: parent
            text: key.spacer ? "" : win.label(key.k)
            color: "white"; font.family: win.font
            font.pixelSize: key.isStr ? 28 : (key.act === "space" ? 15 : 22)
            font.weight: key.isStr ? Font.Light : Font.Normal
            opacity: key.act === "space" ? 0.6 : 1
        }
        property real dx0: 0
        property real moved: 0
        Timer { id: lp; interval: 420; onTriggered: key.longPress() }
        Timer { id: rep; interval: 450; repeat: true; onTriggered: { interval = 55; win.sendKey("BackSpace") } }
        function longPress() {
            var a = win.alts[key.k]; if (!key.isStr || !a) return;
            bubble.visible = false;
            strip.chars = a.split(""); strip.sel = 0;
            var p = key.mapToItem(body, 0, 0);
            strip.x = Math.max(2, Math.min(body.width - strip.width - 2, p.x - 4));
            strip.y = Math.max(0, p.y - win.keyH - 4); strip.visible = true;
        }
        MouseArea {
            id: ma; anchors.fill: parent; enabled: !key.spacer
            onPressed: (m) => {
                key.dx0 = m.x; key.moved = 0;
                if (key.act === "bs") { win.sendKey("BackSpace"); rep.interval = 450; rep.start(); return }
                if (key.isStr) {
                    var p = key.mapToItem(body, 0, 0);
                    bubbleT.text = win.label(key.k); bubble.width = Math.max(key.width + 12, 56);
                    bubble.x = p.x + key.width / 2 - bubble.width / 2; bubble.y = Math.max(0, p.y - bubble.height + 8);
                    bubble.visible = true; lp.start();
                }
            }
            onPositionChanged: (m) => {
                if (strip.visible) {   // slide along the strip to pick
                    var px = key.mapToItem(strip, m.x, m.y).x;
                    strip.sel = Math.max(0, Math.min(strip.chars.length - 1, Math.floor((px - 2) / strip.cellW)));
                } else if (key.act === "space") {   // drag on space bar = move the cursor
                    var d = m.x - key.dx0;
                    while (Math.abs(d) >= 18) { win.sendKey(d > 0 ? "Right" : "Left"); key.dx0 += d > 0 ? 18 : -18; d = m.x - key.dx0; key.moved++ }
                }
            }
            onReleased: {
                lp.stop(); rep.stop(); bubble.visible = false;
                if (strip.visible) { strip.visible = false; win.typeChar(strip.chars[strip.sel]); return }
                if (key.isStr) win.typeChar(key.k);
                else if (key.act === "space") { if (!key.moved) { win.send(" "); if (win.shift === 1) win.shift = 0 } }
                else if (key.act !== "bs") win.action(key.act);
            }
            onCanceled: { lp.stop(); rep.stop(); bubble.visible = false; strip.visible = false }
        }
    }
}
