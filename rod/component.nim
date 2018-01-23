import typetraits, tables, sequtils, json

import nimx / [ types, property_visitor, matrixes, class_registry ]

import node
import rod_types
import ray
import rod.tools.serializer
import rod / utils / [bin_deserializer, json_deserializer, bin_serializer,
                json_serializer, serialization_hash_calculator ]

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

    g.add(component)
    componentGroupsTable[validatedGroup] = g

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

method supportsNewSerialization*(cm: Component): bool {.base.} = false #todo: remove after migration to new serialization will be done

proc createComponent*(name: string): Component =
    if isClassRegistered(name) == false:
        raise newException(Exception, "Component " & name & " is not registered")

    result = newObjectOfClass(name).Component
    result.init()

proc createComponent*[T](): T = createComponent(T.name).T

method draw*(c: Component) {.base.} = discard # Deprecated.
method beforeDraw*(c: Component, index: int): bool {.base.} = discard
method afterDraw*(c: Component, index: int) {.base.} = discard

method update*(c: Component) {.base.} = discard
method componentNodeWasAddedToSceneView*(c: Component) {.base.} = discard
method componentNodeWillBeRemovedFromSceneView*(c: Component) {.base.} = discard
method isPosteffectComponent*(c: Component): bool {.base.} = false

method visitProperties*(c: Component, p: var PropertyVisitor) {.base.} = discard
method getBBox*(c: Component): BBox {.base.} = discard

method deserialize*(c: Component, j: JsonNode, s: Serializer) {.base.}

proc deserializeFromJson*(c: Component, b: BinDeserializer) =
    # Temporary hacky way to fall back to json deserialization when binary is not implemented
    try:
        let strLen = b.readInt32()
        var str = newString(strLen)
        b.readStrNoLen(str)
        let j = parseJson(str)
        let s = Serializer.new()
        s.url = "res://" & b.curCompPath
        c.deserialize(j, s)
    except:
        echo "error deserializing ", c.className
        raise

method deserialize*(c: Component, b: BinDeserializer) {.base.} =
    c.deserializeFromJson(b)

method deserialize*(c: Component, s: JsonDeserializer) {.base.} = discard
method serialize*(c: Component, s: BinSerializer) {.base.} = discard
method serialize*(c: Component, s: JsonSerializer) {.base.} = discard
method serializationHash*(c: Component, b: SerializationHashCalculator) {.base.} = discard

method deserialize*(c: Component, j: JsonNode, s: Serializer) {.base.} =
    let js = s.jdeser
    js.node = j
    c.deserialize(js)

method serialize*(c: Component, s: Serializer): JsonNode {.base.} =
    result = newJObject()
    s.jser.node = result
    c.serialize(s.jser)

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

method rayCast*(c: Component, r: Ray, distance: var float32): bool {.base.} =
    let bbox = c.getBBox()
    if bbox.isEmpty:
        return false

    var inv_mat: Matrix4
    if tryInverse(c.node.worldTransform(), inv_mat) == false:
        return false

    let localRay = r.transform(inv_mat)
    if c.node.getGlobalAlpha() < 0.01 or not c.node.isEnabledInTree():
        result = false
    else:
        result = localRay.intersectWithAABB(bbox.minPoint, bbox.maxPoint, distance)
