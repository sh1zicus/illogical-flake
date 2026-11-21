#!/usr/bin/env python3
import json, os, sys, sqlite3, shutil, tempfile, time, hashlib, re, glob, subprocess, urllib.request, gzip
from concurrent.futures import ThreadPoolExecutor, as_completed

def find_cookie_db():
    candidates = []
    # Zen (Firefox-based)
    zen_default = os.path.expanduser("~/.config/zen/default/cookies.sqlite")
    if os.path.isfile(zen_default):
        candidates.append(zen_default)
    for p in sorted(glob.glob(os.path.expanduser("~/.config/zen/*/cookies.sqlite"))):
        if p not in candidates:
            candidates.append(p)
    # Firefox / LibreWolf / Floorp
    for base in ["~/.mozilla/firefox", "~/.librewolf", "~/.floorp"]:
        for p in sorted(glob.glob(os.path.expanduser(base + "/*/cookies.sqlite"))):
            candidates.append(p)
    for p in candidates:
        if os.path.isfile(p):
            return p
    return None

def read_moz_cookies(db_path):
    tmp = None
    con = None
    try:
        tmp = os.path.join(tempfile.gettempdir(), "qs-ytmusic-cookies-%d.sqlite" % os.getpid())
        shutil.copy2(db_path, tmp)
        for ext in ("-wal", "-shm"):
            if os.path.exists(db_path + ext):
                try:
                    shutil.copy2(db_path + ext, tmp + ext)
                except Exception:
                    pass
        con = sqlite3.connect(tmp, timeout=2)
        cur = con.cursor()
        cur.execute("SELECT host, name, value, path, expiry, isSecure FROM moz_cookies WHERE host LIKE '%youtube.com' OR host LIKE '%google.com' OR host LIKE 'music.youtube.com' OR host LIKE 'youtube.com'")
        rows = cur.fetchall()
        return rows
    except Exception:
        return []
    finally:
        try:
            if con: con.close()
        except Exception:
            pass
        if tmp:
            for p in (tmp, tmp + "-wal", tmp + "-shm"):
                try:
                    if os.path.exists(p): os.remove(p)
                except Exception:
                    pass

def best_cookies(rows):
    best = {}
    for host, name, value, path, expiry, is_secure in rows:
        key = (host, name, path or "/")
        prev = best.get(key)
        try:
            exp = int(expiry or 0)
        except Exception:
            exp = 0
        if (prev is None) or (exp >= prev[4]):
            best[key] = (host, name, value or "", path or "/", exp, int(is_secure or 0))
    return list(best.values())

def cookie_header_for_domain(cookies, domain_suffixes):
    parts = []
    for host, name, value, path, expiry, is_secure in cookies:
        h = host or ""
        if not any(h == s or h.endswith(s) or h.endswith("." + s.lstrip(".")) for s in domain_suffixes):
            continue
        if expiry and expiry > 0 and expiry < int(time.time()) - 60:
            continue
        if value is None:
            continue
        parts.append("%s=%s" % (name, value))
    return "; ".join(parts)

def get_sapisid(cookies):
    vals = {}
    for host, name, value, path, expiry, is_secure in cookies:
        if host.endswith("youtube.com") or host.endswith("google.com") or host.endswith(".google.com") or host.endswith(".youtube.com"):
            if name in ("__Secure-3PAPISID", "SAPISID", "__Secure-1PAPISID"):
                if expiry and expiry > 0 and expiry < int(time.time()) - 60:
                    continue
                vals.setdefault(name, value)
    return vals.get("__Secure-3PAPISID") or vals.get("SAPISID") or vals.get("__Secure-1PAPISID")

def get_sapisid_all(cookies):
    vals = {}
    for host, name, value, path, expiry, is_secure in cookies:
        if host.endswith("youtube.com") or host.endswith(".youtube.com") or host.endswith("google.com") or host.endswith(".google.com"):
            if name in ("SAPISID", "__Secure-1PAPISID", "__Secure-3PAPISID"):
                if expiry and expiry > 0 and expiry < int(time.time()) - 60:
                    continue
                vals.setdefault(name, value)
    return vals

def has_login_cookie(cookies):
    for host, name, value, path, expiry, is_secure in cookies:
        if name in ("LOGIN_INFO", "SID", "__Secure-1PSID", "__Secure-3PSID", "__Secure-3PAPISID", "SAPISID"):
            if expiry and expiry > 0 and expiry < int(time.time()) - 60:
                continue
            if value:
                return True
    return False

