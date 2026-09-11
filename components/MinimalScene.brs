' ==========================================================================
' RoboPlayer SDK - reference integration
'
' This file IS the client documentation. It is the smallest correct
' integration of the SDK as of P9, in the order a client actually writes it.
' Everything here is either required or a decision you have to make; there is
' no decoration.
'
' Read it top to bottom. Watch it run:  telnet <ROKU_IP> 8085
'
' ---------------------------------------------------------------- the shape
'
'   1. Load the library          ComponentLibrary + loadStatus handshake
'   2. Create the player         CreateObject("roSGNode", "rbp:rbpPlayerFacade")
'   3. Size and parent it        the Facade IS the view
'   4. Brand it                  setTheme() - BEFORE load()
'   5. Observe it                playerState, position, errors, analytics
'   6. Load media                load() - returns a result, never throws
'   7. Play                      play()
'   8. Hand over the remote      setFocus(true)
'   9. Tear down                 dispose()
'
' ------------------------------------------------------------- ground rules
'
' * The SDK NEVER throws. Every function returns { ok, code, message }.
'   Check `ok`. Do not wrap calls in error handling that cannot fire.
'
' * The SDK exposes NOTHING except the Facade. There is no findNode() into
'   its internals, by design - so nothing you write can be broken by an
'   SDK update that moves a node around.
'
' * Read-only fields are read-only. Write to `playerState` and you are
'   fighting the state machine, not driving it. Use the functions.
' ==========================================================================


sub init()
    print "[min] 1. init"

    m.lib = m.top.findNode("rbp")

    ' STEP 1 - observe BEFORE setting uri.
    '
    ' This ordering is not stylistic. A library loaded from pkg:/ can reach
    ' "ready" before init() returns, and an observer registered afterwards
    ' would never fire - the player would simply never appear, with nothing
    ' in the log to say why.
    m.lib.observeField("loadStatus", "onLibStatus")

    ' STEP 2 - point at the library.
    '
    ' Must match the file in vendor/. In production this is an HTTPS URL on
    ' your CDN; the filename carries the SDK version, so you roll clients
    ' forward by changing this one string.
    m.libUri = "pkg:/vendor/rbp-lib-1.0.0.zip"
    print "[min] 2. loading library: " + m.libUri
    m.lib.uri = m.libUri
end sub


' loadStatus walks: none -> loading -> ready | failed
'
' EVERY client must handle "failed". The library is fetched at runtime and
' can fail for reasons your app does not control - CDN down, no network,
' corrupt cache. There is no retry inside the SDK; the policy is yours.
sub onLibStatus()
    print "[min]    loadStatus = " + m.lib.loadStatus

    if m.lib.loadStatus = "ready"
        startPlayer()
    else if m.lib.loadStatus = "failed"
        print "[min] !! library failed to load from " + m.libUri
        ' A real app shows its own error screen here.
    end if
end sub


sub startPlayer()
    ' STEP 3 - create the player.
    '
    ' The "rbp:" prefix comes from the ComponentLibrary node id in
    ' MinimalScene.xml, NOT from the SDK. Change the id to "player" and this
    ' becomes "player:rbpPlayerFacade".
    m.player = CreateObject("roSGNode", "rbp:rbpPlayerFacade")
    if m.player = invalid
        ' Almost always a prefix mismatch between the XML id and this string.
        print "[min] !! could not create rbp:rbpPlayerFacade"
        return
    end if
    print "[min] 3. facade created"

    ' STEP 4 - the facade IS the player view. Size it, add it to the scene.
    '
    ' It is a Group, so it sizes and positions like any other node. Full
    ' screen here; a 640x360 preview window works identically, and the whole
    ' overlay lays out from this size rather than from hard-coded offsets.
    m.player.size = [1280, 720]
    m.top.appendChild(m.player)
    print "[min] 4. facade sized and parented"

    applyBranding()
    observePlayer()
    loadAndPlay()
end sub


