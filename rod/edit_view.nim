import math, algorithm, strutils, tables, json, logging

import nimx / [ context, portable_gl, matrixes, button, popup_button, font,
                outline_view, toolbar, color_picker, scroll_view, clip_view,
                text_field, table_view_cell, gesture_detector, menu,
                key_commands, linear_layout, view_event_handling_new,
                mini_profiler, drag_and_drop, image, notification_center,
                animation, window ]

import nimx.editor.tab_view
import nimx.pasteboard.pasteboard
import rod_types, node
import rod.scene_composition
import rod.component.mesh_component
import rod.component.node_selector
import rod.component.sprite
import rod.editor.editor_project_settings

import tools.serializer

import rod.editor.editor_tab_registry
import ray
import viewport

export editor_tab_registry

import variant

const NodePboardKind = "io.github.yglukhov.rod.node"

const toolbarHeight = 30
const defaultTabs = ["Inspector", "Tree"]

const loadingAndSavingAvailable* = not defined(android) and not defined(ios) and
    not defined(emscripten) and not defined(js)

when loadingAndSavingAvailable:
    import native_dialogs
    import rod.editor.editor_open_project_view

const rodPbComposition* = "rod.composition"
const rodPbSprite* = "rod.sprite"
const rodPbFiles* = "rod.files"

type
    EditorTabAnchor* = enum
        etaLeft
        etaRight
        etaBottom
        etaCenter

    EditorTabView* = ref object of View
        rootNode*: Node
        editor*: Editor
        composition*: CompositionDocument

    CompositionDocument* = ref object
        path*: string
        rootNode*: Node
        selectedNode*: Node
        owner*: EditorTabView

    Editor* = ref object
        currentProject*: EditorProject
        compositionEditors*: seq[EditorTabView]
        mCurrentComposition: CompositionDocument
        rootNode*: Node
        sceneView*: SceneView
        window*: Window
        mSelectedNode: Node
        startFromGame*: bool
        workspaceView: WorkspaceView
        cameraSelector: PopupButton

    WorkspaceView* = ref object of View
        editor*: Editor
        toolbar*: Toolbar
        tabs*: seq[EditorTabView]
        anchors*: array[4, TabView]
        horizontalLayout*: LinearLayout
        verticalLayout*: LinearLayout

method setEditedNode*(v: EditorTabView, n: Node) {.base.}=
    discard

method update*(v: EditorTabView) {.base.}= discard

method tabSize*(v: EditorTabView, bounds: Rect): Size {.base.}=
    result = bounds.size

method tabAnchor*(v: EditorTabView): EditorTabAnchor {.base.}=
    result = etaCenter

method onEditorTouchDown*(v: EditorTabView, e: var Event) {.base.}=
    discard

method onSceneChanged*(v: EditorTabView) {.base, deprecated.}=
    discard

method onCompositionChanged*(v: EditorTabView, comp: CompositionDocument) {.base.}=
    discard

proc newTabView(e: Editor): TabView

proc `selectedNode=`*(e: Editor, n: Node) =
    if n != e.mSelectedNode:
        if not e.mSelectedNode.isNil and e.mSelectedNode.componentIfAvailable(LightSource).isNil:
            e.mSelectedNode.removeComponent(NodeSelector)
        e.mSelectedNode = n

        if not e.mCurrentComposition.isNil:
            e.mCurrentComposition.selectedNode = n
            e.mCurrentComposition.owner.setEditedNode(n)

        if not e.mSelectedNode.isNil:
            discard e.mSelectedNode.component(NodeSelector)

        for etv in e.workspaceView.tabs:
            etv.setEditedNode(e.mSelectedNode)


template selectedNode*(e: Editor): Node = e.mSelectedNode

proc onCompositionChanged*(e: Editor, c: CompositionDocument)=
    for etv in e.workspaceView.tabs:
        etv.onCompositionChanged(c)

proc `currentComposition=`*(e: Editor, c: CompositionDocument)=
    if e.mCurrentComposition != c:
        e.mCurrentComposition = c
        e.onCompositionChanged(c)

template currentComposition*(e: Editor): CompositionDocument = e.mCurrentComposition

# todo: mb move to editor_scene_view
proc focusOnNode*(cameraNode: node.Node, focusNode: node.Node) =
    let distance = 100.Coord
    cameraNode.position = newVector3(
        focusNode.position.x,
        focusNode.position.y,
        focusNode.position.z + distance
    )

