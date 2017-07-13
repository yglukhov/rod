import math, algorithm, strutils, tables, json, logging

import nimx / [ context, portable_gl, matrixes, button, popup_button, font,
                outline_view, toolbar, color_picker, scroll_view, clip_view,
                text_field, table_view_cell, gesture_detector, menu,
                key_commands, linear_layout, view_event_handling_new ]

import nimx.editor.tab_view
import nimx.pasteboard.pasteboard

import rod_types, node, inspector_view
import rod.scene_composition
import rod.component.mesh_component
import rod.component.node_selector
import rod.editor_camera_controller
import rod.editor.animation_edit_view
import rod.editor.gizmo_axis
import tools.serializer
import rod.editor.editor_tab
import rod.editor.editor_tree_view

import ray
import viewport

import variant

const NodePboardKind = "io.github.yglukhov.rod.node"

const toolbarHeight = 30
const defaultTabs = ["Inspector", "Tree"]

const loadingAndSavingAvailable = not defined(android) and not defined(ios) and
    not defined(emscripten) and not defined(js)

when loadingAndSavingAvailable:
    import native_dialogs

type
    Editor* = ref object
        rootNode*: Node
        workspaceView: WorkspaceView
        eventCatchingView*: EventCatchingView
        toolbar*: Toolbar
        sceneView*: SceneView
        mSelectedNode: Node
        cameraController*: EditorCameraController
        cameraSelector: PopupButton
        gizmo: GizmoAxis

    WorkspaceView = ref object of View
        editor: Editor
        tabs: seq[EditorTabView]
        anchors: array[4, TabView]
        horizontalLayout: LinearLayout
        verticalLayout: LinearLayout

    EventCatchingView* = ref object of View
        keyDownDelegate*: proc(event: var Event): bool
        keyUpDelegate*: proc(event: var Event): bool
        mouseScrrollDelegate*: proc(event: var Event)
        allowGameInput: bool

    EventCatchingListener = ref object of BaseScrollListener
        view: EventCatchingView

proc newTabView(): TabView

method acceptsFirstResponder(v: EventCatchingView): bool = true

method onKeyUp(v: EventCatchingView, e : var Event): bool =
    if not v.keyUpDelegate.isNil:
        result = v.keyUpDelegate(e)

method onKeyDown(v: EventCatchingView, e : var Event): bool =
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

proc `selectedNode=`*(e: Editor, n: Node) =
    if n != e.mSelectedNode:
        if not e.mSelectedNode.isNil and e.mSelectedNode.componentIfAvailable(LightSource).isNil:
            e.mSelectedNode.removeComponent(NodeSelector)
        e.mSelectedNode = n
        if not e.mSelectedNode.isNil:
            discard e.mSelectedNode.component(NodeSelector)

        for etv in e.workspaceView.tabs:
            etv.editedNode(n)

        e.gizmo.editedNode = e.mSelectedNode

template selectedNode*(e: Editor): Node = e.mSelectedNode

proc focusOnNode*(cameraNode: node.Node, focusNode: node.Node) =
    let distance = 100.Coord
    cameraNode.position = newVector3(
        focusNode.position.x,
        focusNode.position.y,
        focusNode.position.z + distance
    )

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
    e.updateCameraSelector()

    for t in e.workspaceView.tabs:
        t.onSceneChanged()

when loadingAndSavingAvailable:
    import os
    proc saveNode(editor: Editor, selectedNode: Node3D) =
        let path = callDialogFileSave("Save Json")
        if not path.isNil:
            var s = Serializer.new()
            var sData = selectedNode.serialize(s)
            s.save(sData, path)

    proc loadNode(editor: Editor) =
        let path = callDialogFileOpen("Load Json or DAE")
        if not path.isNil:
            try:
                if path.endsWith(".dae"):
                    var p = if not editor.selectedNode.isNil: editor.selectedNode
                            else: editor.rootNode

                    loadSceneAsync path, proc(n: Node) =
                        p.addChild(n)
                        editor.selectedNode = n

                elif path.endsWith(".json"):
                    let ln = newNodeWithURL("file://" & path)
                    if not editor.selectedNode.isNil:
                        editor.selectedNode.addChild(ln)
                    else:
                        editor.rootNode.addChild(ln)

                editor.sceneTreeDidChange()
            except:
                error "ERROR:: Resource at path doesn't load ", path
                error "Exception caught: ", getCurrentExceptionMsg()
                error "stack trace: ", getCurrentException().getStackTrace()

proc selectNode*(editor: Editor, node: Node) =
    for t in editor.workspaceView.tabs:
        t.selectedNode(node)

