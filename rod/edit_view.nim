import math, algorithm, strutils, tables

import nimx.view
import nimx.types
import nimx.button, nimx.popup_button
import nimx.outline_view
import nimx.toolbar
import nimx.font

import node
import inspector_view
import rod_types

import nimx.panel_view
import nimx.animation
import nimx.color_picker
import nimx.context
import nimx.portable_gl
import nimx.scroll_view
import nimx.text_field
import nimx.table_view_cell
import nimx.gesture_detector_newtouch
import nimx.key_commands
import nimx.pasteboard.pasteboard

import rod.scene_composition
import rod.component.mesh_component
import rod.component.node_selector
import rod.editor_camera_controller
import rod.editor.animation_edit_view

import ray
import nimx.view_event_handling_new
import viewport

import variant

const NodePboardKind = "io.github.yglukhov.rod.node"

const loadingAndSavingAvailable = not defined(android) and not defined(ios) and
    not defined(emscripten) and not defined(js)

when loadingAndSavingAvailable:
    import native_dialogs

type EventCatchingView* = ref object of View
    keyDownDelegate*: proc (event: var Event): bool
    keyUpDelegate*: proc (event: var Event): bool
    mouseScrrollDelegate*: proc (event: var Event)

registerClass(EventCatchingView)

type EventCatchingListener = ref object of BaseScrollListener
    view: EventCatchingView

method acceptsFirstResponder(v: EventCatchingView): bool = true

method onKeyUp(v: EventCatchingView, e : var Event): bool =
    echo "editor onKeyUp ", e.keyCode
    if not v.keyUpDelegate.isNil:
        result = v.keyUpDelegate(e)

method onKeyDown(v: EventCatchingView, e : var Event): bool =
    echo "editor onKeyUp ", e.keyCode
    if not v.keyDownDelegate.isNil:
        result = v.keyDownDelegate(e)

method onScroll*(v: EventCatchingView, e: var Event): bool =
    result = true
    if not v.mouseScrrollDelegate.isNil:
        v.mouseScrrollDelegate(e)

proc newEventCatchingListener(v: EventCatchingView): EventCatchingListener =
    result.new
    result.view = v

method onTapDown*(ecl: EventCatchingListener, e : var Event) =
    procCall ecl.BaseScrollListener.onTapDown(e)

method onScrollProgress*(ecl: EventCatchingListener, dx, dy : float32, e : var Event) =
    procCall ecl.BaseScrollListener.onScrollProgress(dx, dy, e)

method onTapUp*(ecl: EventCatchingListener, dx, dy : float32, e : var Event) =
    procCall ecl.BaseScrollListener.onTapUp(dx, dy, e)


type Editor* = ref object
    rootNode*: Node
    eventCatchingView*: EventCatchingView
    treeView*: View
    animationEditView*: AnimationEditView
    animationEditPanel: View
    toolbar*: Toolbar
    sceneView*: SceneView
    mSelectedNode: Node
    outlineView*:OutlineView
    inspector*: InspectorView
    cameraController*: EditorCameraController
    gizmo: Node
    gizmoAxis: Vector3
    cameraSelector: PopupButton

proc `selectedNode=`*(e: Editor, n: Node) =
    if n != e.mSelectedNode:
        if not e.mSelectedNode.isNil and e.mSelectedNode.componentIfAvailable(LightSource).isNil:
            e.mSelectedNode.removeComponent(NodeSelector)
        e.mSelectedNode = n
        if not e.mSelectedNode.isNil:
            discard e.mSelectedNode.component(NodeSelector)
        e.inspector.inspectedNode = n
        e.animationEditView.editedNode = n

template selectedNode*(e: Editor): Node = e.mSelectedNode

proc focusOnNode*(cameraNode: node.Node, focusNode: node.Node) =
    let distance = 100.Coord
    cameraNode.position = newVector3(
        focusNode.position.x,
        focusNode.position.y,
        focusNode.position.z + distance
    )

