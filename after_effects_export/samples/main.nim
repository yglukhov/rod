import nimx.matrixes
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
    let c = newNodeWithCompositionName("BONUS GAME ANIMATION")
    editView.viewport.rootNode.addChild(c)
    let cameraNode = editView.viewport.rootNode.newChild("camera")
    let camera = cameraNode.component(Camera)
    camera.projectionMode = cpOrtho
    cameraNode.positionZ = 1

    mainWindow.addSubview(editView)
    mainWindow.addAnimation(c.animationNamed("anim1"))


runApplication:
    startApplication()
