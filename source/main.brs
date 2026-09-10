' ==========================================================================
' Which scene to launch. Change the one line below and re-deploy.
'
'   "MinimalScene" - THE REFERENCE INTEGRATION. Read this one.
'
'                    The smallest correct client, commented as client
'                    documentation: library handshake, branding, observers,
'                    load, play, focus handover, teardown. Console only -
'                    everything on screen is drawn by the SDK itself, which
'                    is the point.
'
'   "DemoScene"    - validation harness. PASS/FAIL checklist on screen and
'                    the leftover remote keys bound to format and track
'                    cycling. Asserts the whole public surface, P0-P7.
'                    Useful for catching SDK regressions; NOT a model of
'                    good client structure.
' ==========================================================================
function SCENE_NAME() as string
    return "DemoScene"
end function


sub Main()
    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    screen.setMessagePort(m.port)

    sceneName = SCENE_NAME()
    print "[demo] launching " + sceneName

    screen.createScene(sceneName)
    screen.show()

    while true
        msg = wait(0, m.port)
        if type(msg) = "roSGScreenEvent"
            if msg.isScreenClosed() then return
        end if
    end while
end sub
