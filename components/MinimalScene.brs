' ==========================================================================
' Minimal RoboPlayer SDK integration - seven steps, nothing else.
'
' Keep this file boring. It is the reference a client copies.
' ==========================================================================

sub init()
    print "[min] 1. init"

    m.lib = m.top.findNode("rbp")

    ' STEP 1 - observe BEFORE setting uri. A local zip can reach "ready"
    ' before init() returns, and the event would be missed entirely.
    m.lib.observeField("loadStatus", "onLibStatus")

    ' STEP 2 - point at the library. Must match the file in vendor/.
    m.libUri = "pkg:/vendor/rbp-lib-1.0.0.zip"
    print "[min] 2. loading library: " + m.libUri
    m.lib.uri = m.libUri

    m.top.setFocus(true)
end sub


' loadStatus walks: none -> loading -> ready | failed
sub onLibStatus()
    print "[min]    loadStatus = " + m.lib.loadStatus

    if m.lib.loadStatus = "ready"
        startPlayer()
    else if m.lib.loadStatus = "failed"
        ' Every client must handle this. The library is fetched at runtime and
        ' can fail for reasons the app does not control.
        print "[min] !! library failed to load from " + m.libUri
    end if
end sub


sub startPlayer()
    ' STEP 3 - create the player. The "rbp:" prefix comes from the
    ' ComponentLibrary node id in MinimalScene.xml, not from the SDK.
    m.player = CreateObject("roSGNode", "rbp:rbpPlayerFacade")
    if m.player = invalid
        print "[min] !! could not create rbp:rbpPlayerFacade"
        return
    end if
    print "[min] 3. facade created"

    ' STEP 4 - the facade IS the player view. Size it, add it to the scene.
    m.player.size = [1280, 720]
    m.top.appendChild(m.player)
    print "[min] 4. facade sized and parented"

    ' STEP 5 - watch what the player reports.
    m.player.observeField("playerState", "onState")
    m.player.observeField("position", "onPosition")
    m.player.observeField("analyticsEvents", "onAnalytics")
    print "[min] 5. observing playerState, position and analyticsEvents"

    ' STEP 6 - load a media item. Only url is required; format is inferred.
    result = m.player.callFunc("load", {
        url: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8"
        title: "Bip Bop"
    })
    print "[min] 6. load -> ok=" + result.ok.toStr() + " code=" + result.code
    if not result.ok
        print "[min] !! " + result.message
        return
    end if

    ' STEP 7 - play.
    m.player.callFunc("play", invalid)
    print "[min] 7. play requested"
end sub


sub onState(evt as object)
    print "[min]    state -> " + evt.getData()
end sub

sub onPosition(evt as object)
    print "[min]    position -> " + Str(evt.getData()).Trim()
end sub


' Analytics. Forward these to your own tracking - the SDK integrates no vendor.
'
' NOTE: this is a BATCH, not one event. A single transition can produce two
' (bufferEnd + seekEnd), and SceneGraph coalesces rapid writes to a field, so
' the SDK delivers everything that fired in one notification. Reading
' evt.getData().name would silently give you nothing.
sub onAnalytics(evt as object)
    batch = evt.getData()
    if batch = invalid or batch.events = invalid then return

    for each payload in batch.events
        print "[min]    EVENT " + payload.name + " pos=" + Str(payload.position).Trim() + "s state=" + payload.state
    end for
end sub


function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.player = invalid then return false

    if key = "OK"
        if m.player.playerState = "playing"
            m.player.callFunc("pause", invalid)
        else
            m.player.callFunc("play", invalid)
        end if
        return true
    end if

    ' Relative seek. The SDK clamps the target to the stream bounds and
    ' refuses a seek before the stream is ready, so no guarding is needed here.
    if key = "right"
        r = m.player.callFunc("seek", Int(m.player.position) + 30)
        print "[min]    seek +30 -> ok=" + r.ok.toStr() + " " + r.message
        return true
    end if

    if key = "left"
        r = m.player.callFunc("seek", Int(m.player.position) - 30)
        print "[min]    seek -30 -> ok=" + r.ok.toStr() + " " + r.message
        return true
    end if

    if key = "back"
        ' Release the Video node and its observers before leaving.
        m.player.callFunc("dispose", invalid)
        m.player = invalid
        print "[min]    disposed - exiting"
        return false
    end if

    return false
end function