proc rayCastFirstNode(editor: Editor, node: Node, coords: Point): Node =
    let r = editor.sceneView.rayWithScreenCoords(coords)
    var castResult = newSeq[RayCastInfo]()
    node.rayCast(r, castResult)

    if castResult.len > 0:
        castResult.sort( proc (x, y: RayCastInfo): int =
            result = int(x.node.layer < y.node.layer)
            if x.node.layer == y.node.layer:
                result = int(x.distance > y.distance)
                if abs(x.distance - y.distance) < 0.00001:
                    result = getTreeDistance(x.node, y.node) )

        echo "cast ", castResult[0].node.name
        result = castResult[0].node

proc onTouchDown*(editor: Editor, e: var Event) =
    #TODO Hack to sync node tree and treeView
    for t in editor.workspaceView.tabs:
        t.onEditorTouchDown(e)

    if e.keyCode != VirtualKey.MouseButtonPrimary:
        return

    var castedNode = editor.rayCastFirstNode(editor.gizmo.gizmoNode, e.localPosition)
    if not castedNode.isNil:
        editor.gizmo.startTransform(castedNode, e.localPosition)
        return

    castedNode = editor.rayCastFirstNode(editor.rootNode, e.localPosition)
    if not castedNode.isNil:
        editor.selectNode(castedNode)

proc onScroll*(editor: Editor, dx, dy: float32, e: var Event) =
    if editor.selectedNode.isNil:
        return

    editor.gizmo.proccesTransform(e.localPosition)

proc onTouchUp*(editor: Editor, e: var Event) =
    if editor.selectedNode.isNil:
        return

    editor.gizmo.stopTransform()

proc currentCamera*(e: Editor): Camera =
    if e.cameraSelector.selectedIndex >= 0:
        let n = e.rootNode.findNode(e.cameraSelector.selectedItem)
        if not n.isNil:
            result = n.componentIfAvailable(Camera)

proc newToolbarButton(e: Editor, title: string): Button =
    let f = systemFont()
    let width = f.sizeOfString(title).width
    result = Button.new(newRect(0, 0, width + 20, 20))
    result.title = title
    e.toolbar.addSubview(result)

proc addToolbarMenu(e: Editor, item: MenuItem) =
    let b = e.newToolbarButton(item.title)
    b.onAction() do():
        item.popupAtPoint(b, newPoint(0, 25))

proc createSceneMenu(e: Editor) =
    when loadingAndSavingAvailable:
        let m = makeMenu("Scene"):
            - "Load":
                e.loadNode()
            - "Save":
                if not e.selectedNode.isNil:
                    e.saveNode(e.selectedNode)
        e.addToolbarMenu(m)

proc toggleEditTab(e: Editor, tab:EditViewEntry): proc() =
    result = proc()=
        var tabindex = -1
        var tabview: EditorTabView
        for i, t in e.workspaceView.tabs:
            if t.name == tab.name:
                tabindex = i
                tabview = t
                break

        let frame = e.workspaceView.bounds

        if tabindex >= 0:
            var anchorView: TabView
            var anchorIndex = -1

            for i, av in e.workspaceView.anchors:
                if not av.isNil and av.tabIndex(tab.name) >= 0:
                    anchorIndex = i
                    anchorView = av
                    break

            if not anchorView.isNil:
                let edtabi = anchorView.tabIndex(tab.name)
                if edtabi >= 0:
                    anchorView.removeTab(edtabi)
                    if anchorView.tabsCount == 0:
                        anchorView.removeFromSuperview()
                        e.workspaceView.anchors[anchorIndex] = nil

            e.workspaceView.tabs.delete(tabindex)
        else:
            tabview = tab.create()

            var anchor = tabview.tabAnchor()
            var size = tabview.tabSize(frame)
            tabview.rootNode = e.rootNode
            if tab.name == "Tree": ## todo: replace on notifications
                tabview.EditorTreeView.onNodeSelected = proc(n: Node)=
                    e.selectedNode = n

                tabview.EditorTreeView.onTreeChanged do():
                    e.sceneTreeDidChange()

            tabview.init(newRect(newPoint(0.0, 0.0), size))
            tabview.editedNode(e.selectedNode)
            var anchorView = e.workspaceView.anchors[anchor.int]
            if anchorView.isNil or anchorView.tabsCount == 0:
                var tb = newTabView()
                anchorView = tb
                let horl = e.workspaceView.horizontalLayout
                let verl = e.workspaceView.verticalLayout
                case anchor:
                of etaLeft:
                    let dps = horl.dividerPositions()
                    horl.insertSubview(anchorView, 0)
                    horl.setDividerPosition(size.width, 0)
                    if dps.len > 0:
                        horl.setDividerPosition(dps[0], dps.len)

                of etaRight:
                    let dps = horl.dividerPositions()
                    horl.addSubview(anchorView)
                    horl.setDividerPosition(frame.width - size.width, dps.len)
                of etaBottom:
                    verl.addSubview(anchorView)
                    verl.setDividerPosition(frame.height - size.height, 0)
                else:
                    discard
                e.workspaceView.anchors[anchor.int] = anchorView

            anchorView.addTab(tab.name, tabview)
            e.workspaceView.tabs.add(tabview)

