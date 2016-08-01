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
        quitApplication()

    registerTest(generalUITest)
    when defined(runAutoTests):
        startRegisteredTests()

proc startApplication() =
    when isMobile or defined(js):
        var mainWindow = newFullscreenWindow()
    else:
        var mainWindow = newWindow(newRect(40, 40, 1200, 600))

    mainWindow.title = "Rod"

    let editView = EditView.new(mainWindow.bounds)
    editView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    editView.rootNode = newNode("(root)")
    let cameraNode = editView.rootNode.newChild("camera")
    discard cameraNode.component(Camera)
    cameraNode.positionZ = 100

    let light = editView.rootNode.newChild("point_light")
    light.position = newVector3(-100,100,100)
    let lightSource = light.component(LightSource)
    lightSource.setDefaultLightSource()

    mainWindow.addSubview(editView)
    discard startEditingNodeInView(editView.rootNode, editView, false)
    # loadSceneAsync "collada/balloons_test.dae", proc(n: Node) =
    #     editView.rootNode.addChild(n)

    #     mainWindow.addSubview(editView)

    #     registerAnimation(n, editView)

    #     discard startEditingNodeInView(editView.rootNode, editView)

    runAutoTestsIfNeeded()

runApplication:
    startApplication()
