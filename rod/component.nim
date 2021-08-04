import typetraits, tables, json
import nimx / [ types, property_visitor, matrixes, class_registry ]
import rod / [ rod_types, ray ]
import rod / tools / serializer
import rod / utils / [bin_deserializer, json_deserializer, bin_serializer,
                json_serializer, serialization_hash_calculator ]

export Component, ScriptComponent, RenderComponent

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

template scriptComponentChecks(T: typed): bool =
    compiles(new(T).draw()) or compiles(new(T).beforeDraw(0)) or compiles(new(T).afterDraw(0))

template renderComponentChecks(T: typed): bool =
    compiles(new(T).update(0.0)) or compiles(new(T).update())

template checkComponentParent(T: typed, body: untyped):untyped =
    when not (T is ScriptComponent or T is RenderComponent):
        {.error: $T & " invalid component inheritance!".}
    else:
        when (T is ScriptComponent) and scriptComponentChecks(T):
            {.error: $T & " of ScriptComponent can't have draw method".}
        elif (T is RenderComponent) and renderComponentChecks(T):
            {.error: $T & " of RenderComponent can't have update method".}
        else:
            body

template registerComponent*(T: typedesc, group: string = "") =
    checkComponentParent(T):
        registerClass(T)
        registerComponentGroup(group, typetraits.name(T))

template registerComponent*(T: typedesc, creator: (proc(): RootRef), group: string = "") =
    checkComponentParent(T):
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
method isPosteffectComponent*(c: RenderComponent): bool {.base.} = false
method interceptDraw*(c: RenderComponent): bool {.base.} = discard

method update*(c: ScriptComponent, dt: float) {.base.} = discard
method componentNodeWasAddedToSceneView*(c: Component) {.base.} = discard
method componentNodeWillBeRemovedFromSceneView*(c: Component) {.base.} = discard

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

template isEmpty*(b: BBox): bool =
    let d = b.maxPoint - b.minPoint
    abs(d.x) < 0.0001 or abs(d.y) < 0.0001

template intersect*(f: Frustum, bbox: BBox): bool =
    f.minPoint.x < bbox.maxPoint.x and bbox.minPoint.x < f.maxPoint.x and f.minPoint.y < bbox.maxPoint.y and bbox.minPoint.y < f.maxPoint.y

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

method update*(c: UpdateProcComponent, dt: float) =
    c.updateProc()

method draw*(c: DrawProcComponent) =
    c.drawProc()

method rayCast*(c: Component, r: Ray, distance: var float32): bool {.base.} =
    let bbox = c.getBBox()
    if bbox.isEmpty:
        return false

    result = r.intersectWithAABB(bbox.minPoint, bbox.maxPoint, distance)
