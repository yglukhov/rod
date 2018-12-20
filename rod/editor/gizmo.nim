import strutils

import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.image
import nimx.matrixes
import nimx.property_visitor
import nimx.event

import rod.component.camera
import rod.node
import rod.viewport


type Gizmo* = ref object of RootObj
    gizmoNode*: Node
    axisMask*: Vector3
    mEditedNode*: Node
    mPrevCastedAxis: Node

method updateGizmo*(g: Gizmo) {.base.} = discard
method startTransform*(g: Gizmo, selectedGizmo: Node, position: Point) {.base.} = discard
method proccesTransform*(g: Gizmo, position: Point) {.base.} = discard
method stopTransform*(g: Gizmo) {.base.} = discard
method onMouseIn*(g: Gizmo, castedNode: Node) {.base.} = discard
method onMouseOut*(g: Gizmo, castedNode: Node) {.base.} = discard

proc newGizmo*(): Gizmo =
    result = new(Gizmo)
    result.gizmoNode = newNode()
    result.gizmoNode.alpha = 0.0

proc `editedNode=`*(g: Gizmo, n: Node) =
    g.mEditedNode = n
    if not n.isNil:
        g.gizmoNode.alpha = 1.0
        g.updateGizmo()
    else:
        g.gizmoNode.alpha = 0.0

proc editedNode*(g: Gizmo): Node = g.mEditedNode

proc onTouchEv*(g: Gizmo, e: var Event): bool =
    case e.buttonState:
    of bsUp:
        g.stopTransform()

    of bsDown:
        let castedGizmo = g.gizmoNode.sceneView.rayCastFirstNode(g.gizmoNode, e.localPosition)
        if not castedGizmo.isNil:
            result = true
            g.startTransform(castedGizmo, e.localPosition)

    of bsUnknown:
        g.proccesTransform(e.localPosition)

proc onMouseOver*(g: Gizmo, e: var Event) =
    if g.isNil or g.gizmoNode.sceneView.isNil: return

    let castedGizmo = g.gizmoNode.sceneView.rayCastFirstNode(g.gizmoNode, e.localPosition)

    if castedGizmo != g.mPrevCastedAxis:
        if not g.mPrevCastedAxis.isNil:
            g.onMouseOut(g.mPrevCastedAxis)
        if not castedGizmo.isNil:
            g.onMouseIn(castedGizmo)

    g.mPrevCastedAxis = castedGizmo
