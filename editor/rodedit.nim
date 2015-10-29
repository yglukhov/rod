import nimx.matrixes
import nimx.system_logger
import rod.viewport
import rod.edit_view
import rod.component.camera
import rod.node

import rod.component.solid

when defined js:
    import nimx.js_canvas_window
    type PlatformWindow = JSCanvasWindow
else:
    import nimx.sdl_window
    type PlatformWindow = SdlWindow

const isMobile = defined(ios) or defined(android)

type EditView = ref object of View
    viewport: Viewport

method draw*(ev: EditView, r: Rect) =
    ev.viewport.bounds = ev.bounds
    ev.viewport.draw()

proc startApplication() =
    var mainWindow : PlatformWindow
    mainWindow.new()

    when isMobile:
        mainWindow.initFullscreen()
    else:
        mainWindow.init(newRect(40, 40, 1200, 600))

    mainWindow.title = "Rod"

    let editView = EditView.new(mainWindow.bounds)
    editView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    editView.viewport.new()
    editView.viewport.rootNode = newNode("(root)")
    let cameraNode = editView.viewport.rootNode.newChild("camera")
    let camera = cameraNode.component(Camera)
    cameraNode.translation.z = 1

    let greenNode = editView.viewport.rootNode.newChild("greenSolid")
    let greenSolid = greenNode.component(Solid)
    greenSolid.size = newSize(0.1, 0.1)
    greenSolid.color = newColor(0, 1, 0)

    let redNode = greenNode.newChild("redSolid")
    let redSolid = redNode.component(Solid)
    redSolid.size = newSize(0.1, 0.1)
    redSolid.color = newColor(1, 0, 0)
    redNode.translation = newVector3(0.05, 0.05)

    mainWindow.addSubview(editView)

    discard startEditingNodeInView(editView.viewport.rootNode, editView)

when defined js:
    import dom
    window.onload = proc (e: ref TEvent) =
        startApplication()
        startAnimation()
else:
    try:
        startApplication()
        runUntilQuit()
    except:
        logi "Exception caught: ", getCurrentExceptionMsg()
        logi getCurrentException().getStackTrace()
