import nimx / [ types, view, event, view_event_handling, portable_gl, context,
    pasteboard/pasteboard, assets/asset_loading, image, matrixes, clip_view ]

import rod / editor / scene / [gizmo, gizmo_move, node_selector, editor_camera_controller]
import rod / editor / scene / instruments / [ scene_grid ]
import rod / [ node, rod_types, edit_view, viewport, tools/debug_draw]
import rod / component / [ sprite, camera ]
import os
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

method onKeyDown*(v: EditorSceneView, e: var Event): bool =
    result = procCall v.View.onKeyDown(e)
    v.cameraController.onKeyDown(e)

method onKeyUp*(v: EditorSceneView, e: var Event): bool =
    result = procCall v.View.onKeyDown(e)
    v.cameraController.onKeyUp(e)
    if e.keyCode == VirtualKey.F:
        v.cameraController.setToNode(v.composition.selectedNode)
        result = true
    elif e.keyCode == VirtualKey.S and e.modifiers.anyCtrl():
        v.editor.saveComposition(v.composition)
        result = true

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
                    var p = castedNode.parent
                    while not p.isNil and p.composition.isNil and castedNode != v.composition.rootNode:
                        p = p.parent

                    if castedNode != p and p != v.composition.rootNode:    
                        castedNode = p

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
    v.gizmo.gizmoNode.drawNode(true, nil)

method init*(v: EditorSceneView, r: Rect)=
    procCall v.View.init(r)
    v.dragDestination = new(EditorDropDelegate)

    var clipView = new(ClipView, newRect(0,0,r.width, r.height))
    clipView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    
    var sceneGrid = new(EditorSceneGrid, newRect(0,0,r.width, r.height))
    sceneGrid.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    v.addSubview(sceneGrid)

    v.nodeSelector = newNodeSelector()

    if not v.editor.startFromGame:

        let editView = SceneView.new(newRect(0,0,r.width, r.height))
        editView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }

        editView.rootNode = newNode(EditorRootNodeName)
        editView.editing = true

        let cameraNode2d = editView.rootNode.newChild(EditorCameraNodeName2D)
        let c2d = cameraNode2d.component(Camera)
        c2d.viewportSize = EditorViewportSize
        c2d.projectionMode = cpOrtho
        cameraNode2d.position = newVector3(EditorViewportSize.width * 0.5, EditorViewportSize.height * 0.5, 100.0)

        let cameraNode3d = editView.rootNode.newChild(EditorCameraNodeName3D)
        discard cameraNode3d.component(Camera)
        cameraNode3d.positionZ = 100

        editView.rootNode.addChild(v.composition.rootNode)
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
        v.nodeSelector.draw()

    v.addSubview(clipView)
    sceneGrid.scene = v.sceneView
    v.trackMouseOver(true)

# method draw*(v: EditorSceneView, r: Rect) = 
#     procCall v.EditorTabView.draw(r)

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
            var n: Node
            n = newNodeWithURL("file://" & i.data) do():
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

registerEditorTab(RodInternalTab & "/Scene", EditorSceneView)