' ==========================================================================
' STEP 5 - BRANDING  (P6)
'
' CALL THIS BEFORE load(). The theme is injected as the UI builds, not
' applied afterwards as a restyle - theming after load means a visible flash
' of the default colours.
'
' Send only what you want to change. Overrides deep-merge over the defaults,
' so omitting a token keeps it, and you never have to restate the full set.
' ==========================================================================
sub applyBranding()
    result = m.player.callFunc("setTheme", {
        colors: {
            ' CSS-style hex is accepted; the SDK normalises to Roku's
            ' 0xRRGGBBAA and adds opaque alpha when you omit it.
            primary: "#E50914"      ' scrubber fill, active glyph, accents
            text: "#FFFFFF"
        }

        ' Which parts of the player exist at all. Anything switched off
        ' gives its space back - the bar closes up rather than leaving a gap.
        controls: {
            showIcons: true         ' play/pause + skip glyphs
            showTimes: true         ' elapsed and remaining
            showScrubber: true      ' progress track
            showRatingBug: true     ' age rating, top-left, at the start
            ratingBugSeconds: 10    ' 0 = keep it up for the whole stream
            showTitle: false        ' off: your launch screen just showed it

            ' The Audio & Subtitles button and panel. Leave it on unless you
            ' are building your own track menu from audioTracks and
            ' subtitleTracks - switching it off gives you back the down and
            ' options keys.
            showMenus: true
        }

        ' Assets are URLs, NEVER pkg:/ paths.
        '
        ' Inside a ComponentLibrary, pkg:/ resolves to the LIBRARY's package,
        ' not yours - so a pkg:/ logo of yours would silently load nothing.
        ' The SDK refuses those outright and tells you in `warnings`.
        ' assets: { logo: "https://cdn.example.com/logo.png" }
    })

    ' A bad token NEVER fails the theme. It falls back to the default and is
    ' reported here. This is the only way you learn your logo url was
    ' refused, so log it - do not discard it.
    for each w in result.warnings
        print "[min]    theme warning: " + w.path + " -> " + w.reason
    end for
    print "[min] 5. theme applied"
end sub


' ==========================================================================
' STEP 6 - OBSERVE
'
' Everything the player reports is a field. Observe what you need; ignore
' the rest. All of these are READ-ONLY.
' ==========================================================================
sub observePlayer()
    ' Playback state, normalised. Never a raw Roku state.
    ' idle | loading | buffering | playing | paused | seeking | ended | error
    m.player.observeField("playerState", "onState")

    ' Seconds. Updates about once a second by default.
    '
    ' To throttle, set positionInterval to the MINIMUM seconds between
    ' updates. Do NOT set it near 1: sampling at Roku's own tick rate
    ' aliases, and jitter drops roughly every other update. Use 5, not 1.
    m.player.observeField("position", "onPosition")

    ' { code, message }. Fires on playback failures as well as load ones.
    m.player.observeField("errorInfo", "onError")

    ' Track lists. On HLS these can arrive partially and then GROW, so
    ' rebuild your menu from the field rather than caching a snapshot.
    m.player.observeField("tracksReady", "onTracksReady")

    ' Analytics. Forward to your own tracking - the SDK integrates no vendor.
    m.player.observeField("analyticsEvents", "onAnalytics")

    print "[min] 6. observing player fields"
end sub


sub onState(evt as object)
    print "[min]    state -> " + evt.getData()
end sub


sub onPosition(evt as object)
    print "[min]    position -> " + Str(evt.getData()).Trim()
end sub


sub onError(evt as object)
    info = evt.getData()
    if info = invalid or info.code = "none" then return
    print "[min] !! error: " + info.code + " - " + info.message
end sub


' Fires once the manifest has parsed and the track lists have settled. A menu
' opened before this may be incomplete.
sub onTracksReady(evt as object)
    if evt.getData() <> true then return

    print "[min]    audio tracks:    " + Str(m.player.audioTracks.count()).Trim()
    print "[min]    subtitle tracks: " + Str(m.player.subtitleTracks.count()).Trim()

    ' Selection is by track id, validated against the list before it reaches
    ' the Video node - Roku ignores an unknown id in SILENCE, so without that
    ' check you would believe a failed switch had worked.
    '
    ' An empty id turns subtitles off.
    '
    '   m.player.callFunc("selectAudioTrack", m.player.audioTracks[1].id)
    '   m.player.callFunc("selectSubtitleTrack", "")
