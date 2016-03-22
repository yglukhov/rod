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

import math

const isMobile = defined(ios) or defined(android)

type EditView = ref object of SceneView

proc runAutoTestsIfNeeded() =
    uiTest generalUITest:
        discard
        quitApplication()

    registerTest(generalUITest)
    when defined(runAutoTests):
        startRegisteredTests()

proc registerAnimation(n: Node, v: EditView) =
    if not isNil(n.animations):
        for anim in n.animations.values():
            v.window.addAnimation(anim)

    if not n.children.isNil:
       for child in n.children:
            registerAnimation(child, v)

proc startApplication() =
    when isMobile:
        var mainWindow = newFullscreenWindow()
    else:
        var mainWindow = newWindow(newRect(40, 40, 1200, 600))

    mainWindow.title = "Rod"

    let editView = EditView.new(mainWindow.bounds)
    editView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    editView.rootNode = newNode("(root)")
    let cameraNode = editView.rootNode.newChild("camera")
    let camera = cameraNode.component(Camera)
    cameraNode.translation.z = 500

    let light = editView.rootNode.newChild("point_light")
    light.translation = newVector3(-100,100,100)
    let lightSource = light.component(LightSource)
    lightSource.setDefaultLightSource()

    # for i in 0..11:
    #     let n = editView.rootNode.newChild("sprite1")

    #     let sp = n.component(Sprite)

    #     sp.image = imageWithResource("TestOverdawImage.png")

    #     n.translation.x -= sp.image.size.width / 2.0 + float(random(100))
    #     n.translation.y -= sp.image.size.height / 2.0 + float((random(100) - 50))

    mainWindow.addSubview(editView)
    mainWindow.addAnimation(newAnimation())

    loadSceneAsync "collada/single_intro.dae", proc(n: Node) =
        editView.rootNode.addChild(n)

        mainWindow.addSubview(editView)

        registerAnimation(n, editView)

        discard startEditingNodeInView(editView.rootNode, editView)

    runAutoTestsIfNeeded()

when defined js:
    import dom
    dom.window.onload = proc (e: Event) =
        startApplication()
else:
    try:
        startApplication()
        runUntilQuit()
    except:
        logi "Exception caught: ", getCurrentExceptionMsg()
        logi getCurrentException().getStackTrace()
