import nimx.matrixes
import nimx.types
import rod.rod_types

type RayCastInfo* = object
    node*: Node
    distance*: float32
    position*: Vector3

type Ray* = object
    origin*: Vector3
    direction*: Vector3

proc transform*(r:Ray, mat:Matrix4): Ray =
    result.direction.x = r.direction.x * mat[0] + r.direction.y * mat[4] + r.direction.z * mat[8]
    result.direction.y = r.direction.x * mat[1] + r.direction.y * mat[5] + r.direction.z * mat[9]
    result.direction.z = r.direction.x * mat[2] + r.direction.y * mat[6] + r.direction.z * mat[10]
    # result.direction.normalize()

    result.origin = mat * r.origin

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


proc intersectWithAABB*(r: Ray, minCoord, maxCoord: Vector3, distance: var float32): bool =
    #  r.direction is unit direction vector of ray
    var dirfrac = newVector3(1.0 / r.direction.x, 1.0 / r.direction.y, 1.0 / r.direction.z)

    #  minCoord is the corner of AABB with minimal coordinates - left bottom, maxCoord is maximal corner
    #  r.origin is origin of ray
    let t1 = (minCoord.x - r.origin.x)*dirfrac.x
    let t2 = (maxCoord.x - r.origin.x)*dirfrac.x
    let t3 = (minCoord.y - r.origin.y)*dirfrac.y
    let t4 = (maxCoord.y - r.origin.y)*dirfrac.y
    let t5 = (minCoord.z - r.origin.z)*dirfrac.z
    let t6 = (maxCoord.z - r.origin.z)*dirfrac.z

    let tmin = max(max(min(t1, t2), min(t3, t4)), min(t5, t6))
    let tmax = min(min(max(t1, t2), max(t3, t4)), max(t5, t6))

    # if tmax < 0, ray (line) is intersecting AABB, but whole AABB is behing us
    if tmax < 0.0 or tmin < 0.0:
        return false

    # if tmin > tmax, ray doesn't intersect AABB
    if tmin > tmax :
        return false

    distance = tmin
    return true

proc intersectWithTriangle(r: Ray, v0, v1, v2: Vector3, distance: var float32): bool {.used.} =
    let edge1 = v1 - v0
    let edge2 = v2 - v0
    let pvec = cross(r.direction, edge2)
    var u, v: float32

    let det = dot(edge1, pvec) #edge1.x * pvec.x + edge1.y * pvec.y + edge1.z * pvec.z #edge1 & pvec;
    var tvec = newVector3(0.0)
    var qvec = newVector3(0.0)

    if det > 0.0001 :
        tvec = r.origin - v0
        u = dot(tvec, pvec) # tvec.x * pvec.x + tvec.y * pvec.y + tvec.z * pvec.z #tvec & pvec;
        if u < 0.0f or u > det :
            return false

        qvec = cross(tvec, edge1)
        v = dot(r.direction, qvec) #r.direction.x * qvec.x + r.direction.y * qvec.y + r.direction.z * qvec.z  #dir & qvec;
        if v < 0.0f or u + v > det :
            return false

    elif det < -0.0001 :
        tvec = r.origin - v0
        u = dot(tvec, pvec) #tvec.x * pvec.x + tvec.y * pvec.y + tvec.z * pvec.z #tvec & pvec;
        if u > 0.0f or u < det :
            return false

        qvec = cross(tvec, edge1)
        v = dot(r.direction, qvec) #r.direction.x * qvec.x + r.direction.y * qvec.y + r.direction.z * qvec.z  #dir & qvec;
        if v > 0.0f or u + v < det :
            return false
    else:
        return false

    distance = edge2.x * qvec.x + edge2.y * qvec.y + edge2.z * qvec.z  # edge2 & qvec;
    var fInvDet = 1.0 / det
    distance *= fInvDet
    return true
