import nimx.matrixes
import nimx.system_logger
import nimx.animation

import rod.viewport
import rod.edit_view
import rod.component.camera
import rod.node
import rod.quaternion

import rod.component.solid

import rod.component.mesh_component
import rod.component.material
import rod.component.light
import rod.component.sprite
import rod.component
import rod.scene_composition

import nimx.image
import nimx.window
import nimx.autotest

const isMobile = defined(ios) or defined(android)

type EditView = ref object of SceneView

proc runAutoTestsIfNeeded() =
    uiTest generalUITest:
        discard
        when not defined(js):
            quit()

    registerTest(generalUITest)
    when defined(runAutoTests):
        startRegisteredTests()

proc startApplication() =
    when isMobile:
        var mainWindow = newFullscreenWindow()
    else:
        var mainWindow = newWindow(newRect(40, 40, 1200, 600))

    mainWindow.title = "Rod"
    mainWindow.enableAnimation(true)

    let editView = EditView.new(mainWindow.bounds)
    editView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    editView.rootNode = newNode("(root)")
    let cameraNode = editView.rootNode.newChild("camera")
    let camera = cameraNode.component(Camera)
    cameraNode.translation.z = 80

    let light = editView.rootNode.newChild("point_light")
    light.translation = newVector3(0,0,100)
    let lightSource = light.component(LightSource)
    lightSource.setDefaultLightSource()

    loadSceneAsync "../../nimasset/balloon_animation_test.dae", proc(n: Node, a: seq[Animation] = @[]) =
        editView.rootNode.addChild(n)

        mainWindow.addSubview(editView)

        for anim in a:
            editView.window.animations.add(anim)

        discard startEditingNodeInView(editView.rootNode, editView)

    runAutoTestsIfNeeded()

when defined js:
    import dom
    dom.window.onload = proc (e: ref TEvent) =
        startApplication()
else:
    try:
        startApplication()
        runUntilQuit()
    except:
        logi "Exception caught: ", getCurrentExceptionMsg()
        logi getCurrentException().getStackTrace()