def build_innertube_headers(cookies):
    cookie = cookie_header_for_domain(cookies, ["youtube.com", "google.com", "music.youtube.com"])
    headers = {
        "Content-Type": "application/json",
        "Accept-Encoding": "gzip",
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Origin": "https://music.youtube.com",
        "Referer": "https://music.youtube.com/",
        "X-Origin": "https://music.youtube.com",
        "X-Goog-Api-Format-Version": "1",
        "X-Youtube-Client-Name": "67",
        "X-Youtube-Client-Version": "1.20240101.01.00",
        "X-Goog-AuthUser": "0",
    }
    if cookie:
        headers["Cookie"] = cookie
    sapisid = get_sapisid(cookies)
    origin = "https://music.youtube.com"
    if sapisid:
        ts = str(int(time.time()))
        h = hashlib.sha1((ts + " " + sapisid + " " + origin).encode("utf-8")).hexdigest()
        headers["Authorization"] = "SAPISIDHASH %s_%s" % (ts, h)
    return headers

def build_action_headers(cookies):
    """Headers for authenticated actions (like/dislike/add-to-playlist) via www.youtube.com WEB client."""
    cookie = cookie_header_for_domain(cookies, ["youtube.com"])
    origin = "https://www.youtube.com"
    headers = {
        "Content-Type": "application/json",
        "Accept-Encoding": "gzip",
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Origin": origin,
        "Referer": origin + "/",
        "X-Origin": origin,
        "X-Goog-AuthUser": "0",
        "X-Youtube-Client-Name": "1",
        "X-Youtube-Client-Version": "2.20240101.00.00",
    }
    if cookie:
        headers["Cookie"] = cookie
    vals = get_sapisid_all(cookies)
    ts = str(int(time.time()))
    auth_parts = []
    for scheme, cname in (("SAPISIDHASH", "SAPISID"), ("SAPISID1PHASH", "__Secure-1PAPISID"), ("SAPISID3PHASH", "__Secure-3PAPISID")):
        sid = vals.get(cname)
        if sid:
            h = hashlib.sha1((ts + " " + sid + " " + origin).encode("utf-8")).hexdigest()
            auth_parts.append("%s %s_%s" % (scheme, ts, h))
    if auth_parts:
        headers["Authorization"] = " ".join(auth_parts)
    return headers

def innertube_post(headers, payload):
    url = "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false"
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=25) as resp:
        raw = resp.read()
        if raw[:2] == b'\x1f\x8b':
            raw = gzip.decompress(raw)
        return json.loads(raw.decode("utf-8", "ignore"))

def innertube_action_post(endpoint, payload, cookies):
    url = "https://www.youtube.com/youtubei/v1/" + endpoint.lstrip("/")
    headers = build_action_headers(cookies)
    ctx = {"context": {"client": {"clientName": "WEB", "clientVersion": "2.20240101.00.00", "hl": "en", "gl": "US"}}}
    body = dict(ctx)
    if payload and isinstance(payload, dict):
        body.update(payload)
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            raw = resp.read()
            if raw[:2] == b'\x1f\x8b':
                raw = gzip.decompress(raw)
            try:
                obj = json.loads(raw.decode("utf-8", "ignore"))
            except Exception:
                obj = {}
            return True, obj, ""
    except urllib.error.HTTPError as e:
        try:
            raw = e.read()
            if raw[:2] == b'\x1f\x8b':
                try:
                    raw = gzip.decompress(raw)
                except Exception:
                    pass
            obj = json.loads(raw.decode("utf-8", "ignore"))
            msg = ""
            try:
                msg = (((obj.get("error") or {}).get("message")) or "")
            except Exception:
                msg = ""
            return False, obj if isinstance(obj, dict) else {}, msg or ("HTTP %s" % e.code)
        except Exception:
            return False, {}, "HTTP %s" % e.code
    except Exception as e:
        return False, {}, str(e)

def text_runs(node):
    try:
        return "".join(r.get("text", "") for r in ((node or {}).get("runs") or []))
    except Exception:
        return ""

def export_netscape_cookies(cookies, out_path):
    lines = ["# Netscape HTTP Cookie File", ""]
    for host, name, value, path, expiry, is_secure in cookies:
        if not host or not name:
            continue
        if expiry and expiry > 0 and expiry < int(time.time()) - 86400:
            continue
        flag = "TRUE" if host.startswith(".") else "FALSE"
        secure = "TRUE" if is_secure else "FALSE"
        exp = str(int(expiry or 0))
        val = (value or "").replace("\n", "").replace("\r", "")
        lines.append("\t".join([host, flag, path or "/", secure, exp, name, val]))
    tmp = out_path + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        os.replace(tmp, out_path)
        return True
    except Exception:
        try:
            if os.path.exists(tmp): os.remove(tmp)
        except Exception:
            pass
        return False

