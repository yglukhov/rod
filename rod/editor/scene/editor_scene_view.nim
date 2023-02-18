import nimx / [ types, view, event, view_event_handling, portable_gl, context,
    pasteboard/pasteboard, assets/asset_loading, image, matrixes, clip_view, timer ]

import rod / editor / scene / [gizmo, gizmo_move, node_selector, editor_camera_controller]
import rod / editor / scene / components / [ grid, editor_component, viewport_rect ]
import rod / [ node, rod_types, edit_view, viewport, tools/debug_draw]
import rod / component / [ sprite, camera ]
import os, strutils
import logging

type
    EditorDropDelegate* = ref object of DragDestinationDelegate

    EditorSceneView* = ref object of EditorTabView
        gizmo: Gizmo
        selectedNode: Node
        nodeSelector: NodeSelector
        sceneView: SceneView
        cameraController: EditorCameraController
        startPoint: Point
        autosaveTimer: Timer

method onKeyDown*(v: EditorSceneView, e: var Event): bool =
    result = procCall v.View.onKeyDown(e)
    ## camera controller buttons

    if e.keyCode in [ VirtualKey.R, VirtualKey.S, VirtualKey.F ]:
        result = true
    v.cameraController.onKeyDown(e)
    if e.keyCode == VirtualKey.F:
        v.cameraController.setToNode(v.composition.selectedNode)
        result = true
    elif e.keyCode == VirtualKey.S and e.modifiers.anyCtrl():
        v.editor.saveComposition(v.composition)
        result = true

method onKeyUp*(v: EditorSceneView, e: var Event): bool =
    result = procCall v.View.onKeyDown(e)
    v.cameraController.onKeyUp(e)

method onScroll*(v: EditorSceneView, e: var Event): bool=
    if not v.editor.sceneInput:
        v.cameraController.onMouseScrroll(e)
        return true

proc tryRayCast(v: EditorSceneView, e: var Event): Node=
    result = v.sceneView.rayCastFirstNode(v.rootNode, e.localPosition)

method onMouseOver*(v: EditorSceneView, e: var Event) =
    v.gizmo.onMouseOver(e)

method onInterceptTouchEv*(v: EditorSceneView, e: var Event): bool  = not v.editor.sceneInput

method onTouchEv*(v: EditorSceneView, e: var Event): bool =
    result = procCall v.View.onTouchEv(e)
    let gizmoTouch = v.gizmo.onTouchEv(e)
    case e.buttonState:
    of bsUp:
        v.cameraController.onTapUp(0.0,0.0,e)
    of bsDown:
        v.startPoint = e.localPosition
        v.cameraController.onTapDown(e)

        if e.keyCode != VirtualKey.MouseButtonPrimary: return true

        if not gizmoTouch:
            var castedNode = v.tryRayCast(e)
            if not castedNode.isNil:
                when defined(rodedit):
                    echo "castedNode ", castedNode.name
                    while castedNode != v.composition.rootNode and not castedNode.composition.isNil:
                        castedNode = castedNode.parent
                        echo "\t ", castedNode.name
                v.editor.selectedNode = castedNode
            else:
                v.editor.selectedNode = nil

    of bsUnknown:
        var dx = e.localPosition.x - v.startPoint.x
        var dy = e.localPosition.y - v.startPoint.y
        v.cameraController.onScrollProgress(dx, dy, e)

    return v.makeFirstResponder()


proc updateGizmo(v: EditorSceneView)=
    if v.gizmo.isNil:
        v.gizmo = newMoveGizmo()
        v.gizmo.gizmoNode.nodeWasAddedToSceneView(v.sceneView)
    v.gizmo.updateGizmo()
    v.gizmo.gizmoNode.drawNode(true)

