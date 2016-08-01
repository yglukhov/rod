import nimx.types

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
    c.keys.add(k)
