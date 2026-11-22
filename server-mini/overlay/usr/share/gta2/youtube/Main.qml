import QtQuick
import QtQuick.Window

// gta2 YouTube: phone-style YouTube client in the Windows Phone look. Data from gta2-ytd (127.0.0.1:8099,
// InnerTube JSON + yt-dlp for streams); playback in mpv with the Exynos MFC hardware decoder.
// No Google account: subscriptions, history and watch later are local (~/.config/gta2/yt.json).
Window {
    id: win
    visible: true
    color: "black"
    title: "gta2-youtube"
    width: Screen.width; height: Screen.height - 56          // matchbox keeps the navbar space free anyway
    readonly property string api: "http://127.0.0.1:8099"
    readonly property color acc: "#e51400"
    readonly property var tabs: ["home", "subscriptions", "history", "later"]
    property int tab: 0               // 0..3, 4 = search results
    property string query: ""
    property string cont: ""
    property bool loading: false
    property var lists: ({subs: [], hist: [], later: []})
    readonly property int cols: width > height ? 3 : 2

    function req(meth, path, body, cb) {
        var x = new XMLHttpRequest(); x.open(meth, api + path)
        x.onreadystatechange = function () { if (x.readyState === 4) { var j = null; try { j = JSON.parse(x.responseText) } catch (e) {} if (cb) cb(j) } }
        x.send(body ? JSON.stringify(body) : null)
    }
    function dash(a) { var x = new XMLHttpRequest(); x.open("POST", "http://127.0.0.1:8088/ctl"); x.send(JSON.stringify({a: a})) }
    function append(list) { for (var i = 0; i < (list || []).length; i++) feed.append(list[i]) }
    function load(more) {
        if (loading || (more && !cont)) return
        if (!more) { feed.clear(); cont = ""; grid.contentY = grid.originY }
        if (tab >= 1 && tab <= 3) {   // local lists
            req("GET", "/lists", null, function (j) { if (!j) return; lists = j
                var k = ["", "subs", "hist", "later"][tab]
                if (tab === 1) { subsBar.model = j.subs; loading = true
                    req("GET", "/home?feed=subs", null, function (h) { loading = false; append(h ? h.items : []) }) }
                else append(j[k]) })
            return
        }
        loading = true
        var path = tab === 4 ? "/search?q=" + encodeURIComponent(query) : "/home"
        if (more) path += (tab === 4 ? "&" : "?") + "cont=" + encodeURIComponent(cont)
        req("GET", path, null, function (j) { loading = false; if (!j) { toast.show("no connection"); return }
            if (j.error) toast.show("youtube: " + j.error)
            append(j.items); cont = j.cont || "" })
    }
    function setTab(i) { tab = i; load(false) }
    function doSearch(q) { q = q.trim(); if (!q) return; query = q; box.text = q; sugg.model = []; box.focus = false; dash("kbd_hide"); setTab(4) }
    function isSub(cid) { for (var i = 0; i < lists.subs.length; i++) if (lists.subs[i].channel_id === cid) return true; return false }
    function isLater(id) { for (var i = 0; i < lists.later.length; i++) if (lists.later[i].id === id) return true; return false }
    function openVideo(v) { vp.open(v) }
    function play(v) { toast.show("starting…"); req("POST", "/play", v, function (j) { if (!j || !j.ok) toast.show("could not play") }) }

    Component.onCompleted: { req("GET", "/lists", null, function (j) { if (j) lists = j }); load(false) }

    ListModel { id: feed }

    // ---------- top: search bar + tabs ----------
    Rectangle { id: top; width: parent.width; height: 138; color: "black"; z: 3
        Text { x: 22; y: 18; text: "youtube"; color: "white"; font.pixelSize: 30; font.weight: Font.Light }
        Rectangle { id: sbox; x: 150; y: 12; width: parent.width - 172; height: 48; color: "white"
            TextInput { id: box; anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 52; verticalAlignment: TextInput.AlignVCenter
                font.pixelSize: 21; color: "black"; clip: true; selectByMouse: false
                Text { anchors.verticalCenter: parent.verticalCenter; text: "search youtube"; color: "#888"; font.pixelSize: 21; visible: !box.text && !box.activeFocus }
                onActiveFocusChanged: if (activeFocus) win.dash("kbd_show")
                onAccepted: win.doSearch(text)
                onTextEdited: suggT.restart() }
            Text { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: "⌕"; font.pixelSize: 30; color: "#333"
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: box.text ? win.doSearch(box.text) : box.forceActiveFocus() } } }
        Timer { id: suggT; interval: 180
            onTriggered: { var t = box.text; if (t.length < 2) { sugg.model = []; return }
                win.req("GET", "/suggest?q=" + encodeURIComponent(t), null, function (j) { if (box.text === t) sugg.model = j || [] }) } }
        Row { x: 22; y: 82; spacing: 28
            Repeater { model: win.tabs
                Text { text: modelData; font.pixelSize: 28; font.weight: Font.Light; color: index === win.tab ? "white" : "#666"
                    Rectangle { anchors.top: parent.bottom; anchors.topMargin: 4; width: parent.width; height: 3; color: win.acc; visible: index === win.tab }
                    MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: win.setTab(index) } } }
            Text { visible: win.tab === 4; text: "“" + win.query + "”"; font.pixelSize: 28; font.weight: Font.Light; color: "white"; elide: Text.ElideRight; width: 220 } }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: win.acc; visible: win.loading
            Rectangle { id: bar; width: parent.width / 4; height: 2; color: "white"
                NumberAnimation on x { from: -bar.width; to: win.width; duration: 900; loops: Animation.Infinite; running: win.loading } } }
    }

    // subscriptions: channel chips
    ListView { id: subsBar; anchors.top: top.bottom; width: parent.width; height: win.tab === 1 && count ? 58 : 0; visible: height > 0
        orientation: ListView.Horizontal; spacing: 10; leftMargin: 22; rightMargin: 22; clip: true; z: 2
        delegate: Rectangle { height: 44; y: 6; width: ct.width + 28; color: "#222"; radius: 22
            Text { id: ct; anchors.centerIn: parent; text: modelData.name; color: "white"; font.pixelSize: 18 }
            MouseArea { anchors.fill: parent; onClicked: chan.open(modelData.channel_id, modelData.name) } } }

    // ---------- feed ----------
    GridView { id: grid
        anchors.top: subsBar.bottom; anchors.bottom: parent.bottom; width: parent.width
        leftMargin: 12; rightMargin: 12; topMargin: 10; bottomMargin: 20
        cellWidth: (width - 24) / win.cols; cellHeight: cellWidth * 9 / 16 + 96
        model: feed; cacheBuffer: 1600; flickDeceleration: 1500; maximumFlickVelocity: 4000; boundsBehavior: Flickable.DragOverBounds
        onAtYEndChanged: if (atYEnd && count && win.tab !== 1) win.load(true)
        onDragEnded: if (contentY - originY < -110 && (win.tab === 0 || win.tab === 4)) win.load(false)   // pull to refresh
        delegate: Card { width: grid.cellWidth; height: grid.cellHeight; item: model }
        Text { anchors.centerIn: parent; visible: !grid.count && !win.loading; color: "#777"; font.pixelSize: 22
               text: win.tab === 1 ? "long-press a video to subscribe to its channel" : win.tab === 2 ? "nothing watched yet" : win.tab === 3 ? "long-press a video → watch later" : "pull down to refresh" }
    }

    // search suggestions (over the feed)
    Column { id: suggCol; anchors.top: top.bottom; width: parent.width; z: 4; visible: box.activeFocus && sugg.count > 0
        Rectangle { width: parent.width; height: sugg.count * 56; color: "#111"
            Repeater { id: sugg
                Item { y: index * 56; width: parent.width; height: 56
                    Text { x: 24; anchors.verticalCenter: parent.verticalCenter; text: "⌕  " + modelData; color: "white"; font.pixelSize: 21; width: parent.width - 48; elide: Text.ElideRight }
                    MouseArea { anchors.fill: parent; onClicked: win.doSearch(modelData) } } } } }

    // ---------- one video card (thumbnail, duration badge, title, channel · views · age) ----------
    component Card: Item { id: card
        property var item
        property bool pressed: ma.pressed
        function plain() { return {id: item.id, title: item.title, channel: item.channel, channel_id: item.channel_id, dur: item.dur || "", meta: item.meta || ""} }
        Item { anchors.fill: parent; anchors.margins: 6; scale: card.pressed ? 0.97 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }
            Rectangle { id: th; width: parent.width; height: width * 9 / 16; color: "#1c1c1c"
                Image { anchors.fill: parent; asynchronous: true; cache: true; fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 320; sourceSize.height: 180; source: card.item ? win.api + "/thumb?id=" + card.item.id : ""
                        opacity: status === Image.Ready ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 180 } } }
                Rectangle { visible: card.item && card.item.dur; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 6
                    width: dt.width + 10; height: 24; color: "#d0000000"
                    Text { id: dt; anchors.centerIn: parent; text: card.item ? card.item.dur : ""; color: "white"; font.pixelSize: 15 } } }
            Text { id: tt; anchors.top: th.bottom; anchors.topMargin: 8; width: parent.width; text: card.item ? card.item.title : ""
                   color: "white"; font.pixelSize: 18; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; lineHeight: 1.05 }
            Text { anchors.top: tt.bottom; anchors.topMargin: 4; width: parent.width; color: "#a8a8a8"; font.pixelSize: 15; elide: Text.ElideRight
                   text: card.item ? [card.item.channel, card.item.meta].filter(function (s) { return s }).join(" · ") : "" } }
        MouseArea { id: ma; anchors.fill: parent; pressAndHoldInterval: 550
            onClicked: win.openVideo(card.plain())
            onPressAndHold: menu.open(card.plain()) }
    }

    // ---------- long-press menu ----------
    Rectangle { id: menu; anchors.fill: parent; color: "#b0000000"; visible: false; z: 8
        property var v: null
        function open(x) { v = JSON.parse(JSON.stringify(x)); visible = true }
        MouseArea { anchors.fill: parent; onClicked: menu.visible = false }
        Column { anchors.bottom: parent.bottom; width: parent.width
            Rectangle { width: parent.width; height: 80; color: "#1f1f1f"
                Text { x: 24; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 48; text: menu.v ? menu.v.title : ""; color: "#ccc"; font.pixelSize: 18; elide: Text.ElideRight } }
            Repeater { model: [
                    {t: "play", f: function () { win.play(menu.v) }},
                    {t: menu.v && win.isLater(menu.v.id) ? "remove from watch later" : "watch later", f: function () { win.req("POST", "/later", {item: menu.v, on: !win.isLater(menu.v.id)}, function (j) { if (j && j.lists) win.lists = j.lists; if (win.tab === 3) win.load(false) }) }},
                    {t: menu.v && win.isSub(menu.v.channel_id) ? "unsubscribe " + menu.v.channel : "subscribe to " + (menu.v ? menu.v.channel : ""), f: function () { win.req("POST", "/sub", {channel_id: menu.v.channel_id, name: menu.v.channel, on: !win.isSub(menu.v.channel_id)}, function (j) { if (j && j.lists) win.lists = j.lists }) }},
                    {t: "open channel", f: function () { chan.open(menu.v.channel_id, menu.v.channel) }}]
                Rectangle { width: menu.width; height: 66; color: "#1f1f1f"; visible: index < 2 || (menu.v && menu.v.channel_id)
                    Text { x: 24; anchors.verticalCenter: parent.verticalCenter; text: modelData.t; color: "white"; font.pixelSize: 22 }
                    MouseArea { anchors.fill: parent; onClicked: { menu.visible = false; modelData.f() } } } } } }

    // ---------- channel page ----------
    Rectangle { id: chan; anchors.fill: parent; color: "black"; z: 6; visible: false
        property string cid: ""; property string name: ""; property string ccont: ""
        function open(id, n) { if (!id) return; cid = id; name = n; chm.clear(); ccont = ""; visible = true; more() }
        function more() { win.loading = true
            win.req("GET", "/channel?id=" + cid + (ccont ? "&cont=" + encodeURIComponent(ccont) : ""), null, function (j) {
                win.loading = false; if (!j) return; for (var i = 0; i < (j.items || []).length; i++) chm.append(j.items[i]); chan.ccont = j.cont || "" }) }
        ListModel { id: chm }
        Text { x: 22; y: 16; text: "←"; color: "white"; font.pixelSize: 34; MouseArea { anchors.fill: parent; anchors.margins: -14; onClicked: chan.visible = false } }
        Text { x: 70; y: 16; width: parent.width - 260; text: chan.name; color: "white"; font.pixelSize: 30; font.weight: Font.Light; elide: Text.ElideRight }
        Rectangle { anchors.right: parent.right; anchors.rightMargin: 20; y: 14; width: 170; height: 44; color: win.isSub(chan.cid) ? "#333" : win.acc
            Text { anchors.centerIn: parent; text: win.isSub(chan.cid) ? "subscribed" : "subscribe"; color: "white"; font.pixelSize: 19 }
            MouseArea { anchors.fill: parent; onClicked: win.req("POST", "/sub", {channel_id: chan.cid, name: chan.name, on: !win.isSub(chan.cid)}, function (j) { if (j && j.lists) win.lists = j.lists }) } }
        GridView { anchors.fill: parent; anchors.topMargin: 74; leftMargin: 12; rightMargin: 12
            cellWidth: (width - 24) / win.cols; cellHeight: cellWidth * 9 / 16 + 96; model: chm; cacheBuffer: 1600
            onAtYEndChanged: if (atYEnd && count && chan.ccont) chan.more()
            delegate: Card { width: GridView.view.cellWidth; height: GridView.view.cellHeight; item: model } } }

    // ---------- video page (before playback): big thumbnail + play, info, related ----------
    Rectangle { id: vp; anchors.fill: parent; color: "black"; z: 7; visible: false
        property var v: ({})
        property var d: ({})
        property bool descOpen: false
        function open(x) { v = JSON.parse(JSON.stringify(x)); d = {}; descOpen = false; rel.clear(); visible = true; vflick.contentY = 0
            win.req("GET", "/video?id=" + v.id, null, function (j) { if (!j || j.id !== vp.v.id) return; vp.d = j; for (var i = 0; i < j.related.length; i++) rel.append(j.related[i]) }) }
        ListModel { id: rel }
        transform: Translate { id: vpT; x: 0 }
        onVisibleChanged: if (visible) { vpIn.restart() }
        ParallelAnimation { id: vpIn
            NumberAnimation { target: vpT; property: "x"; from: 90; to: 0; duration: 240; easing.type: Easing.OutCubic }
            NumberAnimation { target: vp; property: "opacity"; from: 0; to: 1; duration: 200 } }
        Flickable { id: vflick; anchors.fill: parent; contentHeight: vcol.height + 30; flickDeceleration: 1500; maximumFlickVelocity: 4000
            Column { id: vcol; width: parent.width; spacing: 10
                Item { width: parent.width; height: width * 9 / 16
                    Image { anchors.fill: parent; asynchronous: true; fillMode: Image.PreserveAspectCrop; sourceSize.width: 480; sourceSize.height: 360
                            source: vp.v.id ? win.api + "/thumb?q=hq&id=" + vp.v.id : "" }
                    Rectangle { anchors.centerIn: parent; width: 120; height: 120; radius: 60; color: win.acc; scale: pm.pressed ? 0.92 : 1
                        Text { anchors.centerIn: parent; anchors.horizontalCenterOffset: 6; text: "▶"; color: "white"; font.pixelSize: 54 }
                        MouseArea { id: pm; anchors.fill: parent; anchors.margins: -20; onClicked: win.play(vp.d.title ? {id: vp.v.id, title: vp.d.title, channel: vp.d.channel, channel_id: vp.d.channel_id, dur: vp.v.dur, meta: vp.v.meta} : vp.v) } }
                    Text { x: 18; y: 12; text: "←"; color: "white"; font.pixelSize: 38; style: Text.Outline; styleColor: "black"
                        MouseArea { anchors.fill: parent; anchors.margins: -14; onClicked: vp.visible = false } } }
                Text { x: 22; width: parent.width - 44; text: vp.d.title || vp.v.title || ""; color: "white"; font.pixelSize: 25; wrapMode: Text.Wrap }
                Text { x: 22; width: parent.width - 44; color: "#a8a8a8"; font.pixelSize: 17
                       text: [vp.d.views, vp.d.date].filter(function (s) { return s }).join(" · ") || vp.v.meta || "" }
                Row { x: 22; spacing: 12; height: 50
                    Text { anchors.verticalCenter: parent.verticalCenter; width: vp.width - 44 - 340; elide: Text.ElideRight; color: "white"; font.pixelSize: 20
                           text: (vp.d.channel || vp.v.channel || "") + (vp.d.subs ? "   " : ""); MouseArea { anchors.fill: parent; onClicked: chan.open(vp.d.channel_id || vp.v.channel_id, vp.d.channel || vp.v.channel) } }
                    Rectangle { width: 150; height: 44; anchors.verticalCenter: parent.verticalCenter; color: win.isSub(vp.d.channel_id || vp.v.channel_id) ? "#333" : win.acc
                        Text { anchors.centerIn: parent; text: win.isSub(vp.d.channel_id || vp.v.channel_id) ? "subscribed" : "subscribe"; color: "white"; font.pixelSize: 18 }
                        MouseArea { anchors.fill: parent; onClicked: { var c = vp.d.channel_id || vp.v.channel_id; if (c) win.req("POST", "/sub", {channel_id: c, name: vp.d.channel || vp.v.channel, on: !win.isSub(c)}, function (j) { if (j && j.lists) win.lists = j.lists }) } } }
                    Rectangle { width: 170; height: 44; anchors.verticalCenter: parent.verticalCenter; color: "#333"
                        Text { anchors.centerIn: parent; text: win.isLater(vp.v.id) ? "✓ watch later" : "+ watch later"; color: "white"; font.pixelSize: 18 }
                        MouseArea { anchors.fill: parent; onClicked: win.req("POST", "/later", {item: vp.v, on: !win.isLater(vp.v.id)}, function (j) { if (j && j.lists) win.lists = j.lists }) } } }
                Text { x: 22; width: parent.width - 44; color: "#cfcfcf"; font.pixelSize: 17; wrapMode: Text.Wrap; visible: !!vp.d.desc
                       text: vp.d.desc || ""; maximumLineCount: vp.descOpen ? 400 : 4; elide: Text.ElideRight
                       MouseArea { anchors.fill: parent; onClicked: vp.descOpen = !vp.descOpen } }
                Text { x: 22; text: rel.count ? "up next" : (vp.d.id ? "" : "loading…"); color: "#888"; font.pixelSize: 22; font.weight: Font.Light }
                Repeater { model: rel
                    Item { width: vcol.width; height: 128; scale: rm.pressed ? 0.98 : 1
                        Rectangle { id: rth; x: 22; y: 6; width: 205; height: 115; color: "#1c1c1c"
                            Image { anchors.fill: parent; asynchronous: true; fillMode: Image.PreserveAspectCrop; sourceSize.width: 320; sourceSize.height: 180; source: win.api + "/thumb?id=" + model.id }
                            Rectangle { visible: !!model.dur; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 4; width: rdt.width + 8; height: 21; color: "#d0000000"
                                Text { id: rdt; anchors.centerIn: parent; text: model.dur; color: "white"; font.pixelSize: 13 } } }
                        Column { x: 242; y: 6; width: parent.width - 264; spacing: 4
                            Text { width: parent.width; text: model.title; color: "white"; font.pixelSize: 18; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                            Text { width: parent.width; text: model.channel; color: "#a8a8a8"; font.pixelSize: 15; elide: Text.ElideRight }
                            Text { width: parent.width; text: model.meta; color: "#a8a8a8"; font.pixelSize: 15; elide: Text.ElideRight } }
                        MouseArea { id: rm; anchors.fill: parent; onClicked: vp.open({id: model.id, title: model.title, channel: model.channel, channel_id: model.channel_id, dur: model.dur, meta: model.meta})
                                    onPressAndHold: menu.open({id: model.id, title: model.title, channel: model.channel, channel_id: model.channel_id, dur: model.dur, meta: model.meta}) } } } } } }

    // ---------- toast ----------
    Rectangle { id: toast; z: 9; width: parent.width; height: 52; color: win.acc; y: -height
        property alias text: tl.text
        function show(t) { text = t; y = 0; hideT.restart() }
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Text { id: tl; x: 22; anchors.verticalCenter: parent.verticalCenter; color: "white"; font.pixelSize: 19 }
        Timer { id: hideT; interval: 2200; onTriggered: toast.y = -toast.height } }

    // BACK (hardware key / navbar sends Escape): close the top layer, else leave search results
    Shortcut { sequences: ["Esc", "Back"]; context: Qt.WindowShortcut; onActivated: {
            if (menu.visible) menu.visible = false
            else if (vp.visible) vp.visible = false
            else if (chan.visible) chan.visible = false
            else if (box.activeFocus) { box.focus = false; win.dash("kbd_hide") }
            else if (win.tab === 4) win.setTab(0) } }
}
