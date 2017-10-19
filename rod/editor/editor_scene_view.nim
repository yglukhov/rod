import nimx / [ types, view, event, view_event_handling, view_event_handling_new,
    gesture_detector, drag_and_drop, pasteboard/pasteboard, assets/asset_loading, image,
    matrixes, clip_view, context, portable_gl ]

import rod / editor / gizmo_axis
import rod / [node, rod_types, edit_view, component, viewport, ray]
import rod / component / [ sprite, light, camera ]

import rod.editor_camera_controller

import logging, sequtils, algorithm

type
    EditorDropDelegate* = ref object of DragDestinationDelegate

    EditorSceneView* = ref object of EditorTabView
        gizmo: GizmoAxis
        selectedNode: Node
        sceneView: SceneView
        cameraController: EditorCameraController
        startPoint: Point

proc rayCastFirstNode(v: EditorSceneView, node: Node, coords: Point): Node =
    let r = v.sceneView.rayWithScreenCoords(coords)
    var castResult = newSeq[RayCastInfo]()
    node.rayCast(r, castResult)

    if castResult.len > 0:
        castResult.sort( proc (x, y: RayCastInfo): int =
            result = int(x.node.layer < y.node.layer)
            if x.node.layer == y.node.layer:
                result = int(x.distance > y.distance)
                if abs(x.distance - y.distance) < 0.00001:
                    result = getTreeDistance(x.node, y.node) )

        result = castResult[0].node

method onKeyDown*(v: EditorSceneView, e: var Event): bool =
    result = procCall v.View.onKeyDown(e)
    v.cameraController.onKeyDown(e)

method onKeyUp*(v: EditorSceneView, e: var Event): bool =
    result = procCall v.View.onKeyDown(e)
    v.cameraController.onKeyUp(e)
    if e.keyCode == VirtualKey.F:
        v.cameraController.setToNode(v.composition.selectedNode)


method onScroll*(v: EditorSceneView, e: var Event): bool=
    v.cameraController.onMouseScrroll(e)
    return true

proc castGizmo(v: EditorSceneView, e: var Event ): Node =
    result = v.rayCastFirstNode(v.gizmo.gizmoNode, e.localPosition)

proc tryRayCast(v: EditorSceneView, e: var Event): Node=
    result = v.rayCastFirstNode(v.rootNode, e.localPosition)

method onTouchEv*(v: EditorSceneView, e: var Event): bool =
    result = procCall v.View.onTouchEv(e)
    case e.buttonState:
    of bsUp:
        v.gizmo.stopTransform()
        v.cameraController.onTapUp(0.0,0.0,e)
    of bsDown:
        v.startPoint = e.localPosition
        if e.keyCode != VirtualKey.MouseButtonPrimary: return true
        let gizmoNode = v.castGizmo(e)
        if not gizmoNode.isNil:
            v.gizmo.startTransform(gizmoNode, e.localPosition)
        else:
            var castedNode = v.tryRayCast(e)
            if not castedNode.isNil:
                v.editor.selectedNode = castedNode
            else:
                v.editor.selectedNode = nil

        v.cameraController.onTapDown(e)

    of bsUnknown:
        v.gizmo.proccesTransform(e.localPosition)
        var dx = v.startPoint.x - e.localPosition.x
        var dy = v.startPoint.y - e.localPosition.y
        v.cameraController.onScrollProgress(dx, dy, e)
    return v.makeFirstResponder()

proc updateGizmo(v: EditorSceneView)=
    if v.gizmo.isNil:
        v.gizmo = newGizmoAxis()
        v.gizmo.gizmoNode.nodeWasAddedToSceneView(v.sceneView)
    v.gizmo.updateGizmo()
    v.gizmo.gizmoNode.drawNode(true, nil)

method init*(v: EditorSceneView, r: Rect)=
    procCall v.View.init(r)
    v.dragDestination = new(EditorDropDelegate)

    var clipView = new(ClipView, newRect(0,0,r.width, r.height))
    clipView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }

    if not v.editor.startFromGame:

        let editView = SceneView.new(newRect(0,0,r.width, r.height))
        editView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }

        editView.rootNode = v.rootNode
        editView.editing = true

        let cameraNode = editView.rootNode.newChild("camera")
        discard cameraNode.component(Camera)
        cameraNode.positionZ = 100

        clipView.addSubview(editView)

        v.sceneView = editView
    else:
        v.sceneView = v.rootNode.sceneView
        v.sceneView.editing = true
        v.sceneView.setFrame(clipView.bounds)
        clipView.addSubview(v.sceneView)

    v.cameraController = newEditorCameraController(v.sceneView)
    v.sceneView.afterDrawProc = proc()=
        currentContext().gl.clearDepthStencil()
        v.updateGizmo()

    v.addSubview(clipView)

method tabSize*(v: EditorSceneView, bounds: Rect): Size=
    result = newSize(bounds.width, 250.0)

method tabAnchor*(v: EditorSceneView): EditorTabAnchor =
    result = etaCenter

method update*(v: EditorSceneView) = discard

method setEditedNode*(v: EditorSceneView, n: Node)=
    v.selectedNode = n
    v.gizmo.editedNode = v.selectedNode

method acceptsFirstResponder(v: EditorSceneView): bool = true

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
        var n = try: newNodeWithURL("file://" & i.data) except: nil
        if not n.isNil:
            var editorScene = target.EditorSceneView
            if editorScene.selectedNode.isNil:
                editorScene.rootNode.addChild(n)
            else:
                editorScene.selectedNode.addChild(n)

            editorScene.composition.selectedNode = n
            editorScene.editor.onCompositionChanged(editorScene.composition)

            discard target.makeFirstResponder()
        else:
            warn "Can't deserialize ", i.data

    of rodPbSprite:
        loadAsset[Image]("file://" & i.data) do(image: Image, err: string):
            if image.isNil:
                warn "Can't load image from ", i.data
                return

            var n = newNode(i.data)
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

registerEditorTab(RodInternalTab & "/Scene", EditorSceneView)
