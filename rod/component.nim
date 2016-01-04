import typetraits
import tables, sequtils
import json

import nimx.types

import node
import property_visitor
import rod_types

export Component

method init*(c: Component) {.base.} = discard

var componentRegistry = initTable[string, proc(): Component]()

proc registeredComponents*(): seq[string] = toSeq(keys(componentRegistry))

proc registerComponent*[T]() =
    componentRegistry.add T.name, proc(): Component =
        result = T.new()

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

method animatableProperty1*(c: Component, name: string) : (proc (v: Coord)) {.base.} = discard
method visitProperties*(c: Component, p: var PropertyVisitor) {.base.} = discard
method deserialize*(c: Component, j: JsonNode) {.base.} = discard

type UpdateProcComponent = ref object of Component
    updateProc: proc()

type DrawProcComponent = ref object of Component
    drawProc: proc()

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
