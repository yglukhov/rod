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
#import rod.scene_composition
import nimx.image
import nimx.window
import nimx.autotest

const isMobile = defined(ios) or defined(android)

type EditView = ref object of View
    viewport: Viewport

method draw*(ev: EditView, r: Rect) =
    ev.viewport.draw()

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
    editView.viewport.new()
    editView.viewport.view = editView
    editView.viewport.rootNode = newNode("(root)")
    let cameraNode = editView.viewport.rootNode.newChild("camera")
    let camera = cameraNode.component(Camera)
    cameraNode.translation.z = 1

    let light = editView.viewport.rootNode.newChild("point_light")
    light.translation = newVector3(-600,200,0)
    let lightMesh = light.component(MeshComponent)
    lightMesh.loadWithResource("cube.obj")
    lightMesh.material.setAmbientColor(0.9, 0.9, 0.0)
    lightMesh.material.isWireframe = true
    lightMesh.material.removeDiffuseColor()
    lightMesh.material.removeSpecularColor()
    lightMesh.material.removeShininess()
    lightMesh.material.isLightReceiver = false
    let lightSource = light.component(LightSource)
    lightSource.setDefaultLightSource()
    lightSource.lightAmbient = 0.3
    lightSource.lightDiffuse = 0.5
    lightSource.lightSpecular = 0.7

    # let light2 = editView.viewport.rootNode.newChild("point_light2")
    # light2.translation = newVector3(-20,10,-60)
    # let lightMesh2 = light2.component(MeshComponent)
    # lightMesh2.loadMeshComponentWithResource("cube.obj")
    # lightMesh2.material.setAmbientColor(0.9, 0.9, 0.0)
    # lightMesh2.material.isWireframe = true
    # lightMesh2.material.removeDiffuseColor()
    # lightMesh2.material.removeSpecularColor()
    # lightMesh2.material.removeShininess()
    # lightMesh2.material.isLightReceiver = false
    # let lightSource2 = light2.component(LightSource)
    # lightSource2.setDefaultLightSource()


    # let mapleTree = editView.viewport.rootNode.newChild("maple_tree")
    # mapleTree.translation = newVector3(-5,-10,-80)
    # let meshTree = mapleTree.component(MeshComponent)
    # meshTree.loadMeshComponentWithResource("tree_maple.obj")
    # meshTree.material.albedoTexture = imageWithResource("tree_maple_color.png")
    # meshTree.material.setDiffuseColor(0.5, 0.5, 0.5)
    # meshTree.material.removeSpecularColor()

    # let baloon = editView.viewport.rootNode.newChild("baloon")
    # baloon.translation = newVector3(0, 0, -70)
    # baloon.scale = newVector3(0.1, 0.1, 0.1)
    # let meshBaloon = baloon.component(MeshComponent)
    # meshBaloon.loadMeshComponentWithResource("ball.obj")
    # meshBaloon.material.setAmbientColor(0.4, 0.1, 0.1)
    # meshBaloon.material.setDiffuseColor(0.8, 0.1, 0.1)
    # meshBaloon.material.setSpecularColor(0.9, 0.9, 0.9)

    # let composition = editView.viewport.rootNode.newChild("composition")
    # composition.loadScene("collada/balloons_test.dae")

    discard """
    let baloon = editView.viewport.rootNode.newChild("baloon")
    let anim = newAnimation()
    let toVal = 360.0
    anim.animate val in 0.0..toVal:
        baloon.rotation = aroundY(val)
    anim.loopDuration = 5.0

    baloon.translation = newVector3(-10, 0, -50)
    baloon.scale = newVector3(1.5, 1.5, 1.5)
    let meshBaloon = baloon.component(MeshComponent)
    meshBaloon.loadMeshComponentWithResource("star/balloon_star.obj")
    meshBaloon.material.setAmbientColor(0.1, 0.1, 0.0)
    meshBaloon.material.setDiffuseColor(1.5, 1.5, 1.5)
    meshBaloon.material.setSpecularColor(2.7, 2.7, 2.7)
    meshBaloon.material.albedoTexture = imageWithResource("star/balloon_star_color.png")
    meshBaloon.material.normalTexture = imageWithResource("star/balloon_star_tpNormals.png")
    meshBaloon.material.reflectionTexture = imageWithResource("star/sky_midafternoon.jpg")
    # meshBaloon.material.fallofTexture = imageWithResource("star/balloon_star_falloff.png")

    let baloon2 = editView.viewport.rootNode.newChild("baloon2")
    let anim2 = newAnimation()
    let toVal2 = 0.0
    anim2.animate val in -360.0..toVal2:
        baloon2.rotation = aroundY(val)
    anim2.loopDuration = 5.0

    baloon2.translation = newVector3(10, -7, -50)
    baloon2.scale = newVector3(1.1, 1.1, 1.1)
    let meshBaloon2 = baloon2.component(MeshComponent)
    meshBaloon2.loadMeshComponentWithResource("star/ballon_star_mid.obj")
    meshBaloon2.material.setAmbientColor(0.1, 0.1, 0.0)
    meshBaloon2.material.setDiffuseColor(1.5, 1.5, 1.5)
    meshBaloon2.material.setSpecularColor(2.7, 2.7, 2.7)
    meshBaloon2.material.reflectionTexture = imageWithResource("star/sky_midafternoon.jpg")


    let baloon3 = editView.viewport.rootNode.newChild("baloon3")
    baloon3.translation = newVector3(0, 0, -50)
    baloon3.scale = newVector3(0.8, 0.8, 0.8)
    let meshBaloon3 = baloon3.component(MeshComponent)
    meshBaloon3.loadMeshComponentWithResource("star/ballon_star_mid.obj")
    meshBaloon3.material.setAmbientColor(0.1, 0.1, 0.0)
    meshBaloon3.material.setDiffuseColor(1.5, 1.5, 1.5)
    meshBaloon3.material.setSpecularColor(2.7, 2.7, 2.7)
    meshBaloon3.material.reflectionTexture = imageWithResource("star/sky_midafternoon.jpg")

    let baloon4 = editView.viewport.rootNode.newChild("baloon4")
    baloon4.translation = newVector3(0, -14, -50)
    baloon4.scale = newVector3(0.8, 0.8, 0.8)
    baloon4.rotation = aroundY(90.0)
    let meshBaloon4 = baloon4.component(MeshComponent)
    meshBaloon4.loadMeshComponentWithResource("star/ballon_star_mid.obj")
    meshBaloon4.material.setAmbientColor(0.1, 0.1, 0.0)
    meshBaloon4.material.setDiffuseColor(1.5, 1.5, 1.5)
    meshBaloon4.material.setSpecularColor(2.7, 2.7, 2.7)
    meshBaloon4.material.reflectionTexture = imageWithResource("star/sky_midafternoon.jpg")

    mainWindow.addAnimation(anim)
    mainWindow.addAnimation(anim2)
    """

    mainWindow.addSubview(editView)

    discard startEditingNodeInView(editView.viewport.rootNode, editView)

    runAutoTestsIfNeeded()

when defined js:
    import dom
    window.onload = proc (e: ref TEvent) =
        startApplication()
else:
    try:
        startApplication()
        runUntilQuit()
    except:
        logi "Exception caught: ", getCurrentExceptionMsg()
        logi getCurrentException().getStackTrace()
