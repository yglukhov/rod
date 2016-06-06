import math
import algorithm

import nimx.view
import nimx.types
import nimx.button

import node
import panel_view
import outline_view
import inspector_view
import rod_types

import nimx.animation
import nimx.color_picker
import nimx.context
import nimx.portable_gl
import nimx.scroll_view
import nimx.text_field
import nimx.table_view_cell
import nimx.gesture_detector_newtouch

import rod.scene_composition
import rod.component.mesh_component
import rod.component.node_selector
import rod.editor_camera_controller

import ray
import nimx.view_event_handling_new
import viewport

import variant

when defined(js):
    import dom except Event
elif not defined(android) and not defined(ios) and not defined(emscripten):
    import native_dialogs

type EventCatchingView* = ref object of View
    keyUpDelegate*: proc (event: var Event)
    keyDownDelegate*: proc (event: var Event)
    mouseScrrollDelegate*: proc (event: var Event)

type EventCatchingListener = ref object of BaseScrollListener
    view: EventCatchingView

method acceptsFirstResponder(v: EventCatchingView): bool = true

method onKeyUp(v: EventCatchingView, e : var Event): bool =
    echo "editor onKeyUp ", e.keyCode
    if not v.keyUpDelegate.isNil:
        v.keyUpDelegate(e)

method onKeyDown(v: EventCatchingView, e : var Event): bool =
    echo "editor onKeyUp ", e.keyCode
    if not v.keyDownDelegate.isNil:
        v.keyDownDelegate(e)

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
    rootNode*: Node3D
    eventCatchingView*: EventCatchingView
    treeView*: View
    sceneView*: SceneView
    selectedNode*: Node3D
    outlineView*:OutlineView
    cameraController*: EditorCameraController

proc focusOnNode*(cameraNode: node.Node, focusNode: node.Node) =
    let distance = 100.Coord
    cameraNode.translation = newVector3(
        focusNode.translation.x,
        focusNode.translation.y,
        focusNode.translation.z + distance
    )

proc newSettingsView(e: Editor, r: Rect): PanelView =
    result = PanelView.new(r)
    result.collapsible = true

    let title = newLabel(newRect(22, 6, 108, 15))
    title.textColor = whiteColor()
    title.text = "Editor Settings"

    result.addSubview(title)

    var y: Coord = 36
    let bgColorLabel = newLabel(newRect(6, y, 50, 20))
    bgColorLabel.textColor = newGrayColor(0.78)
    bgColorLabel.text = "Background:"

    result.addSubview(bgColorLabel)

    let bgColorButton = newButton(result, newPoint(102, y), newSize(40, 20), "...")
    let pv = result
    var cPicker: ColorPickerView
    bgColorbutton.onAction do():
        if cPicker.isNil:
            cPicker = newColorPickerView(newRect(0, 0, 300, 200))
            cPicker.onColorSelected = proc(c: Color) =
                currentContext().gl.clearColor(c.r, c.g, c.b, c.a)
            cPicker.setFrameOrigin(newPoint(pv.frame.x - 300, pv.frame.y))
            pv.window.addSubview(cPicker)
        else:
            cPicker.removeFromSuperview()
            cPicker = nil

    y += bgColorLabel.frame.height + 6

    let cameraFocusButton = newButton(result, newPoint(6, y), newSize(120, 20), "Zoom Selection")
    y += 26
    cameraFocusButton.onAction do():
        if not e.selectedNode.isNil:
            let cam = e.rootNode.findNode("camera")
            if not cam.isNil:
                e.rootNode.findNode("camera").focusOnNode(e.selectedNode)
    result.addSubview(cameraFocusButton)

proc getTreeViewIndexPathForNode(editor: Editor, n: Node3D, indexPath: var seq[int]) =
    # running up and calculate the path to the node in the tree
    let parent = n.parent
    indexPath.insert(parent.children.find(n), 0)

    # because there is the root node, it's necessary to add 0
    if parent.isNil or parent == editor.rootNode:
        indexPath.insert(0, 0)
        return

    editor.getTreeViewIndexPathForNode(parent, indexPath)

