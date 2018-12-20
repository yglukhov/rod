import algorithm
import strutils, tables
import nimx.view
import nimx.text_field
import nimx.button
import nimx.popup_button
import nimx.menu
import nimx.scroll_view
import nimx.linear_layout
import nimx.slider
import nimx.property_visitor
import nimx.expanding_view
import nimx.stack_view

import variant

export view

import rod.node
import rod.component
import rod.rod_types
import rod.viewport
import rod.component.camera

import rod.property_editors.propedit_registry
import rod.property_editors.standard_editors
# import rod.editor.editor_tab
import rod.edit_view

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
            let propView = propertyEditorForProperty(n, visitor.name, visitor.setterAndGetter, visitor.onChangeCallback, changeSceneSettingsView)
            propView.autoresizingMask = {afFlexibleWidth}
            let propHolder = newView(propView.frame)
            propHolder.addSubview(propView)
            expView.addContent(propHolder)

        n.visitProperties(visitor)
        i.propView.addSubview(expView)

        if not n.components.isNil:
            for v in n.components:
                closureScope:
                    expView = newExpandingView(newRect(0, 0, 328, 20.0))
                    expView.title = v.className
                    let component = v
                    expView.expand()

                    let removeButton = newButton(expView, newPoint(328 - 18, 0), newSize(18.0, 18), "-")
                    removeButton.autoresizingMask = {afFlexibleMinX}
                    removeButton.onAction do():
                        n.removeComponent(component)
                        i.inspectedNode = n

                v.visitProperties(visitor)
                i.propView.addSubview(expView)

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

    if not n.children.isNil:
        for ch in n.children:
            result.add(ch.getAllCameras)

proc reloadEditScene(v: SceneSettingsView)=
    if not v.propView.subviews.isNil:
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
    v.reloadEditScene()

method update*(v: SceneSettingsView)=
    let cams = v.currSceneView.rootNode.getAllCameras()
    if cams != v.currCameras:
        v.reloadEditScene()
        echo "reload cameras"

registerEditorTab("EditScene Settings", SceneSettingsView)
