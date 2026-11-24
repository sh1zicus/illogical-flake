pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string homePath: FileUtils.trimFileProtocol(Directories.home)
    readonly property string configDir: homePath + "/.config/ytmtui"
    readonly property string sessionPath: configDir + "/session.json"
    readonly property string browsePath: configDir + "/browse.json"
    readonly property string authPath: configDir + "/auth.json"
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string ownSocketPath: runtimeDir + "/qs-ytmusic-mpv.sock"

    readonly property string ytDlpBin: "/nix/store/g2g4il5g9gk78bnljbhf8z7c1axhsc37-yt-dlp-2026.08.19/bin/yt-dlp"
    readonly property string mpvBin: "/nix/store/rxqi040jn5cgfpcvk3j4wszwlkhn2n8n-mpv-with-scripts-0.41.0/bin/mpv"
    readonly property string playerctlBin: "/nix/store/7kfpibyrrfjhgfbxmska745dj6anivc4-playerctl-2.4.1/bin/playerctl"
    readonly property string ytmtuiBin: "/nix/store/9kidginsrhlp01jri4kzj3dfxaddy4rv-ytmtui-0.1.23/bin/ytmtui"
    readonly property string authHelperPath: homePath + "/.config/quickshell/ii/services/ytmusic_auth.py"
    readonly property string cookiesPath: runtimeDir + "/qs-ytmusic-cookies.txt"

    property bool cookiesReady: false
    property bool cookiesExporting: false
    property var _pendingCollection: null

    // Like / add-to-playlist state (per-track, best-effort; no server-synced initial state)
    property string likeState: "none" // none | liked | disliked
    property bool likeActionBusy: false
    property bool addToPlaylistBusy: false
    property bool addablePlaylistsBusy: false
    property var addablePlaylists: []
    property string addablePlaylistsForId: ""

    property bool daemonRunning: false
    property bool busy: false
    property string statusText: ""
    property string errorText: ""

    property var currentTrack: null
    property var queue: []
    property int queueIndex: -1
    property real positionSecs: 0
    property real durationSecs: 0
    property bool paused: false
    property int volume: 100
    property string repeatMode: "off"
    property bool shuffle: false

    property var browseShelves: []
    property bool authenticated: false

    property var searchResults: []
    property bool searchBusy: false
    property string searchQuery: ""
    property bool autoplayEnabled: true
    property bool radioBusy: false
    property string radioForId: ""

    property var libraryPlaylists: []
    property bool libraryBusy: false

    // Independent playback backend (mpv + yt-dlp), used when ytmtui daemon is not running.
    property bool usingOwnPlayer: false
    property bool resolvingUrl: false
    property bool resolvingCollection: false
    property bool userStopRequested: false
    property bool switchStopRequested: false
    property int pendingPlayIndex: -1
    property string pendingPlayId: ""
    property double ownPlayStartedAtMs: 0
    property int _activeMpvGeneration: 0
    property var pendingMpvCommand: null
    property bool ownMprisSeen: false

    signal actionFinished(string action, bool ok, string message)

    function _pickYtThumb(thumbnails) {
        try {
            if (!Array.isArray(thumbnails) || thumbnails.length === 0) return "";
            let best = thumbnails[0];
            for (let i = 1; i < thumbnails.length; i++) {
                const t = thumbnails[i];
                if (!t) continue;
                const bw = (best && best.width) ? Number(best.width) : 0;
                const tw = t.width ? Number(t.width) : 0;
                if (tw > bw) best = t;
            }
            return (best && best.url) ? best.url : "";
        } catch (e) { return ""; }
    }

    function _ytDlpBaseArgs() {
        const args = [root.ytDlpBin, "--flat-playlist", "-J", "--no-warnings"];
        if (root.cookiesReady) args.push("--cookies", root.cookiesPath);
        return args;
    }

    function _beginCollectionResolve(col) {
        if (!col) return;
        const id = String(col.id || "");
        if (!id) {
            root.errorText = "No collection id";
            root.actionFinished("open", false, "No collection id");
            return;
        }
        if (id.indexOf("ytmtui-category:") === 0) {
            root.statusText = "";
            root.errorText = "This category can't be opened here";
            root.actionFinished("open", false, "Category browsing is not supported");
            return;
        }
        if (collectionResolveProc.running || collectionInnertubeProc.running) {
            root.actionFinished("open", false, "Busy loading collection");
            return;
        }

        const urls = [];
        if (id.indexOf("MPREb") === 0) {
            urls.push("https://music.youtube.com/browse/" + id);
            urls.push("https://music.youtube.com/playlist?list=" + encodeURIComponent(id));
        } else if (id.indexOf("VL") === 0) {
            urls.push("https://music.youtube.com/playlist?list=" + encodeURIComponent(id.substring(2)));
            urls.push("https://music.youtube.com/browse/" + id);
            urls.push("https://music.youtube.com/playlist?list=" + encodeURIComponent(id));
        } else if (id === "VLLM" || id === "LM") {
            urls.push("https://music.youtube.com/playlist?list=LM");
            urls.push("https://music.youtube.com/browse/VLLM");
        } else {
            urls.push("https://music.youtube.com/playlist?list=" + encodeURIComponent(id));
            urls.push("https://music.youtube.com/browse/" + id);
        }

        root.resolvingCollection = true;
        root.busy = true;
        root.errorText = "";
        root.statusText = "Loading " + (col.title || "collection") + "…";
        collectionResolveProc.collectionId = id;
        collectionResolveProc.collectionTitle = col.title || "Collection";
        collectionResolveProc.candidateUrls = urls;
        collectionResolveProc.candidateIndex = 0;
        collectionResolveProc.command = root._ytDlpBaseArgs().concat([urls[0]]);
        collectionResolveProc.running = true;
    }

    function playCollection(col) {
        if (!col) return;
        if (collectionResolveProc.running || collectionInnertubeProc.running) {
            root.actionFinished("open", false, "Busy");
            return;
        }
        root._pendingCollection = col;
        if (cookiesExportProc.running) {
            // export in progress (e.g. refresh); it will pick up pending collection on exit
            root.resolvingCollection = true;
            root.busy = true;
            root.statusText = "Loading " + (col.title || "collection") + "…";
            return;
        }
        root.cookiesExporting = true;
        cookiesExportProc.command = ["python3", root.authHelperPath, "export", root.cookiesPath];
        cookiesExportProc.running = true;
    }

    Process {
        id: cookiesExportProc
        stdout: StdioCollector {
            id: cookiesExportOut
            waitForEnd: true
        }
        stderr: StdioCollector { waitForEnd: true }
        onExited: (code, status) => {
            root.cookiesExporting = false;
            const ok = code === 0 && String(cookiesExportOut.text || "").trim().indexOf("ok") === 0;
            root.cookiesReady = ok;
            const pending = root._pendingCollection;
            root._pendingCollection = null;
            if (pending) {
                root._beginCollectionResolve(pending);
            }
        }
    }

    Process {
        id: collectionResolveProc
        property string collectionId: ""
        property string collectionTitle: "Collection"
        property var candidateUrls: []
        property int candidateIndex: 0
        stdout: StdioCollector {
            id: collectionResolveOut
            waitForEnd: true
            onStreamFinished: {
                try {
                    const txt = (collectionResolveOut.text || "").trim();
                    if (!txt || txt === "null") {
                        collectionResolveProc._parsedTracks = [];
                        return;
                    }
                    const data = JSON.parse(txt);
                    const entries = (data && Array.isArray(data.entries)) ? data.entries : [];
                    const tracks = [];
                    for (let i = 0; i < entries.length; i++) {
                        const e = entries[i];
                        if (!e || typeof e !== "object") continue;
                        let vid = e.id || "";
                        if ((!vid || !/^[A-Za-z0-9_-]{11}$/.test(String(vid))) && e.url) {
                            const m = String(e.url).match(/[?&]v=([A-Za-z0-9_-]{11})/);
                            if (m) vid = m[1];
                            if (!vid) {
                                const m2 = String(e.url).match(/\/shorts\/([A-Za-z0-9_-]{11})/);
                                if (m2) vid = m2[1];
                            }
                        }
                        vid = String(vid || "");
                        if (!/^[A-Za-z0-9_-]{11}$/.test(vid)) continue;
                        let artist = "";
                        if (Array.isArray(e.creators) && e.creators.length > 0) artist = e.creators.filter(Boolean).join(", ");
                        if (!artist) artist = e.artist || e.uploader || e.channel || "";
                        const thumb = root._pickYtThumb(e.thumbnails) || ("https://i.ytimg.com/vi/" + vid + "/mqdefault.jpg");
                        let dur = 0;
                        if (e.duration !== undefined && e.duration !== null) dur = Number(e.duration) || 0;
                        tracks.push({
                            id: vid,
                            title: e.title || "Track",
                            artist: artist,
                            album: e.album || "",
                            thumbnail_url: thumb,
                            duration_secs: dur
                        });
                    }
                    collectionResolveProc._parsedTracks = tracks;
                } catch (e) {
                    collectionResolveProc._parsedTracks = [];
                }
            }
        }
        stderr: StdioCollector { id: collectionResolveErr; waitForEnd: true }
        property var _parsedTracks: []
        onExited: (code, status) => {
            if (code === 0 && Array.isArray(collectionResolveProc._parsedTracks) && collectionResolveProc._parsedTracks.length > 0) {
                const tracks = collectionResolveProc._parsedTracks;
                collectionResolveProc._parsedTracks = [];
                root.resolvingCollection = false;
                root.busy = actionProc.running;
                root.queue = tracks;
                root.queueIndex = 0;
                root.statusText = "Loaded " + tracks.length + " tracks";
                root.playTrackObject(tracks[0], 0, tracks);
                root.actionFinished("open", true, tracks.length + " tracks");
                return;
            }
            collectionResolveProc._parsedTracks = [];
            const next = collectionResolveProc.candidateIndex + 1;
            if (next < collectionResolveProc.candidateUrls.length) {
                collectionResolveProc.candidateIndex = next;
                collectionResolveProc.command = root._ytDlpBaseArgs().concat([collectionResolveProc.candidateUrls[next]]);
                collectionResolveProc.running = true;
                return;
            }
            // Fallback: try innertube browse using browser cookies (no ytmtui auth required)
            if (collectionResolveProc.collectionId && !collectionInnertubeProc.running) {
                root.statusText = "Loading " + (collectionResolveProc.collectionTitle || "collection") + "…";
                collectionInnertubeProc.collectionId = collectionResolveProc.collectionId;
                collectionInnertubeProc.collectionTitle = collectionResolveProc.collectionTitle;
                collectionInnertubeProc.command = ["python3", root.authHelperPath, "browse", collectionResolveProc.collectionId];
                collectionInnertubeProc.running = true;
                return;
            }
            root.resolvingCollection = false;
            root.busy = actionProc.running;
            let msg = (collectionResolveErr.text || "").trim();
            const lines = msg.split("\n").filter(l => l && l.indexOf("WARNING:") !== 0);
            msg = (lines.length > 0 ? lines[lines.length - 1] : msg.split("\n")[0]) || "";
            root.errorText = msg ? ("Couldn't open collection: " + msg) : "Couldn't open collection";
            root.statusText = "";
            root.actionFinished("open", false, root.errorText || "failed");
        }
    }

    Process {
        id: collectionInnertubeProc
        property string collectionId: ""
        property string collectionTitle: "Collection"
        stdout: StdioCollector {
            id: collectionInnertubeOut
            waitForEnd: true
            onStreamFinished: {
                try {
                    const txt = (collectionInnertubeOut.text || "").trim();
                    if (!txt || txt === "[]") {
                        collectionInnertubeProc._parsedTracks = [];
                        return;
                    }
                    const arr = JSON.parse(txt);
                    if (!Array.isArray(arr)) { collectionInnertubeProc._parsedTracks = []; return; }
                    const tracks = [];
                    for (let i = 0; i < arr.length; i++) {
                        const e = arr[i];
                        if (!e || typeof e !== "object") continue;
                        const vid = String(e.id || "");
                        if (!/^[A-Za-z0-9_-]{11}$/.test(vid)) continue;
                        tracks.push({
                            id: vid,
                            title: e.title || "Track",
                            artist: e.artist || "",
                            album: e.album || "",
                            thumbnail_url: e.thumbnail_url || ("https://i.ytimg.com/vi/" + vid + "/mqdefault.jpg"),
                            duration: e.duration || ""
                        });
                    }
                    collectionInnertubeProc._parsedTracks = tracks;
                } catch (e) {
                    collectionInnertubeProc._parsedTracks = [];
                }
            }
        }
        stderr: StdioCollector { waitForEnd: true }
        property var _parsedTracks: []
        onExited: (code, status) => {
            const tracks = Array.isArray(collectionInnertubeProc._parsedTracks) ? collectionInnertubeProc._parsedTracks : [];
            collectionInnertubeProc._parsedTracks = [];
            root.resolvingCollection = false;
            root.busy = actionProc.running;
            if (tracks.length > 0) {
                root.queue = tracks;
                root.queueIndex = 0;
                root.statusText = "Loaded " + tracks.length + " tracks";
                root.playTrackObject(tracks[0], 0, tracks);
                root.actionFinished("open", true, tracks.length + " tracks");
                return;
            }
            root.errorText = "Couldn't open collection (bad request or unavailable)";
            root.statusText = "";
            root.actionFinished("open", false, root.errorText);
        }
    }

    function trackTitle(track) {
        if (!track) return "";
        return track.title || track.name || "";
    }
    function trackArtist(track) {
        if (!track) return "";
        return track.artist || track.uploader || "";
    }
    function trackSubtitle(track) {
        if (!track) return "";
        const a = trackArtist(track);
        const al = track.album || "";
        if (a && al) return a + " · " + al;
        return a || al || "";
    }
    function trackId(track) {
        if (!track) return "";
        return track.id || track.videoId || track.video_id || "";
    }

    function refresh() {
        browseFile.reload();
        sessionFile.reload();
        authFile.reload();
        pollNow();
        exportCookies();
        refreshLibrary();
    }

    function exportCookies() {
        if (cookiesExportProc.running || cookiesExporting) return;
        // don't override a pending collection resolve; this is a best-effort background refresh
        root.cookiesExporting = true;
        cookiesExportProc.command = ["python3", root.authHelperPath, "export", root.cookiesPath];
        cookiesExportProc.running = true;
    }

    function refreshLibrary() {
        if (libraryProc.running) return;
        root.libraryBusy = true;
        libraryProc.command = ["python3", root.authHelperPath, "library", root.ytDlpBin];
        libraryProc.running = true;
    }

    function pollNow() {
        if (nowProc.running) return;
        nowProc.running = true;
    }

    function pollQueue() {
        if (queueProc.running) return;
        queueProc.running = true;
    }

    function clearQueue() {
        if (root.daemonRunning) {
            runSimple([root.ytmtuiBin, "queue", "clear"], "queue clear");
        } else {
            root.stopOwnPlayer();
            root.queue = [];
            root.queueIndex = -1;
            root.currentTrack = null;
            root.statusText = "Queue cleared";
        }
    }

    function stopOwnPlayer() {
        root.userStopRequested = true;
        root.switchStopRequested = false;
        root.pendingMpvCommand = null;
        root.sendMpvCommand(["quit"]);
        if (ownMpvProc.running) ownMpvProc.running = false;
        Quickshell.execDetached([root.playerctlBin, "--player=mpv", "stop"]);
        root.usingOwnPlayer = false;
        root.paused = true;
        root.positionSecs = 0;
        root.statusText = "Stopped";
        Qt.callLater(function() { Quickshell.execDetached(["rm", "-f", root.ownSocketPath]); });
    }

    function sendMpvCommand(cmdArgs) {
        if (!cmdArgs) return;
        try {
            const payload = JSON.stringify(cmdArgs);
            Quickshell.execDetached([
                "python3", "-c",
                "import json,socket,sys\ns=socket.socket(socket.AF_UNIX)\ns.settimeout(0.2)\ntry:\n s.connect(sys.argv[1])\n s.sendall((json.dumps({'command':json.loads(sys.argv[2])})+'\\n').encode())\nexcept Exception:\n pass\nfinally:\n try:\n  s.close()\n except Exception:\n  pass",
                root.ownSocketPath,
                payload
            ]);
        } catch (e) {}
    }

    function isPlayableId(id) {
        return /^[A-Za-z0-9_-]{11}$/.test(String(id || ""));
    }

    function queueHasId(id) {
        if (!id) return false;
        for (let i = 0; i < root.queue.length; i++) {
            const tid = root.trackId(root.queue[i]);
            if (tid === id) return true;
        }
        return false;
    }

    function _tracksFromYtDlpJson(txt) {
        try {
            const data = JSON.parse(txt || "null");
            if (!data) return [];
            let entries = [];
            if (Array.isArray(data)) entries = data;
            else if (Array.isArray(data.entries)) entries = data.entries;
            const tracks = [];
            for (let i = 0; i < entries.length; i++) {
                const e = entries[i];
                if (!e || typeof e !== "object") continue;
                let vid = e.id || "";
                if ((!vid || !root.isPlayableId(vid)) && e.url) {
                    const m = String(e.url).match(/[?&]v=([A-Za-z0-9_-]{11})/);
                    if (m) vid = m[1];
                    if (!vid) {
                        const m2 = String(e.url).match(/\/shorts\/([A-Za-z0-9_-]{11})/);
                        if (m2) vid = m2[1];
                    }
                }
                vid = String(vid || "");
                if (!root.isPlayableId(vid)) continue;
                let artist = "";
                if (Array.isArray(e.creators) && e.creators.length > 0) artist = e.creators.filter(Boolean).join(", ");
                if (!artist) artist = e.artist || e.uploader || e.channel || "";
                let dur = 0;
                if (e.duration !== undefined && e.duration !== null) dur = Number(e.duration) || 0;
                tracks.push({
                    id: vid,
                    title: e.title || "Track",
                    artist: artist,
                    album: e.album || "",
                    thumbnail_url: root._pickYtThumb(e.thumbnails) || ("https://i.ytimg.com/vi/" + vid + "/mqdefault.jpg"),
                    duration_secs: dur
                });
            }
            return tracks;
        } catch (e) {
            return [];
        }
    }

    function performSearch(query) {
        const q = String(query || "").trim();
        if (!q) return;
        if (searchProc.running) return;
        root.searchBusy = true;
        root.searchQuery = q;
        root.errorText = "";
        root.statusText = "Searching…";
        const args = [root.ytDlpBin, "--flat-playlist", "-J", "--no-warnings"];
        if (root.cookiesReady) args.push("--cookies", root.cookiesPath);
        args.push("ytsearch20:" + q);
        searchProc.command = args;
        searchProc.running = true;
    }

    Process {
        id: libraryProc
        stdout: StdioCollector {
            id: libraryOut
            waitForEnd: true
            onStreamFinished: {
                try {
                    const txt = (libraryOut.text || "").trim();
                    if (!txt) {
                        libraryProc._parsedItems = [];
                        return;
                    }
                    const arr = JSON.parse(txt);
                    if (!Array.isArray(arr)) { libraryProc._parsedItems = []; return; }
                    const items = [];
                    for (let i = 0; i < arr.length; i++) {
                        const e = arr[i];
                        if (!e || typeof e !== "object") continue;
                        const id = String(e.id || "").trim();
                        if (!id) continue;
                        items.push({
                            title: String(e.title || id),
                            id: id,
                            count: String(e.count || "")
                        });
                    }
                    libraryProc._parsedItems = items;
                } catch (e) {
                    libraryProc._parsedItems = [];
                }
            }
        }
        stderr: StdioCollector { waitForEnd: true }
        property var _parsedItems: []
        onExited: (code, status) => {
            root.libraryBusy = false;
            const items = Array.isArray(libraryProc._parsedItems) ? libraryProc._parsedItems : [];
            libraryProc._parsedItems = [];
            if (items.length > 0) {
                root.libraryPlaylists = items;
                root.errorText = "";
                root.statusText = "";
            } else {
                if (root.libraryPlaylists.length > 0) {
                    root.statusText = "Couldn't refresh library";
                } else {
                    root.libraryPlaylists = [];
                    root.statusText = "No playlists found — sign in to YouTube Music in your browser (Zen/Firefox)";
                }
            }
        }
    }

    Process {
        id: searchProc
        stdout: StdioCollector {
            id: searchOut
            waitForEnd: true
            onStreamFinished: {
                const tracks = root._tracksFromYtDlpJson(searchOut.text || "");
                root.searchResults = tracks;
                root.statusText = tracks.length > 0 ? ("Found " + tracks.length + " results") : "No results";
            }
        }
        stderr: StdioCollector { id: searchErr; waitForEnd: true }
        onExited: (code, status) => {
            root.searchBusy = false;
            if (code !== 0) {
                let msg = (searchErr.text || "").trim();
                const lines = msg.split("\n").filter(l => l && l.indexOf("WARNING:") !== 0);
                msg = (lines.length > 0 ? lines[lines.length - 1] : msg.split("\n")[0]) || "";
                root.errorText = msg ? ("Search failed: " + msg) : "Search failed";
                root.statusText = "";
                root.searchResults = [];
                root.actionFinished("search", false, root.errorText);
            } else {
                root.actionFinished("search", true, root.searchResults.length + " results");
            }
        }
    }

    function openInput(text) {
        const raw = String(text || "").trim();
        if (!raw) return;

        let videoId = "";
        let listId = "";
        let browseId = "";

        try {
            // URL parsing
            let s = raw;
            if (s.indexOf("v=") >= 0) {
                const m = s.match(/[?&]v=([A-Za-z0-9_-]{11})/);
                if (m) videoId = m[1];
            }
            if (!videoId) {
                const m = s.match(/youtu\.be\/([A-Za-z0-9_-]{11})/);
                if (m) videoId = m[1];
            }
            if (!videoId) {
                const m = s.match(/\/shorts\/([A-Za-z0-9_-]{11})/);
                if (m) videoId = m[1];
            }
            const lm = s.match(/[?&]list=([A-Za-z0-9_-]+)/);
            if (lm) listId = lm[1];
            const bm = s.match(/\/browse\/([A-Za-z0-9_-]+)/);
            if (bm) browseId = bm[1];
        } catch (e) {}

        // raw IDs
        if (!videoId && !listId && !browseId && raw.indexOf(" ") < 0) {
            if (/^[A-Za-z0-9_-]{11}$/.test(raw)) {
                videoId = raw;
            } else if (/^(PL|OLAK5uy_|VL|MPREb|RDCLAK|RDTMAK|RDAMVM|RDMM|LM|UU|LL)[A-Za-z0-9_-]+$/.test(raw)) {
                if (raw.indexOf("MPREb") === 0) browseId = raw;
                else listId = raw;
            } else if (/^(FEmusic_|VLOLAK)[A-Za-z0-9_-]+$/.test(raw)) {
                browseId = raw;
            }
        }

        if (listId) {
            root.playCollection({ id: listId, title: "Playlist" });
            return;
        }
        if (browseId) {
            root.playCollection({ id: browseId, title: "Collection" });
            return;
        }
        if (videoId) {
            root.playSingleTrack({ id: videoId, title: "YouTube Track" });
            return;
        }

        // Fallback: treat as search query
        root.performSearch(raw);
    }

    function ensureRadioAfterCurrent() {
        if (!root.autoplayEnabled) return;
        if (root.radioBusy || radioFetchProc.running) return;
        let seed = root.currentTrack;
        if (!seed && root.queueIndex >= 0 && root.queueIndex < root.queue.length) seed = root.queue[root.queueIndex];
        const id = root.trackId(seed);
        if (!root.isPlayableId(id)) return;
        // Avoid refetching for same seed repeatedly in tight loops
        if (root.radioForId === id && root.queue.length > root.queueIndex + 1) return;
        root.radioBusy = true;
        root.radioForId = id;
        root.statusText = "Loading recommendations…";
        radioFetchProc.seedId = id;
        const url = "https://www.youtube.com/watch?v=" + id + "&list=RD" + id;
        const rcmd = [root.ytDlpBin, "--flat-playlist", "-J", "--no-warnings"];
        if (root.cookiesReady) rcmd.push("--cookies", root.cookiesPath);
        rcmd.push(url);
        radioFetchProc.command = rcmd;
        radioFetchProc.running = true;
    }

    Process {
        id: radioFetchProc
        property string seedId: ""
        stdout: StdioCollector {
            id: radioOut
            waitForEnd: true
            onStreamFinished: {
                const tracks = root._tracksFromYtDlpJson(radioOut.text || "");
                if (!tracks || tracks.length === 0) return;
                const toAdd = [];
                const seen = {};
                // mark existing
                for (let i = 0; i < root.queue.length; i++) {
                    const tid = root.trackId(root.queue[i]);
                    if (tid) seen[tid] = true;
                }
                for (let i = 0; i < tracks.length; i++) {
                    const t = tracks[i];
                    const tid = root.trackId(t);
                    if (!root.isPlayableId(tid)) continue;
                    if (tid === radioFetchProc.seedId && toAdd.length === 0) continue; // skip seed at start
                    if (seen[tid]) continue;
                    seen[tid] = true;
                    toAdd.push(t);
                    if (toAdd.length >= 25) break;
                }
                radioFetchProc._toAdd = toAdd;
            }
        }
        stderr: StdioCollector { id: radioErr; waitForEnd: true }
        property var _toAdd: []
        onExited: (code, status) => {
            const added = Array.isArray(radioFetchProc._toAdd) ? radioFetchProc._toAdd : [];
            radioFetchProc._toAdd = [];
            root.radioBusy = false;
            if (added.length > 0) {
                let q = root.queue.slice();
                // if queue is empty, seed with current? shouldn't happen here
                q = q.concat(added);
                root.queue = q;
                if ((root.statusText || "").indexOf("Loading recommendations") === 0) {
                    root.statusText = root.paused ? "Paused" : "Playing";
                }
                root.actionFinished("radio", true, "Added " + added.length + " tracks");
            } else {
                if ((root.statusText || "").indexOf("Loading recommendations") === 0) {
                    root.statusText = root.queueIndex < root.queue.length - 1 ? "Ready" : "End of queue";
                }
            }
        }
    }

    function playTrackObject(track, index, autoplayQueue) {
        if (!track) return;
        const id = root.trackId(track);
        if (!id) {
            root.statusText = "Track has no id";
            root.actionFinished("play", false, "no track id");
            return;
        }
        if (autoplayQueue && Array.isArray(autoplayQueue)) root.queue = autoplayQueue;
        if (index !== undefined && index !== null && index >= 0) root.queueIndex = index;
        root.pendingPlayIndex = (index !== undefined && index !== null) ? index : -1;
        root.pendingPlayId = id;
        root.currentTrack = track;
        root.positionSecs = 0;
        root.durationSecs = 0;
        root.paused = false;
        root.errorText = "";
        root.statusText = "Starting playback…";
        root.likeState = "none";
        root.resolvingUrl = false;
        root.userStopRequested = false;
        root.ownMprisSeen = false;

        // Bump generation so exits from previous mpv runs are ignored.
        const nextGen = (root._activeMpvGeneration || 0) + 1;
        root._activeMpvGeneration = nextGen;
        ownMpvProc.playGeneration = nextGen;
        root.ownPlayStartedAtMs = Date.now();

        const watchUrl = "https://music.youtube.com/watch?v=" + id;
        const vol = Math.max(0, Math.min(150, (root.volume > 0 ? root.volume : 100)));
        const ytdlRaw = ["retries=10", "fragment_retries=10", "socket_timeout=15", "extractor_retries=3"];
        if (root.cookiesReady) ytdlRaw.push("cookies=" + root.cookiesPath);
        const cmd = [
            "bash", "-lc", 'rm -f "$1"; exec "${@:2}"', "qs-ytmusic-mpv",
            root.ownSocketPath,
            root.mpvBin, "--no-video", "--no-terminal", "--force-window=no",
            "--idle=no", "--keep-open=no",
            "--input-ipc-server=" + root.ownSocketPath,
            "--term-playing-msg=",
            "--audio-client-name=qs-ytmusic",
            "--volume=" + vol,
            "--network-timeout=15",
            "--cache=yes",
            "--demuxer-max-bytes=150MiB",
            "--demuxer-readahead-secs=30",
            "--stream-lavf-o=reconnect=1,reconnect_streamed=1,reconnect_delay_max=5",
            "--ytdl-format=bestaudio/best",
            "--script-opts=ytdl_hook-ytdl_path=" + root.ytDlpBin,
            "--ytdl-raw-options=" + ytdlRaw.join(",")
        ];
        cmd.push(watchUrl);

        if (ownMpvProc.running) {
            // Stop current player and start next once it exits (avoid races/double-starts).
            root.pendingMpvCommand = cmd;
            root.switchStopRequested = true;
            ownMpvProc.running = false;
        } else {
            root.pendingMpvCommand = null;
            root.switchStopRequested = false;
            ownMpvProc.command = cmd;
            ownMpvProc.running = true;
        }
        root.usingOwnPlayer = true;
        ownStatusTimer.restart();
        if (root.autoplayEnabled) {
            const remaining = root.queue.length - (root.queueIndex + 1);
            if (remaining <= 1) Qt.callLater(function() { root.ensureRadioAfterCurrent(); });
        }
    }

    function playTrackAt(index) {
        if (index < 0 || index >= root.queue.length) return;
        root.playTrackObject(root.queue[index], index, root.queue);
    }

    function playSingleTrack(track) {
        if (!track) return;
        root.queue = [track];
        root.queueIndex = 0;
        root.playTrackObject(track, 0, [track]);
        if (root.autoplayEnabled) {
            Qt.callLater(function() { root.ensureRadioAfterCurrent(); });
        }
    }

    function playNextOwn() {
        if (root.queue.length === 0) return;
        let next = root.queueIndex + 1;
        if (next >= root.queue.length) {
            if (root.repeatMode === "all") next = 0;
            else return;
        }
        root.playTrackAt(next);
    }

    function playPrevOwn() {
        if (root.queue.length === 0) return;
        if (root.positionSecs > 3) {
            root.sendMpvCommand(["seek", 0, "absolute"]);
            Quickshell.execDetached([root.playerctlBin, "--player=mpv", "position", "0"]);
            root.positionSecs = 0;
            return;
        }
        let prev = root.queueIndex - 1;
        if (prev < 0) prev = 0;
        root.playTrackAt(prev);
    }

    function transport(cmd) {
        const c = (cmd || "").toLowerCase();
        const ownActive = root.usingOwnPlayer || ownMpvProc.running;

        if (ownActive) {
            if (c === "play-pause") {
                const wantPause = !root.paused;
                root.sendMpvCommand(["set_property", "pause", wantPause]);
                Quickshell.execDetached([root.playerctlBin, "--player=mpv", "play-pause"]);
                root.paused = wantPause;
                root.statusText = wantPause ? "Paused" : "Playing";
                return;
            }
            if (c === "next") { root.playNextOwn(); return; }
            if (c === "previous" || c === "prev") { root.playPrevOwn(); return; }
            if (c === "stop") { root.stopOwnPlayer(); return; }
            return;
        }

        if (!root.daemonRunning) {
            if (c === "play-pause" && root.queue.length > 0) {
                const idx = root.queueIndex >= 0 ? root.queueIndex : 0;
                root.playTrackAt(idx);
            } else if (c === "next") {
                root.playNextOwn();
            } else if (c === "previous" || c === "prev") {
                root.playPrevOwn();
            } else if (c === "stop") {
                root.stopOwnPlayer();
            }
            return;
        }

        // ytmtui daemon owns playback: target mpv only (avoid browser players).
        if (c === "play-pause") Quickshell.execDetached([root.playerctlBin, "--player=mpv", "play-pause"]);
        else if (c === "next") Quickshell.execDetached([root.playerctlBin, "--player=mpv", "next"]);
        else if (c === "previous" || c === "prev") Quickshell.execDetached([root.playerctlBin, "--player=mpv", "previous"]);
        else if (c === "stop") Quickshell.execDetached([root.playerctlBin, "--player=mpv", "stop"]);
    }

    function jump(index) {
        if (index < 0) return;
        if (root.daemonRunning) {
            runSimple([root.ytmtuiBin, "jump", String(index)], "jump");
        } else {
            root.playTrackAt(index);
        }
    }

    function openPlayer() {
        Quickshell.execDetached(["sh", "-c",
            "xdg-terminal-exec ytmtui 2>/dev/null || " +
            "kitty -e ytmtui 2>/dev/null || " +
            "foot -e ytmtui 2>/dev/null || " +
            "alacritty -e ytmtui 2>/dev/null || " +
            "wezterm start -- ytmtui 2>/dev/null || " +
            "ghostty -e ytmtui 2>/dev/null || " +
            "xterm -e ytmtui 2>/dev/null &"]);
    }

    function runSimple(cmd, actionName) {
        if (actionProc.running) {
            root.actionFinished(actionName, false, "busy");
            return;
        }
        root.busy = true;
        actionProc.actionName = actionName;
        actionProc.command = cmd;
        actionProc.running = true;
    }

    function applyNowData(data) {
        if (!data || typeof data !== "object") return;
        root.daemonRunning = true;
        root.errorText = "";
        const cur = data.current || data.track || data.now || (data.title ? data : null);
        if (cur && typeof cur === "object") root.currentTrack = cur;
        else if (data.title) root.currentTrack = data;

        if (data.queue && Array.isArray(data.queue)) root.queue = data.queue;
        if (data.queue_index !== undefined) root.queueIndex = Number(data.queue_index);
        else if (data.queueIndex !== undefined) root.queueIndex = Number(data.queueIndex);
        else if (data.index !== undefined) root.queueIndex = Number(data.index);

        if (data.position_secs !== undefined) root.positionSecs = Number(data.position_secs) || 0;
        else if (data.position !== undefined) root.positionSecs = Number(data.position) || 0;
        else if (data.elapsed !== undefined) root.positionSecs = Number(data.elapsed) || 0;

        if (data.paused !== undefined) root.paused = !!data.paused;
        if (data.volume !== undefined) root.volume = Number(data.volume) || 0;
        if (data.repeat !== undefined) root.repeatMode = String(data.repeat);
        if (data.shuffle !== undefined) root.shuffle = !!data.shuffle;
    }

    function applyQueueData(data) {
        if (Array.isArray(data)) {
            root.queue = data;
            root.daemonRunning = true;
            return;
        }
        if (data && typeof data === "object") {
            root.daemonRunning = true;
            if (Array.isArray(data.queue)) root.queue = data.queue;
            if (Array.isArray(data.items)) root.queue = data.items;
            if (data.queue_index !== undefined) root.queueIndex = Number(data.queue_index);
            if (data.queueIndex !== undefined) root.queueIndex = Number(data.queueIndex);
            if (data.current) root.currentTrack = data.current;
            if (data.position_secs !== undefined) root.positionSecs = Number(data.position_secs) || 0;
            if (data.paused !== undefined) root.paused = !!data.paused;
            if (data.volume !== undefined) root.volume = Number(data.volume) || 0;
            if (data.repeat !== undefined) root.repeatMode = String(data.repeat);
            if (data.shuffle !== undefined) root.shuffle = !!data.shuffle;
        }
    }

    function applySessionFallback() {
        try {
            const txt = sessionFile.text();
            if (!txt || txt.length < 2) return;
            const s = JSON.parse(txt);
            if (!s || typeof s !== "object") return;
            // Don't overwrite state while our own player is active or resolving.
            if (!root.daemonRunning && !root.usingOwnPlayer && !root.resolvingUrl) {
                if (Array.isArray(s.queue)) root.queue = s.queue;
                if (s.queue_index !== undefined) root.queueIndex = Number(s.queue_index);
                if (s.current) root.currentTrack = s.current;
                root.positionSecs = 0;
                root.paused = true;
                if (s.volume !== undefined) root.volume = Number(s.volume) || 0;
                if (s.repeat !== undefined) root.repeatMode = String(s.repeat);
                if (s.shuffle !== undefined) root.shuffle = !!s.shuffle;
                if (root.errorText === "" && (root.statusText === "" || root.statusText === "Playing")) root.statusText = "";
            }
        } catch (e) {}
    }

    function applyBrowse() {
        try {
            const txt = browseFile.text();
            if (!txt || txt.length < 2) return;
            const b = JSON.parse(txt);
            if (!Array.isArray(b)) return;
            const out = [];
            const maxShelves = 12;
            const maxItems = 20;
            for (let i = 0; i < b.length && out.length < maxShelves; i++) {
                const s = b[i];
                if (!s || typeof s !== "object") continue;
                const items = Array.isArray(s.items) ? s.items : [];
                const cleanItems = [];
                for (let j = 0; j < items.length && cleanItems.length < maxItems; j++) {
                    const it = items[j];
                    if (it && typeof it === "object") cleanItems.push(it);
                }
                if (cleanItems.length === 0 && !s.title) continue;
                out.push({
                    title: s.title || ("Shelf " + (i + 1)),
                    items: cleanItems
                });
            }
            root.browseShelves = out;
        } catch (e) {}
    }

    function setVolume(percent) {
        let p = Math.round(Number(percent));
        if (isNaN(p)) return;
        p = Math.max(0, Math.min(150, p));
        root.volume = p;
        if (root.usingOwnPlayer || ownMpvProc.running) {
            root.sendMpvCommand(["set_property", "volume", p]);
            Quickshell.execDetached([root.playerctlBin, "--player=mpv", "volume", String(p / 100.0)]);
        }
    }

    function seekTo(secs) {
        let v = Number(secs);
        if (isNaN(v) || v < 0) return;
        root.positionSecs = v;
        if (root.usingOwnPlayer || ownMpvProc.running) {
            root.sendMpvCommand(["seek", v, "absolute"]);
            Quickshell.execDetached([root.playerctlBin, "--player=mpv", "position", String(v)]);
        }
    }

    Timer {
        interval: root.daemonRunning ? 2500 : 8000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    FileView {
        id: sessionFile
        path: root.sessionPath
        watchChanges: true
        onLoaded: root.applySessionFallback()
        onFileChanged: reload()
    }

    FileView {
        id: browseFile
        path: root.browsePath
        watchChanges: true
        onLoaded: root.applyBrowse()
        onFileChanged: reload()
    }

    FileView {
        id: authFile
        path: root.authPath
        watchChanges: true
        onLoaded: {
            try {
                const t = authFile.text();
                root.authenticated = !!(t && t.length > 10);
            } catch (e) { root.authenticated = false; }
        }
        onFileChanged: reload()
    }

    Process {
        id: nowProc
        command: [root.ytmtuiBin, "--json", "now"]
        stdout: StdioCollector {
            id: nowOut
            waitForEnd: true
            onStreamFinished: {
                try {
                    const t = (nowOut.text || "").trim();
                    if (t.startsWith("{") || t.startsWith("[")) {
                        root.applyNowData(JSON.parse(t));
                        root.daemonRunning = true;
                        root.pollQueue();
                    } else {
                        root.daemonRunning = false;
                        root.applySessionFallback();
                    }
                } catch (e) {
                    root.daemonRunning = false;
                    root.applySessionFallback();
                }
            }
        }
        stderr: StdioCollector {
            id: nowErr
            waitForEnd: true
            onStreamFinished: {
                const t = (nowErr.text || "").trim();
                if (t.indexOf("not running") !== -1) root.daemonRunning = false;
                if (!root.daemonRunning) root.applySessionFallback();
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.daemonRunning = false;
                root.applySessionFallback();
            }
        }
    }

    Process {
        id: queueProc
        command: [root.ytmtuiBin, "--json", "queue"]
        stdout: StdioCollector {
            id: queueOut
            waitForEnd: true
            onStreamFinished: {
                try {
                    const t = (queueOut.text || "").trim();
                    if (t.startsWith("{") || t.startsWith("[")) {
                        root.applyQueueData(JSON.parse(t));
                    }
                } catch (e) {}
            }
        }
        stderr: StdioCollector { waitForEnd: true }
    }

    Process {
        id: actionProc
        property string actionName: ""
        stdout: StdioCollector { id: actionOut; waitForEnd: true }
        stderr: StdioCollector { id: actionErr; waitForEnd: true }
        onExited: (code, status) => {
            root.busy = false;
            const msg = ((actionOut.text || "") + "\n" + (actionErr.text || "")).trim();
            root.actionFinished(actionProc.actionName, code === 0, msg);
            if (code === 0) root.refresh();
        }
    }

    // --- Independent playback (mpv, with yt-dlp hook) ---
    Process {
        id: ownMpvProc
        property int playGeneration: 0
        stdout: StdioCollector { id: ownMpvOut; waitForEnd: true }
        stderr: StdioCollector { id: ownMpvErr; waitForEnd: true }
        onStarted: {
            if (ownMpvProc.playGeneration === root._activeMpvGeneration) {
                root.statusText = "Starting playback…";
            }
        }
        onExited: (code, status) => {
            if (root.pendingMpvCommand && root.pendingMpvCommand.length > 0 && ownMpvProc.playGeneration === root._activeMpvGeneration) {
                const cmd = root.pendingMpvCommand;
                root.pendingMpvCommand = null;
                root.switchStopRequested = false;
                root.userStopRequested = false;
                ownMpvProc.command = cmd;
                ownMpvProc.running = true;
                root.usingOwnPlayer = true;
                root.statusText = "Starting playback…";
                ownStatusTimer.restart();
                return;
            }

            if (ownMpvProc.playGeneration !== root._activeMpvGeneration) {
                return;
            }

            const stoppedByUser = root.userStopRequested;
            const stoppedForSwitch = root.switchStopRequested;
            root.userStopRequested = false;
            root.switchStopRequested = false;
            root.usingOwnPlayer = false;
            root.paused = true;
            if (stoppedByUser) {
                root.statusText = "Stopped";
                return;
            }
            if (stoppedForSwitch) {
                return;
            }

            const canAdvance = root.queue.length > 0 && root.queueIndex >= 0 &&
                (root.queueIndex < root.queue.length - 1 || root.repeatMode === "all");
            const trackDur = root.durationSecs > 0 ? root.durationSecs : 0;
            const elapsedMs = Date.now() - (root.ownPlayStartedAtMs || 0);
            const playedMeaningfully = root.positionSecs >= 6 || elapsedMs >= 12000;
            const nearEnd = trackDur > 0 ? (root.positionSecs >= trackDur - 4) : playedMeaningfully;

            if (code === 0) {
                if (canAdvance && (nearEnd || playedMeaningfully)) {
                    Qt.callLater(function() { root.playNextOwn(); });
                    return;
                }
                if (!playedMeaningfully) {
                    const errLine = (ownMpvErr.text || "").trim().split("\n").filter(l => l.length > 0).slice(-1)[0] || "";
                    const err = errLine.length > 0 ? ("Playback ended early: " + errLine) : "Playback ended early (stream/yt-dlp issue?)";
                    root.errorText = err;
                    root.statusText = err;
                    root.actionFinished("play", false, err);
                    return;
                }
                if (root.autoplayEnabled && (nearEnd || playedMeaningfully)) {
                    root.usingOwnPlayer = true; // keep UI in playing context while fetching
                    root.statusText = "Loading recommendations…";
                    Qt.callLater(function() {
                        root.ensureRadioAfterCurrent();
                        // poll briefly for appended tracks then advance
                        radioAdvanceTimer.restart();
                    });
                    return;
                }
                root.statusText = "Stopped";
                return;
            }

            const errLine = (ownMpvErr.text || "").trim().split("\n").filter(l => l.length > 0).slice(-1)[0] || "";
            const err = errLine.length > 0 ? errLine : ("mpv exited (" + code + ")");
            root.errorText = err;
            root.statusText = "Playback error: " + err;
            root.actionFinished("play", false, err);
        }
    }

    Timer {
        id: ownStatusTimer
        interval: 1000
        repeat: true
        running: root.usingOwnPlayer
        onTriggered: {
            if (!root.usingOwnPlayer) return;
            const elapsed = Date.now() - (root.ownPlayStartedAtMs || 0);
            if (root.statusText === "Starting playback…" && root.ownMprisSeen) {
                root.statusText = root.paused ? "Paused" : "Playing";
            } else if (root.statusText === "Starting playback…" && elapsed > 12000 && root.positionSecs <= 0 && root.durationSecs <= 0) {
                root.statusText = "Starting playback… (no player response yet)";
            }
            if (!mpvIpcPollProc.running) mpvIpcPollProc.running = true;
        }
    }

    Process {
        id: mpvIpcPollProc
        command: ["python3", "-c",
            "import json,socket,sys\n" +
            "p=sys.argv[1]\n" +
            "def req(s,c):\n" +
            " s.sendall((json.dumps({'command':c})+'\\n').encode())\n" +
            " d=b''\n" +
            " while b'\\n' not in d:\n" +
            "  ch=s.recv(4096)\n" +
            "  if not ch: break\n" +
            "  d+=ch\n" +
            " try: return json.loads(d.split(b'\\n',1)[0].decode('utf-8','ignore'))\n" +
            " except Exception: return {}\n" +
            "try:\n" +
            " s=socket.socket(socket.AF_UNIX); s.settimeout(0.25); s.connect(p)\n" +
            " out=[]\n" +
            " for prop in ('time-pos','duration','pause','volume'):\n" +
            "  r=req(s,['get_property',prop]); out.append(r.get('data'))\n" +
            " print(json.dumps(out))\n" +
            "except Exception:\n" +
            " pass\n" +
            "finally:\n" +
            " try: s.close()\n" +
            " except Exception: pass\n",
            root.ownSocketPath
        ]
        stdout: StdioCollector {
            id: mpvIpcOut
            waitForEnd: true
            onStreamFinished: {
                try {
                    const t = (mpvIpcOut.text || "").trim();
                    if (!t || t[0] !== "[") return;
                    const arr = JSON.parse(t);
                    if (!Array.isArray(arr) || arr.length < 4) return;
                    const pos = Number(arr[0]);
                    const dur = Number(arr[1]);
                    const paused = arr[2];
                    const vol = Number(arr[3]);
                    if (!isNaN(pos) && pos >= 0) root.positionSecs = pos;
                    if (!isNaN(dur) && dur > 0) root.durationSecs = dur;
                    if (paused === true || paused === false) root.paused = paused;
                    if (!isNaN(vol) && vol >= 0) root.volume = Math.round(vol);
                    root.ownMprisSeen = true;
                    if (root.statusText === "Starting playback…" || root.statusText === "Starting playback… (no player response yet)") {
                        root.statusText = root.paused ? "Paused" : "Playing";
                    }
                } catch (e) {}
            }
        }
        stderr: StdioCollector { waitForEnd: true }
    }

    Timer {
        id: radioAdvanceTimer
        interval: 1500
        repeat: true
        running: false
        property int tries: 0
        onTriggered: {
            tries += 1;
            const canAdvance = root.queue.length > 0 && root.queueIndex >= 0 && root.queueIndex < root.queue.length - 1;
            if (canAdvance) {
                running = false; tries = 0;
                root.playNextOwn();
                return;
            }
            if (!root.radioBusy && !radioFetchProc.running) {
                // one more wait or give up
                if (tries >= 4) { running = false; tries = 0; root.usingOwnPlayer = false; root.statusText = "End of queue"; }
                return;
            }
            if (tries >= 12) { running = false; tries = 0; root.usingOwnPlayer = false; root.statusText = "End of queue"; }
        }
        onRunningChanged: { if (running) tries = 0; }
    }

    Process {
        id: mpvVolProc
        command: [root.playerctlBin, "--player=mpv", "volume"]
        stdout: StdioCollector {
            id: mpvVolOut; waitForEnd: true
            onStreamFinished: {
                const t = (mpvVolOut.text || "").trim();
                const v = parseFloat(t);
                if (!isNaN(v) && v >= 0) {
                    root.volume = Math.round(v * 100);
                    root.ownMprisSeen = true;
                }
            }
        }
        stderr: StdioCollector { waitForEnd: true }
    }

    Process {
        id: mpvPosProc
        command: [root.playerctlBin, "--player=mpv", "position"]
        stdout: StdioCollector {
            id: mpvPosOut; waitForEnd: true
            onStreamFinished: {
                const t = (mpvPosOut.text || "").trim();
                const v = parseFloat(t);
                if (!isNaN(v) && v >= 0) {
                    root.positionSecs = v;
                    root.ownMprisSeen = true;
                }
            }
        }
        stderr: StdioCollector { waitForEnd: true }
    }

    Process {
        id: mpvStateProc
        command: [root.playerctlBin, "--player=mpv", "status"]
        stdout: StdioCollector {
            id: mpvStateOut; waitForEnd: true
            onStreamFinished: {
                const s = (mpvStateOut.text || "").trim();
                if (s === "Playing") {
                    root.paused = false;
                    root.ownMprisSeen = true;
                } else if (s === "Paused") {
                    root.paused = true;
                    root.ownMprisSeen = true;
                }
            }
        }
        stderr: StdioCollector { waitForEnd: true }
    }

    Process {
        id: mpvLenProc
        command: [root.playerctlBin, "--player=mpv", "metadata", "mpris:length"]
        stdout: StdioCollector {
            id: mpvLenOut; waitForEnd: true
            onStreamFinished: {
                const t = (mpvLenOut.text || "").trim();
                const v = parseFloat(t);
                if (!isNaN(v) && v > 0) {
                    root.durationSecs = v / 1000000.0;
                    root.ownMprisSeen = true;
                }
            }
        }
        stderr: StdioCollector { waitForEnd: true }
    }

    // --- Like / add-to-playlist actions (browser cookies via helper) ---
    property string _likePendingState: "none"

    function currentPlayableVideoId() {
        const t = root.currentTrack ? root.currentTrack : ((root.queueIndex >= 0 && root.queueIndex < root.queue.length) ? root.queue[root.queueIndex] : null);
        const id = root.trackId(t);
        return root.isPlayableId(id) ? id : "";
    }

    function toggleLike() {
        const vid = root.currentPlayableVideoId();
        if (!vid) { root.actionFinished("like", false, "No track playing"); return; }
        if (root.likeActionBusy || likeActionProc.running) return;
        const desired = (root.likeState === "liked") ? "removelike" : "like";
        root._likePendingState = (desired === "like") ? "liked" : "none";
        root.likeActionBusy = true;
        root.statusText = desired === "like" ? "Liking…" : "Removing like…";
        likeActionProc.actionName = (desired === "like") ? "like" : "removelike";
        likeActionProc.command = ["python3", root.authHelperPath, desired, vid];
        likeActionProc.running = true;
    }

    function toggleDislike() {
        const vid = root.currentPlayableVideoId();
        if (!vid) { root.actionFinished("dislike", false, "No track playing"); return; }
        if (root.likeActionBusy || likeActionProc.running) return;
        const desired = (root.likeState === "disliked") ? "removelike" : "dislike";
        root._likePendingState = (desired === "dislike") ? "disliked" : "none";
        root.likeActionBusy = true;
        root.statusText = desired === "dislike" ? "Disliking…" : "Removing dislike…";
        likeActionProc.actionName = (desired === "dislike") ? "dislike" : "removelike";
        likeActionProc.command = ["python3", root.authHelperPath, desired, vid];
        likeActionProc.running = true;
    }

    function fetchAddablePlaylists() {
        const vid = root.currentPlayableVideoId();
        if (!vid) { root.actionFinished("playlists", false, "No track playing"); return; }
        if (addablePlaylistsProc.running) return;
        root.addablePlaylistsBusy = true;
        root.addablePlaylistsForId = vid;
        root.addablePlaylists = [];
        addablePlaylistsProc.command = ["python3", root.authHelperPath, "addable_playlists", vid];
        addablePlaylistsProc.running = true;
    }

    function addCurrentTrackToPlaylist(playlistId, playlistTitle) {
        const vid = root.currentPlayableVideoId();
        if (!vid) { root.actionFinished("add-to-playlist", false, "No track playing"); return; }
        playlistId = String(playlistId || "").trim();
        if (!playlistId) { root.actionFinished("add-to-playlist", false, "No playlist id"); return; }
        if (addToPlaylistProc.running) return;
        root.addToPlaylistBusy = true;
        root.statusText = "Adding to " + (playlistTitle || "playlist") + "…";
        addToPlaylistProc.targetTitle = playlistTitle || playlistId;
        addToPlaylistProc.targetPlaylistId = playlistId;
        addToPlaylistProc.targetVideoId = vid;
        addToPlaylistProc.command = ["python3", root.authHelperPath, "add_to_playlist", playlistId, vid];
        addToPlaylistProc.running = true;
    }

    Process {
        id: likeActionProc
        property string actionName: ""
        stdout: StdioCollector { id: likeActionOut; waitForEnd: true }
        stderr: StdioCollector { id: likeActionErr; waitForEnd: true }
        onExited: (code, status) => {
            root.likeActionBusy = false;
            let ok = false;
            let msg = "";
            try {
                const txt = (likeActionOut.text || "").trim();
                if (txt.startsWith("{")) {
                    const obj = JSON.parse(txt);
                    ok = !!obj.ok && code === 0;
                    msg = obj.error || "";
                } else {
                    ok = code === 0;
                }
            } catch (e) {
                ok = code === 0;
            }
            if (!ok && !msg) msg = (likeActionErr.text || "").trim().split("\n")[0] || "Failed";
            if (ok) {
                root.likeState = root._likePendingState;
                root.statusText = root.likeState === "liked" ? "Liked" : (root.likeState === "disliked" ? "Disliked" : "Like removed");
                root.errorText = "";
            } else {
                root.errorText = msg;
            }
            root.actionFinished(likeActionProc.actionName, ok, ok ? "" : msg);
        }
    }

    Process {
        id: addablePlaylistsProc
        stdout: StdioCollector {
            id: addablePlaylistsOut
            waitForEnd: true
            onStreamFinished: {
                try {
                    const txt = (addablePlaylistsOut.text || "").trim();
                    if (!txt || txt[0] !== "[") { addablePlaylistsProc._parsed = []; return; }
                    const arr = JSON.parse(txt);
                    if (!Array.isArray(arr)) { addablePlaylistsProc._parsed = []; return; }
                    const out = [];
                    for (let i = 0; i < arr.length; i++) {
                        const e = arr[i];
                        if (!e || typeof e !== "object") continue;
                        const id = String(e.id || "").trim();
                        const title = String(e.title || "").trim();
                        if (!id || !title) continue;
                        // WL shown by YouTube as Watch later, LM handled separately via like; keep all editable playlists
                        out.push({ id: id, title: title, contains: String(e.contains || "NONE") });
                    }
                    addablePlaylistsProc._parsed = out;
                } catch (e) {
                    addablePlaylistsProc._parsed = [];
                }
            }
        }
        stderr: StdioCollector { waitForEnd: true }
        property var _parsed: []
        onExited: (code, status) => {
            root.addablePlaylistsBusy = false;
            const out = Array.isArray(addablePlaylistsProc._parsed) ? addablePlaylistsProc._parsed : [];
            addablePlaylistsProc._parsed = [];
            root.addablePlaylists = out;
            if (out.length === 0) {
                root.actionFinished("playlists", false, "No playlists found (are you signed in in browser?)");
            }
        }
    }

    Process {
        id: addToPlaylistProc
        property string targetTitle: ""
        property string targetPlaylistId: ""
        property string targetVideoId: ""
        stdout: StdioCollector { id: addToPlaylistOut; waitForEnd: true }
        stderr: StdioCollector { id: addToPlaylistErr; waitForEnd: true }
        onExited: (code, status) => {
            root.addToPlaylistBusy = false;
            let ok = false;
            let msg = "";
            try {
                const txt = (addToPlaylistOut.text || "").trim();
                if (txt.startsWith("{")) {
                    const obj = JSON.parse(txt);
                    ok = !!obj.ok && code === 0;
                    msg = obj.error || "";
                } else {
                    ok = code === 0;
                }
            } catch (e) {
                ok = code === 0;
            }
            if (!ok && !msg) msg = (addToPlaylistErr.text || "").trim().split("\n")[0] || "Failed";
            if (ok) {
                root.errorText = "";
                root.statusText = "Added to " + addToPlaylistProc.targetTitle;
                // optimistic update for picker state
                if (root.addablePlaylistsForId === addToPlaylistProc.targetVideoId && Array.isArray(root.addablePlaylists)) {
                    const copy = root.addablePlaylists.slice();
                    for (let i = 0; i < copy.length; i++) {
                        if (copy[i] && copy[i].id === addToPlaylistProc.targetPlaylistId) {
                            copy[i] = Object.assign({}, copy[i], { contains: "ALL" });
                        }
                    }
                    root.addablePlaylists = copy;
                }
            } else {
                root.errorText = msg;
                root.statusText = "Couldn't add to playlist";
            }
            root.actionFinished("add-to-playlist", ok, ok ? addToPlaylistProc.targetTitle : msg);
        }
    }
}
