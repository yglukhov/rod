import nimx/[view, text_field, button, popup_button,
    scroll_view, linear_layout, slider,
    property_visitor, expanding_view
]
import rod/[node, component, rod_types, viewport]
import rod/property_editors/[propedit_registry, standard_editors]
import rod/component/camera
import rod/edit_view
import rod/editor/scene/components/grid
import tables
import variant

export view

type SceneSettingsView* = ref object of EditorTabView
    propView: LinearLayout
    scView: ScrollView
    currCameras: seq[Node]
    currSceneView: SceneView
    autoUpdate: bool

proc reloadEditScene(v: SceneSettingsView)

method init*(i: SceneSettingsView, r: Rect) =
    procCall i.View.init(r)
    i.resizingMask = "wh"

    i.propView = newVerticalLayout(newRect(0, 20, i.bounds.width, 20))
    i.propView.resizingMask = "wb"
    i.propView.topMargin = 5
    i.propView.bottomMargin = 5
    i.propView.leftMargin = 5
    i.propView.rightMargin = 5

    i.scView = newScrollView(i.propView)
    i.scView.horizontalScrollBar = nil
    i.scView.resizingMask = "wh"
    i.scView.setFrame(newRect(0.0, 0.0, i.bounds.width, i.bounds.height - 20.0))
    i.addSubview(i.scView)

    i.reloadEditScene()

proc inspect(i: SceneSettingsView, expView: var ExpandingView, visitor: var PropertyVisitor, comps: seq[Component]) =
    for v in comps:
        expView = newExpandingView(newRect(0, 0, 328, 20.0))
        expView.title = v.className
        expView.expand()

        v.visitProperties(visitor)
        i.propView.addSubview(expView)

proc `inspectedNode=`*(i: SceneSettingsView, n: Node) =
    let scrollBar = i.scView.verticalScrollBar()
    let oldPos = scrollBar.value()

    while i.propView.subviews.len() > 1:
        i.propView.subviews[1].removeFromSuperview()

    if not n.isNil:
        proc changeSceneSettingsView() =
            i.inspectedNode = n

        var expView= newExpandingView(newRect(0, 50, 328, 20.0))
        expView.title = "Camera node"
        expView.expand()

        var visitor : PropertyVisitor
        visitor.requireName = true
        visitor.requireSetter = true
        visitor.requireGetter = true
        visitor.flags = { pfEditable }
        visitor.commit = proc() =
            let propView = propertyEditorForProperty(n, visitor.name, visitor.setterAndGetter, nil, changeSceneSettingsView)
            propView.autoresizingMask = {afFlexibleWidth}
            let propHolder = newView(propView.frame)
            propHolder.addSubview(propView)
            expView.addContent(propHolder)

        n.visitProperties(visitor)
        i.propView.addSubview(expView)

        var comps: seq[Component]
        for c in n.components:
            comps.add(c)

        var gridComp = n.sceneView.rootNode.componentIfAvailable(EditorGrid)
        if not gridComp.isNil:
            comps.add(gridComp)

        i.inspect(expView, visitor, comps)

        scrollBar.value = oldPos
        scrollBar.sendAction()
    else:
        discard

method tabSize*(v: SceneSettingsView, bounds: Rect): Size=
    result = newSize(300.0, bounds.height)

method tabAnchor*(v: SceneSettingsView): EditorTabAnchor =
    result = etaRight

proc getAllCameras(n: Node): seq[Node]=
    result = @[]
    if not n.componentIfAvailable(Camera).isNil:
        result.add(n)

    for ch in n.children:
        result.add(ch.getAllCameras)

proc reloadEditScene(v: SceneSettingsView)=
    while v.propView.subviews.len > 0:
        v.propView.subviews[0].removeFromSuperview()

    var curScene: SceneView
    var root: Node
    var curCameraNode: Node

    if not v.editor.currentComposition.isNil:
        curScene = v.editor.currentComposition.rootNode.sceneView
    else:
        if v.editor.sceneView.isNil: return
        curScene = v.editor.sceneView

    root = curScene.rootNode
    curCameraNode = curScene.camera.node

    var cameraNodes = root.getAllCameras()
    var cameraNames = newSeq[string]()
    for c in cameraNodes:
        cameraNames.add(c.name)

    var curCameraIdx = cameraNodes.find(curCameraNode)
    if curCameraIdx < 0: return
    v.currSceneView = curScene
    v.currCameras = cameraNodes
    var cameraSel = PopupButton.new(newRect(10, 10, v.bounds.width, 20))
    cameraSel.items = cameraNames
    cameraSel.selectedIndex = curCameraIdx
    v.propView.addSubview(cameraSel)
    cameraSel.onAction do():
        let camn = cameraNodes[cameraSel.selectedIndex]
        curScene.camera = camn.component(Camera)
        v.inspectedNode = camn

    v.inspectedNode = curCameraNode

method onCompositionChanged*(v: SceneSettingsView, comp: CompositionDocument) =
    procCall v.EditorTabView.onCompositionChanged(comp)
    v.reloadEditScene()

method update*(v: SceneSettingsView)=
    let cams = v.currSceneView.rootNode.getAllCameras()
    if cams != v.currCameras:
        v.reloadEditScene()
        echo "reload cameras"

registerEditorTab("EditScene Settings", SceneSettingsView)
