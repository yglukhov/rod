import tables

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

proc registerAnimation(n: Node, v: EditView) =
    if not isNil(n.animations):
        for anim in n.animations.values():
            v.window.addAnimation(anim)
            # anim.loopPattern = lpStartToEndToStart
            # anim.loopDuration *= 2.0
            # anim.numberOfLoops = 1

    if not n.children.isNil:
       for child in n.children:
            registerAnimation(child, v)

proc startApplication() =
    when isMobile:
        var mainWindow = newFullscreenWindow()
    else:
        var mainWindow = newWindow(newRect(40, 40, 1200, 600))

    mainWindow.title = "Rod"
    #mainWindow.enableAnimation(true)

    let editView = EditView.new(mainWindow.bounds)
    editView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    editView.rootNode = newNode("(root)")
    let cameraNode = editView.rootNode.newChild("camera")
    let camera = cameraNode.component(Camera)
    cameraNode.translation.z = 250


    let light = editView.rootNode.newChild("point_light")
    light.translation = newVector3(-100,100,100)
    let lightSource = light.component(LightSource)
    lightSource.setDefaultLightSource()

    # let anim = newAnimation()
    # mainWindow.addAnimation(anim)

    loadSceneAsync "collada/motion.dae", proc(n: Node) =

        editView.rootNode.addChild(n)

        mainWindow.addSubview(editView)

        # echo "Node: ", n.name
        # if not isNil(n.animations):
        #     echo "ANIMATIONS: ", n.animations.len
        #     for anim in n.animations.values():
        #         editView.window.addAnimation(anim)
        #         anim.loopDuration *= 2.0

        registerAnimation(n, editView)

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