when not defined(js) and not defined(android) and not defined(ios):
    import os
import streams
import json
import tools.serializer
proc saveNode(editor: Editor, selectedNode: Node3D): bool =
    when not defined(js) and not defined(emscripten) and not defined(android) and not defined(ios):
        let path = callDialogFileSave("Save Json")
        if not path.isNil:
            var s = Serializer.new()
            s.save(selectedNode, path)

    return false

proc loadNode(editor: Editor): bool =
    when not defined(js) and not defined(emscripten) and not defined(android) and not defined(ios):
        let path = callDialogFileOpen("Select Json")
        if not path.isNil:
            let ln = newNodeWithResource(path)
            if not editor.selectedNode.isNil:
                editor.selectedNode.addChild(ln)
            else:
                editor.rootNode.addChild(ln)
            return true

    return false

proc newTreeView(e: Editor, inspector: InspectorView): PanelView =
    result = PanelView.new(newRect(0, 0, 200, 600)) #700
    result.collapsible = true

    let title = newLabel(newRect(22, 6, 108, 15))
    title.textColor = whiteColor()
    title.text = "Scene"

    result.addSubview(title)

    let outlineView = OutlineView.new(newRect(1, 28, result.bounds.width - 3, result.bounds.height - 60)) #-40
    e.outlineView = outlineView
    outlineView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
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

        if not n.isNil:
            if not e.selectedNode.isNil and e.selectedNode.componentIfAvailable(LightSource).isNil:
                e.selectedNode.removeComponent(NodeSelector)
                if e.selectedNode != n:
                    e.selectedNode = n
                    discard e.selectedNode.component(NodeSelector)
            else:
                e.selectedNode = n
                discard e.selectedNode.component(NodeSelector)

        inspector.inspectedNode = n

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
        outlineView.reloadData()

    outlineView.reloadData()

    let outlineScrollView = newScrollView(outlineView)
    outlineScrollView.setFrameSize(newSize(outlineScrollView.frame.size.width, outlineScrollView.frame.size.height - 7))
    result.addSubview(outlineScrollView)

    let createNodeButton = Button.new(newRect(2, result.bounds.height - 20, 20, 20))
    # createNodeButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
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
        outlineView.reloadData()
        outlineView.selectItemAtIndexPath(sip)
    result.addSubview(createNodeButton)

    let deleteNodeButton = Button.new(newRect(24, result.bounds.height - 20, 20, 20))
    # deleteNodeButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
    deleteNodeButton.title = "-"
    deleteNodeButton.onAction do():
        if outlineView.selectedIndexPath.len != 0:
            let n = outlineView.itemAtIndexPath(outlineView.selectedIndexPath).get(Node3D)
            n.removeFromParent()
            var sip = outlineView.selectedIndexPath
            sip.delete(sip.len-1)
            outlineView.selectItemAtIndexPath(sip)
            outlineView.reloadData()
    result.addSubview(deleteNodeButton)

    let refreshButton = Button.new(newRect(46, result.bounds.height - 20, 60, 20))
    # refreshButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
    refreshButton.title = "Refresh"
    refreshButton.onAction do():
        outlineView.reloadData()
    result.addSubview(refreshButton)

    when not defined(android) and not defined(ios):
        let loadButton = Button.new(newRect(110, result.bounds.height - 20, 60, 20))
        # loadButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
        loadButton.title = "Load"
        loadButton.onAction do():
            when defined(js):
                alert("Loading is currenlty availble in native version only.")
            elif defined(emscripten):
                discard
            else:
                var sip = outlineView.selectedIndexPath
                var p = e.rootNode
                if sip.len == 0:
                    sip.add(0)
                else:
                    p = outlineView.itemAtIndexPath(sip).get(Node3D)

                outlineView.expandRow(sip)
                let path = callDialogFileOpen("Select file")
                if not isNil(path) and path != "":
                    loadSceneAsync path, proc(n: Node) =
                        p.addChild(n)
                        outlineView.reloadData()
        result.addSubview(loadButton)

        when not defined(js) and not defined(android) and not defined(ios):
            let saveButton = Button.new(newRect(110, result.bounds.height - 40, 60, 20))
            saveButton.title = "Save J"
            saveButton.onAction do():
                if outlineView.selectedIndexPath.len > 0:
                    var selectedNode = outlineView.itemAtIndexPath(outlineView.selectedIndexPath).get(Node3D)
                    if not selectedNode.isNil:
                        discard e.saveNode(selectedNode)
            result.addSubview(saveButton)

            let loadJButton = Button.new(newRect(50, result.bounds.height - 40, 60, 20))
            loadJButton.title = "Load J"
            loadJButton.onAction do():
                discard e.loadNode()
            result.addSubview(loadJButton)