def ytdlp_flat_entries(yt_dlp_bin, cookies_path, url, timeout=40, extra_args=None):
    if not yt_dlp_bin or not cookies_path or not os.path.isfile(cookies_path):
        return []
    try:
        cmd = [yt_dlp_bin, "--cookies", cookies_path, "--flat-playlist", "-J", "--no-warnings"]
        if extra_args:
            cmd.extend(extra_args)
        cmd.append(url)
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        if p.returncode != 0:
            return []
        data = json.loads(p.stdout.decode("utf-8", "ignore") or "null")
        if not data or not isinstance(data, dict):
            return []
        entries = data.get("entries") or []
        return entries if isinstance(entries, list) else []
    except Exception:
        return []

def add_library_item(items, seen, bid, title, sub=""):
    if not bid or not isinstance(bid, str):
        return
    bid = bid.strip()
    if not bid or bid in seen:
        return
    # filter channels/artists/profiles and system lists
    if bid.startswith("UC") or bid.startswith("ytmtui-category:"):
        return
    if bid in ("WL", "HL"):
        return
    cnt = ""
    mm = re.search(r'(\d+)\s*tracks?', sub or "", re.I)
    if mm:
        cnt = mm.group(1)
    seen.add(bid)
    items.append({"id": bid, "title": title or bid, "count": cnt})

def is_music_playlist(yt_dlp_bin, cookies_path, pid):
    """Heuristic: treat as music playlist if sampled entries look like songs."""
    try:
        # probe via music.youtube.com first (some playlists behave better there)
        url = "https://music.youtube.com/playlist?list=" + pid
        entries = ytdlp_flat_entries(yt_dlp_bin, cookies_path, url, timeout=25, extra_args=["--playlist-end", "3"])
        if not entries:
            # fallback to regular youtube
            url = "https://www.youtube.com/playlist?list=" + pid
            entries = ytdlp_flat_entries(yt_dlp_bin, cookies_path, url, timeout=25, extra_args=["--playlist-end", "3"])
        if not entries:
            return False
        durations = []
        for e in entries[:3]:
            if not isinstance(e, dict):
                continue
            d = e.get("duration")
            try:
                if d is not None:
                    durations.append(float(d))
            except Exception:
                pass
        if not durations:
            # no duration info (e.g. shorts in flat listing) -> not a typical music playlist
            return False
        # music-like: at least one reasonably song-length item and nothing extremely long
        has_song = any(20 <= d <= 600 for d in durations)
        all_long = all(d > 900 for d in durations)
        if has_song and not all_long:
            return True
        return False
    except Exception:
        return False

