import algorithm
import nimx.types, nimx.animation

type
    KeyFrame* = object
        p*: float
        v*: float
        inTangent*: Point
        outTangent*: Point

    AnimationCurve* = ref object
        keys*: seq[KeyFrame]
        color*: Color

proc point*(k: KeyFrame): Point = newPoint(k.p, k.v)
proc inTangentAbs*(k: KeyFrame): Point = k.point + k.inTangent
proc outTangentAbs*(k: KeyFrame): Point = k.point + k.outTangent

proc `point=`*(k: var KeyFrame, p: Point) =
    k.p = p.x
    k.v = p.y

proc newAnimationCurve*(): AnimationCurve =
    result.new()
    result.keys = @[]

proc addKey*(c: AnimationCurve, p, v: float) =
    var k: KeyFrame
    k.p = p
    k.v = v
    k.inTangent = newPoint(-0.5, 50)
    k.outTangent = newPoint(0.5, -50)
    let lb = lowerBound(c.keys, k) do(a, b: KeyFrame) -> int:
        cmp(a.p, b.p)
    c.keys.insert(k, lb)

proc valueAtPos*(c: AnimationCurve, p: float): float =
    let s = c
    if p < 0:
        return s.keys[0].v
    elif p > 1:
        return s.keys[^1].v

    var k : KeyFrame
    k.p = p
    let lb = lowerBound(s.keys, k) do(a, b: KeyFrame) -> int:
        cmp(a.p, b.p)

    if lb >= s.keys.len: return s.keys[^1].v

    var a, b : int
    if p < s.keys[lb].p:
        if lb == 0: return s.keys[0].v
        a = lb - 1
        b = lb
    elif p > s.keys[lb].p:
        a = lb
        b = lb + 1
    else:
        return s.keys[lb].v

    let temporalLength = s.keys[b].p - s.keys[a].p
    let normalizedP = (p - s.keys[a].p) / temporalLength

    let spacialLength = abs(s.keys[b].v - s.keys[a].v)

    # echo "a: ", s.keys[a].v
    # echo "b: ", s.keys[b].v
    # echo "len: ", spacialLength
    # echo "1: ", s.keys[a].outTangent.x / temporalLength, ", ", s.keys[a].outTangent.y / spacialLength
    # echo "2: ", -s.keys[b].inTangent.x / temporalLength, ", ", s.keys[b].inTangent.y / spacialLength
    # echo "p: ", normalizedP
    result = bezierXForProgress(s.keys[a].outTangent.x / temporalLength,
                        s.keys[a].outTangent.y / spacialLength,
                        -s.keys[b].inTangent.x / temporalLength,
                        s.keys[b].inTangent.y / spacialLength,
                        normalizedP)
    result = s.keys[a].v + result * spacialLength
    # echo "result: ", result
    #result = interpolate(s.keys[a].v, s.keys[b].v, normalizedP)
