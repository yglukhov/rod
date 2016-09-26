import typetraits
import tables, sequtils
import json

import nimx.types
import nimx.property_visitor
import nimx.matrixes
import nimx.class_registry

import node
import rod_types
import ray
import rod.tools.serializer

export Component

method init*(c: Component) {.base.} = discard

var componentGroupsTable* = initTable[string, seq[string]]()

proc registerComponentGroup(group, component: string) =
    var validatedGroup = group
    if validatedGroup.isNil:
        validatedGroup = "Other"

    var g = componentGroupsTable.getOrDefault(validatedGroup)
    if g.isNil:
        g = newSeq[string]()
        componentGroupsTable[validatedGroup] = g

    componentGroupsTable[validatedGroup].add(component)

proc registeredComponents*(): seq[string] =
    result = newSeq[string]()
    for c in registeredClassesOfType(Component):
        result.add(c)

template registerComponent*(T: typedesc, group: string = nil ) =
    registerClass(T)
    registerComponentGroup(group, typetraits.name(T))

template registerComponent*(T: typedesc, creator: (proc(): RootRef), group: string = nil ) =
    registerClass(T, creator)
    registerComponentGroup(group, typetraits.name(T))

proc createComponent*(name: string): Component =
    if isClassRegistered(name) == false:
        raise newException(Exception, "Component " & name & " is not registered")

    result = newObjectOfClass(name).Component
    result.init()

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

template isEmpty*(b: BBox): bool = (b.maxPoint - b.minPoint == newVector3())

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
    if bbox.isEmpty:
        return false

    var inv_mat: Matrix4
    if tryInverse(c.node.worldTransform(), inv_mat) == false:
        return false

    let localRay = r.transform(inv_mat)
    if c.node.getGlobalAlpha() < 0.0001:
        result = false
    else:
        result = localRay.intersectWithAABB(bbox.minPoint, bbox.maxPoint, distance)
