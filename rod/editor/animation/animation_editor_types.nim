import nimx / [ types, matrixes, animation, property_visitor ]
import rod/animation/[animation_sampler, property_animation], rod / [ quaternion, rod_types ]
import algorithm
import variant, tables, json

type
    EInterpolation* = enum
        eiLinear
        eiBezier
        eiDiscrete
        eiPresampled

    EAnimationTimeFunc* = ref object
        case kind*: EInterpolation
        of eiBezier:
            points: array[4, float]
        else:
            discard

    EditedKey* = ref object
        property*: EditedProperty
        position*: Coord
        value*: Variant
        timeFunc*: EAnimationTimeFunc

    EditedProperty* = ref object
        enabled*: bool
        rawName: string #nodeName.componentIndex.componentProperty, nodeName.nodeProperty, etc
        node: Node
        sng*: Variant
        keys*: seq[EditedKey]

    EditedAnimation* = ref object 
        fps: int
        name*: string
        duration*: float
        properties*: seq[EditedProperty]

    AbstractAnimationCurve* = ref object of RootObj
        color*: Color

    AnimationCurve*[T] = ref object of AbstractAnimationCurve
        sampler*: BezierKeyFrameAnimationSampler[T]

proc name*(e: EditedProperty): string =
    if not e.node.isNil:
        result = e.node.name
    result &= e.rawName

proc newEditedProperty*(n: Node, name: string, sng: Variant): EditedProperty =
    result.new()
    result.rawName = name
    result.sng = sng
    result.node = n
    result.enabled = true

proc sortKeys*(p: EditedProperty)=
    p.keys.sort() do(a, b: EditedKey) -> int:
        cmp(a.position, b.position)

proc addKeyAtPosition*(p: EditedProperty, pos: Coord) =
    var k = new(EditedKey)
    k.property = p
    k.position = pos
    # k.value = value

    template getKeyValue(T: typedesc) =
        let val = p.sng.get(SetterAndGetter[T]).getter()
        k.value = newVariant(val)
        echo "value is ", val, " at pos ", pos

    template getSetterAndGetterTypeId(T: typedesc): TypeId = getTypeId(SetterAndGetter[T])
    switchAnimatableTypeId(p.sng.typeId, getSetterAndGetterTypeId, getKeyValue)
    p.keys.add(k)

    p.sortKeys()

proc keyAtIndex*(e: EditedProperty, ki: int): EditedKey =
    if ki >= 0 and ki < e.keys.len:
        return e.keys[ki]

proc propertyAtIndex*(e: EditedAnimation, pi: int): EditedProperty =
    if pi >= 0 and pi < e.properties.len:
        return e.properties[pi]

proc keyAtIndex*(e: EditedAnimation, pi, ki: int): EditedKey =
    let p = e.propertyAtIndex(pi)
    if p.isNil: return
    result = p.keyAtIndex(ki)
 
template keyValue(k: EditedKey, body: untyped) =
    template getKeyValueAUX(T: typedesc) =
        let value{.inject} = k.value.get(T)
        body
    switchAnimatableTypeId(k.value.typeId, getTypeId, getKeyValueAUX)

#todo: remove this serialization
proc `%`(q: Quaternion): JsonNode = 
    result = newJArray()
    result.add(%q.x)
    result.add(%q.y)
    result.add(%q.z)
    result.add(%q.w)

proc `%`(q: Color): JsonNode = 
    result = newJArray()
    result.add(%q.r)
    result.add(%q.g)
    result.add(%q.b)
    result.add(%q.a)

proc `%`*(a: EditedAnimation): JsonNode = 
    result = newJobject()
    # result["name"] = %a.name
    # result["duration"] = %a.duration
    for prop in a.properties:
        if not prop.enabled: continue
        var jp = newJObject()
        jp["duration"] = %a.duration #stupid?
        var keys = newJArray()
        for k in prop.keys:
            var jk = newJobject()
            jk["p"] = %k.position
            k.keyValue:
                jk["v"] = %value
            # jk["i"] = k.
            keys.add(jk)

        jp["keys"] = keys
        result[prop.name] = jp


