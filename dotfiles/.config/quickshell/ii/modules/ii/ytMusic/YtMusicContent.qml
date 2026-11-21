import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    focus: true
    implicitWidth: 900
    implicitHeight: 600

    property int viewIndex: 0
    readonly property var navItems: [
        { index: 0, icon: "play_circle", label: "Now Playing" },
        { index: 1, icon: "home", label: "For You" },
        { index: 2, icon: "search", label: "Search" },
        { index: 3, icon: "library_music", label: "Library" }
    ]

    property string noticeText: ""
    property bool seeking: false
    property real seekPreview: 0

    function fmtTime(secs) {
        if (secs === undefined || secs === null || isNaN(secs) || secs < 0) return "0:00";
        secs = Math.floor(secs);
        const h = Math.floor(secs / 3600);
        const m = Math.floor((secs % 3600) / 60);
        const s = secs % 60;
        if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }
    function parseDurationString(str) {
        if (!str || typeof str !== "string") return 0;
        const p = str.split(":").map(x => parseInt(x, 10));
        if (p.some(isNaN)) return 0;
        if (p.length === 3) return p[0]*3600 + p[1]*60 + p[2];
        if (p.length === 2) return p[0]*60 + p[1];
        if (p.length === 1) return p[0];
        return 0;
    }
    function curTrack() {
        if (YtMusicService.currentTrack) return YtMusicService.currentTrack;
        if (YtMusicService.queueIndex >= 0 && YtMusicService.queueIndex < YtMusicService.queue.length)
            return YtMusicService.queue[YtMusicService.queueIndex];
        return null;
    }
    function curTitle() {
        const t = curTrack();
        return (t && (t.title || t.name)) ? (t.title || t.name) : "Nothing playing";
    }
    function curArtist() {
        const t = curTrack();
        if (!t) return "";
        const a = t.artist || t.uploader || "";
        const al = t.album || "";
        if (a && al) return a + " · " + al;
        return a || al || "";
    }
    function playableId(t) {
        if (!t) return "";
        const id = t.id || t.videoId || t.video_id || "";
        if (!id || id.indexOf("ytmtui-") === 0) return "";
        return /^[A-Za-z0-9_-]{11}$/.test(id) ? id : "";
    }
    function trackThumb(t) {
        if (!t) return "";
        const direct = t.thumbnail_url || t.thumbnail || t.artUrl || t.art_url || "";
        if (direct) return direct;
        const id = playableId(t);
        return id ? "https://i.ytimg.com/vi/" + id + "/mqdefault.jpg" : "";
    }
    function curThumb() { return trackThumb(curTrack()); }
    function durationSecs() {
        if (YtMusicService.durationSecs > 0) return YtMusicService.durationSecs;
        const t = curTrack();
        if (!t) return 0;
        if (t.duration_secs) return Number(t.duration_secs) || 0;
        return parseDurationString(t.duration);
    }
    function displayPosition() {
        return root.seeking ? root.seekPreview : YtMusicService.positionSecs;
    }
    function trackArtistLine(t) {
        if (!t) return "";
        const a = t.artist || t.uploader || "";
        const al = t.album || "";
        if (a && al) return a + " · " + al;
        return a || al || "";
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            GlobalStates.ytMusicOpen = false;
            event.accepted = true;
        } else if (event.key === Qt.Key_Space) {
            YtMusicService.transport("play-pause");
            event.accepted = true;
        }
    }

    Connections {
        target: YtMusicService
        function onActionFinished(action, ok, message) {
            root.noticeText = (ok ? "✓ " : "✗ ") + action + (message ? (": " + message.split("\n")[0]) : "");
            noticeTimer.restart();
        }
    }
    Timer { id: noticeTimer; interval: 3500; onTriggered: root.noticeText = "" }

    Rectangle {
        anchors.fill: parent
        anchors.margins: Appearance.sizes.hyprlandGapsOut
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    width: 34; height: 34; radius: 10
                    color: Appearance.colors.colSecondaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "music_note"; iconSize: 20
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    StyledText {
                        text: "YouTube Music"
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        text: YtMusicService.errorText.length > 0 ? YtMusicService.errorText
                            : (YtMusicService.statusText.length > 0 ? YtMusicService.statusText
                                : (YtMusicService.usingOwnPlayer ? (YtMusicService.paused ? "Paused" : "Playing") : "Ready"))
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: YtMusicService.errorText.length > 0 ? Appearance.colors.colError : Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    visible: root.noticeText.length > 0
                    radius: height / 2
                    color: Appearance.colors.colSecondaryContainer
                    implicitHeight: 24
                    implicitWidth: noticeLabel.implicitWidth + 16
                    StyledText {
                        id: noticeLabel; anchors.centerIn: parent
                        text: root.noticeText
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
                RippleButton {
                    implicitWidth: 32; implicitHeight: 32; buttonRadius: 16
                    colBackground: "transparent"; colBackgroundHover: Appearance.colors.colLayer2
                    onClicked: YtMusicService.refresh()
                    contentItem: Item {
                        anchors.fill: parent
                        MaterialSymbol { anchors.centerIn: parent; text: "refresh"; iconSize: 20; color: Appearance.colors.colOnLayer0 }
                    }
                    StyledToolTip { text: "Refresh" }
                }
                RippleButton {
                    implicitWidth: 32; implicitHeight: 32; buttonRadius: 16
                    colBackground: "transparent"; colBackgroundHover: Appearance.colors.colLayer2
                    onClicked: GlobalStates.ytMusicOpen = false
                    contentItem: Item {
                        anchors.fill: parent
                        MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: 20; color: Appearance.colors.colOnLayer0 }
                    }
                    StyledToolTip { text: "Close (Esc)" }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                // Sidebar
                Rectangle {
                    Layout.preferredWidth: 170
                    Layout.fillHeight: true
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer1
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 6
                        Repeater {
                            model: root.navItems
                            delegate: RippleButton {
                                id: navBtn
                                required property var modelData
                                readonly property bool selected: root.viewIndex === modelData.index
                                Layout.fillWidth: true
                                implicitHeight: 38
                                buttonRadius: Appearance.rounding.normal
                                toggled: selected
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2
                                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                                onClicked: root.viewIndex = modelData.index
                                contentItem: RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                                    MaterialSymbol { text: navBtn.modelData.icon; iconSize: 20; color: navBtn.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1 }
                                    StyledText { text: navBtn.modelData.label; font.pixelSize: Appearance.font.pixelSize.small; font.weight: navBtn.selected ? Font.DemiBold : Font.Normal; color: navBtn.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1 }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                        StyledText {
                            Layout.fillWidth: true; Layout.margins: 4
                            wrapMode: Text.Wrap
                            text: "Space: play/pause\nEsc: close"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: root.viewIndex

                    // 0: Now Playing (centered like old view)
                    Item {
                        Rectangle { anchors.fill: parent; radius: Appearance.rounding.large; color: Appearance.colors.colLayer1 }
                        ColumnLayout {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 40, 520)
                            spacing: 14

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: 300; height: 300
                                radius: 22
                                color: Appearance.colors.colLayer2
                                clip: true
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border
                                Image {
                                    anchors.fill: parent
                                    source: root.curThumb() || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize: Qt.size(300, 300)
                                    visible: status === Image.Ready
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: root.curThumb().length === 0
                                    text: "album"; iconSize: 96
                                    color: Appearance.colors.colSubtext
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: root.curTitle()
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: root.curArtist() || "—"
                                font.pixelSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }

                            // Seekable progress
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                StyledSlider {
                                    id: progressSlider
                                    Layout.fillWidth: true
                                    enabled: root.durationSecs() > 0 && (YtMusicService.usingOwnPlayer || YtMusicService.daemonRunning)
                                    from: 0
                                    to: Math.max(1, root.durationSecs())
                                    stepSize: 1
                                    configuration: StyledSlider.Configuration.S
                                    highlightColor: Appearance.colors.colPrimary
                                    trackColor: Appearance.colors.colLayer2
                                    handleColor: Appearance.colors.colPrimary
                                    value: root.displayPosition()
                                    onPressedChanged: {
                                        if (pressed) {
                                            root.seeking = true;
                                            root.seekPreview = value;
                                        } else {
                                            YtMusicService.seekTo(value);
                                            root.seeking = false;
                                        }
                                    }
                                    onMoved: {
                                        if (root.seeking) root.seekPreview = value;
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    StyledText { text: root.fmtTime(root.displayPosition()); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                                    Item { Layout.fillWidth: true }
                                    StyledText { text: root.durationSecs() > 0 ? root.fmtTime(root.durationSecs()) : "--:--"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                                }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 10
                                RippleButton {
                                    implicitWidth: 40; implicitHeight: 40; buttonRadius: 20
                                    enabled: !!root.playableId(root.curTrack()) && !YtMusicService.likeActionBusy
                                    toggled: YtMusicService.likeState === "liked"
                                    colBackground: "transparent"; colBackgroundHover: Appearance.colors.colLayer2
                                    colBackgroundToggled: "transparent"; colBackgroundToggledHover: Appearance.colors.colLayer2
                                    onClicked: YtMusicService.toggleLike()
                                    contentItem: Item {
                                        anchors.fill: parent
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: YtMusicService.likeState === "liked" ? "thumb_up" : "thumb_up"
                                            iconSize: 22
                                            fill: YtMusicService.likeState === "liked" ? 1 : 0
                                            color: YtMusicService.likeState === "liked" ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                        }
                                    }
                                    StyledToolTip { text: YtMusicService.likeState === "liked" ? "Remove like" : "Like" }
                                }
                                RippleButton {
                                    implicitWidth: 40; implicitHeight: 40; buttonRadius: 20
                                    enabled: !!root.playableId(root.curTrack()) && !YtMusicService.likeActionBusy
                                    toggled: YtMusicService.likeState === "disliked"
                                    colBackground: "transparent"; colBackgroundHover: Appearance.colors.colLayer2
                                    colBackgroundToggled: "transparent"; colBackgroundToggledHover: Appearance.colors.colLayer2
                                    onClicked: YtMusicService.toggleDislike()
                                    contentItem: Item {
                                        anchors.fill: parent
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "thumb_down"
                                            iconSize: 22
                                            fill: YtMusicService.likeState === "disliked" ? 1 : 0
                                            color: YtMusicService.likeState === "disliked" ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                                        }
                                    }
                                    StyledToolTip { text: YtMusicService.likeState === "disliked" ? "Remove dislike" : "Dislike" }
                                }
                                RippleButton {
                                    implicitWidth: 46; implicitHeight: 46; buttonRadius: 23
                                    enabled: YtMusicService.usingOwnPlayer || YtMusicService.queue.length > 0 || YtMusicService.daemonRunning
                                    colBackground: "transparent"; colBackgroundHover: Appearance.colors.colLayer2
                                    onClicked: YtMusicService.transport("previous")
                                    contentItem: Item { anchors.fill: parent; MaterialSymbol { anchors.centerIn: parent; text: "skip_previous"; iconSize: 28; color: Appearance.colors.colOnLayer1 } }
                                }
                                RippleButton {
                                    implicitWidth: 60; implicitHeight: 60; buttonRadius: 30
                                    enabled: YtMusicService.usingOwnPlayer || YtMusicService.queue.length > 0 || YtMusicService.daemonRunning
                                    colBackground: Appearance.colors.colPrimary
                                    colBackgroundHover: Appearance.colors.colPrimaryHover
                                    colRipple: Appearance.colors.colPrimaryActive
                                    onClicked: YtMusicService.transport("play-pause")
                                    contentItem: Item {
                                        anchors.fill: parent
                                        MaterialSymbol { anchors.centerIn: parent; text: YtMusicService.paused ? "play_arrow" : "pause"; iconSize: 32; fill: 1; color: Appearance.colors.colOnPrimary }
                                    }
                                }
                                RippleButton {
                                    implicitWidth: 46; implicitHeight: 46; buttonRadius: 23
                                    enabled: YtMusicService.usingOwnPlayer || YtMusicService.queue.length > 0 || YtMusicService.daemonRunning
                                    colBackground: "transparent"; colBackgroundHover: Appearance.colors.colLayer2
                                    onClicked: YtMusicService.transport("next")
                                    contentItem: Item { anchors.fill: parent; MaterialSymbol { anchors.centerIn: parent; text: "skip_next"; iconSize: 28; color: Appearance.colors.colOnLayer1 } }
                                }
                                RippleButton {
                                    implicitWidth: 40; implicitHeight: 40; buttonRadius: 20
                                    enabled: !!root.playableId(root.curTrack()) && !YtMusicService.addablePlaylistsBusy && !YtMusicService.addToPlaylistBusy
                                    toggled: playlistPicker.visible
                                    colBackground: "transparent"; colBackgroundHover: Appearance.colors.colLayer2
                                    colBackgroundToggled: "transparent"; colBackgroundToggledHover: Appearance.colors.colLayer2
                                    onClicked: {
                                        if (playlistPicker.visible) {
                                            playlistPicker.closePicker();
                                        } else {
                                            playlistPicker.openPicker();
                                        }
                                    }
                                    contentItem: Item {
                                        anchors.fill: parent
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "playlist_add"
                                            iconSize: 22
                                            color: playlistPicker.visible ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                        }
                                    }
                                    StyledToolTip { text: "Add to playlist" }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                MaterialSymbol { text: YtMusicService.volume <= 0 ? "volume_off" : (YtMusicService.volume < 50 ? "volume_down" : "volume_up"); iconSize: 20; color: Appearance.colors.colSubtext }
                                StyledSlider {
                                    Layout.fillWidth: true
                                    from: 0; to: 100; stepSize: 1
                                    value: YtMusicService.volume
                                    configuration: StyledSlider.Configuration.S
                                    onMoved: YtMusicService.setVolume(Math.round(value))
                                }
                                StyledText { Layout.preferredWidth: 42; horizontalAlignment: Text.AlignRight; text: YtMusicService.volume + "%"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                            }
                        }
                    }

                    // 1: For You
                    Item {
                        Rectangle { anchors.fill: parent; radius: Appearance.rounding.large; color: Appearance.colors.colLayer1 }
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 14; spacing: 10
                            StyledText { text: "For You"; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer1 }
                            Item {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                StyledText {
                                    anchors.centerIn: parent; visible: YtMusicService.browseShelves.length === 0
                                    width: parent.width - 60; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                                    text: "No cached recommendations yet.\nOpen ytmtui once to populate."; color: Appearance.colors.colSubtext
                                }
                                Flickable {
                                    anchors.fill: parent
                                    contentWidth: width; contentHeight: browseCol.implicitHeight
                                    clip: true; boundsBehavior: Flickable.StopAtBounds
                                    ScrollBar.vertical: StyledScrollBar {}
                                    ColumnLayout {
                                        id: browseCol; width: parent.width; spacing: 16
                                        Repeater {
                                            model: YtMusicService.browseShelves
                                            delegate: ColumnLayout {
                                                required property var modelData
                                                Layout.fillWidth: true; spacing: 8
                                                StyledText { text: (modelData && modelData.title) ? modelData.title : "Shelf"; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer1 }
                                                Flow {
                                                    Layout.fillWidth: true; spacing: 8
                                                    Repeater {
                                                        model: (modelData && modelData.items) ? modelData.items : []
                                                        delegate: RippleButton {
                                                            id: shelfItem
                                                            required property var modelData
                                                            implicitWidth: 160; implicitHeight: 186
                                                            buttonRadius: Appearance.rounding.normal
                                                            colBackground: Appearance.colors.colLayer2; colBackgroundHover: Appearance.colors.colLayer2Hover
                                                            property var trackObj: {
                                                                if (!modelData) return null;
                                                                if (modelData.Track) return modelData.Track;
                                                                if (modelData.track) return modelData.track;
                                                                if (modelData.title || modelData.name) return modelData;
                                                                return null;
                                                            }
                                                            property var collectionObj: (modelData && modelData.Collection) ? modelData.Collection : null
                                                            property var displayObj: trackObj ? trackObj : (collectionObj ? collectionObj : modelData)
                                                            property bool playable: !!trackObj && root.playableId(trackObj).length > 0
                                                            property bool openableCollection: !!collectionObj && !trackObj
                                                            property bool clickableItem: playable || openableCollection
                                                            property string displayTitle: trackObj ? (trackObj.title || trackObj.name || "Track")
                                                                : (collectionObj ? (collectionObj.title || "Collection")
                                                                : ((modelData && modelData.title) ? modelData.title : "Item"))
                                                            property string displaySub: trackObj ? ((trackObj.artist || trackObj.uploader || "") + (trackObj.album ? ((trackObj.artist || trackObj.uploader) ? " · " : "") + trackObj.album : ""))
                                                                : (collectionObj ? (collectionObj.subtitle || collectionObj.kind || "") : "")
                                                            property string displayThumb: root.trackThumb(displayObj)
                                                            enabled: clickableItem && !YtMusicService.resolvingCollection
                                                            opacity: clickableItem ? 1.0 : 0.55
                                                            onClicked: {
                                                                if (playable && trackObj) YtMusicService.playSingleTrack(trackObj);
                                                                else if (openableCollection) YtMusicService.playCollection(collectionObj);
                                                            }
                                                            contentItem: ColumnLayout {
                                                                anchors.fill: parent; anchors.margins: 8; spacing: 6
                                                                Rectangle {
                                                                    Layout.fillWidth: true; Layout.preferredHeight: 112; radius: Appearance.rounding.small; color: Appearance.colors.colLayer1; clip: true
                                                                    Image { anchors.fill: parent; source: shelfItem.displayThumb; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(144,112); visible: status === Image.Ready }
                                                                    MaterialSymbol { anchors.centerIn: parent; visible: shelfItem.displayThumb.length === 0; text: shelfItem.playable ? "play_circle" : (shelfItem.openableCollection ? "queue_music" : "library_music"); iconSize: 32; color: Appearance.colors.colSubtext }
                                                                }
                                                                StyledText { Layout.fillWidth: true; text: shelfItem.displayTitle; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Medium; color: Appearance.colors.colOnLayer1; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap }
                                                                StyledText { Layout.fillWidth: true; text: shelfItem.displaySub; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext; elide: Text.ElideRight; visible: text.length > 0 }
                                                                Item { Layout.fillHeight: true }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 2: Search / Open
                    Item {
                        Rectangle { anchors.fill: parent; radius: Appearance.rounding.large; color: Appearance.colors.colLayer1 }
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 14; spacing: 10
                            StyledText { text: "Search & Open"; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer1 }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                ToolbarTextField {
                                    id: searchField
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    implicitHeight: 32
                                    topPadding: 5
                                    bottomPadding: 5
                                    leftPadding: 12
                                    rightPadding: 12
                                    placeholderText: "Search songs, artists…"
                                    onAccepted: YtMusicService.performSearch(text)
                                }
                                RippleButton {
                                    implicitWidth: 32; implicitHeight: 32; buttonRadius: 16
                                    colBackground: Appearance.colors.colSecondaryContainer
                                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                    enabled: !YtMusicService.searchBusy && searchField.text.trim().length > 0
                                    onClicked: YtMusicService.performSearch(searchField.text)
                                    contentItem: Item { anchors.fill: parent; MaterialSymbol { anchors.centerIn: parent; text: YtMusicService.searchBusy ? "hourglass_top" : "search"; iconSize: 18; color: Appearance.colors.colOnSecondaryContainer } }
                                    StyledToolTip { text: "Search" }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                ToolbarTextField {
                                    id: openField
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    implicitHeight: 32
                                    topPadding: 5
                                    bottomPadding: 5
                                    leftPadding: 12
                                    rightPadding: 12
                                    placeholderText: "Paste YouTube/playlist URL or ID"
                                    onAccepted: { YtMusicService.openInput(text); text = ""; }
                                }
                                RippleButton {
                                    implicitWidth: 32; implicitHeight: 32; buttonRadius: 16
                                    colBackground: Appearance.colors.colSecondaryContainer
                                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                    enabled: !YtMusicService.resolvingCollection && openField.text.trim().length > 0
                                    onClicked: { YtMusicService.openInput(openField.text); openField.text = ""; }
                                    contentItem: Item { anchors.fill: parent; MaterialSymbol { anchors.centerIn: parent; text: "open_in_new"; iconSize: 18; color: Appearance.colors.colOnSecondaryContainer } }
                                    StyledToolTip { text: "Open/play" }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                RippleButton {
                                    id: autoplayBtn
                                    implicitHeight: 30
                                    implicitWidth: autoplayLabel.implicitWidth + 20
                                    buttonRadius: Appearance.rounding.small
                                    toggled: YtMusicService.autoplayEnabled
                                    colBackground: toggled ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                                    colBackgroundHover: toggled ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                                    onClicked: YtMusicService.autoplayEnabled = !YtMusicService.autoplayEnabled
                                    contentItem: StyledText {
                                        id: autoplayLabel
                                        anchors.centerIn: parent
                                        text: "Autoplay: " + (YtMusicService.autoplayEnabled ? "On" : "Off")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: autoplayBtn.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: YtMusicService.radioBusy ? "Loading recommendations…" : (YtMusicService.searchBusy ? "Searching…" : "Tip: paste a playlist link from your library to play it")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                StyledText {
                                    anchors.centerIn: parent
                                    visible: YtMusicService.searchResults.length === 0 && !YtMusicService.searchBusy
                                    width: parent.width - 40
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    text: "Search for music or paste a link/ID\n(video, playlist, album — including your own)"
                                    color: Appearance.colors.colSubtext
                                }
                                ListView {
                                    anchors.fill: parent
                                    clip: true
                                    spacing: 4
                                    model: YtMusicService.searchResults
                                    ScrollBar.vertical: StyledScrollBar {}
                                    delegate: RippleButton {
                                        id: srItem
                                        required property var modelData
                                        required property int index
                                        width: ListView.view ? ListView.view.width : 300
                                        implicitHeight: 58
                                        buttonRadius: Appearance.rounding.normal
                                        colBackground: "transparent"
                                        colBackgroundHover: Appearance.colors.colLayer2
                                        onClicked: YtMusicService.playSingleTrack(modelData)
                                        contentItem: RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 10
                                            Rectangle {
                                                width: 40; height: 40; radius: 8; color: Appearance.colors.colLayer2; clip: true
                                                Image { anchors.fill: parent; source: root.trackThumb(srItem.modelData); fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(40,40); visible: status === Image.Ready }
                                                MaterialSymbol { anchors.centerIn: parent; visible: root.trackThumb(srItem.modelData).length === 0; text: "music_note"; iconSize: 20; color: Appearance.colors.colSubtext }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 1
                                                StyledText { Layout.fillWidth: true; text: (modelData && (modelData.title || modelData.name)) ? (modelData.title || modelData.name) : "Unknown"; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Normal; color: Appearance.colors.colOnLayer1; elide: Text.ElideRight }
                                                StyledText { Layout.fillWidth: true; text: root.trackArtistLine(modelData); font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext; elide: Text.ElideRight; visible: text.length > 0 }
                                            }
                                            MaterialSymbol { text: "play_arrow"; iconSize: 20; color: Appearance.colors.colSubtext }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 3: Library
                    Item {
                        Rectangle { anchors.fill: parent; radius: Appearance.rounding.large; color: Appearance.colors.colLayer1 }
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 14; spacing: 10
                            RowLayout {
                                Layout.fillWidth: true
                                StyledText { text: "Library"; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer1 }
                                Rectangle {
                                    visible: YtMusicService.libraryPlaylists.length > 0
                                    radius: 10; color: Appearance.colors.colSecondaryContainer
                                    implicitWidth: libCount.implicitWidth + 14; implicitHeight: 22
                                    StyledText { id: libCount; anchors.centerIn: parent; text: YtMusicService.libraryPlaylists.length; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colOnSecondaryContainer }
                                }
                                Item { Layout.fillWidth: true }
                                StyledText {
                                    visible: YtMusicService.libraryBusy
                                    text: "Loading…"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }
                                RippleButton {
                                    implicitWidth: 32; implicitHeight: 32; buttonRadius: 16
                                    colBackground: "transparent"; colBackgroundHover: Appearance.colors.colLayer2
                                    onClicked: YtMusicService.refreshLibrary()
                                    contentItem: Item { anchors.fill: parent; MaterialSymbol { anchors.centerIn: parent; text: "refresh"; iconSize: 20; color: Appearance.colors.colOnLayer0 } }
                                    StyledToolTip { text: "Refresh library" }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                StyledText {
                                    anchors.centerIn: parent
                                    visible: YtMusicService.libraryPlaylists.length === 0 && !YtMusicService.libraryBusy
                                    width: parent.width - 60
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    text: "No playlists found.\nMake sure you're signed in to ytmtui (ytmtui setup),\nor paste a playlist link in Search."
                                    color: Appearance.colors.colSubtext
                                }
                                ListView {
                                    anchors.fill: parent
                                    clip: true
                                    spacing: 4
                                    model: YtMusicService.libraryPlaylists
                                    ScrollBar.vertical: StyledScrollBar {}
                                    delegate: RippleButton {
                                        id: libItem
                                        required property var modelData
                                        required property int index
                                        width: ListView.view ? ListView.view.width : 300
                                        implicitHeight: 56
                                        buttonRadius: Appearance.rounding.normal
                                        colBackground: "transparent"
                                        colBackgroundHover: Appearance.colors.colLayer2
                                        onClicked: YtMusicService.playCollection({ id: modelData.id, title: modelData.title || "Playlist" })
                                        contentItem: RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 10
                                            Rectangle {
                                                width: 40; height: 40; radius: 8; color: Appearance.colors.colLayer2
                                                MaterialSymbol { anchors.centerIn: parent; text: (modelData && (modelData.id === "VLLM" || modelData.id === "LM")) ? "favorite" : "queue_music"; iconSize: 22; color: Appearance.colors.colSubtext }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 1
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: (modelData && modelData.title) ? modelData.title : "Playlist"
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.weight: Font.Medium
                                                    color: Appearance.colors.colOnLayer1
                                                    elide: Text.ElideRight
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: {
                                                        if (!modelData) return "";
                                                        const c = modelData.count || "";
                                                        return c ? (c + " tracks") : "Playlist";
                                                    }
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colSubtext
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            MaterialSymbol { text: "play_circle"; iconSize: 22; color: Appearance.colors.colSubtext }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Right side: current queue
                Rectangle {
                    Layout.preferredWidth: 270
                    Layout.fillHeight: true
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer1
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 14; spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText { text: "Queue"; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer1 }
                            Rectangle {
                                radius: 10; color: Appearance.colors.colSecondaryContainer
                                implicitWidth: qc.implicitWidth + 14; implicitHeight: 22
                                StyledText { id: qc; anchors.centerIn: parent; text: YtMusicService.queue.length; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colOnSecondaryContainer }
                            }
                            Item { Layout.fillWidth: true }
                            RippleButton {
                                implicitHeight: 30; implicitWidth: clr.implicitWidth + 18; buttonRadius: Appearance.rounding.small
                                colBackground: Appearance.colors.colLayer2; colBackgroundHover: Appearance.colors.colLayer2Hover
                                onClicked: YtMusicService.clearQueue()
                                contentItem: StyledText { id: clr; anchors.centerIn: parent; text: "Clear"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer1 }
                            }
                        }
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            StyledText {
                                anchors.centerIn: parent; visible: YtMusicService.queue.length === 0
                                width: parent.width - 40; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                                text: "Queue is empty\nPick a track from For You"; color: Appearance.colors.colSubtext
                            }
                            ListView {
                                anchors.fill: parent; clip: true; spacing: 4
                                model: YtMusicService.queue
                                ScrollBar.vertical: StyledScrollBar {}
                                delegate: RippleButton {
                                    id: qItem
                                    required property var modelData
                                    required property int index
                                    width: ListView.view ? ListView.view.width : 300
                                    implicitHeight: 58
                                    buttonRadius: Appearance.rounding.normal
                                    readonly property bool isCurrent: index === YtMusicService.queueIndex
                                    colBackground: isCurrent ? Appearance.colors.colSecondaryContainer : "transparent"
                                    colBackgroundHover: isCurrent ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2
                                    onClicked: YtMusicService.jump(index)
                                    contentItem: RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 10
                                        Rectangle {
                                            width: 40; height: 40; radius: 8; color: Appearance.colors.colLayer2; clip: true
                                            Image { anchors.fill: parent; source: root.trackThumb(qItem.modelData); fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(40,40); visible: status === Image.Ready }
                                            MaterialSymbol { anchors.centerIn: parent; visible: root.trackThumb(qItem.modelData).length === 0; text: qItem.isCurrent ? "graphic_eq" : "music_note"; iconSize: 20; color: qItem.isCurrent ? Appearance.colors.colPrimary : Appearance.colors.colSubtext }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 1
                                            StyledText { Layout.fillWidth: true; text: (modelData && (modelData.title || modelData.name)) ? (modelData.title || modelData.name) : "Unknown"; font.pixelSize: Appearance.font.pixelSize.small; font.weight: qItem.isCurrent ? Font.DemiBold : Font.Normal; color: qItem.isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1; elide: Text.ElideRight }
                                            StyledText { Layout.fillWidth: true; text: { const a=modelData?(modelData.artist||modelData.uploader||""):""; const al=modelData?(modelData.album||""):""; if(a&&al) return a+" · "+al; return a||al||""; } font.pixelSize: Appearance.font.pixelSize.smallest; color: qItem.isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext; elide: Text.ElideRight; visible: text.length>0 }
                                        }
                                        StyledText { text: (modelData && modelData.duration) ? modelData.duration : ""; font.pixelSize: Appearance.font.pixelSize.smallest; color: qItem.isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext }
                                    }
                                }
                            }
                        }
                    }

                }

            }
        }

        // Click-catcher to close playlist picker
        MouseArea {
            anchors.fill: parent
            visible: playlistPicker.visible
            z: 90
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: playlistPicker.closePicker()
        }

        Rectangle {
            id: playlistPicker
            z: 100
            visible: false
            width: 320
            height: Math.min(420, Math.max(180, pickerContent.implicitHeight + 24))
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter

            function openPicker() {
                visible = true;
                YtMusicService.fetchAddablePlaylists();
            }
            function closePicker() { visible = false; }

            ColumnLayout {
                id: pickerContent
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol { text: "playlist_add"; iconSize: 20; color: Appearance.colors.colOnLayer1 }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Add to playlist"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                    RippleButton {
                        implicitWidth: 28; implicitHeight: 28; buttonRadius: 14
                        colBackground: "transparent"; colBackgroundHover: Appearance.colors.colLayer2
                        onClicked: playlistPicker.closePicker()
                        contentItem: Item { anchors.fill: parent; MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: 18; color: Appearance.colors.colOnLayer1 } }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: YtMusicService.addablePlaylistsBusy
                    text: "Loading playlists…"
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !YtMusicService.addablePlaylistsBusy && YtMusicService.addablePlaylists.length === 0
                    text: "No playlists found or not signed in."
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: YtMusicService.addablePlaylists.length > 0
                    clip: true
                    spacing: 4
                    model: YtMusicService.addablePlaylists
                    ScrollBar.vertical: StyledScrollBar {}
                    delegate: RippleButton {
                        id: plPickItem
                        required property var modelData
                        required property int index
                        width: ListView.view ? ListView.view.width : 280
                        implicitHeight: 44
                        buttonRadius: Appearance.rounding.normal
                        readonly property bool added: (modelData && modelData.contains && modelData.contains !== "NONE")
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2
                        onClicked: {
                            if (!modelData) return;
                            YtMusicService.addCurrentTrackToPlaylist(modelData.id, modelData.title);
                            playlistPicker.closePicker();
                        }
                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8
                            MaterialSymbol {
                                text: plPickItem.added ? "check_circle" : "queue_music"
                                iconSize: 18
                                color: plPickItem.added ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: (modelData && modelData.title) ? modelData.title : "Playlist"
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                visible: plPickItem.added
                                text: "Added"
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
        }
    }
}