proc getTreeViewIndexPathForNode(editor: Editor, n: Node3D, indexPath: var seq[int]) =
    # running up and calculate the path to the node in the tree
    let parent = n.parent
    indexPath.insert(parent.children.find(n), 0)

    # because there is the root node, it's necessary to add 0
    if parent.isNil or parent == editor.rootNode:
        indexPath.insert(0, 0)
        return

    editor.getTreeViewIndexPathForNode(parent, indexPath)

proc updateCameraSelector(e: Editor) =
    var items = newSeq[string]()
    var i = 0
    var selectedIndex = -1
    discard e.rootNode.findNode() do(n: Node) -> bool:
        let cam = n.componentIfAvailable(Camera)
        if not cam.isNil:
            if not n.name.isNil:
                if cam == n.sceneView.camera:
                    selectedIndex = i
                items.add(n.name)
                inc i
    e.cameraSelector.items = items
    e.cameraSelector.selectedIndex = selectedIndex

proc sceneTreeDidChange(e: Editor) =
    e.outlineView.reloadData()
    e.updateCameraSelector()

when loadingAndSavingAvailable:
    import os, json
    import tools.serializer
    proc saveNode(editor: Editor, selectedNode: Node3D) =
        let path = callDialogFileSave("Save Json")
        if not path.isNil:
            var s = Serializer.new()
            var sData = selectedNode.serialize(s)
            s.save(sData, path)
            # s.save(selectedNode, path)

    proc loadNode(editor: Editor) =
        let path = callDialogFileOpen("Load Json or DAE")
        if not path.isNil:
            if path.endsWith(".dae"):
                var sip = editor.outlineView.selectedIndexPath
                var p = editor.rootNode
                if sip.len == 0:
                    sip.add(0)
                else:
                    p = editor.outlineView.itemAtIndexPath(sip).get(Node3D)

                editor.outlineView.expandRow(sip)
                loadSceneAsync path, proc(n: Node) =
                    p.addChild(n)
            elif path.endsWith(".json"):
                let ln = newNodeWithResource(path)
                if not editor.selectedNode.isNil:
                    editor.selectedNode.addChild(ln)
                else:
                    editor.rootNode.addChild(ln)
            editor.sceneTreeDidChange()

proc newAnimationEditView(e: Editor): PanelView =
    result = PanelView.new(newRect(0, 0, 800, 300)) #700
    result.collapsible = true
    let title = newLabel(newRect(22, 6, 108, 15))
    title.textColor = whiteColor()
    title.text = "Animation"
    result.addSubview(title)
    let ae = AnimationEditView.new(newRect(0, result.titleHeight, result.bounds.width, result.contentHeight))
    ae.autoresizingMask = {afFlexibleWidth, afFlexibleHeight}
    e.animationEditView = ae
    result.addSubview(ae)
    ae.moveToBack()