def cmd_library(cookies, yt_dlp_bin=None):
    headers = build_innertube_headers(cookies)
    ctx = {"context": {"client": {"clientName": "WEB_REMIX", "clientVersion": headers.get("X-Youtube-Client-Version", "1.20240101.01.00"), "hl": "en", "gl": "US"}}}
    items = []
    seen = set()

    def collect(o, d=0):
        if d > 18:
            return
        if isinstance(o, dict):
            if "musicTwoRowItemRenderer" in o and isinstance(o["musicTwoRowItemRenderer"], dict):
                r = o["musicTwoRowItemRenderer"]
                title = ""
                try:
                    runs = r.get("title", {}).get("runs", [])
                    if runs:
                        title = runs[0].get("text", "") or ""
                except Exception:
                    pass
                bid = None
                try:
                    bid = ((r.get("navigationEndpoint") or {}).get("browseEndpoint") or {}).get("browseId")
                except Exception:
                    pass
                sub = text_runs(r.get("subtitle"))
                add_library_item(items, seen, bid, title, sub)
            if "musicResponsiveListItemRenderer" in o and isinstance(o["musicResponsiveListItemRenderer"], dict):
                r = o["musicResponsiveListItemRenderer"]
                bid = None
                try:
                    bid = ((r.get("navigationEndpoint") or {}).get("browseEndpoint") or {}).get("browseId")
                except Exception:
                    pass
                title = ""
                try:
                    title = text_runs(r.get("flexColumns", [{}])[0].get("musicResponsiveListItemFlexColumnRenderer", {}).get("text"))
                except Exception:
                    pass
                sub = ""
                try:
                    if len(r.get("flexColumns", [])) > 1:
                        sub = text_runs(r["flexColumns"][1].get("musicResponsiveListItemFlexColumnRenderer", {}).get("text"))
                except Exception:
                    pass
                add_library_item(items, seen, bid, title, sub)
            for v in o.values():
                collect(v, d + 1)
        elif isinstance(o, list):
            for v in o[:400]:
                collect(v, d + 1)

    # 1) Try innertube (best for YTM-specific library) - may work if auth accepted
    for bid0 in ("FEmusic_liked_playlists", "FEmusic_library_landing"):
        try:
            obj = innertube_post(headers, {**ctx, "browseId": bid0})
            collect(obj, 0)
        except Exception:
            pass

    logged_in = has_login_cookie(cookies)

    # 2) Fallback: enumerate playlists via yt-dlp using browser cookies, filter to music-like playlists
    need_more = (len([x for x in items if x.get("id") not in ("LM", "VLLM", "SE", "VLSE")]) == 0)
    if yt_dlp_bin and (need_more or len(items) <= 1) and logged_in:
        tmp = os.path.join(tempfile.gettempdir(), "qs-ytmusic-lib-cookies-%d.txt" % os.getpid())
        try:
            if export_netscape_cookies(cookies, tmp):
                entries = ytdlp_flat_entries(yt_dlp_bin, tmp, "https://www.youtube.com/feed/playlists", timeout=45)
                candidates = []
                seen_pid = set()
                for e in entries:
                    if not isinstance(e, dict):
                        continue
                    pid = str(e.get("id") or "").strip()
                    title = str(e.get("title") or "").strip()
                    if not pid or pid in seen_pid:
                        continue
                    seen_pid.add(pid)
                    # Map YouTube Liked videos to YTM Liked Music context
                    if pid == "LL":
                        add_library_item(items, seen, "LM", "Liked Music", "")
                        continue
                    if pid in ("LM", "VLLM"):
                        add_library_item(items, seen, "LM", "Liked Music", "")
                        continue
                    if pid in ("WL", "HL"):
                        continue
                    candidates.append((pid, title))

                # Probe candidates in parallel to keep only music-like playlists
                if candidates:
                    def _probe(item):
                        pid, title = item
                        ok = is_music_playlist(yt_dlp_bin, tmp, pid)
                        return (pid, title, ok)

                    max_workers = min(4, max(1, len(candidates)))
                    with ThreadPoolExecutor(max_workers=max_workers) as ex:
                        futs = {ex.submit(_probe, c): c for c in candidates}
                        for fut in as_completed(futs):
                            try:
                                pid, title, ok = fut.result()
                                if ok:
                                    add_library_item(items, seen, pid, title or pid, "")
                            except Exception:
                                pass
        except Exception:
            pass
        finally:
            try:
                if os.path.exists(tmp): os.remove(tmp)
            except Exception:
                pass

    # 3) Ensure Liked Music present if logged in
    if logged_in and "LM" not in seen and "VLLM" not in seen:
        items.insert(0, {"id": "LM", "title": "Liked Music", "count": ""})
        seen.add("LM")

    print(json.dumps(items, ensure_ascii=False))

