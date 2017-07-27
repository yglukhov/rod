import algorithm
import nimx.types, nimx.matrixes, nimx.animation, nimx.property_visitor
import variant

import rod.animation.animation_sampler, rod.quaternion

type
    AbstractAnimationCurve* = ref object of RootObj
        color*: Color
    AnimationCurve*[T] = ref object of AbstractAnimationCurve
        sampler*: BezierKeyFrameAnimationSampler[T]

method getSampler*(a: AbstractAnimationCurve): AbstractAnimationSampler {.base.} = nil
method getSampler*[T](a: AnimationCurve[T]): AbstractAnimationSampler = a.sampler

method numberOfKeys*(c: AbstractAnimationCurve): int {.base.} = 0
method numberOfKeys*[T](c: AnimationCurve[T]): int = c.sampler.keys.len

method numberOfDimensions*(c: AbstractAnimationCurve): int {.base.} = 0
method numberOfDimensions*[T](c: AnimationCurve[T]): int =
    when T is Coord | int | bool:
        1
    elif T is Vector2:
        2
    elif T is Vector3:
        3
    elif T is Vector4 | Color | Quaternion:
        4
    else:
        {.error: "Unknown type".}

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
    when T is Coord | int | bool:
        Coord(c.sampler.keys[iKey].v)
    elif T is Vector2 | Vector3 | Vector4 | Color:
        Coord(c.sampler.keys[iKey].v[iDimension])
    elif T is Quaternion:
        Coord(array[4, Coord](c.sampler.keys[iKey].v)[iDimension])
    else:
        {.error: "Unknown type".}

method setKeyValue*(c: AbstractAnimationCurve, iKey, iDimension: int, v: Coord) {.base.} = discard
method setKeyValue*[T](c: AnimationCurve[T], iKey, iDimension: int, v: Coord) =
    when T is Coord | int | bool:
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
method addKeyAtPosWithValueFromGetter*[T](c: AnimationCurve[T], pos: float, sng: Variant) =
    var k: BezierKeyFrame[T]
    k.p = pos
    k.v = sng.get(SetterAndGetter[T]).getter()
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