proc updateCameraSelector(e: Editor) = discard #todo: fix this!
    # var items = newSeq[string]()
    # var i = 0
    # var selectedIndex = -1
    # discard e.rootNode.findNode() do(n: Node) -> bool:
    #     let cam = n.componentIfAvailable(Camera)
    #     if not cam.isNil:
    #         if not n.name.isNil:
    #             if cam == n.sceneView.camera:
    #                 selectedIndex = i
    #             items.add(n.name)
    #             inc i
    # e.cameraSelector.items = items
    # e.cameraSelector.selectedIndex = selectedIndex

proc sceneTreeDidChange*(e: Editor) =
    e.updateCameraSelector()

    for t in e.workspaceView.tabs:
        t.onSceneChanged()

when loadingAndSavingAvailable:
    import os
    proc saveNode(editor: Editor, selectedNode: Node) =
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
    editor.selectedNode = node

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
    e.workspaceView.toolbar.addSubview(result)

proc addToolbarMenu(e: Editor, item: MenuItem) =
    let b = e.newToolbarButton(item.title)
    b.onAction() do():
        item.popupAtPoint(b, newPoint(0, 25))

proc createCompositionEditor*(e: Editor, c: CompositionDocument = nil): EditorTabView=
    var rt: EditViewEntry
    var found = false
    for t in registeredEditorTabs():
        if t.name == RodInternalTab & "/Scene":
            rt = t
            found = true
            break

    if not found:
        warn "Can't create ", RodInternalTab & "/Scene", " tab!"
        return

    var tabView = rt.create().EditorTabView
    tabView.editor = e
    var comp: CompositionDocument
    if not c.isNil:
        var compRoot = c.rootNode
        if compRoot.isNil:
            compRoot = newNodeWithUrl("file://"&c.path)
            c.rootNode = compRoot

        tabview.rootNode = compRoot
        comp = c
    else:
        comp = new(CompositionDocument)
        comp.rootNode = newNode("(root)")
        tabView.rootNode = comp.rootNode

    comp.owner = tabView

    let frame = e.workspaceView.bounds
    var size = tabview.tabSize(frame)

    tabview.init(newRect(newPoint(0.0, 0.0), size))
    tabview.composition = comp
    e.compositionEditors.add(tabView)

    result = tabView

proc createSceneMenu(e: Editor) =
    when loadingAndSavingAvailable:
        let m = makeMenu("Scene"):
            - "New":
                var sceneEdit = e.createCompositionEditor()
                if not sceneEdit.isNil:
                    var anchor = sceneEdit.tabAnchor()
                    e.workspaceView.anchors[anchor.int].addTab("new composition", sceneEdit)

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
            tabview = tab.create().EditorTabView
            tabview.editor = e

            var anchor = tabview.tabAnchor()
            var size = tabview.tabSize(frame)
            tabview.rootNode = e.rootNode

            tabview.init(newRect(newPoint(0.0, 0.0), size))
            tabview.setEditedNode(e.selectedNode)
            var anchorView = e.workspaceView.anchors[anchor.int]
            if anchorView.isNil or anchorView.tabsCount == 0:
                var tb = e.newTabView()
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
    var toolBarMenus = newSeq[MenuItem]()
    var defMenu = newMenuItem("Tabs")
    defMenu.children = @[]
    toolBarMenus.add(defMenu)

    for rv in registeredEditorTabs():
        var spname = rv.name.split("/")
        if spname.len > 1:
            if spname[0] != RodInternalTab:
                var parentMenu: MenuItem
                var levelMenus = toolBarMenus
                for pi in 0 ..< spname.len:
                    var cm: MenuItem
                    for m in levelMenus:
                        if m.title == spname[pi]:
                            levelMenus = m.children
                            cm = m
                            break

                    if cm.isNil:
                        cm = newMenuItem(spname[pi])
                        if pi == spname.len - 1:
                            cm.action = e.toggleEditTab(rv)
                        else:
                            if pi == 0:
                                toolBarMenus.add(cm)
                            cm.children = @[]

                        if not parentMenu.isNil:
                            parentMenu.children.add(cm)

                    parentMenu = cm
                    levelMenus = cm.children
        else:
            var rmi = newMenuItem(rv.name)
            rmi.action = e.toggleEditTab(rv)
            defMenu.children.add(rmi)

    for m in toolBarMenus:
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
            - "Profiler":
                sharedProfiler().enabled = not sharedProfiler().enabled

        e.addToolbarMenu(m)