def cmd_browse(cookies, bid):
    headers = build_innertube_headers(cookies)
    ctx = {"context": {"client": {"clientName": "WEB_REMIX", "clientVersion": headers.get("X-Youtube-Client-Version", "1.20240101.01.00"), "hl": "en", "gl": "US"}}}
    tracks = []
    seen = set()

    def add_from_mrlir(r):
        vid = None
        try:
            ov = r.get("overlay", {}).get("musicItemThumbnailOverlayRenderer", {}).get("content", {}).get("musicPlayButtonRenderer", {}).get("playNavigationEndpoint", {}).get("watchEndpoint", {})
            vid = ov.get("videoId")
        except Exception:
            pass
        if not vid:
            try:
                vid = r.get("playlistItemData", {}).get("videoId")
            except Exception:
                pass
        if not vid:
            try:
                for fc in r.get("flexColumns", []):
                    for run in fc.get("musicResponsiveListItemFlexColumnRenderer", {}).get("text", {}).get("runs", []):
                        v = ((run.get("navigationEndpoint") or {}).get("watchEndpoint") or {}).get("videoId")
                        if v:
                            vid = v
                            break
                    if vid:
                        break
            except Exception:
                pass
        if not vid or not re.match(r'^[A-Za-z0-9_-]{11}$', str(vid)):
            return
        vid = str(vid)
        if vid in seen:
            return
        title = ""
        try:
            title = "".join(x.get("text", "") for x in r["flexColumns"][0]["musicResponsiveListItemFlexColumnRenderer"]["text"]["runs"])
        except Exception:
            pass
        artist = ""
        try:
            if len(r.get("flexColumns", [])) > 1:
                artist = text_runs(r["flexColumns"][1]["musicResponsiveListItemFlexColumnRenderer"]["text"])
        except Exception:
            pass
        durtxt = ""
        try:
            fcols = r.get("fixedColumns", [])
            if fcols:
                durtxt = text_runs(fcols[0].get("musicResponsiveListItemFixedColumnRenderer", {}).get("text"))
        except Exception:
            pass
        thumb = ""
        try:
            ths = r.get("thumbnail", {}).get("musicThumbnailRenderer", {}).get("thumbnail", {}).get("thumbnails", [])
            if ths:
                thumb = (ths[-1] or {}).get("url", "") or ""
        except Exception:
            pass
        if not thumb:
            thumb = "https://i.ytimg.com/vi/" + vid + "/mqdefault.jpg"
        seen.add(vid)
        tracks.append({"id": vid, "title": title or "Track", "artist": artist, "album": "", "thumbnail_url": thumb, "duration": durtxt})

    def walk(o, d=0):
        conts = []
        if d > 18:
            return conts
        if isinstance(o, dict):
            if "musicResponsiveListItemRenderer" in o and isinstance(o["musicResponsiveListItemRenderer"], dict):
                add_from_mrlir(o["musicResponsiveListItemRenderer"])
            for k in ("continuationCommand", "reloadContinuationData"):
                if k in o:
                    tok = ((o.get(k) or {}).get("token"))
                    if tok:
                        conts.append(tok)
            if "nextContinuationData" in o:
                tok = ((o.get("nextContinuationData") or {}).get("continuation"))
                if tok:
                    conts.append(tok)
            for v in o.values():
                conts += walk(v, d + 1)
        elif isinstance(o, list):
            for v in o[:500]:
                conts += walk(v, d + 1)
        return conts

    try:
        obj = innertube_post(headers, {**ctx, "browseId": bid})
        conts = walk(obj, 0)
        seen_c = set()
        q = []
        for c in conts:
            if c and c not in seen_c:
                seen_c.add(c); q.append(c)
        steps = 0
        while q and steps < 20 and len(tracks) < 2000:
            tok = q.pop(0); steps += 1
            try:
                obj = innertube_post(headers, {**ctx, "continuation": tok})
            except Exception:
                break
            conts = walk(obj, 0)
            for c in conts:
                if c and c not in seen_c:
                    seen_c.add(c); q.append(c)
        print(json.dumps(tracks, ensure_ascii=False))
    except Exception:
        print("[]")

def cmd_export(cookies, out_path):
    if export_netscape_cookies(cookies, out_path):
        print("ok")
    else:
        print("fail")

def cmd_like_action(cookies, action, video_id):
    if not video_id or not re.match(r'^[A-Za-z0-9_-]{11}$', str(video_id)):
        print(json.dumps({"ok": False, "error": "Invalid video id"}, ensure_ascii=False))
        return
    endpoint = {
        "like": "like/like",
        "dislike": "like/dislike",
        "removelike": "like/removelike",
        "indifferent": "like/removelike",
    }.get(action)
    if not endpoint:
        print(json.dumps({"ok": False, "error": "Unknown action"}, ensure_ascii=False))
        return
    ok, obj, msg = innertube_action_post(endpoint, {"target": {"videoId": str(video_id)}}, cookies)
    if ok and isinstance(obj, dict) and "error" not in obj:
        print(json.dumps({"ok": True}, ensure_ascii=False))
    else:
        print(json.dumps({"ok": False, "error": msg or "Failed"}, ensure_ascii=False))