end sub


' NOTE: this is a BATCH, not one event.
'
' A single transition can produce two (bufferEnd + seekEnd), and SceneGraph
' coalesces rapid writes to a field - so the SDK delivers everything that
' fired in one notification. Reading evt.getData().name would silently give
' you nothing.
'
' `sequence` increments per batch. If it jumps, you missed a notification -
' which is how you detect under-reporting instead of quietly living with it.
sub onAnalytics(evt as object)
    batch = evt.getData()
    if batch = invalid or batch.events = invalid then return

    for each payload in batch.events
        print "[min]    EVENT " + payload.name + " pos=" + Str(payload.position).Trim() + "s state=" + payload.state
    end for
end sub


' ==========================================================================
' STEP 7-8 - LOAD, PLAY, HAND OVER THE REMOTE
' ==========================================================================
sub loadAndPlay()
    ' `url` is the ONLY required field. `format` is inferred from the
    ' extension when omitted (.m3u8 -> HLS, .mpd -> DASH, .mp4 -> MP4).
    '
    ' load() never throws. It returns { ok, code, message }.
    result = m.player.callFunc("load", {
        url: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8"
        title: "Bip Bop"
        ageRating: "TV-14"   ' drives the rating bug, top-left
    })

    print "[min] 7. load -> ok=" + result.ok.toStr() + " code=" + result.code
    if not result.ok
        print "[min] !! " + result.message
        return
    end if

    m.player.callFunc("play", invalid)

    ' STEP 8 - hand over the remote. THIS IS THE WHOLE OF P7's INTEGRATION.
    '
    ' From this one line the SDK handles, on screen and against real state:
    '
    '   OK / play            play-pause toggle
    '   left / right         skip by skipInterval (default 10s)
    '   rewind / fastforward trick play; indicator reads 2x / 3x / 4x
    '   down                 onto the button row under the bar, landing on
    '                        play/pause. left / right walk the row:
    '                          rewind  play/pause  forward  Audio & Subtitles
    '                        OK presses the highlighted one; up goes back.
    '                        Rewind and forward SKIP by skipInterval - they
    '                        do not scan, because inside a scan OK means
    '                        "stop here"; scanning stays on the remote keys.
    '   options (*)          open that panel directly, from anywhere
    '   back                 close the panel / step up / hide the controls
    '   any key              wake the controls when they have auto-hidden
    '
    ' ...plus the controls overlay, its auto-hide, the scrubber, the time
    ' labels, the buffering notice and the rating bug.
    '
    ' Nothing inside the SDK is focusable, so it can never steal focus from
    ' your own UI, and keys it does not claim bubble straight back to you.
    m.player.setFocus(true)
    print "[min] 8. focus handed to the player - the remote now drives it"
end sub


' ==========================================================================
' STEP 9 - KEYS YOU STILL OWN
'
' Only keys the SDK DECLINES reach this function. It bubbles them up the
' node tree, which is why this fires without the scene holding focus itself.
'
' Free for you today:  up, replay, and any key the SDK has no meaning for.
' Claimed by the SDK:  OK, play, left, right, rewind, fastforward,
'                      down (button row), options (* - track panel).
'
' down belongs to the SDK while the button row has anything in it; options
' only while the track menu is on. Switch off controls.showMenus and options
' comes back to you. Switch off showIcons AND showMenus and the row is empty,
' so down comes back too.
'
' `back` reaches you only on the SECOND press - the first one hides the
' controls. That is deliberate: it means `back` always does the least
' destructive thing available before it exits.
'
' One caveat worth knowing: while the controls are HIDDEN the SDK claims
' every key to wake them first, so your own bindings arrive only while the
' controls are on screen.
' ==========================================================================
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.player = invalid then return false

    if key = "back"
        ' STEP 9 - tear down. Releases the Video node and its observers.
        '
        ' Do this whenever the player goes away, not only on exit. Skipping
        ' it leaks the Video node, and a leaked Video node keeps decoding.
        m.player.callFunc("dispose", invalid)
        m.player = invalid
        print "[min] 9. disposed - exiting"

        ' false, so the key bubbles on and the channel closes normally.
        return false
    end if

    return false
end function
