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

    let editView = EditView.new(mainWindow.bounds)
    editView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    editView.rootNode = newNode("(root)")
    let cameraNode = editView.rootNode.newChild("camera")
    let camera = cameraNode.component(Camera)
    cameraNode.translation.z = 1

    let light = editView.rootNode.newChild("point_light")
    light.translation = newVector3(-100,100,70)
    let lightMesh = light.component(MeshComponent)
    let lightSource = light.component(LightSource)
    lightSource.setDefaultLightSource()
    lightSource.lightAmbient = 0.2
    lightSource.lightDiffuse = 0.3
    lightSource.lightSpecular = 0.5
    lightSource.lightConstant = 1.0
    lightSource.lightLinear = 0.0014
    lightSource.lightQuadratic = 0.000007

    # let baloon = editView.rootNode.newChild("baloon")
    # let anim = newAnimation()
    # let toVal = 360.0
    # anim.animate val in 0.0..toVal:
    #     baloon.rotation = aroundY(val)
    # anim.loopDuration = 5.0
    # mainWindow.addAnimation(anim)

    loadSceneAsync "collada/balloons_test.dae", proc(n: Node) =
        editView.rootNode.addChild(n)

        mainWindow.addSubview(editView)

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