proc createWorkspaceLayout(e: Editor)

proc createProjectMenu(e: Editor) =
    let m = makeMenu("Project"):
        - "Open":
            var openProj = new(EditorOpenProjectView)
            openProj.init(e.workspaceView.bounds)
            e.workspaceView.addSubview(openProj)

            openProj.onOpen = proc(p: EditorProject)=
                openProj.removeFromSuperview()
                e.currentProject = p
                e.workspaceView.removeFromSuperview()
                e.createWorkspaceLayout()

                echo "try open project ", p

            openProj.onClose = proc()=
                openProj.removeFromSuperview()

        - "Save":
            if e.currentProject.path.len == 0:
                echo "not saved project"

            e.currentProject.tabs = @[]
            for t in e.workspaceView.tabs:
                e.currentProject.tabs.add((name:t.name, frame: zeroRect))
            e.currentProject.saveProject()

    e.addToolbarMenu(m)

proc createGameInputToggle(e: Editor) =
    let toggle = e.newToolbarButton("Game Input")
    toggle.behavior = bbToggle
    #todo: fix this!!!
    # toggle.onAction do():
    #     e.eventCatchingView.allowGameInput = (toggle.value == 1)
    # toggle.value = if e.eventCatchingView.allowGameInput: 1 else: 0

proc createCameraSelector(e: Editor) =
    e.cameraSelector = PopupButton.new(newRect(0, 0, 150, 20))
    e.updateCameraSelector()
    e.workspaceView.toolbar.addSubview(e.cameraSelector)

    e.cameraSelector.onAction do():
        let cam = e.currentCamera()
        if not cam.isNil:
            e.rootNode.sceneView.camera = cam
            # e.cameraController.setCamera(cam.node)

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

    e.sceneView.afterDrawProc = nil
    e.sceneView.removeFromSuperview()
    e.sceneView.setFrame(e.workspaceView.frame)

    if e.startFromGame:
        let rootEditorView = e.workspaceView.superview
        rootEditorView.replaceSubview(e.workspaceView, e.sceneView)

    e.sceneView.editing = false

proc createCloseEditorButton(e: Editor, cb: proc()) =
    e.newToolbarButton("x").onAction do():
        e.sceneView.dragDestination = nil
        e.endEditing()
        cb()

#todo: replace this with copyNode, pasteNode, cutNode
# proc onKeyDown(editor: Editor, e: var Event): bool =
#     editor.cameraController.onKeyDown(e)
#     let cmd = commandFromEvent(e)
#     result = false
#     case commandFromEvent(e):
#     of kcCopy, kcCut:
#         let n = editor.mSelectedNode
#         if not n.isNil:
#             var s = Serializer.new()
#             var sData = n.serialize(s)
#             let pbi = newPasteboardItem(NodePboardKind, $sData)
#             pasteboardWithName(PboardGeneral).write(pbi)
#             if cmd == kcCut:
#                 n.removeFromParent()
#                 editor.sceneTreeDidChange()
#             result = true

#     of kcPaste:
#         let pbi = pasteboardWithName(PboardGeneral).read(NodePboardKind)
#         if not pbi.isNil:
#             let j = parseJson(pbi.data)
#             let n = newNode()
#             n.loadComposition(j)
#             if not editor.mSelectedNode.isNil:
#                 editor.mSelectedNode.addChild(n)
#                 editor.sceneTreeDidChange()
#             result = true
#     else: result = false

# proc onKeyUp(editor: Editor, e: var Event): bool =
#     editor.cameraController.onKeyUp(e)
#     if e.keyCode == VirtualKey.F:
#         editor.cameraController.setToNode(editor.selectedNode)

proc newTabView(e: Editor): TabView =
    result = TabView.new(newRect(0, 0, 100, 100))
    result.dockingTabs = true
    result.userConfigurable = true

