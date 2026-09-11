' ==========================================================================
' RoboPlayer SDK - validation harness  (P0 - P9)
'
' This is NOT the file to copy. Copy MinimalScene.brs - it is the reference
' integration, written in the order a client actually writes it.
'
' This one asserts. It walks the whole public surface, prints a PASS/FAIL
' checklist on screen, and binds the leftover remote keys to the things a
' real client would put behind its own menu. It exists to catch regressions
' in the SDK, not to show good client structure.
'
' ------------------------------------------------------------ what it covers
'
'   P0   ComponentLibrary loads, rbp: prefix resolves, facade is a Group
'   P1   Facade fields exist; load() validates and normalises a media item
'   P2   play / pause / stop / seek against a real stream; HLS, DASH, MP4
'   P3   state machine: guarded transitions, startup vs stall, session stats
'   P4   analytics batches, sequence numbers, event payloads
'   P5   audio + subtitle enumeration and selection
'   P6   theme deep-merge, colour normalisation, asset rejection warnings
'   P7   controls overlay, key routing, trick play, auto-hide, rating bug
'   P9   button row (rewind, play/pause, forward, Audio & Subtitles),
'        track panel, two-row overlay focus
'
' --------------------------------------------------------------- the key map
'
' From P9 the SDK owns playback AND track selection. Only one harness key
' is left.
'
'   OK, play              SDK    play / pause
'   left, right           SDK    skip by skipInterval
'   rewind, fastforward   SDK    trick play, indicator 2x/3x/4x
'   down                  SDK    onto the button row, landing on play/pause
'   left, right (on row)  SDK    walk the row; OK activates the button
'   up (on row)           SDK    back to the progress bar
'   options (*)           SDK    open the Audio & Subtitles panel directly
'   back (1st press)      SDK    hide the controls
'
'   back (2nd press)      demo   dispose() then exit
'   up                    demo   cycle stream format (HLS/DASH/MP4/MULTI)
'
' The audio and subtitle cycling this harness used to bind on `down` and
' `options` is gone. The SDK claims both keys now, so those handlers could
' never fire - and the panel does the same job properly, with names instead
' of blind cycling.
'
' Keys the SDK declines bubble up to this scene. They only arrive while the
' controls are VISIBLE - with them hidden the SDK claims every key to wake
' them first.
' ==========================================================================


' ==========================================================================
' CONFIG
'
' Bump the filename whenever you bump the SDK manifest, and copy the new zip
' into vendor/.
'
' useLocal = true   -> loads from vendor/ inside this channel. No server.
' useLocal = false  -> loads over HTTP. Use this if the device rejects pkg:/
'                      (ComponentLibrary is designed for remote loading, and
'                      not all firmware accepts a local path).
' ==========================================================================
function CONFIG() as object
    return {
        useLocal: true
        localUri:  "pkg:/vendor/rbp-lib-1.0.0.zip"
        httpUri:   "http://192.168.0.109:8080/rbp-lib-1.0.0.zip"
    }
end function


sub init()
    m.top.backgroundColor = "0x0B0B0FFF"

    m.status  = m.top.findNode("statusLabel")
    m.results = m.top.findNode("resultsLabel")
    m.host    = m.top.findNode("playerHost")
    m.lib     = m.top.findNode("rbp")

    m.lines = []
    m.passCount = 0
    m.failCount = 0
    m.finished  = false

    cfg = CONFIG()
    if cfg.useLocal
        m.libUrl = cfg.localUri
    else
        m.libUrl = cfg.httpUri
    end if

    ' REQUIRED ORDERING: observe before setting uri. A fast fetch can reach
    ' "ready" before init() returns, and the event would be missed.
    m.lib.observeField("loadStatus", "onLibStatus")

    setStatus("loading " + m.libUrl)
    m.lib.uri = m.libUrl
    m.top.setFocus(true)
end sub


' ==========================================================================
' LIBRARY LOAD
'
' loadStatus walks "none" -> "loading" -> "ready" | "failed". Only the last
' two are terminal; everything before them is progress noise.
' ==========================================================================
sub onLibStatus()
    st = m.lib.loadStatus
    setStatus("loadStatus: " + st)

    if m.finished then return

    if st = "ready"
        m.finished = true
        pass("component library loaded")
        runChecks()
    else if st = "failed"
        m.finished = true
        fail("component library failed to load")
        addLine("      uri: " + m.libUrl)
        if Left(m.libUrl, 5) = "pkg:/"
            addLine("      Not every firmware accepts a packaged path. Set")
            addLine("      CONFIG().useLocal to false and serve the zip over HTTP.")
        end if
        summarize()
    end if
