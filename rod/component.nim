import typetraits, tables, json
import nimx / [ types, property_visitor, matrixes, class_registry ]
import rod / [ rod_types, ray, message_queue ]
import rod / tools / serializer
import rod / utils / [bin_deserializer, json_deserializer, bin_serializer,
                json_serializer, serialization_hash_calculator ]

export Component, ScriptComponent, RenderComponent
export message_queue

method init*(c: Component) {.base.} = discard

var componentGroupsTable* = initTable[string, seq[string]]()

proc registerComponentGroup(group, component: string = "") =
    var validatedGroup = group
    if validatedGroup.len == 0:
        validatedGroup = "Other"

    var g = componentGroupsTable.getOrDefault(validatedGroup)
    g.add(component)
    componentGroupsTable[validatedGroup] = g

proc registeredComponents*(): seq[string] =
    result = newSeq[string]()
    for c in registeredClassesOfType(Component):
        result.add(c)

template registerComponent*(T: typedesc, group: string = "") =
    registerClass(T)
    registerComponentGroup(group, typetraits.name(T))

template registerComponent*(T: typedesc, creator: (proc(): RootRef), group: string = "") =
    registerClass(T, creator)
    registerComponentGroup(group, typetraits.name(T))

proc createComponent*(name: string): Component =
    if isClassRegistered(name) == false:
        raise newException(Exception, "Component " & name & " is not registered")

    result = newObjectOfClass(name).Component
    result.init()

proc createComponent*[T](): T = createComponent(T.name).T

method isRenderComponent*(c: Component): bool {.base.} = discard
method isRenderComponent*(c: RenderComponent): bool = true

method draw*(c: RenderComponent) {.base.} = discard # Deprecated.
method beforeDraw*(c: RenderComponent, index: int): bool {.base.} = discard
method afterDraw*(c: RenderComponent, index: int) {.base.} = discard

method onMessage*(c: ScriptComponent, id: MessageId, data: string, sender: Node) {.base.} = discard
method update*(c: ScriptComponent) {.base.} = discard
method componentNodeWasAddedToSceneView*(c: Component) {.base.} = discard
method componentNodeWillBeRemovedFromSceneView*(c: Component) {.base.} = discard
method isPosteffectComponent*(c: RenderComponent): bool {.base.} = false

method visitProperties*(c: Component, p: var PropertyVisitor) {.base.} = discard
method getBBox*(c: Component): BBox {.base.} = discard

method serialize*(c: Component, s: Serializer): JsonNode {.base.} =
    # Deprecated. If your compoenent hits this, override the new JsonSerializer serialization
    doAssert(false, "Not implemented")

method deserialize*(c: Component, j: JsonNode, s: Serializer) {.base.} =
    # Deprecated. If your compoenent hits this, override the new JsonDeserializer serialization
    doAssert(false, "Not implemented")

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

method deserialize*(c: Component, s: JsonDeserializer) {.base.} =
    let ss = Serializer.new()
    ss.jdeser = s
    ss.url = s.compPath
    c.deserialize(s.node, ss)

method serialize*(c: Component, s: JsonSerializer) {.base.} =
    let ss = Serializer.new()
    ss.jser = s
    ss.url = s.url
    s.node = c.serialize(ss)
    if "_c" notin s.node:
        s.node["_c"] = %className(c)

method serialize*(c: Component, b: BinSerializer) {.base.} =
    let js = newJsonSerializer()
    js.node = newJObject()
    c.serialize(js)
    let j = js.node
    let name = j["_c"]
    j.delete("_c")
    var s = ""
    toUgly(s, j)
    b.write(s.len.int32)
    b.writeStrNoLen(s)

method serializationHash*(c: Component, b: SerializationHashCalculator) {.base.} = discard

type UpdateProcComponent = ref object of ScriptComponent
    updateProc: proc()

type DrawProcComponent = ref object of RenderComponent
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

    result = r.intersectWithAABB(bbox.minPoint, bbox.maxPoint, distance)