def cmd_add_to_playlist(cookies, playlist_id, video_id):
    playlist_id = str(playlist_id or "").strip()
    video_id = str(video_id or "").strip()
    if not playlist_id:
        print(json.dumps({"ok": False, "error": "Missing playlist id"}, ensure_ascii=False))
        return
    if not video_id or not re.match(r'^[A-Za-z0-9_-]{11}$', video_id):
        print(json.dumps({"ok": False, "error": "Invalid video id"}, ensure_ascii=False))
        return
    ok, obj, msg = innertube_action_post(
        "browse/edit_playlist",
        {
            "playlistId": playlist_id,
            "actions": [{"addedVideoId": video_id, "action": "ACTION_ADD_VIDEO"}],
        },
        cookies,
    )
    if ok and isinstance(obj, dict) and "error" not in obj:
        print(json.dumps({"ok": True}, ensure_ascii=False))
    else:
        print(json.dumps({"ok": False, "error": msg or "Failed"}, ensure_ascii=False))

def cmd_addable_playlists(cookies, video_id):
    video_id = str(video_id or "").strip()
    if not video_id or not re.match(r'^[A-Za-z0-9_-]{11}$', video_id):
        print(json.dumps([], ensure_ascii=False))
        return
    ok, obj, msg = innertube_action_post(
        "playlist/get_add_to_playlist",
        {"videoIds": [video_id]},
        cookies,
    )
    items = []
    if not ok or not isinstance(obj, dict):
        print(json.dumps([], ensure_ascii=False))
        return

    def walk(o, d=0):
        if d > 14:
            return
        if isinstance(o, dict):
            if "playlistAddToOptionRenderer" in o and isinstance(o["playlistAddToOptionRenderer"], dict):
                r = o["playlistAddToOptionRenderer"]
                pid = str(r.get("playlistId") or "").strip()
                title = text_runs(r.get("title"))
                contains = str(r.get("containsSelectedVideos") or "NONE")
                if not title:
                    # fallback: sometimes no runs text in our simplified extract; try runs manually
                    try:
                        title = "".join(x.get("text", "") for x in (r.get("title") or {}).get("runs", []))
                    except Exception:
                        title = ""
                if pid and title:
                    items.append({"id": pid, "title": title, "contains": contains})
            for v in o.values():
                walk(v, d + 1)
        elif isinstance(o, list):
            for v in o:
                walk(v, d + 1)

    walk(obj, 0)
    # dedupe, keep order
    out = []
    seen = set()
    for it in items:
        if it["id"] in seen:
            continue
        seen.add(it["id"])
        out.append(it)
    print(json.dumps(out, ensure_ascii=False))

def cmd_remove_from_playlist(cookies, playlist_id, video_id):
    playlist_id = str(playlist_id or "").strip()
    video_id = str(video_id or "").strip()
    if not playlist_id or not video_id or not re.match(r'^[A-Za-z0-9_-]{11}$', video_id):
        print(json.dumps({"ok": False, "error": "Invalid arguments"}, ensure_ascii=False))
        return
    ok, obj, msg = innertube_action_post(
        "browse/edit_playlist",
        {
            "playlistId": playlist_id,
            "actions": [{"action": "ACTION_REMOVE_VIDEO_BY_VIDEO_ID", "removedVideoId": video_id}],
        },
        cookies,
    )
    if ok and isinstance(obj, dict) and "error" not in obj:
        print(json.dumps({"ok": True}, ensure_ascii=False))
    else:
        print(json.dumps({"ok": False, "error": msg or "Failed"}, ensure_ascii=False))

def load_cookies():
    db = find_cookie_db()
    if not db:
        return []
    rows = read_moz_cookies(db)
    return best_cookies(rows)

def main():
    if len(sys.argv) < 2:
        print("[]")
        return
    cmd = sys.argv[1]
    cookies = load_cookies()
    if cmd == "library":
        yt_dlp_bin = sys.argv[2] if len(sys.argv) >= 3 else None
        cmd_library(cookies, yt_dlp_bin)
    elif cmd == "browse" and len(sys.argv) >= 3:
        cmd_browse(cookies, sys.argv[2])
    elif cmd == "export" and len(sys.argv) >= 3:
        cmd_export(cookies, sys.argv[2])
    elif cmd in ("like", "dislike", "removelike", "indifferent") and len(sys.argv) >= 3:
        cmd_like_action(cookies, cmd, sys.argv[2])
    elif cmd == "addable_playlists" and len(sys.argv) >= 3:
        cmd_addable_playlists(cookies, sys.argv[2])
    elif cmd == "add_to_playlist" and len(sys.argv) >= 4:
        cmd_add_to_playlist(cookies, sys.argv[2], sys.argv[3])
    elif cmd == "remove_from_playlist" and len(sys.argv) >= 4:
        cmd_remove_from_playlist(cookies, sys.argv[2], sys.argv[3])
    else:
        print("[]")

if __name__ == "__main__":
    main()
