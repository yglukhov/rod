import math, algorithm, strutils, tables, json, logging

import nimx / [ context, portable_gl, matrixes, button, popup_button, font,
                outline_view, color_picker, scroll_view, clip_view,
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
import rod.editor.editor_workspace_view
import rod.editor.editor_types
export editor_types

import tools.serializer

import rod.editor.editor_tab_registry
import ray
import viewport

export editor_tab_registry

import variant

when loadingAndSavingAvailable:
    import native_dialogs
    import rod.editor.editor_open_project_view
    import os

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
        if not e.startFromGame:
            for stv in e.workspaceView.compositionEditors:
                if stv.composition == e.mCurrentComposition:
                    stv.setEditedNode(e.mSelectedNode)
                    break
        else:
            for stv in e.workspaceView.compositionEditors:
                stv.setEditedNode(e.mSelectedNode)

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

proc saveComposition*(e: Editor, c: CompositionDocument)

when loadingAndSavingAvailable:
    proc saveComposition*(e: Editor, c: CompositionDocument)=
        if c.path.len == 0:
            c.path = callDialogFileSave("Save composition")

        if c.path.len > 0:
            var s = Serializer.new()
            var data = c.rootNode.serialize(s)
            echo "data to save ", data.pretty()
            writeFile(c.path, $data)

        echo "try save composition ", c.path

    proc openComposition*(e: Editor, p: string)=
        try:
            var n = newNodeWithUrl("file://" & p)
            var c:CompositionDocument

            for tb in e.workspaceView.compositionEditors:
                if tb.composition.path == p:
                    c = tb.composition
                    c.rootNode = n
                    tb.onCompositionChanged(c)
                    e.workspaceView.selectTab(tb)
                    return

            c = new(CompositionDocument)
            c.path = p
            c.rootNode = n
            var tbv = e.workspaceView.createCompositionEditor(c)
            if not tbv.isNil:
                tbv.name = splitFile(p).name
                e.workspaceView.addTab(tbv)
                e.workspaceView.selectTab(tbv)
        except:
            warn "Can't load composition at ", p

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

else:
    proc saveComposition*(e: Editor, c: CompositionDocument)= discard
    proc openComposition*(e: Editor, p: string) = discard

proc selectNode*(editor: Editor, node: Node) =
    editor.selectedNode = node

proc currentCamera*(e: Editor): Camera =
    if e.cameraSelector.selectedIndex >= 0:
        let n = e.rootNode.findNode(e.cameraSelector.selectedItem)
        if not n.isNil:
            result = n.componentIfAvailable(Camera)

proc createGameInputToggle(e: Editor) =
    let toggle = e.workspaceView.newToolbarButton("Game Input")
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
    discard e.sceneView.makeFirstResponder()

proc createCloseEditorButton(e: Editor, cb: proc()) =
    e.workspaceView.newToolbarButton("x").onAction do():
        e.sceneView.dragDestination = nil
        e.endEditing()
        cb()

proc copyNode*(e: Editor, n: Node = nil)=
    var cn = n
    if n.isNil:
        cn = e.selectedNode

    if not cn.isNil:
        var s = Serializer.new()
        var data = cn.serialize(s)
        let pbi = newPasteboardItem(NodePboardKind, $data)
        pasteboardWithName(PboardGeneral).write(pbi)

proc cutNode*(e: Editor, n: Node = nil)=
    e.copyNode(n)
    var cn = n
    if n.isNil:
        cn = e.selectedNode

    if not cn.isNil:
        cn.removeFromParent()
        e.sceneTreeDidChange()

proc pasteNode*(e: Editor, n: Node = nil)=
    let pbi = pasteboardWithName(PboardGeneral).read(NodePboardKind)
    if not pbi.isNil:
        let j = parseJson(pbi.data)
        let pn = newNode()
        pn.loadComposition(j)

        var cn = n
        if cn.isNil:
            cn = e.selectedNode

        if cn.isNil:
            cn = e.rootNode

        cn.addChild(pn)
        e.sceneTreeDidChange()

proc onFirstResponderChanged(e: Editor, fr: View)=
    for t in e.workspaceView.compositionEditors:
        if fr.isDescendantOf(t):
            # echo " Compositioneditor become frist responder " ,t.name
            e.currentComposition = t.composition
            e.sceneView = t.rootNode.sceneView # todo: fix this
            break

proc startEditorForProject*(w: Window, p: EditorProject): Editor=
    result.new()

    var editor = result
    editor.window = w
    editor.currentProject = p
    editor.startFromGame = false
    editor.workspaceView = createWorkspaceLayout(w, editor)

    sharedNotificationCenter().addObserver(NimxFristResponderChangedInWindow, editor) do(args: Variant):
        editor.onFirstResponderChanged(args.get(View))

    var updateAnimation = newAnimation()
    updateAnimation.onAnimate = proc(p: float)=
        for t in editor.workspaceView.tabs:
            t.update()
        for t in editor.workspaceView.compositionEditors:
            t.update()
    w.addAnimation(updateAnimation)

proc startEditingNodeInView*(n: Node, v: View, startFromGame: bool = true): Editor =
    var editor = new(Editor)
    editor.rootNode = n
    editor.window = v.window
    editor.sceneView = n.sceneView
    editor.sceneView.editing = true
    editor.startFromGame = startFromGame
    editor.workspaceView = createWorkspaceLayout(v.window, editor)

    var updateAnimation = newAnimation()
    updateAnimation.onAnimate = proc(p: float)=
        for t in editor.workspaceView.tabs:
            t.update()
        for t in editor.workspaceView.compositionEditors:
            t.update()
    editor.window.addAnimation(updateAnimation)

    editor.createCloseEditorButton() do():
        updateAnimation.cancel()

    result = editor

# default tabs hacky registering
import rod.editor.editor_default_tabs