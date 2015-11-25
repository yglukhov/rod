import nimx.types
import nimx.matrixes

type SetterAndGetter[T] = tuple[setter: proc(v: T), getter: proc(): T]

type PropertyKind* = enum
    pkCoord,
    pkVec2,
    pkVec3,
    pkVec4,
    pkColor

type PropertyVisitor* = object of RootObj
    qualifiers: seq[string]
    requireSetter*: bool
    requireGetter*: bool
    requireName*: bool

    case kind*: PropertyKind
    of pkCoord: tcoord*: SetterAndGetter[Coord]
    of pkVec2: tvec2*: SetterAndGetter[Vector2]
    of pkVec3: tvec3*: SetterAndGetter[Vector3]
    of pkVec4: tvec4*: SetterAndGetter[Vector4]
    of pkColor: tcolor*: SetterAndGetter[Color]
    name*: string
    commit*: proc()

template clear(sg: SetterAndGetter) =
    sg.setter = nil
    sg.getter = nil

proc clear*(p: var PropertyVisitor) =
    p.tcoord.clear()
    p.tvec2.clear()
    p.tvec2.clear()
    p.tvec4.clear()

proc pushQualifier*(p: var PropertyVisitor, q: string) =
    if p.qualifiers.isNil:
        p.qualifiers = newSeq[string]()
    p.qualifiers.add(q)

proc popQualifier*(p: var PropertyVisitor) =
    p.qualifiers.setLen(p.qualifiers.len - 1)

template kindForType(t: typedesc[Coord]): PropertyKind = pkCoord
template kindForType(t: typedesc[Vector2]): PropertyKind = pkVec2
template kindForType(t: typedesc[Vector3]): PropertyKind = pkVec3
template kindForType(t: typedesc[Vector4]): PropertyKind = pkVec4
template kindForType(t: typedesc[Color]): PropertyKind = pkColor

proc setSetter*(p: var PropertyVisitor, s: proc(c: Coord)) = p.tcoord.setter = s
proc setSetter*(p: var PropertyVisitor, s: proc(c: Vector2)) = p.tvec2.setter = s
proc setSetter*(p: var PropertyVisitor, s: proc(c: Vector3)) = p.tvec3.setter = s
proc setSetter*(p: var PropertyVisitor, s: proc(c: Vector4)) = p.tvec4.setter = s
proc setSetter*(p: var PropertyVisitor, s: proc(c: Color)) = p.tcolor.setter = s

proc setGetter*(p: var PropertyVisitor, s: proc(): Coord) = p.tcoord.getter = s
proc setGetter*(p: var PropertyVisitor, s: proc(): Vector2) = p.tvec2.getter = s
proc setGetter*(p: var PropertyVisitor, s: proc(): Vector3) = p.tvec3.getter = s
proc setGetter*(p: var PropertyVisitor, s: proc(): Vector4) = p.tvec4.getter = s
proc setGetter*(p: var PropertyVisitor, s: proc(): Color) = p.tcolor.getter = s

template visitProperty*(p: PropertyVisitor, propName: string, s: untyped) =
    p.kind = kindForType(type(s))
    if p.requireSetter:
        p.setSetter(proc(v: type(s)) = s = v)
    if p.requireGetter:
        p.setGetter(proc(): type(s) = s)
    if p.requireName:
        p.name = propName
    p.commit()
