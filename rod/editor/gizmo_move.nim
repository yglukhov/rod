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
import rod.editor.gizmo
import rod.component.primitives.cone
import rod.component.primitives.cube
import rod.component.mesh_component
import rod.component.material
import rod.quaternion


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


proc getAxisColor(name: string): Color =
    if name.contains("_x"):
        result = newColor(1, 0, 0, 1)
    elif name.contains("_y"):
        result = newColor(0, 1, 0, 1)
    elif name.contains("_z"):
        result = newColor(0, 0, 1, 0.3)

proc createPlane(name: string): Node =
    result = newNode(name)
    let size = 4.0
    let cubeNode = newNode()
    result.addChild(cubeNode)

    cubeNode.positionX = size
    cubeNode.positionY = size
    cubeNode.alpha = 0.8

    let cube = cubeNode.addComponent(CubeComponent)
    cube.size = newVector3(size, size, 0.1)
    cube.material.diffuse = getAxisColor(name)

proc createArrow(name: string): Node =
    result = newNode(name)
    let h = 16.0
    let cylNode = newNode()
    let coneNode = newNode()

    coneNode.positionY = h

    result.addChild(cylNode)
    result.addChild(coneNode)

    let cylinder = cylNode.addComponent(ConeComponent)
    cylinder.height = h
    cylinder.material.diffuse = getAxisColor(name)
    cylinder.radius1 = 0.6
    cylinder.radius2 = 0.6

    let cone = coneNode.addComponent(ConeComponent)
    cone.radius1 = 1.5
    cone.radius2 = 0.0
    cone.material.diffuse = getAxisColor(name)

proc createMesh(): Node =
    result = newNode("gizmo_axis")

    let axis_x = createArrow("axis_x")
    let axis_y = createArrow("axis_y")
    let axis_z = createArrow("axis_z")
    result.addChild(axis_x)
    result.addChild(axis_y)
    result.addChild(axis_z)

    axis_x.rotation = newQuaternionFromEulerYXZ(0, 0, -90)
    axis_z.rotation = newQuaternionFromEulerYXZ(90, 0, 0)

    let plane_x = createPlane("plane_x")
    let plane_y = createPlane("plane_y")
    let plane_z = createPlane("plane_z")
    result.addChild(plane_x)
    result.addChild(plane_y)
    result.addChild(plane_z)

    plane_x.rotation = newQuaternionFromEulerYXZ(0, -90, 0)
    plane_y.rotation = newQuaternionFromEulerYXZ(90, 0, 0)


proc newMoveGizmo*(): MoveGizmo =
    result = new(MoveGizmo)
    result.gizmoNode = createMesh()
    # result.gizmoNode.loadComposition( getMoveAxisJson() )
    result.gizmoNode.alpha = 0.0

method startTransform*(ga: MoveGizmo, selectedGizmo: Node, position: Point) =
    let axis = selectedGizmo.parent
    if axis.name.contains("axis_x"):
        ga.axisMask = newVector3(1.0, 0.0, 0.0)
    elif axis.name.contains("axis_y"):
        ga.axisMask = newVector3(0.0, 1.0, 0.0)
    elif axis.name.contains("axis_z"):
        ga.axisMask = newVector3(0.0, 0.0, 1.0)

    elif axis.name.contains("plane_x"):
        ga.axisMask = newVector3(0.0, 1.0, 1.0)
    elif axis.name.contains("plane_y"):
        ga.axisMask = newVector3(1.0, 0.0, 1.0)
    elif axis.name.contains("plane_z"):
        ga.axisMask = newVector3(1.0, 1.0, 0.0)

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

method onMouseIn*(g: MoveGizmo, castedNode: Node) =
    for ch in castedNode.parent.children:
        ch.getComponent(MeshComponent).material.diffuse = newColor(1, 1, 0, 1)

method onMouseOut*(g: MoveGizmo, castedNode: Node) =
    let parent = castedNode.parent
    for ch in parent.children:
        ch.getComponent(MeshComponent).material.diffuse = getAxisColor(parent.name)