proc newTreeView(e: Editor): PanelView =
    result = PanelView.new(newRect(0, 0, 200, 500)) #700
    result.collapsible = true

    let title = newLabel(newRect(22, 6, 108, 15))
    title.textColor = whiteColor()
    title.text = "Scene"

    result.addSubview(title)

    let outlineView = OutlineView.new(newRect(1, 28, result.bounds.width - 3, result.bounds.height - 60))
    e.outlineView = outlineView
    outlineView.autoresizingMask = { afFlexibleWidth, afFlexibleMaxX }
    outlineView.numberOfChildrenInItem = proc(item: Variant, indexPath: openarray[int]): int =
        if indexPath.len == 0:
            return 1
        else:
            let n = item.get(Node3D)
            if n.children.isNil:
                return 0
            else:
                return n.children.len

    outlineView.childOfItem = proc(item: Variant, indexPath: openarray[int]): Variant =
        if indexPath.len == 1:
            return newVariant(e.rootNode)
        else:
            return newVariant(item.get(Node3D).children[indexPath[^1]])

    outlineView.createCell = proc(): TableViewCell =
        result = newTableViewCell(newLabel(newRect(0, 0, 100, 20)))

    outlineView.configureCell = proc (cell: TableViewCell, indexPath: openarray[int]) =
        let n = outlineView.itemAtIndexPath(indexPath).get(Node3D)
        let textField = TextField(cell.subviews[0])
        if not cell.selected:
            textField.textColor = newGrayColor(0.9)
        else:
            textField.textColor = newGrayColor(0.0)
        textField.text = if n.name.isNil: "(nil)" else: n.name

    outlineView.onSelectionChanged = proc() =
        let ip = outlineView.selectedIndexPath
        let n = if ip.len > 0:
                outlineView.itemAtIndexPath(ip).get(Node3D)
            else:
                nil
        e.selectedNode = n

    outlineView.onDragAndDrop = proc(fromIp, toIp: openarray[int]) =
        let f = outlineView.itemAtIndexPath(fromIp).get(Node3D)
        var tos = @toIp
        tos.setLen(tos.len - 1)
        let t = outlineView.itemAtIndexPath(tos).get(Node3D)
        let toIndex = toIp[^1]
        if f.parent == t:
            let cIndex = t.children.find(f)
            if toIndex < cIndex:
                t.children.delete(cIndex)
                t.children.insert(f, toIndex)
            elif toIndex > cIndex:
                t.children.delete(cIndex)
                t.children.insert(f, toIndex - 1)
        else:
            f.removeFromParent()
            t.insertChild(f, toIndex)
        e.sceneTreeDidChange()

    outlineView.reloadData()

    let outlineScrollView = newScrollView(outlineView)
    outlineScrollView.autoresizingMask = {afFlexibleWidth, afFlexibleHeight}
    result.addSubview(outlineScrollView)

    let createNodeButton = Button.new(newRect(2, result.bounds.height - 20, 20, 20))
    createNodeButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
    createNodeButton.title = "+"
    createNodeButton.onAction do():
        var sip = outlineView.selectedIndexPath
        var n = e.rootNode
        if sip.len == 0:
            sip.add(0)
        else:
            n = outlineView.itemAtIndexPath(sip).get(Node3D)

        outlineView.expandRow(sip)
        discard n.newChild("New Node")
        sip.add(n.children.len - 1)
        e.sceneTreeDidChange()
        outlineView.selectItemAtIndexPath(sip)
    result.addSubview(createNodeButton)

    let deleteNodeButton = Button.new(newRect(24, result.bounds.height - 20, 20, 20))
    deleteNodeButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
    deleteNodeButton.title = "-"
    deleteNodeButton.onAction do():
        if outlineView.selectedIndexPath.len != 0:
            let n = outlineView.itemAtIndexPath(outlineView.selectedIndexPath).get(Node3D)
            n.removeFromParent()
            var sip = outlineView.selectedIndexPath
            sip.delete(sip.len-1)
            outlineView.selectItemAtIndexPath(sip)
            e.sceneTreeDidChange()
    result.addSubview(deleteNodeButton)

    let refreshButton = Button.new(newRect(46, result.bounds.height - 20, 60, 20))
    refreshButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
    refreshButton.title = "Refresh"
    refreshButton.onAction do():
        e.sceneTreeDidChange()
    result.addSubview(refreshButton)

#import tables
proc onTouchDown*(editor: Editor, e: var Event) =
    #TODO Hack to sync node tree and treeView
    editor.outlineView.reloadData()

    if e.keyCode != VirtualKey.MouseButtonPrimary:
        return

    let r = editor.sceneView.rayWithScreenCoords(e.localPosition)
    var castResult = newSeq[RayCastInfo]()
    editor.sceneView.rootNode().rayCast(r, castResult)

    if castResult.len > 0:
        castResult.sort( proc (x, y: RayCastInfo): int =
            result = int(x.node.layer < y.node.layer)
            if x.node.layer == y.node.layer:
                result = int(x.distance > y.distance)
                if abs(x.distance - y.distance) < 0.00001:
                    result = getTreeDistance(x.node, y.node) )

        echo "cast ", castResult[0].node.name
        #work with gizmo
        if castResult[0].node.name.contains("gizmo_axis"):
            let nodeSelector = editor.selectedNode.getComponent(NodeSelector)
            if not nodeSelector.isNil:
                nodeSelector.startTransform(castResult[0].node, e.position)
            return

        # make node select
        var indexPath = newSeq[int]()
        editor.getTreeViewIndexPathForNode(castResult[0].node, indexPath)

        if indexPath.len > 1:
            editor.outlineView.selectItemAtIndexPath(indexPath)
            editor.outlineView.expandBranch(indexPath)


