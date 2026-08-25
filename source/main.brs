' ==========================================================================
' Which scene to launch:
'
'   "MinimalScene" - smallest correct integration. Seven steps, console only.
'                    This is the reference a client copies.
'
'   "DemoScene"    - full validation harness. PASS/FAIL checklist on screen,
'                    seek and teardown bound to the remote.
'
' Change the one line below and re-deploy.
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