proc onTouch*(editor: Editor, e: var Event) =
    #TODO Hack to sync node tree and treeView
    editor.outlineView.reloadData()

    let r = editor.sceneView.rayWithScreenCoords(e.localPosition)
    var castResult = newSeq[RayCastInfo]()
    editor.sceneView.rootNode().rayCast(r, castResult)

    if castResult.len > 0:
        castResult.sort( proc (x, y: RayCastInfo): int =
            result = int(x.distance > y.distance)
            if abs(x.distance - y.distance) < 0.00001:
                result = getTreeDistance(x.node, y.node) )

        var indexPath = newSeq[int]()
        editor.getTreeViewIndexPathForNode(castResult[0].node, indexPath)

        if indexPath.len > 1:
            editor.outlineView.selectItemAtIndexPath(indexPath)
            editor.outlineView.expandBranch(indexPath)


proc startEditingNodeInView*(n: Node3D, v: View): Editor =
    var editor = Editor.new()
    editor.rootNode = n
    editor.sceneView = n.sceneView # Warning!

    let inspectorView = InspectorView.new(newRect(200, 0, 340, 700))
    let settingsView = editor.newSettingsView(newRect(v.window.bounds.width - 200, v.window.bounds.height - 200, 200, 200))

    let cam = editor.rootNode.findNode("camera")
    editor.cameraController = newEditorCameraController(cam)

    editor.eventCatchingView = EventCatchingView.new(newRect(0, 0, 1960, 1680))
    let eventListner = editor.eventCatchingView.newEventCatchingListener()
    editor.eventCatchingView.addGestureDetector(newScrollGestureDetector( eventListner ))

    eventListner.tapDownDelegate = proc (event: var Event) =
        editor.onTouch(event)
        editor.cameraController.onTapDown(event)
    eventListner.scrollProgressDelegate = proc (dx, dy : float32, e : var Event) =
        editor.cameraController.onScrollProgress(dx, dy, e)
    eventListner.tapUpDelegate = proc ( dx, dy : float32, e : var Event) =
        editor.cameraController.onTapUp(dx, dy, e)
    editor.eventCatchingView.mouseScrrollDelegate = proc (event: var Event) =
        editor.cameraController.onMouseScrroll(event)
    editor.eventCatchingView.keyUpDelegate = proc (event: var Event) =
        editor.cameraController.onKeyUp(event)
        if event.keyCode == VirtualKey.F:
            editor.cameraController.setToNode(editor.selectedNode)
    editor.eventCatchingView.keyDownDelegate = proc (event: var Event) =
        editor.cameraController.onKeyDown(event)

    v.window.addSubview(editor.eventCatchingView)

    editor.treeView = newTreeView(editor, inspectorView)
    v.window.addSubview(editor.treeView)

    v.window.addSubview(inspectorView)
    v.window.addSubview(settingsView)

    let fpsAnimation = newAnimation()
    v.SceneView.addAnimation(fpsAnimation)

    return editor

proc endEditing*(e: Editor) =
    discard
