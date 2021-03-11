import strutils, json, logging, times

import nimx / [ matrixes, button, popup_button, key_commands, animation,
        notification_center, window, view_event_handling ]

import clipboard
import rod_types, node
import rod/scene_composition
import rod / editor / [editor_project_settings, editor_tab_registry,
        editor_workspace_view, editor_types, animation/animation_editor_types]

import rod/utils/json_serializer
export editor_types

export editor_tab_registry

import variant

when loadingAndSavingAvailable:
    import os_files/dialog
    import os


proc `selectedNode=`*(e: Editor, n: Node) =
    if n != e.mSelectedNode:
        e.mSelectedNode = n

        if not e.mCurrentComposition.isNil:
            e.mCurrentComposition.selectedNode = n
            e.mCurrentComposition.owner.setEditedNode(n)

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

proc getEditorTab*[T](e: Editor): T =
    for t in e.workspaceView.tabs:
        if t of T:
            return t.T

proc onCompositionSaved*(e: Editor, c: CompositionDocument) =
    for t in e.workspaceView.compositionEditors:
        t.onCompositionSaved(c)

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

proc onEditModeChanged*(e: Editor, m: EditMode) =
    e.mode = m
    for t in e.workspaceView.tabs:
        t.onEditModeChanged(m)

proc sceneTreeDidChange*(e: Editor) =
    e.updateCameraSelector()

    for t in e.workspaceView.tabs:
        t.onCompositionChanged(e.currentComposition)

proc nodeToJson(n: Node, path: string): JsonNode =
    let s = newJsonSerializer()
    s.url = "file://" & path
    n.serialize(s)
    s.node

when loadingAndSavingAvailable:
    proc relativeUrl*(url: string, base: string): string =
        result = url
        result.removePrefix("file://")
        result = relativePath(result, base).replace("\\", "/")
else:
    proc relativeUrl*(url: string, base: string): string = url

when defined(rodedit):
    proc makeCompositionRefsRelative(e: Editor, n: Node, path: string) =
        var children = n.children
        var nextChildren: seq[Node]

        while children.len > 0:
            nextChildren.setLen(0)
            for ch in children:
                if not ch.composition.isNil:
                    ch.composition.originalUrl = ch.composition.url
                    ch.composition.url = relativeUrl(ch.composition.url, path.parentDir()).replace(".jcomp", "")
                    echo "fix compref ", ch.composition.originalUrl, " >> ", ch.composition.url, " base ", path
                else:
                    nextChildren.add(ch.children)
            children = nextChildren

    proc revertComposotionRef(e: Editor, n: Node) =
        var children = n.children
        var nextChildren: seq[Node]

        while children.len > 0:
            nextChildren.setLen(0)
            for ch in children:
                if not ch.composition.isNil:
                    ch.composition.url = ch.composition.originalUrl
                    ch.composition.originalUrl.setLen(0)
                else:
                    nextChildren.add(ch.children)
            children = nextChildren