method getSampler*(a: AbstractAnimationCurve): AbstractAnimationSampler {.base.} = nil
method getSampler*[T](a: AnimationCurve[T]): AbstractAnimationSampler = a.sampler

method numberOfKeys*(c: AbstractAnimationCurve): int {.base.} = 0
method numberOfKeys*[T](c: AnimationCurve[T]): int = c.sampler.keys.len

# method numberOfDimensions*(c: AbstractAnimationCurve): int {.base.} = 0
# method numberOfDimensions*[T](c: AnimationCurve[T]): int =
#     when T is Coord | int | int16 | bool:
#         1
#     elif T is Vector2:
#         2
#     elif T is Vector3:
#         3
#     elif T is Vector4 | Color | Quaternion:
#         4
#     else:
#         {.error: "Unknown type".}

method keyTime*(c: AbstractAnimationCurve, i: int): float {.base.} = 0
method keyTime*[T](c: AnimationCurve[T], i: int): float = c.sampler.keys[i].p

method setKeyTime*(c: AbstractAnimationCurve, i: int, t: float) {.base.} = discard
method setKeyTime*[T](c: AnimationCurve[T], i: int, t: float) = c.sampler.keys[i].p = t

method keyInTangent*(c: AbstractAnimationCurve, i: int): Point {.base.} = zeroPoint
method keyInTangent*[T](c: AnimationCurve[T], i: int): Point = newPoint(c.sampler.keys[i].inX, c.sampler.keys[i].inY)

method setKeyInTangent*(c: AbstractAnimationCurve, i: int, p: Point) {.base.} = discard
method setKeyInTangent*[T](c: AnimationCurve[T], i: int, p: Point) =
    c.sampler.keys[i].inX = p.x
    c.sampler.keys[i].inY = p.y

method keyOutTangent*(c: AbstractAnimationCurve, i: int): Point {.base.} = zeroPoint
method keyOutTangent*[T](c: AnimationCurve[T], i: int): Point = newPoint(c.sampler.keys[i].outX, c.sampler.keys[i].outY)

method setKeyOutTangent*(c: AbstractAnimationCurve, i: int, p: Point) {.base.} = discard
method setKeyOutTangent*[T](c: AnimationCurve[T], i: int, p: Point) =
    c.sampler.keys[i].outX = p.x
    c.sampler.keys[i].outY = p.y

proc `[]`(c: Color, i: int): Coord =
    case i
    of 0: c.r
    of 1: c.g
    of 2: c.b
    of 3: c.a
    else: 0

proc `[]=`(c: var Color, i: int, v: Coord) =
    case i
    of 0: c.r = v
    of 1: c.g = v
    of 2: c.b = v
    of 3: c.a = v
    else: discard

method keyValue*(c: AbstractAnimationCurve, iKey, iDimension: int): Coord {.base.} = 0
method keyValue*[T](c: AnimationCurve[T], iKey, iDimension: int): Coord =
    when T is Coord | int | int16 | bool:
        Coord(c.sampler.keys[iKey].v)
    elif T is Vector2 | Vector3 | Vector4 | Color:
        Coord(c.sampler.keys[iKey].v[iDimension])
    elif T is Quaternion:
        Coord(array[4, Coord](c.sampler.keys[iKey].v)[iDimension])
    else:
        {.error: "Unknown type".}

method setKeyValue*(c: AbstractAnimationCurve, iKey, iDimension: int, v: Coord) {.base.} = discard
method setKeyValue*[T](c: AnimationCurve[T], iKey, iDimension: int, v: Coord) =
    when T is Coord | int | int16 | bool:
        c.sampler.keys[iKey].v = T(v)
    elif T is Vector2 | Vector3 | Vector4 | Color:
        c.sampler.keys[iKey].v[iDimension] = v
    elif T is Quaternion:
        array[4, Coord](c.sampler.keys[iKey].v)[iDimension] = v
    else:
        {.error: "Unknown type".}

