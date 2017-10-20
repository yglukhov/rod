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
import rod.editor.gizmos.move_axis
import rod.editor.gizmo


type MoveGizmo* = ref object of Gizmo
    screenPoint: Vector3
    offset: Vector3

method updateGizmo*(g: MoveGizmo) =
    if g.mEditedNode.isNil:
        return

    g.gizmoNode.position = g.mEditedNode.worldPos

    var dist = (g.gizmoNode.sceneView.camera.node.worldPos - g.gizmoNode.worldPos).length
    let wp1 = g.gizmoNode.sceneView.camera.node.worldTransform() * newVector3(0.0, 0.0, -dist)
    let wp2 = g.gizmoNode.sceneView.camera.node.worldTransform() * newVector3(100.0, 0.0, -dist)

    let p1 = g.gizmoNode.sceneView.worldToScreenPoint(wp1)
    let p2 = g.gizmoNode.sceneView.worldToScreenPoint(wp2)

    let cameraScale = g.gizmoNode.sceneView.camera.node.scale
    let scale = 450.0 / abs(p2.x - p1.x) * cameraScale.x
    g.gizmoNode.scale = newVector3(scale, scale, scale)

proc newMoveGizmo*(): MoveGizmo =
    result = new(MoveGizmo)
    result.gizmoNode = newNode()
    result.gizmoNode.loadComposition( getMoveAxisJson() )
    result.gizmoNode.alpha = 0.0

    result.updateGizmo()

method startTransform*(ga: MoveGizmo, selectedGizmo: Node, position: Point) =
    if selectedGizmo.name.contains("gizmo_axis_x"):
        ga.axisMask = newVector3(1.0, 0.0, 0.0)
    elif selectedGizmo.name.contains("gizmo_axis_y"):
        ga.axisMask = newVector3(0.0, 1.0, 0.0)
    elif selectedGizmo.name.contains("gizmo_axis_z"):
        ga.axisMask = newVector3(0.0, 0.0, 1.0)

    ga.screenPoint = ga.gizmoNode.sceneView.worldToScreenPoint(ga.gizmoNode.worldPos)
    ga.offset = ga.gizmoNode.worldPos - ga.gizmoNode.sceneView.screenToWorldPoint(newVector3(position.x, position.y, ga.screenPoint.z))

method proccesTransform*(g: MoveGizmo, position: Point) =
    if g.mEditedNode.isNil:
        return

    let curScreenPoint = newVector3(position.x, position.y, g.screenPoint.z)
    var curPosition: Vector3
    curPosition = g.mEditedNode.sceneView.screenToWorldPoint(curScreenPoint) + g.offset
    curPosition = curPosition - g.gizmoNode.worldPos
    g.gizmoNode.position = g.gizmoNode.worldPos + curPosition * g.axisMask
    if not g.mEditedNode.parent.isNil:
        g.mEditedNode.position = g.mEditedNode.parent.worldToLocal(g.gizmoNode.position)
    else:
        g.mEditedNode.position = g.gizmoNode.position

method stopTransform*(g: MoveGizmo) =
    g.axisMask = newVector3(0.0, 0.0, 0.0)