proc createTabView(e: Editor)=
    var m = newMenuItem("Tabs")
    m.children = @[]
    for rv in registeredEditorTabs():
        var rmi = newMenuItem(rv.name)
        rmi.action = e.toggleEditTab(rv)
        m.children.add(rmi)

    e.addToolbarMenu(m)

proc createViewMenu(e: Editor) =
    when loadingAndSavingAvailable:
        let m = makeMenu("View"):
            - "Zoom on Selection":
                if not e.selectedNode.isNil:
                    let cam = e.rootNode.findNode("camera")
                    if not cam.isNil:
                        e.rootNode.findNode("camera").focusOnNode(e.selectedNode)
            - "-"
            - "2D":
                let cam = e.currentCamera()
                if not cam.isNil: cam.projectionMode = cpOrtho
            - "3D":
                let cam = e.currentCamera()
                if not cam.isNil: cam.projectionMode = cpPerspective

        e.addToolbarMenu(m)

proc createGameInputToggle(e: Editor) =
    let toggle = e.newToolbarButton("Game Input")
    toggle.behavior = bbToggle
    toggle.onAction do():
        e.eventCatchingView.allowGameInput = (toggle.value == 1)
    toggle.value = if e.eventCatchingView.allowGameInput: 1 else: 0

proc createCameraSelector(e: Editor) =
    e.cameraSelector = PopupButton.new(newRect(0, 0, 150, 20))
    e.updateCameraSelector()
    e.toolbar.addSubview(e.cameraSelector)

    e.cameraSelector.onAction do():
        let cam = e.currentCamera()
        if not cam.isNil:
            e.rootNode.sceneView.camera = cam
            e.cameraController.setCamera(cam.node)

proc createChangeBackgroundColorButton(e: Editor) =
    var cPicker: ColorPickerView
    let b = e.newToolbarButton("Background Color")
    b.onAction do():
        if cPicker.isNil:
            cPicker = newColorPickerView(newRect(0, 0, 300, 200))
            cPicker.onColorSelected = proc(c: Color) =
                e.sceneView.backgroundColor = c
            let popupPoint = b.convertPointToWindow(newPoint(0, b.bounds.height + 5))
            cPicker.setFrameOrigin(popupPoint)
            b.window.addSubview(cPicker)
        else:
            cPicker.removeFromSuperview()
            cPicker = nil

proc endEditing*(e: Editor) =
    if not e.selectedNode.isNil:
        let nodeSelector = e.selectedNode.getComponent(NodeSelector)
        if not nodeSelector.isNil:
            e.selectedNode.removeComponent(NodeSelector)

    e.gizmo.gizmoNode.nodeWillBeRemovedFromSceneView()
    e.sceneView.afterDrawProc = nil
    e.gizmo = nil
    e.sceneView.removeFromSuperview()
    e.sceneView.setFrame(e.workspaceView.frame)
    let rootEditorView = e.workspaceView.superview
    rootEditorView.replaceSubview(e.workspaceView, e.sceneView)
    e.sceneView.editing = false

proc createCloseEditorButton(e: Editor) =
    e.newToolbarButton("x").onAction do():
        e.endEditing()

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
            let n = newNode()
            n.loadComposition(j)
            if not editor.mSelectedNode.isNil:
                editor.mSelectedNode.addChild(n)
                editor.sceneTreeDidChange()
    of kcDelete:
        let n = editor.mSelectedNode
        if not n.isNil:
            n.removeFromParent()
            editor.mSelectedNode = nil
            editor.sceneTreeDidChange()

    else: result = false

proc onKeyUp(editor: Editor, e: var Event): bool =
    editor.cameraController.onKeyUp(e)
    if e.keyCode == VirtualKey.F:
        editor.cameraController.setToNode(editor.selectedNode)