proc onScroll*(editor: Editor, dx, dy: float32, e: var Event) =
    if editor.selectedNode.isNil:
        return

    let nodeSelector = editor.selectedNode.getComponent(NodeSelector)
    if not nodeSelector.isNil:
        nodeSelector.proccesTransform(e.position)

proc onTouchUp*(editor: Editor, e: var Event) =
    if editor.selectedNode.isNil:
        return

    let nodeSelector = editor.selectedNode.getComponent(NodeSelector)
    if not nodeSelector.isNil:
        nodeSelector.stopTransform()

proc newToolbarButton(e: Editor, title: string): Button =
    let f = systemFont()
    let width = f.sizeOfString(title).width
    result = Button.new(newRect(0, 0, width + 20, 20))
    result.title = title
    e.toolbar.addSubview(result)

proc createOpenAndSaveButtons(e: Editor) =
    when loadingAndSavingAvailable:
        e.newToolbarButton("Load").onAction do():
            e.loadNode()

        e.newToolbarButton("Save J").onAction do():
            if e.outlineView.selectedIndexPath.len > 0:
                var selectedNode = e.outlineView.itemAtIndexPath(e.outlineView.selectedIndexPath).get(Node3D)
                if not selectedNode.isNil:
                    e.saveNode(selectedNode)

proc createZoomSelectionButton(e: Editor) =
    e.newToolbarButton("Zoom Selection").onAction do():
        if not e.selectedNode.isNil:
            let cam = e.rootNode.findNode("camera")
            if not cam.isNil:
                e.rootNode.findNode("camera").focusOnNode(e.selectedNode)

proc createToggleAnimationEditorButton(e: Editor) =
    e.newToolbarButton("Animations").onAction do():
        if e.animationEditPanel.window.isNil:
            e.toolbar.window.addSubview(e.animationEditPanel)
        else:
            e.animationEditPanel.removeFromSuperview()

proc createCameraSelector(e: Editor) =
    e.cameraSelector = PopupButton.new(newRect(0, 0, 150, 20))
    e.updateCameraSelector()
    e.toolbar.addSubview(e.cameraSelector)

    e.cameraSelector.onAction do():
        if e.cameraSelector.selectedIndex >= 0:
            let n = e.rootNode.findNode(e.cameraSelector.selectedItem)
            if not n.isNil:
                let cam = n.componentIfAvailable(Camera)
                if not cam.isNil:
                    e.rootNode.sceneView.camera = cam

proc createChangeBackgroundColorButton(e: Editor) =
    var cPicker: ColorPickerView
    let b = e.newToolbarButton("Background Color")
    b.onAction do():
        if cPicker.isNil:
            cPicker = newColorPickerView(newRect(0, 0, 300, 200))
            cPicker.onColorSelected = proc(c: Color) =
                currentContext().gl.clearColor(c.r, c.g, c.b, c.a)
            let popupPoint = b.convertPointToWindow(newPoint(0, b.bounds.height + 5))
            cPicker.setFrameOrigin(popupPoint)
            b.window.addSubview(cPicker)
        else:
            cPicker.removeFromSuperview()
            cPicker = nil