method init*(v: EditorSceneView, r: Rect)=
    procCall v.View.init(r)
    v.dragDestination = new(EditorDropDelegate)

    var clipView = new(ClipView, newRect(0,0,r.width, r.height))
    clipView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    v.nodeSelector = newNodeSelector()

    if not v.editor.startFromGame:

        let editView = SceneView.new(newRect(0,0,r.width, r.height))
        editView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }

        editView.rootNode = newNode(EditorRootNodeName)
        let gc = editView.rootNode.component(EditorGrid)

        editView.editing = true

        for camSettings in v.editor.currentProject.editorCameras:
            let camNode = editView.rootNode.newChild(camSettings.name)
            let cam = camNode.component(Camera)
            cam.viewportSize = camSettings.viewportSize
            cam.projectionMode = camSettings.projectionMode

            if cam.projectionMode == cpOrtho:
                camNode.scale = newVector3(1.2, 1.2, 1.2)
                camNode.position = newVector3(cam.viewportSize.width * 0.5, cam.viewportSize.height * 0.5, 100.0)
            else:
                camNode.positionZ = 100

        editView.rootNode.addChild(v.composition.rootNode)
        clipView.addSubview(editView)

        discard editView.rootNode.newChild("overlay").component(ViewportRect)
        v.sceneView = editView
        v.autosaveTimer = setInterval(v.editor.currentProject.autosaveInterval) do():
            v.editor.saveComposition(v.composition, autosave = true)
    else:
        v.sceneView = v.rootNode.sceneView
        v.sceneView.editing = true
        v.sceneView.setFrame(clipView.bounds)
        clipView.addSubview(v.sceneView)

    v.cameraController = newEditorCameraController(v.sceneView)
    v.sceneView.afterDrawProc = proc() {.gcsafe.} =
        currentContext().gl.clearDepthStencil()
        v.updateGizmo()
        v.nodeSelector.draw()

    v.addSubview(clipView)
    v.trackMouseOver(true)


method tabSize*(v: EditorSceneView, bounds: Rect): Size=
    result = newSize(bounds.width, 250.0)

method tabAnchor*(v: EditorSceneView): EditorTabAnchor =
    result = etaCenter

method update*(v: EditorSceneView) = discard

method setEditedNode*(v: EditorSceneView, n: Node)=
    v.selectedNode = n
    v.gizmo.editedNode = n
    v.nodeSelector.selectedNode = n

method onDragEnter*(dd: EditorDropDelegate, target: View, i: PasteboardItem) =
    if i.kind in [rodPbComposition, rodPbFiles, rodPbSprite]:
        target.backgroundColor.a = 0.5

method onDragExit*(dd: EditorDropDelegate, target: View, i: PasteboardItem) =
    if i.kind in [rodPbComposition, rodPbFiles, rodPbSprite]:
        target.backgroundColor.a = 0.0

method onDrop*(dd: EditorDropDelegate, target: View, i: PasteboardItem) =
    target.backgroundColor.a = 0.0
    case i.kind:
    of rodPbComposition:
        try:
            echo "try drop node ", i.data
            var n = newNodeWithURL("file://" & i.data)
            echo "node isnil ", n.isNil
            if not n.isNil:
                var editorScene = target.EditorSceneView
                var cs = editorScene.selectedNode
                if cs.isNil:
                    cs = editorScene.rootNode
                else:
                    if not cs.composition.isNil and cs != editorScene.composition.rootNode:
                        cs = editorScene.selectedNode.parent
                    if cs.isNil:
                        raise newException(Exception, "Can't attach to prefab. Attaching to prafab parent failed, parent is nil")
                echo "add child "
                cs.addChild(n)
                editorScene.composition.selectedNode = cs
                editorScene.editor.onCompositionChanged(editorScene.composition)

                discard target.makeFirstResponder()
        except:
            warn "Can't deserialize ", i.data, " ", getCurrentExceptionMsg()

    of rodPbSprite:
        loadAsset[Image]("file://" & i.data) do(image: Image, err: string):
            if image.isNil:
                warn "Can't load image from ", i.data
                return

            var spName = splitFile(i.data)
            var n = newNode(spName.name)
            n.component(Sprite).image = image

            var editorScene = target.EditorSceneView
            if editorScene.selectedNode.isNil:
                editorScene.rootNode.addChild(n)
            else:
                editorScene.selectedNode.addChild(n)

            editorScene.composition.selectedNode = n
            editorScene.editor.onCompositionChanged(editorScene.composition)
            # editorScene.editor.selectedNode = n
    else:
        discard

proc allComprefs(n: Node, s: var seq[Composition])=
    if not n.composition.isNil:
        s.add(n.composition)
    for ch in n.children:
        ch.allComprefs(s)

proc updateComprRef(c: Composition) =
    echo "updateCompRef ", c.url
    var n: Node
    n = newNodeWithURL(c.url)
    if not n.isNil:
        c.node.removeAllChildren()
        while n.children.len > 0:
            c.node.addChild(n.children[0])

method onCompositionSaved*(v: EditorSceneView, comp: CompositionDocument) =
    if comp.owner == v: return

    let compPath = "file://" & comp.path.replace("\\", "/")
    var comps: seq[Composition]
    v.composition.rootNode.allComprefs(comps)
    for c in comps:
        if c.url == compPath:
            c.updateComprRef()

registerEditorTab(RodInternalTab & "/Scene", EditorSceneView)