when loadingAndSavingAvailable:
    proc currentProjectPath*(e: Editor): string =
        result = e.currentProject.path
        if result.len == 0 or e.startFromGame:
            result = getAppDir() & "/../.."

    proc autosaveDir(e: Editor): string =
        const dir = ".rodedit" / "autosave"
        result = e.currentProjectPath() / dir
        if not dirExists(result):
            createDir(result)

    proc name(c: CompositionDocument): string =
        if c.path.len > 0:
            result = splitFile(c.path).name
        elif not c.rootNode.isnil:
            result = c.rootNode.name

    proc saveComposition*(e: Editor, c: CompositionDocument, saveAs = false, autosave = false): string {.discardable.} =
        var newPath = c.path
        if autosave:
            newPath = e.autosaveDir() / c.name & format(getTime(), "(dd-MM-yy hh-mm-ss)") & ".jcomp"
            info "autosave ", c.name, " to ", newPath

        if not autosave and (c.path.len == 0 or saveAs):
            var di: DialogInfo
            # di.folder = e.currentProject.path
            di.extension = "jcomp"
            di.kind = dkSaveFile
            di.filters = @[(name:"JCOMP", ext:"*.jcomp")]

            di.title = "Save composition" & (if saveAs: " as" else: "")

            newPath = di.show()
        try:
            if newPath.len == 0: return
            when defined(rodedit):
                e.makeCompositionRefsRelative(c.rootNode, newPath)
                var composition = c.rootNode.composition
                if not c.rootNode.composition.isNil:
                    c.rootNode.composition = nil # hack to serialize content

            let data = nodeToJson(c.rootNode, newPath)
            if c.animations.len > 0:
                var janims = newJObject()
                for a in c.animations:
                    janims[a.name] = %a
                data["animations"] = janims
            writeFile(newPath, data.pretty())
            when defined(rodedit):
                e.revertComposotionRef(c.rootNode)
                c.rootNode.composition = composition

            if not autosave:
                c.path = newPath
                c.rootNode.name = c.name
                e.workspaceView.setTabTitle(c.owner, c.name)

                e.onCompositionSaved(c)
            result = newPath
        except:
            error "Can't save composition at ", newPath
            error "Exception caught: ", getCurrentExceptionMsg()
            error "stack trace: ", getCurrentException().getStackTrace()

    proc loadCompositionDocument*(e: Editor, path: string, cb: proc(r: CompositionDocument)) =
        try:
            var p = path
            if p.find("file://") == -1:
                p = "file://" & p

            var comp = newComposition(p)
            comp.loadComposition do():
                let n = comp.node
                var c = new(CompositionDocument)
                c.path = p
                c.path.removePrefix("file://")
                c.rootNode = n

                when defined(rodedit):
                    echo "try parse anims ", not n.isNil

                    if not n.isNil and not n.jAnimations.isNil:
                        for k, v in n.jAnimations:
                            try:
                                var a = n.toEditedAnimation(v)
                                a.name = k
                                c.animations.add(a)
                            except:
                                echo getStackTrace(getCurrentException())
                                echo getCurrentExceptionMsg()
                                echo "failed to parse animation"
                        if c.animations.len > 0:
                            c.currentAnimation = c.animations[0]
                cb(c)
        except:
            error "Can't load composition at ", path
            error "Exception caught: ", getCurrentExceptionMsg()
            error "stack trace: ", getCurrentException().getStackTrace()
            # e.openComposition(path)

    proc openComposition*(e: Editor, p: string) =
        e.loadCompositionDocument(p) do(c: CompositionDocument):
            var c = c
            for tb in e.workspaceView.compositionEditors:
                if tb.composition.path == c.path:
                    c = tb.composition
                    c.rootNode = c.rootNode
                    tb.onCompositionChanged(c)
                    e.workspaceView.selectTab(tb)
                    return

            var tbv = e.workspaceView.createCompositionEditor(c)
            if not tbv.isNil:
                tbv.name = splitFile(c.path).name
                e.workspaceView.addTab(tbv)
                e.workspaceView.selectTab(tbv)

    proc loadCompositionToScene*(e: Editor, p: string, cb: proc(c: CompositionDocument) = nil) =
        e.loadCompositionDocument(p) do(c: CompositionDocument):
            if not e.currentComposition.isNil:
                var p = e.currentComposition.selectedNode
                if p.isNil:
                    p = e.currentComposition.rootNode
                p.addChild(c.rootNode)
                e.currentComposition.owner.onCompositionChanged(e.currentComposition)
                if not cb.isNil:
                    cb(c)
else:
    proc currentProjectPath*(e: Editor): string = discard
    proc saveComposition*(e: Editor, c: CompositionDocument, saveAs = false, autosave = false): string {.discardable.} = discard
    proc openComposition*(e: Editor, p: string) = discard
    proc loadCompositionToScene*(e: Editor, p: string, cb: proc(c: CompositionDocument) = nil) = discard

proc selectNode*(editor: Editor, node: Node) =
    editor.selectedNode = node

proc currentCamera*(e: Editor): Camera =
    if e.cameraSelector.selectedIndex >= 0:
        let n = e.rootNode.findNode(e.cameraSelector.selectedItem)
        if not n.isNil:
            result = n.componentIfAvailable(Camera)

proc endEditing*(e: Editor) =
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
        try:
            let data = $nodeToJson(cn, e.currentProjectPath())
            clipboardWithName(CboardGeneral).writeData(NodePboardKind, cast[seq[byte]](data))
        except:
            echo getCurrentExceptionMsg()
            echo getStackTrace(getCurrentException())

proc cutNode*(e: Editor, n: Node = nil)=
    e.copyNode(n)
    var cn = n
    if n.isNil:
        cn = e.selectedNode

    if not cn.isNil:
        cn.removeFromParent()
        e.sceneTreeDidChange()

proc pasteNode*(e: Editor, n: Node = nil)=
    var data:seq[byte]
    if not clipboardWithName(CboardGeneral).readData(NodePboardKind, data):
        return
    try:
        let j = parseJson(cast[string](data))
        let pn = newNode()
        pn.loadNodeFromJson(j, "file://" & e.currentProjectPath()) do():
            var cn = n
            if cn.isNil:
                cn = e.selectedNode

            if cn.isNil:
                cn = e.rootNode

            cn.addChild(pn)
            e.selectedNode = pn
            e.sceneTreeDidChange()
    except:
        echo getCurrentExceptionMsg()
        echo getStackTrace(getCurrentException())

