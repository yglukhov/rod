import strutils

import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.image
import nimx.matrixes
import nimx.property_visitor

import rod.component.camera
import rod.node
import rod.viewport
import rod.editor.gizmos.move_axis


type GizmoAxis* = ref object
    gizmoNode*: Node
    moveAxis: Vector3
    mEditedNode*: Node

proc updateGizmo*(ns: GizmoAxis) =
    if ns.mEditedNode.isNil:
        return

    ns.gizmoNode.position = ns.mEditedNode.worldPos

    var dist = (ns.gizmoNode.sceneView.camera.node.worldPos - ns.gizmoNode.worldPos).length
    let wp1 = ns.gizmoNode.sceneView.camera.node.worldTransform() * newVector3(0.0, 0.0, -dist)
    let wp2 = ns.gizmoNode.sceneView.camera.node.worldTransform() * newVector3(100.0, 0.0, -dist)

    let p1 = ns.gizmoNode.sceneView.worldToScreenPoint(wp1)
    let p2 = ns.gizmoNode.sceneView.worldToScreenPoint(wp2)

    let cameraScale = ns.gizmoNode.sceneView.camera.node.scale
    let scale = 450.0 / abs(p2.x - p1.x) * cameraScale.x
    ns.gizmoNode.scale = newVector3(scale, scale, scale)

proc newGizmoAxis*(): GizmoAxis =
    result = new(GizmoAxis)
    result.gizmoNode = newNode()
    # let distance = (ns.node.worldPos - ns.node.sceneView.camera.node.worldPos).length()
    # if distance > 0.1:
    result.gizmoNode.loadComposition( getMoveAxisJson() )
    result.gizmoNode.alpha = 0.0

    result.updateGizmo()


var screenPoint, offset: Vector3
proc startTransform*(ga: GizmoAxis, selectedGizmo: Node, position: Point) =
    if selectedGizmo.name.contains("gizmo_axis_x"):
        ga.moveAxis = newVector3(1.0, 0.0, 0.0)
    elif selectedGizmo.name.contains("gizmo_axis_y"):
        ga.moveAxis = newVector3(0.0, 1.0, 0.0)
    elif selectedGizmo.name.contains("gizmo_axis_z"):
        ga.moveAxis = newVector3(0.0, 0.0, 1.0)

    screenPoint = ga.gizmoNode.sceneView.worldToScreenPoint(ga.gizmoNode.worldPos)
    offset = ga.gizmoNode.worldPos - ga.gizmoNode.sceneView.screenToWorldPoint(newVector3(position.x, position.y, screenPoint.z))

proc proccesTransform*(ns: GizmoAxis, position: Point) =
    if ns.mEditedNode.isNil:
        return

    let curScreenPoint = newVector3(position.x, position.y, screenPoint.z)
    var curPosition: Vector3
    curPosition = ns.mEditedNode.sceneView.screenToWorldPoint(curScreenPoint) + offset
    curPosition = curPosition - ns.gizmoNode.worldPos
    ns.gizmoNode.position = ns.gizmoNode.worldPos + curPosition * ns.moveAxis

    if not ns.mEditedNode.parent.isNil:
        ns.mEditedNode.position = ns.mEditedNode.parent.worldToLocal(ns.gizmoNode.position)
    else:
        ns.mEditedNode.position = ns.gizmoNode.position


proc stopTransform*(ns: GizmoAxis) =
    ns.moveAxis = newVector3(0.0, 0.0, 0.0)

proc `editedNode=`*(ga: GizmoAxis, n: Node) =
    ga.mEditedNode = n
    if not n.isNil:
        ga.gizmoNode.alpha = 1.0
        ga.updateGizmo()
    else:
        ga.gizmoNode.alpha = 0.0
