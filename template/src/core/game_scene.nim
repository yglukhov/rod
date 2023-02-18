import nimx/[view, types, button, animation, mini_profiler, matrixes, view_event_handling]
import rod/[viewport, rod_types, node, component, component/ui_component, edit_view]
import asset_loader

export asset_loader, viewport

const viewportSize = newSize(1920, 1080)

type GameScene* = ref object of SceneView
    assetLoader: AssetsLoader

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

method assetBundles*(gs: GameScene): seq[AssetBundleDescriptor] {.base.} = discard
method onResourcesLoaded*(gs: GameScene) {.base.} = discard

method init*(gs: GameScene, frame: Rect)=
    procCall gs.SceneView.init(frame)
    gs.rootNode = newNode("root")
    gs.addDefaultOrthoCamera("camera")

    proc afterResourcesPreloaded() =
        gs.onResourcesLoaded()

    let abd = gs.assetBundles()
    if abd.len > 0:
        gs.assetLoader.load(abd, onLoadProgress = nil, onLoaded = afterResourcesPreloaded)
    else:
        afterResourcesPreloaded()

method viewOnExit*(gs: GameScene) =
    if gs.assetBundles().len > 0:
        gs.assetLoader.free()