proc convertToComposition*(e: Editor, n: Node) =
    discard
    var comp = new(CompositionDocument)
    comp.rootNode = n
    let path = e.saveComposition(comp)
    if path.len == 0: return
    if not n.parent.isNil:
        e.selectedNode = n.parent
        n.removeFromParent()
    e.loadCompositionToScene(path) do(c: CompositionDocument):
        c.rootNode.position = n.position
        c.rootNode.scale = n.scale
        c.rootNode.rotation = n.rotation
        c.rootNode.alpha = n.alpha


proc onFirstResponderChanged(e: Editor, fr: View)=
    for t in e.workspaceView.compositionEditors:
        if fr.isDescendantOf(t):
            # echo " Compositioneditor become frist responder " ,t.name
            e.currentComposition = t.composition
            e.sceneView = t.rootNode.sceneView # todo: fix this
            break

proc initNotifHandlers(e: Editor)=
    e.notifCenter = newNotificationCenter()

    e.notifCenter.addObserver(RodEditorNotif_onCompositionSave, e) do(args: Variant):
        when loadingAndSavingAvailable:
            e.saveComposition(e.mCurrentComposition)
        else: discard

    e.notifCenter.addObserver(RodEditorNotif_onCompositionSaveAs, e) do(args: Variant):
        when loadingAndSavingAvailable:
            e.saveComposition(e.mCurrentComposition, saveAs = true)
        else: discard

    e.notifCenter.addObserver(RodEditorNotif_onCompositionOpen, e) do(args: Variant):
        when loadingAndSavingAvailable:
            var di: DialogInfo
            # di.folder = e.currentProject.path
            di.kind = dkOpenFile
            di.filters = @[(name:"JCOMP", ext:"*.jcomp"), (name:"Json", ext:"*.json")]
            di.title = "Open composition"
            let path = di.show()
            if path.len > 0:
                e.openComposition(path)
        else: discard

    e.notifCenter.addObserver(RodEditorNotif_onCompositionAdd, e) do(args: Variant):
        when loadingAndSavingAvailable:
            var di: DialogInfo
            # di.folder = e.currentProject.path
            di.kind = dkOpenFile
            di.filters = @[(name:"JCOMP", ext:"*.jcomp"), (name:"Json", ext:"*.json")]
            di.title = "Open composition"
            let path = di.show()
            if path.len > 0:
                e.loadCompositionToScene(path)
        else: discard

    e.notifCenter.addObserver(RodEditorNotif_onConvertToComp, e) do(args: Variant):
        when loadingAndSavingAvailable:
            e.convertToComposition(e.selectedNode)
        else:
            discard

proc onKeyDown(ed: Editor, e: var Event): bool =
    # echo "editor onKeyDown ", e.keyCode
    case commandFromEvent(e)
    of kcCopy:
        ed.copyNode()
        result = true
    of kcCut:
        ed.cutNode()
        result = true
    of kcPaste:
        ed.pasteNode()
        result = true
    of kcUndo:
        echo "editor undo"
        result = true
    else:
        discard

proc createWorkspace(w: Window, e: Editor): WorkspaceView =
    result = createWorkspaceLayout(w, e)
    result.onKeyDown = proc(ev: var Event): bool =
        e.onKeyDown(ev)

proc startEditorForProject*(w: Window, p: EditorProject): Editor=
    result.new()

    var editor = result
    editor.window = w
    editor.currentProject = p
    editor.currentProject.loadEditorSettings()
    editor.startFromGame = false
    editor.initNotifHandlers()
    editor.workspaceView = createWorkspace(w, editor)

    sharedNotificationCenter().addObserver(NimxFristResponderChangedInWindow, editor) do(args: Variant):
        editor.onFirstResponderChanged(args.get(View))

    var updateAnimation = newAnimation()
    updateAnimation.onAnimate = proc(p: float)=
        if not editor.mSelectedNode.isNil and editor.mSelectedNode.sceneView.isNil:
            # Ingame editor should consider that nodes could be removed by game's logic.
            # Should be done differently when proper "observing" is implemented.
            editor.selectedNode = nil
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
    editor.initNotifHandlers()
    editor.workspaceView = createWorkspace(v.window, editor)

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
import nimx/assets/[asset_loading, json_loading]

registerAssetLoader(["json", "jcomp"]) do(url: string, callback: proc(j: JsonNode)):
    loadJsonFromURL(url, callback)

import rod/editor/editor_default_tabs
