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

type SampleView = ref object of View
    viewport: Viewport

method draw*(ev: SampleView, r: Rect) =
    ev.viewport.draw()

proc startApplication() =
    var mainWindow : PlatformWindow
    mainWindow.new()

    when isMobile:
        mainWindow.initFullscreen()
    else:
        mainWindow.init(newRect(40, 40, 1200, 600))

    mainWindow.title = "Rod"

    let editView = SampleView.new(mainWindow.bounds)
    editView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    editView.viewport.new()
    editView.viewport.view = editView
    editView.viewport.rootNode = newNode()
    let c = newNodeWithCompositionName("TEST4")
    editView.viewport.rootNode.addChild(c)
    let cameraNode = editView.viewport.rootNode.newChild("camera")
    let camera = cameraNode.component(Camera)
    camera.projectionMode = cpOrtho
    cameraNode.translation.z = 1

    camera.manualGetProjectionMatrix = proc(bounds: Rect, mat: var Matrix4) =
        let logicalWidth = bounds.width
        mat.ortho(0, bounds.width, bounds.height, 0, camera.zNear, camera.zFar)

    mainWindow.addSubview(editView)

    mainWindow.addAnimation(c.animationNamed("anim1"))

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