proc onKeyDown(editor: Editor, e: var Event): bool =
    editor.cameraController.onKeyDown(e)
    let cmd = commandFromEvent(e)
    result = true
    case commandFromEvent(e):
    of kcCopy, kcCut:
        let n = editor.mSelectedNode
        if not n.isNil:
            var s = Serializer.new()
            var sData = n.serialize(s)
            let pbi = newPasteboardItem(NodePboardKind, $sData)
            pasteboardWithName(PboardGeneral).write(pbi)
            if cmd == kcCut:
                n.removeFromParent()
                editor.sceneTreeDidChange()
    of kcPaste:
        let pbi = pasteboardWithName(PboardGeneral).read(NodePboardKind)
        if not pbi.isNil:
            let j = parseJson(pbi.data)
            let serializer = Serializer.new()
            let n = newNode()
            n.deserialize(j, serializer)
            if not editor.mSelectedNode.isNil:
                editor.mSelectedNode.addChild(n)
                editor.sceneTreeDidChange()
    of kcDelete:
        let n = editor.mSelectedNode
        if not n.isNil:
            n.removeFromParent()
            editor.sceneTreeDidChange()

    else: result = false

proc onKeyUp(editor: Editor, e: var Event): bool =
    editor.cameraController.onKeyUp(e)
    if e.keyCode == VirtualKey.F:
        editor.cameraController.setToNode(editor.selectedNode)

proc startEditingNodeInView*(n: Node3D, v: View, startFromGame: bool = true): Editor =
    var editor = Editor.new()
    editor.rootNode = n
    editor.sceneView = n.sceneView # Warning!

    const toolbarHeight = 30

    editor.inspector = InspectorView.new(newRect(200, toolbarHeight, 340, 700))

    editor.toolbar = Toolbar.new(newRect(0, 0, 20, toolbarHeight))

    let cam = editor.rootNode.findNode("camera")
    editor.cameraController = newEditorCameraController(cam)

    editor.eventCatchingView = EventCatchingView.new(newRect(0, 0, 1960, 1680))
    let eventListner = editor.eventCatchingView.newEventCatchingListener()
    editor.eventCatchingView.addGestureDetector(newScrollGestureDetector( eventListner ))

    eventListner.tapDownDelegate = proc (event: var Event) =
        editor.onTouchDown(event)
        editor.cameraController.onTapDown(event)
    eventListner.scrollProgressDelegate = proc (dx, dy : float32, e : var Event) =
        editor.onScroll(dx, dy, e)
        editor.cameraController.onScrollProgress(dx, dy, e)
    eventListner.tapUpDelegate = proc ( dx, dy : float32, e : var Event) =
        editor.onTouchUp(e)
        editor.cameraController.onTapUp(dx, dy, e)
    editor.eventCatchingView.mouseScrrollDelegate = proc (event: var Event) =
        editor.cameraController.onMouseScrroll(event)
    editor.eventCatchingView.keyUpDelegate = proc (event: var Event): bool =
        editor.onKeyUp(event)
    editor.eventCatchingView.keyDownDelegate = proc (event: var Event): bool =
        editor.onKeyDown(event)

    v.window.addSubview(editor.eventCatchingView)

    editor.treeView = newTreeView(editor)
    editor.treeView.setFrameOrigin(newPoint(0, toolbarHeight))
    v.window.addSubview(editor.treeView)

    editor.animationEditPanel = newAnimationEditView(editor)
    editor.animationEditPanel.setFrameOrigin(newPoint(0, editor.treeView.frame.maxY))

    editor.createOpenAndSaveButtons()
    editor.createZoomSelectionButton()
    editor.createToggleAnimationEditorButton()
    editor.createCameraSelector()
    editor.createChangeBackgroundColorButton()

    v.window.addSubview(editor.inspector)
    v.window.addSubview(editor.toolbar)

    if startFromGame:
        let closeEditorButton = Button.new(newRect(v.window.bounds.width - 23, 3, 20, 20))
        closeEditorButton.title = "x"
        editor.toolbar.addSubview(closeEditorButton)
        closeEditorButton.onAction do():
            editor.eventCatchingView.removeFromSuperview()
            editor.treeView.removeFromSuperview()
            editor.toolbar.removeFromSuperview()
            editor.inspector.removeFromSuperview()
            closeEditorButton.removeFromSuperview()

    return editor

proc endEditing*(e: Editor) =
    discard
