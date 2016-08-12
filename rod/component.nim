import typetraits
import tables, sequtils
import json

import nimx.types
import nimx.property_visitor
import nimx.matrixes

import node
import rod_types
import ray
import rod.tools.serializer

export Component

method init*(c: Component) {.base.} = discard

var componentRegistry = initTable[string, proc(): Component]()

proc registeredComponents*(): seq[string] = toSeq(keys(componentRegistry))

proc registerComponent*[T]() =
    componentRegistry.add T.name, proc(): Component =
        result = T.new()

proc registerComponent*[T](creator: proc(): Component) =
    componentRegistry.add T.name, creator

proc createComponent*(name: string): Component =
    let p = componentRegistry.getOrDefault(name)
    if not p.isNil:
        result = p()
        result.init()
    if result.isNil:
        raise newException(Exception, "Component " & name & " is not registered")

proc createComponent*[T](): T = createComponent(T.name).T

method draw*(c: Component) {.base.} = discard
method update*(c: Component) {.base.} = discard
method componentNodeWasAddedToSceneView*(c: Component) {.base.} = discard
method componentNodeWillBeRemovedFromSceneView*(c: Component) {.base.} = discard
method isPosteffectComponent*(c: Component): bool {.base.} = false

method visitProperties*(c: Component, p: var PropertyVisitor) {.base.} = discard
method deserialize*(c: Component, j: JsonNode, s: Serializer) {.base.} = discard
method serialize*(c: Component, s: Serializer): JsonNode {.base.} = discard
method getBBox*(c: Component): BBox {.base.} = discard

type UpdateProcComponent = ref object of Component
    updateProc: proc()

type DrawProcComponent = ref object of Component
    drawProc: proc()

proc newBBox*(): BBox =
    result.new()

proc newBBox*(min, max: Vector3): BBox =
    result.new()
    result.minPoint = min
    result.maxPoint = max

proc newComponentWithUpdateProc*(p: proc()): Component =
    var r : UpdateProcComponent
    r.new()
    r.updateProc = p
    result = r

proc newComponentWithDrawProc*(p: proc()): Component =
    var r : DrawProcComponent
    r.new()
    r.drawProc = p
    result = r

method update*(c: UpdateProcComponent) =
    c.updateProc()

method draw*(c: DrawProcComponent) =
    c.drawProc()

type OverlayComponent* = ref object of Component

method componentNodeWasAddedToSceneView*(c: OverlayComponent) =
    inc c.node.sceneView.numberOfNodesWithBackComposition

method componentNodeWillBeRemovedFromSceneView*(c: OverlayComponent) =
    dec c.node.sceneView.numberOfNodesWithBackComposition

method rayCast*(c: Component, r: Ray, distance: var float32): bool {.base.} =
    let bbox = c.getBBox()
    if bbox.isNil:
        return false

    var inv_mat: Matrix4
    if tryInverse(c.node.worldTransform(), inv_mat) == false:
        return false

    let localRay = r.transform(inv_mat)
    if c.node.getGlobalAlpha() < 0.0001:
        result = false
    else:
        result = localRay.intersectWithAABB(bbox.minPoint, bbox.maxPoint, distance)
