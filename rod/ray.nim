import nimx.matrixes
import nimx.types

type Ray* = object
    origin*: Vector3
    direction*: Vector3

proc intersectWithPlane*(r: Ray, planeNormal: Vector3, dist: Coord, output: var Vector3): bool =
    var denom = dot(r.direction, planeNormal)
    if denom != 0:
        var t = -(dot(r.origin, planeNormal) + dist) / denom
        if t < 0:
            return false
        output = r.origin + r.direction * t
        return true
    elif dot(planeNormal, r.origin) + dist == 0:
        output = r.origin
        return true
    else:
        return false

proc intersectWithPlane*(r: Ray, planeNormal, pointOnPlane: Vector3, output: var Vector3): bool =
    r.intersectWithPlane(planeNormal, -dot(planeNormal, pointOnPlane), output)
