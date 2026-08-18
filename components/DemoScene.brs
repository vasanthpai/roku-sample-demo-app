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

    r = facade.callFunc("play", invalid)
    if r <> invalid and r.ok = true
        pass("play() accepted")
    else
        fail("play() failed")
    end if

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

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.facade = invalid then return false
    if m.disposed = true
        addLine("      facade is disposed - reload the channel")
        return true
    end if


    if key = "OK"
        if m.facade.playerState = "playing"
            m.facade.callFunc("pause", invalid)
        else
            m.facade.callFunc("play", invalid)
        end if
        return true
    end if

    if key = "right"
        r = m.facade.callFunc("seek", int(m.facade.position) + 30)
        addLine("      seek +30 -> ok=" + r.ok.toStr() + " " + r.message)
        return true
    end if

    if key = "left"
        r = m.facade.callFunc("seek", int(m.facade.position) - 30)
        addLine("      seek -30 -> ok=" + r.ok.toStr() + " " + r.message)
        return true
    end if

        if key = "up"
        r = m.facade.callFunc("seek", 99999)
        addLine("      seek 99999 -> ok=" + r.ok.toStr() + " (clamps to duration-1)")
        return true
    end if

    if key = "down"
        m.facade.callFunc("dispose", invalid)
        m.disposed = true
        addLine("      dispose() called - playback should stop")
        return true
    end if

    return false
end function