import rod.viewport
import rod.rod_types
import rod.node

import rod.component
import rod.component.ui_component
import rod.edit_view

import nimx.view
import nimx.types
import nimx.button
import nimx.animation
import nimx.mini_profiler
import nimx.matrixes
import nimx.view_event_handling

const viewportSize = newSize(1920, 1080)

type GameScene* = ref object of SceneView

proc centerOrthoCameraPosition*(gs: GameScene) =
    assert(not gs.camera.isNil, "GameSceneBase's camera is nil")
    let cameraNode = gs.camera.node

    cameraNode.positionX = viewportSize.width / 2
    cameraNode.positionY = viewportSize.height / 2

proc addDefaultOrthoCamera*(gs: GameScene, cameraName: string) =
    let cameraNode = gs.rootNode.newChild(cameraName)
    let camera = cameraNode.component(Camera)

    camera.projectionMode = cpOrtho
    camera.viewportSize = viewportSize
    cameraNode.positionZ = 1
    gs.centerOrthoCameraPosition()

method acceptsFirstResponder(v: GameScene): bool = true

method onKeyDown*(gs: GameScene, e: var Event): bool =
    if e.keyCode == VirtualKey.E:
        ## start's editor
        discard startEditingNodeInView(gs.rootNode, gs)
        result = true

method init*(gs: GameScene, frame: Rect)=
    procCall gs.SceneView.init(frame)
    gs.rootNode = newNode("root")
    gs.addDefaultOrthoCamera("camera")

## viewOnEnter called when SceneView was added to Window
method viewOnEnter*(gs: GameScene)=
    let gui = gs.rootNode.newChild("Gui")

    ## load seialized node from json, constructed in editor
    let hello = newNodeWithResource("helloworld")
    gui.addChild(hello)

    let btnExit = newButton(newRect(0, 0, 200, 50))
    btnExit.title = "Exit"
    btnExit.onAction do():
        quit()

    let btnParent = newNode()
    btnParent.position = newVector3(1920.0, 1080.0)
    btnParent.anchor = newVector3(220.0, 70.0)
    gui.addChild(btnParent)

    btnParent.addComponent(UIComponent).view = btnExit

    let logo = hello.findNode("nimlogo")

    let logoScale = logo.scale

    let anim = newAnimation()
    anim.loopDuration = 2.0
    anim.numberOfLoops = -1
    anim.loopPattern = lpStartToEndToStart
    anim.onAnimate = proc(p: float) =
        logo.scale = interpolate(logoScale, logoScale * 1.1, backEaseInOut(p))

    gs.addAnimation(anim)