end sub


' Everything this demo actually validates about the SDK lives here.
sub runChecks()
    facade = CreateObject("roSGNode", "rbp:rbpPlayerFacade")

    ' A missing or renamed component yields invalid rather than a crash, so
    ' this is what catches a library built without the facade in it.
    if facade = invalid
        fail("CreateObject(""rbp:rbpPlayerFacade"") returned invalid")
        addLine("      Check sg_component_libs_provided=rbp in the lib manifest")
        addLine("      and that the ComponentLibrary node id is ""rbp"".")
        summarize()
        return
    end if
    pass("created rbp:rbpPlayerFacade")

    if facade.isSubtype("Group")
        pass("facade extends Group")
    else
        fail("facade is not a Group (subtype: " + facade.subtype() + ")")
    end if

    ' The Facade is the player view, so parenting it should be all it takes
    ' to get pixels on screen.
    m.host.appendChild(facade)
    m.facade = facade

    ' P7: the SDK owns input now. Handing it focus is the whole integration
    ' step - one line, and OK/left/right/rewind/fastforward/back are wired to
    ' real controls. Anything the SDK does not claim bubbles back up to this
    ' scene's own onKeyEvent, which is how the harness keys below still work.
    facade.setFocus(true)

    if m.host.getChildCount() = 1
        pass("facade parented into playerHost")
    else
        fail("facade did not attach to playerHost")
    end if

    ' ---- P1: Facade surface + media model -----------------------------
    for each fieldName in ["playerState", "position", "duration", "errorInfo", "mediaItem"]
        if facade.hasField(fieldName)
            pass("field exposed: " + fieldName)
        else
            fail("field missing: " + fieldName)
        end if
    end for

    if facade.playerState = "idle"
        pass("initial state is idle")
    else
        fail("initial state is " + facade.playerState)
    end if

    ' --- valid load ---
    r = facade.callFunc("load", {
        url: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8"
        title: "Bip Bop"
        ageRating: "TV-14"
        duration: 596
    })

    if r <> invalid and r.ok = true
        pass("load() accepted a valid item")
    else
        fail("load() rejected a valid item")
        if r <> invalid then addLine("      " + r.message)
    end if

    if facade.mediaItem.format = "hls"
        pass("format inferred from url -> hls")
    else
        fail("format was " + Chr(34) + facade.mediaItem.format + Chr(34))
    end if

    if facade.duration = 596
        pass("duration mapped to the facade")
    else
        fail("duration was " + Str(facade.duration).Trim())
    end if

    ' --- invalid load: no url ---
    r = facade.callFunc("load", { title: "no url" })
    if r <> invalid and r.ok = false and r.code = "missingUrl"
        pass("load() rejects a missing url")
    else
        fail("load() did not reject a missing url")
    end if

    ' --- invalid load: not an object ---
    r = facade.callFunc("load", "garbage")
    if r <> invalid and r.ok = false and r.code = "invalidMediaItem"
        pass("load() rejects non-object input without crashing")
    else
        fail("load() mishandled non-object input")
    end if

    ' --- seek is rejected before the stream is ready ---
    r = facade.callFunc("seek", 30)
    if r <> invalid and r.ok = false
        pass("seek() rejected before stream ready")
    else
        fail("seek() ran before the stream was ready")
    end if

    summarize()

        ' ---- P2: playback -------------------------------------------------
    facade.size = [1280, 720]

    facade.observeField("playerState", "onPlayerState")
    facade.observeField("position", "onPlayerPosition")
    facade.observeField("duration", "onPlayerDuration")
    facade.observeField("errorInfo", "onError")

    ' ---- P3: session state --------------------------------------------
    for each fieldName in ["isSeeking", "positionInterval", "sessionStats"]
        if facade.hasField(fieldName)
            pass("field exposed: " + fieldName)
        else
            fail("field missing: " + fieldName)
        end if
    end for

    facade.observeField("isSeeking", "onSeeking")
    facade.observeField("sessionStats", "onStats")

    ' ---- P4: analytics ------------------------------------------------
    if facade.hasField("analyticsEvents")
        pass("field exposed: analyticsEvents")
    else
        fail("field missing: analyticsEvents")
    end if

    m.lastSequence = 0
    facade.observeField("analyticsEvents", "onAnalytics")

    ' ---- P5: tracks ---------------------------------------------------
    for each fieldName in ["audioTracks", "subtitleTracks", "currentAudioTrack", "currentSubtitleTrack", "tracksReady", "captionMode"]
        if facade.hasField(fieldName)
            pass("field exposed: " + fieldName)
        else
            fail("field missing: " + fieldName)
        end if
    end for

    ' ---- P6: theming --------------------------------------------------
    for each fieldName in ["theme", "themeWarnings"]
        if facade.hasField(fieldName)
            pass("field exposed: " + fieldName)
        else
            fail("field missing: " + fieldName)
        end if
    end for

    ' Defaults must be in place before any client call.
    if facade.theme.colors.primary = "0x3FBAC3FF"
        pass("theme defaults applied at init")
    else
        fail("theme default primary was " + facade.theme.colors.primary)
    end if

    ' A partial override keeps every other token, and a pkg:/ asset is
    ' refused with a reason rather than silently loading nothing.
    r = facade.callFunc("setTheme", {
        colors: { primary: "#E50914", background: "#1A0000" }
        assets: { logo: "pkg:/images/logo.png" }
    })

    if facade.theme.colors.primary = "0xE50914FF"
        pass("client colour applied, alpha added")
    else
        fail("primary was " + facade.theme.colors.primary)
    end if

    if facade.theme.colors.text = "0xFFFFFFFF"
        pass("untouched tokens kept their defaults")
    else
        fail("text was overwritten: " + facade.theme.colors.text)
    end if

    if r.warnings.count() = 1 and r.warnings[0].reason = "pkgPathNotSupported"
        pass("pkg:/ asset refused with a reason")
    else
        fail("pkg:/ asset was not reported")
    end if

    facade.observeField("audioTracks", "onAudioTracks")
    facade.observeField("subtitleTracks", "onSubtitleTracks")
    facade.observeField("tracksReady", "onTracksReady")
    facade.observeField("captionMode", "onCaptionMode")

    r = facade.callFunc("play", invalid)
    if r <> invalid and r.ok = true
        pass("play() accepted")
    else
        fail("play() failed")
    end if

    m.mediaIndex = 0
    addLine("      watching state/position - video should appear")