proc keyPoint*(c: AbstractAnimationCurve, iKey, iDimension: int): Point =
    result.x = c.keyTime(iKey)
    result.y = c.keyValue(iKey, iDimension)

proc setKeyPoint*(c: AbstractAnimationCurve, iKey, iDimension: int, p: Point) =
    c.setKeyTime(iKey, p.x)
    c.setKeyValue(iKey, iDimension, p.y)

proc keyInTangentAbs*(c: AbstractAnimationCurve, iKey, iDimension: int): Point =
    result = c.keyPoint(iKey, iDimension)
    let p2 = c.keyPoint(iKey - 1, iDimension)
    let t = c.keyInTangent(iKey)
    result.x -= (result.x - p2.x) * t.x
    result.y -= t.y

proc keyOutTangentAbs*(c: AbstractAnimationCurve, iKey, iDimension: int): Point =
    result = c.keyPoint(iKey, iDimension)
    let p2 = c.keyPoint(iKey + 1, iDimension)
    let t = c.keyOutTangent(iKey)
    result.x += (p2.x - result.x) * t.x
    result.y += t.y

proc setKeyInTangentAbs*(c: AbstractAnimationCurve, iKey, iDimension: int, v: Point) =
    let kp = c.keyPoint(iKey, iDimension)
    let pp = c.keyPoint(iKey - 1, iDimension)
    var relTangent = kp - v
    relTangent.x /= kp.x - pp.x
    c.setKeyInTangent(iKey, relTangent)

proc setKeyOutTangentAbs*(c: AbstractAnimationCurve, iKey, iDimension: int, v: Point) =
    let kp = c.keyPoint(iKey, iDimension)
    let np = c.keyPoint(iKey + 1, iDimension)
    var relTangent = v - kp
    relTangent.x /= np.x - kp.x
    c.setKeyOutTangent(iKey, relTangent)

method deleteKey*(c: AbstractAnimationCurve, iKey: int) {.base.} = discard
method deleteKey*[T](c: AnimationCurve[T], iKey: int) = c.sampler.keys.delete(iKey)

method applyValueAtPosToSetter*(c: AbstractAnimationCurve, pos: float, sng: Variant) {.base.} = discard
method applyValueAtPosToSetter*[T](c: AnimationCurve[T], pos: float, sng: Variant) =
    sng.get(SetterAndGetter[T]).setter(c.sampler.sample(pos))

method addKeyAtPosWithValueFromGetter*(c: AbstractAnimationCurve, pos: float, sng: Variant) {.base.} = discard
method addKeyAtPosWithValueFromGetter*[T](c: AnimationCurve[T], pos: float, sngv: Variant) =
    var k: BezierKeyFrame[T]
    k.p = pos
    
    let sng = sngv.get(SetterAndGetter[T])
    echo "addKeyAtPos has valid type ", sngv.ofType(SetterAndGetter[T]), " isnil ", sng.getter.isnil, " T ", T
    k.v = sng.getter()
    k.inX = -0.5
    k.inY = 50
    k.outX = 0.5
    k.outY = -50
    let lb = lowerBound(c.sampler.keys, k) do(a, b: BezierKeyFrame[T]) -> int:
        cmp(a.p, b.p)
    c.sampler.keys.insert(k, lb)

proc newAnimationCurve*[T](s: BezierKeyFrameAnimationSampler[T]): AnimationCurve[T] =
    result.new()
    result.sampler = s

proc newAnimationCurve*[T](): AnimationCurve[T] = newAnimationCurve(newBezierKeyFrameAnimationSampler[T](@[]))
