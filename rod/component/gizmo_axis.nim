import strutils

import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.image
import nimx.matrixes
import nimx.property_visitor

import rod.component
import rod.quaternion
import rod.component.camera
import rod.node
import rod.viewport
import rod.editor.gizmos.move_axis


type GizmoAxis* = ref object of Component
    gizmoNode: Node
    moveAxis: Vector3
    mEditedNode*: Node

method init*(ga: GizmoAxis) =
    procCall ga.Component.init()

proc updateGizmo(ns: GizmoAxis) =
    if ns.mEditedNode.isNil:
        return

    ns.gizmoNode.position = ns.mEditedNode.worldPos

    var dist = (ns.gizmoNode.sceneView.camera.node.worldPos - ns.node.worldPos).length
    let wp1 = ns.node.sceneView.camera.node.worldTransform() * newVector3(0.0, 0.0, -dist)
    let wp2 = ns.node.sceneView.camera.node.worldTransform() * newVector3(100.0, 0.0, -dist)

    let p1 = ns.node.sceneView.worldToScreenPoint(wp1)
    let p2 = ns.node.sceneView.worldToScreenPoint(wp2)

    let cameraScale = ns.gizmoNode.sceneView.camera.node.scale
    let scale = 450.0 / abs(p2.x - p1.x) * cameraScale.x
    ns.gizmoNode.scale = newVector3(scale, scale, scale)


method componentNodeWasAddedToSceneView*(ns: GizmoAxis) =
    ns.gizmoNode = newNode()
    # let distance = (ns.node.worldPos - ns.node.sceneView.camera.node.worldPos).length()
    # if distance > 0.1:
    ns.gizmoNode.loadComposition( getMoveAxisJson() )
    ns.node.addChild(ns.gizmoNode)
    ns.gizmoNode.alpha = 0.0

    ns.updateGizmo()


method draw*(ga: GizmoAxis) =
    ga.updateGizmo()

var screenPoint, offset: Vector3
proc startTransform*(ga: GizmoAxis, selectedGizmo: Node, position: Point) =
    if selectedGizmo.name.contains("gizmo_axis_x"):
        ga.moveAxis = newVector3(1.0, 0.0, 0.0)
    elif selectedGizmo.name.contains("gizmo_axis_y"):
        ga.moveAxis = newVector3(0.0, 1.0, 0.0)
    elif selectedGizmo.name.contains("gizmo_axis_z"):
        ga.moveAxis = newVector3(0.0, 0.0, 1.0)

    screenPoint = ga.node.sceneView.worldToScreenPoint(ga.gizmoNode.worldPos)
    offset = ga.gizmoNode.worldPos - ga.node.sceneView.screenToWorldPoint(newVector3(position.x, position.y, screenPoint.z))

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

method visitProperties*(ga: GizmoAxis, p: var PropertyVisitor) =
    p.visitProperty("moveAxis", ga.moveAxis)

registerComponent(GizmoAxis)