proc createWorkspaceLayout(e: Editor) =
    let v = WorkspaceView.new(e.window.bounds)
    v.editor = e
    v.tabs = @[]
    e.workspaceView = v
    v.autoresizingMask = {afFlexibleWidth, afFlexibleHeight}

    let s = e.newTabView()

    v.toolbar = Toolbar.new(newRect(0, 0, 20, toolbarHeight))
    v.toolbar.userResizeable = false

    v.verticalLayout = newVerticalLayout(newRect(0, toolbarHeight, v.bounds.width, v.bounds.height - toolbarHeight))
    v.verticalLayout.userResizeable = true
    v.horizontalLayout = newHorizontalLayout(newRect(0, 0, 800, 200))
    v.horizontalLayout.userResizeable = true
    v.horizontalLayout.resizingMask = "wh"
    v.verticalLayout.resizingMask = "wh"
    v.horizontalLayout.addSubview(s)

    v.addSubview(v.toolbar)

    v.verticalLayout.addSubview(v.horizontalLayout)
    v.addSubview(v.verticalLayout)
    v.anchors[etaCenter.int] = s

    when loadingAndSavingAvailable:
        e.createProjectMenu()

    if e.startFromGame and not e.rootNode.isNil:
        let rootEditorView = e.sceneView.superview
        rootEditorView.replaceSubview(e.sceneView, v)

        var comp = new(CompositionDocument)
        comp.rootNode = e.rootNode

        var compTab = e.createCompositionEditor(comp)
        if not compTab.isNil:
            var anchor = compTab.tabAnchor()
            e.workspaceView.anchors[anchor.int].addTab(e.rootNode.name, compTab)

    else:
        var compTab = e.createCompositionEditor()
        if not compTab.isNil:
            var anchor = compTab.tabAnchor()
            e.workspaceView.anchors[anchor.int].addTab("new composition", compTab)
            e.rootNode = compTab.rootNode

        e.window.addSubview(v)

    if e.currentProject.tabs.isNil:
        for rt in registeredEditorTabs():
            if rt.name in defaultTabs:
                e.toggleEditTab(rt)()
    else:
        for rt in registeredEditorTabs():
            for st in e.currentProject.tabs:
                if st.name == rt.name:
                    e.toggleEditTab(rt)()
                    break

    e.createSceneMenu()
    e.createViewMenu()
    e.createTabView()
    e.createGameInputToggle()
    # e.createCameraSelector() #todo: fix this!
    e.createChangeBackgroundColorButton()

proc onFirstResponderChanged(e: Editor, fr: View)=
    for t in e.compositionEditors:
        if fr.isDescendantOf(t):
            echo " Compositioneditor become frist responder " ,t.name
            e.currentComposition = t.composition
            e.sceneView = t.rootNode.sceneView # todo: fix this
            break

proc startEditorForProject*(w: Window, p: EditorProject): Editor=
    result.new()

    var editor = result
    editor.window = w
    editor.currentProject = p
    editor.compositionEditors = @[]
    editor.startFromGame = false
    editor.createWorkspaceLayout()

    sharedNotificationCenter().addObserver(NimxFristResponderChangedInWindow, editor) do(args: Variant):
        editor.onFirstResponderChanged(args.get(View))

    w.setNeedsDisplay()
    var updateAnimation = newAnimation()
    updateAnimation.onAnimate = proc(p: float)=
        for t in editor.workspaceView.tabs:
            t.update()
        for t in editor.compositionEditors:
            t.update()
    w.addAnimation(updateAnimation)

proc startEditingNodeInView*(editor: Editor, n: Node, v: View, startFromGame: bool = true)=
    editor.rootNode = n
    editor.window = v.window
    editor.sceneView = n.sceneView
    editor.sceneView.editing = true

    editor.startFromGame = startFromGame
    editor.createWorkspaceLayout()

    var updateAnimation = newAnimation()
    updateAnimation.onAnimate = proc(p: float)=
        for t in editor.workspaceView.tabs:
            t.update()
        for t in editor.compositionEditors:
            t.update()
    editor.window.addAnimation(updateAnimation)

    if startFromGame:
        editor.createCloseEditorButton() do():
            updateAnimation.cancel()

proc startEditingNodeInView*(n: Node, v: View, startFromGame: bool = true): Editor =
    result.new()
    result.compositionEditors = @[]
    result.startEditingNodeInView(n, v, startFromGame)

# default tabs hacky registering
import rod.editor.editor_default_tabs