method onKeyDown(v: WorkspaceView, e: var Event): bool = v.editor.onKeyDown(e)
method onKeyUp(v: WorkspaceView, e: var Event): bool = v.editor.onKeyUp(e)

proc newTabView(): TabView =
    result = TabView.new(newRect(0, 0, 100, 100))
    result.dockingTabs = true
    result.userConfigurable = true

proc createWorkspaceLayout(e: Editor) =
    let v = WorkspaceView.new(e.sceneView.frame)
    v.editor = e
    v.tabs = @[]

    e.workspaceView = v
    v.autoresizingMask = e.sceneView.autoresizingMask

    let s = newTabView()
    let sceneClipView = ClipView.new(zeroRect)
    s.addTab("Scene", sceneClipView)

    v.verticalLayout = newVerticalLayout(newRect(0, toolbarHeight, v.bounds.width, v.bounds.height - toolbarHeight))
    v.verticalLayout.userResizeable = true
    v.horizontalLayout = newHorizontalLayout(newRect(0, 0, 800, 200))
    v.horizontalLayout.userResizeable = true
    v.horizontalLayout.resizingMask = "wh"
    v.verticalLayout.resizingMask = "wh"
    v.horizontalLayout.addSubview(s)

    v.addSubview(e.toolbar)

    v.verticalLayout.addSubview(v.horizontalLayout)
    v.addSubview(v.verticalLayout)
    v.anchors[etaCenter.int] = s
    e.sceneView.editing = true

    let rootEditorView = e.sceneView.superview
    rootEditorView.replaceSubview(e.sceneView, v)
    e.sceneView.setFrame(sceneClipView.bounds)
    e.eventCatchingView.setFrame(sceneClipView.bounds)
    sceneClipView.addSubview(e.sceneView)
    sceneClipView.addSubview(e.eventCatchingView)

    for rt in registeredEditorTabs():
        if rt.name in defaultTabs:
            e.toggleEditTab(rt)()

method onTouchEv*(v: EventCatchingView, e: var Event): bool =
    if not v.allowGameInput:
        result = procCall v.View.onTouchEv(e)

proc createEventCatchingView(e: Editor) =
    e.eventCatchingView = EventCatchingView.new(newRect(0, 0, 1960, 1680))
    e.eventCatchingView.resizingMask = "wh"
    #e.eventCatchingView.backgroundColor = newColor(1, 0, 0)
    let eventListener = e.eventCatchingView.newEventCatchingListener()
    e.eventCatchingView.addGestureDetector(newScrollGestureDetector(eventListener))

    eventListener.tapDownDelegate = proc(evt: var Event) =
        e.onTouchDown(evt)
        e.cameraController.onTapDown(evt)
    eventListener.scrollProgressDelegate = proc(dx, dy: float32, evt: var Event) =
        e.onScroll(dx, dy, evt)
        e.cameraController.onScrollProgress(dx, dy, evt)
    eventListener.tapUpDelegate = proc(dx, dy: float32, evt: var Event) =
        e.onTouchUp(evt)
        e.cameraController.onTapUp(dx, dy, evt)
    e.eventCatchingView.mouseScrrollDelegate = proc(evt: var Event) =
        e.cameraController.onMouseScrroll(evt)
    e.eventCatchingView.keyUpDelegate = proc(evt: var Event): bool =
        e.onKeyUp(evt)
    e.eventCatchingView.keyDownDelegate = proc(evt: var Event): bool =
        e.onKeyDown(evt)

proc startEditingNodeInView*(n: Node3D, v: View, startFromGame: bool = true): Editor =
    let editor = Editor.new()
    editor.rootNode = n
    editor.sceneView = n.sceneView

    # Create widgets and stuff
    editor.toolbar = Toolbar.new(newRect(0, 0, 20, toolbarHeight))
    editor.cameraController = newEditorCameraController(editor.sceneView)
    editor.createEventCatchingView()

    # Toolbar buttons
    editor.createSceneMenu()
    editor.createViewMenu()
    editor.createTabView()
    editor.createGameInputToggle()
    editor.createCameraSelector()
    editor.createChangeBackgroundColorButton()
    if startFromGame:
        editor.createCloseEditorButton()

    editor.createWorkspaceLayout()

    editor.gizmo = newGizmoAxis()
    editor.gizmo.gizmoNode.nodeWasAddedToSceneView(editor.sceneView)
    editor.sceneView.afterDrawProc = proc() =
        currentContext().gl.clearDepthStencil()
        editor.gizmo.updateGizmo()
        editor.gizmo.gizmoNode.drawNode(true, nil)

    return editor