end sub


' ==========================================================================
' OUTPUT
' ==========================================================================
sub summarize()
    setStatus(itoa(m.passCount) + " passed, " + itoa(m.failCount) + " failed")
end sub

sub pass(msg as string)
    m.passCount = m.passCount + 1
    addLine("PASS  " + msg)
end sub

sub fail(msg as string)
    m.failCount = m.failCount + 1
    addLine("FAIL  " + msg)
end sub

sub setStatus(msg as string)
    print "[demo] " + msg
    if m.status <> invalid then m.status.text = msg
end sub

sub addLine(line as string)
    print "[demo] " + line
    m.lines.push(line)

    ' The panel occupies the band between the header and the player's control
    ' bar - roughly y 185 to 570, about 18 lines at this font size. Without a
    ' cap the list grew forever, ran underneath the controls and then off the
    ' bottom of the screen, so the newest lines - the ones actually being
    ' waited on - were the first to become unreadable.
    '
    ' Every line still goes to the console above, so nothing is lost.
    while m.lines.count() > 18
        m.lines.shift()
    end while

    text = ""
    for each entry in m.lines
        if text <> "" then text = text + Chr(10)
        text = text + entry
    end for

    if m.results <> invalid then m.results.text = text
end sub

' Str() pads positive numbers with a leading space.
function itoa(n as integer) as string
    return Str(n).Trim()
end function

sub onPlayerState(evt as object)
    addLine("      state -> " + evt.getData())
end sub

sub onPlayerPosition(evt as object)
    addLine("      position -> " + Str(evt.getData()).Trim())
end sub

sub onPlayerDuration(evt as object)
    addLine("      duration -> " + Str(evt.getData()).Trim() + "s")
end sub

' ==========================================================================
' FORMAT VERIFICATION
'
' The SDK claims HLS, DASH, ISM and MP4. inferFormat() is unit tested, but a
' format only counts as supported once it has actually played on hardware.
'
' These are public test streams and may move or disappear - if one fails,
' check the URL in a browser before assuming the SDK is at fault.
' ==========================================================================
function MEDIA_ITEMS() as object
    return [
        {
            label: "HLS"
            title: "Bip Bop (HLS)"
            ' Drives the P7d rating bug: shown top-left for the first 10s of
            ' playback, then it goes. Different lengths on purpose - the box
            ' is sized from the text, not fixed.
            ageRating: "TV-14"
            url: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8"
        }
        {
            label: "DASH"
            title: "Big Buck Bunny (DASH)"
            ageRating: "U"
            url: "https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd"
        }
        {
            label: "MP4"
            title: "Sintel trailer (MP4)"
            ageRating: "PG-13"
            url: "https://media.w3.org/2010/05/sintel/trailer.mp4"
        }
        {
            ' 10 audio renditions and 13 subtitle renditions - the only one of
            ' these streams that actually exercises track selection.
            ' No ageRating: the bug must simply not appear for this one.
            label: "MULTI"
            title: "Apple advanced (multi-track HLS)"
            url: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8"
        }
    ]
