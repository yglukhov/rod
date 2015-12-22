import nimx.matrixes
import nimx.system_logger
import rod.viewport
import rod.edit_view
import rod.component.camera
import rod.node

import rod.component.solid

import rod.component.mesh_component
import rod.component.material
import rod.component.light
import rod.component
import nimx.image

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
    editView.viewport.view = editView
    editView.viewport.rootNode = newNode("(root)")
    let cameraNode = editView.viewport.rootNode.newChild("camera")
    let camera = cameraNode.component(Camera)
    cameraNode.translation.z = 1


    let light = editView.viewport.rootNode.newChild("point_light_1")
    light.translation = newVector3(0,0,-800)
    let lightMesh = light.component(MeshComponent)
    lightMesh.loadWithResource("cube.obj")
    lightMesh.material.setAmbientColor(0.9, 0.9, 0.0)
    lightMesh.material.isWireframe = true
    lightMesh.material.removeDiffuseColor()
    lightMesh.material.removeSpecularColor()
    lightMesh.material.removeShininess()
    lightMesh.material.isLightReceiver = false
    let lightSource = light.component(LightSource)

    let light2 = editView.viewport.rootNode.newChild("point_light_2")
    light2.translation = newVector3(60,60,10)
    let lightMesh2 = light2.component(MeshComponent)
    lightMesh2.loadWithResource("cube.obj")
    lightMesh2.material.setAmbientColor(0.9, 0.9, 0.0)
    lightMesh2.material.isWireframe = true
    lightMesh2.material.removeDiffuseColor()
    lightMesh2.material.removeSpecularColor()
    lightMesh2.material.removeShininess()
    lightMesh2.material.isLightReceiver = false
    let lightSource2 = light2.component(LightSource)


    let mapleTree = editView.viewport.rootNode.newChild("maple_tree")
    mapleTree.translation = newVector3(-5,-10,-80)
    let meshTree = mapleTree.component(MeshComponent)
    meshTree.loadWithResource("tree_maple.obj")
    meshTree.material.albedoTexture = imageWithResource("tree_maple_color.png")
    meshTree.material.setDiffuseColor(0.5, 0.5, 0.5)
    meshTree.material.removeSpecularColor()

    let baloon = editView.viewport.rootNode.newChild("baloon")
    baloon.translation = newVector3(0, 0, -70)
    baloon.scale = newVector3(0.1, 0.1, 0.1)
    let meshBaloon = baloon.component(MeshComponent)
    meshBaloon.loadWithResource("ball.obj")
    meshBaloon.material.setAmbientColor(0.4, 0.1, 0.1)
    meshBaloon.material.setDiffuseColor(0.8, 0.1, 0.1)
    meshBaloon.material.setSpecularColor(0.9, 0.9, 0.9)

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