end function


sub loadMedia(index as integer)
    items = MEDIA_ITEMS()
    if index < 0 or index >= items.count() then return

    m.mediaIndex = index
    item = items[index]
    addLine("      --- loading " + item.label + " ---")

    rating = ""
    if item.ageRating <> invalid then rating = item.ageRating

    r = m.facade.callFunc("load", { url: item.url, title: item.title, ageRating: rating })
    if r = invalid or r.ok <> true
        msg = "load returned invalid"
        if r <> invalid then msg = r.code + " " + r.message
        fail(item.label + " load rejected: " + msg)
        return
    end if

    ' The format the SDK inferred from the url - the thing being verified.
    pass(item.label + " load ok, format=" + m.facade.mediaItem.format)
    m.facade.callFunc("play", invalid)
end sub


sub onError(evt as object)
    e = evt.getData()
    if e = invalid or e.code = invalid or e.code = "none" then return
    addLine("      ERROR " + e.code + ": " + e.message)
end sub


sub onSeeking(evt as object)
    addLine("      isSeeking -> " + evt.getData().toStr())
end sub


sub onStats(evt as object)
    s = evt.getData()
    addLine("      stats: startup=" + Str(s.startupMs).Trim() + "ms rebuffers=" + Str(s.rebufferCount).Trim() + " stalled=" + Str(s.rebufferMs).Trim() + "ms dropped=" + Str(s.droppedCount).Trim())
end sub


' What a client's analytics integration looks like: read the batch, forward
' each payload, and use the sequence to notice if a notification was missed.
sub onAnalytics(evt as object)
    batch = evt.getData()
    if batch = invalid or batch.events = invalid then return

    expected = m.lastSequence + 1
    if batch.sequence <> expected and m.lastSequence > 0
        addLine("      !! analytics gap: expected #" + Str(expected).Trim() + " got #" + Str(batch.sequence).Trim())
    end if
    m.lastSequence = batch.sequence

    for each p in batch.events
        addLine("      EVENT " + p.name + " pos=" + Str(p.position).Trim() + "s state=" + p.state)
    end for
end sub


sub onAudioTracks(evt as object)
    tracks = evt.getData()
    addLine("      audio tracks: " + Str(tracks.count()).Trim())
    for each t in tracks
        addLine("        [" + t.id + "] " + t.label + " (" + t.language + ")")
    end for
end sub

sub onSubtitleTracks(evt as object)
    tracks = evt.getData()
    addLine("      subtitle tracks: " + Str(tracks.count()).Trim())
    for each t in tracks
        addLine("        [" + t.id + "] " + t.label + " (" + t.language + ")")
    end for
end sub

sub onTracksReady(evt as object)
    addLine("      tracksReady -> " + evt.getData().toStr())
end sub

sub onCaptionMode(evt as object)
    addLine("      device captionMode -> " + Chr(34) + evt.getData() + Chr(34))
end sub



function onKeyEvent(key as string, press as boolean) as boolean
    ' Only keys the SDK did NOT claim reach this function. From P7 onward the
    ' player handles OK/play (pause), left/right (skip), rewind/fastforward
    ' (trick play) and the first `back` (hide controls) entirely on its own.
    '
    ' What is left here is harness-only: switching stream format. Track
    ' selection belongs to the SDK's own panel from P9.
    '
    ' Note these only arrive while the controls are on screen. With the
    ' overlay hidden the SDK swallows every key to wake it first, so a user
    ' cannot skip or switch by accident while reaching for the remote.
    if not press then return false
    if m.facade = invalid then return false
    if m.disposed = true
        ' Back must still work, or the user is trapped with no way out.
        if key = "back" then return false
        addLine("      disposed - press back to exit")
        return true
    end if

    if key = "up"
        ' Cycle HLS -> DASH -> MP4. Watch that each one reaches "playing".
        nextIndex = m.mediaIndex + 1
        if nextIndex >= MEDIA_ITEMS().count() then nextIndex = 0
        loadMedia(nextIndex)
        return true
    end if

    if key = "back"
        ' Reaching here means the controls were already hidden and the SDK
        ' declined the key. What a real client does on exit: release the Video
        ' node and its observers, then let the channel close on the next press.
        m.facade.callFunc("dispose", invalid)
        m.disposed = true
        addLine("      back -> dispose() - press back again to exit")
        return true
    end if

    return false
end function