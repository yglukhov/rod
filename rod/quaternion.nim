import math

import nimx.types
import nimx.matrixes

const ForwardVector* = newVector3(0, 0, -1)
const UpVector* = newVector3(0, 1, 0)
const DownVector* = -UpVector
const LeftVector* = newVector3(-1, 0, 0)
const RightVector* = -LeftVector

type Quaternion* = distinct array[4, Coord]


template toArr(q: Quaternion): array[4, Coord] =
    array[4, Coord](q)

template x*(v: Quaternion): Coord = toArr(v)[0]
template y*(v: Quaternion): Coord = toArr(v)[1]
template z*(v: Quaternion): Coord = toArr(v)[2]
template w*(v: Quaternion): Coord = toArr(v)[3]

template `x=`*(v: var Quaternion, val: Coord) = toArr(v)[0] = val
template `y=`*(v: var Quaternion, val: Coord) = toArr(v)[1] = val
template `z=`*(v: var Quaternion, val: Coord) = toArr(v)[2] = val
template `w=`*(v: var Quaternion, val: Coord) = toArr(v)[3] = val

proc `$`*(q: Quaternion): string {.inline.} = $(TVector4[Coord](q))

proc newQuaternion*(): Quaternion =
    result.w = 1

proc newQuaternion*(x, y, z, w: Coord): Quaternion =
    result.w = w
    result.x = x
    result.y = y
    result.z = z

proc newQuaternion*(angle: Coord, axis: Vector3): Quaternion =
    var normAxis = axis
    normAxis.normalize()
    let rangle = -degToRad(angle) / 2
    let sinAngle = sin(rangle)
    let cosAngle = cos(rangle)

    result.w = cosAngle
    result.x = normAxis.x * sinAngle
    result.y = normAxis.y * sinAngle
    result.z = normAxis.z * sinAngle

template aroundX*(x: Coord): Quaternion = newQuaternion(x, newVector3(1, 0, 0))
template aroundY*(y: Coord): Quaternion = newQuaternion(y, newVector3(0, 1, 0))
template aroundZ*(z: Coord): Quaternion = newQuaternion(z, newVector3(0, 0, 1))

proc newQuaternion*(x, y, z: Coord): Quaternion =
    # Order of rotations: Z first, then X, then Y (mimics typical FPS camera with gimbal lock at top/bottom)
    let xr = degToRad(x) / 2
    let yr = degToRad(y) / 2
    let zr = degToRad(z) / 2
    let sinX = sin(xr)
    let cosX = cos(xr)
    let sinY = sin(yr)
    let cosY = cos(yr)
    let sinZ = sin(zr)
    let cosZ = cos(zr)

    result.w = cosY * cosX * cosZ + sinY * sinX * sinZ
    result.x = cosY * sinX * cosZ + sinY * cosX * sinZ
    result.y = sinY * cosX * cosZ - cosY * sinX * sinZ
    result.z = cosY * cosX * sinZ - sinY * sinX * cosZ

proc multiply*(q1, rhs: Quaternion, res: var Quaternion) =
    res.w = q1.w * rhs.w - q1.x * rhs.x - q1.y * rhs.y - q1.z * rhs.z
    res.x = q1.w * rhs.x + q1.x * rhs.w + q1.y * rhs.z - q1.z * rhs.y
    res.y = q1.w * rhs.y + q1.y * rhs.w + q1.z * rhs.x - q1.x * rhs.z
    res.z = q1.w * rhs.z + q1.z * rhs.w + q1.x * rhs.y - q1.y * rhs.x

proc `*`*(lhs, rhs: Quaternion): Quaternion =
    multiply(lhs, rhs, result)

proc `*`*(lhs: Quaternion, rhs: Vector3): Vector3 =
    let qVec = newVector3(lhs.x, lhs.y, lhs.z)
    let cross1 = qVec.cross(rhs)
    let cross2 = qVec.cross(cross1)
    return rhs + (cross1 * lhs.w + cross2) * 2

template `*`*(lhs: Quaternion, rhs: float32): Quaternion = Quaternion(TVector4[Coord](lhs) * rhs)
template `/`*(lhs: Quaternion, rhs: float32): Quaternion = Quaternion(TVector4[Coord](lhs) / rhs)
template `-`*(lhs, rhs: Quaternion): Quaternion = Quaternion(TVector4[Coord](lhs) - TVector4[Coord](rhs))
template `+`*(lhs, rhs: Quaternion): Quaternion = Quaternion(TVector4[Coord](lhs) + TVector4[Coord](rhs))

proc `*=`*(q1: var Quaternion, q2: Quaternion) =
    var qc = q1
    multiply(qc, q2, q1)

proc newQuaternionFromEulerZXY*(x, y, z: Coord): Quaternion = aroundZ(z) * aroundX(x) * aroundY(y)
proc newQuaternionFromEulerXYZ*(x, y, z: Coord): Quaternion = aroundX(x) * aroundY(y) * aroundZ(z)
proc newQuaternionFromEulerYXZ*(x, y, z: Coord): Quaternion = aroundY(y) * aroundX(x) * aroundZ(z)
proc newQuaternionFromEulerYZX*(x, y, z: Coord): Quaternion = aroundY(y) * aroundZ(z) * aroundX(x)


 #     |       2     2                                |
 #     | 1 - 2Y  - 2Z    2XY - 2ZW      2XZ + 2YW     |
 #     |                                              |
 #     |                       2     2                |
 # M = | 2XY + 2ZW       1 - 2X  - 2Z   2YZ - 2XW     |
 #     |                                              |
 #     |                                      2     2 |
 #     | 2XZ - 2YW       2YZ + 2XW      1 - 2X  - 2Y  |

proc toMatrix4*(q: Quaternion): Matrix4 =
    var qw = q.w;
    var qx = q.x;
    var qy = q.y;
    var qz = q.z;

    let n = 1.0f / sqrt(qx*qx + qy*qy + qz*qz + qw*qw)
    qx *= n
    qy *= n
    qz *= n
    qw *= n

    result = [
        1.0f - 2.0f*qy*qy - 2.0f*qz*qz, 2.0f*qx*qy - 2.0f*qz*qw, 2.0f*qx*qz + 2.0f*qy*qw, 0.0f,
        2.0f*qx*qy + 2.0f*qz*qw, 1.0f - 2.0f*qx*qx - 2.0f*qz*qz, 2.0f*qy*qz - 2.0f*qx*qw, 0.0f,
        2.0f*qx*qz - 2.0f*qy*qw, 2.0f*qy*qz + 2.0f*qx*qw, 1.0f - 2.0f*qx*qx - 2.0f*qy*qy, 0.0f,
        0.0f, 0.0f, 0.0f, 1.0f]

proc lengthSquared*(q: Quaternion): Coord = q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z

proc isAround(lhs, rhs: Coord): bool =
    const M_EPSILON = 0.000001
    result = lhs + M_EPSILON >= rhs and lhs - M_EPSILON <= rhs

proc normalized*(q: Quaternion): Quaternion =
    let lenSquared = q.lengthSquared()
    if lenSquared > 0 and not lenSquared.isAround(1.0):
        let invLen = 1.0f / sqrt(lenSquared)
        return q * invLen
    else:
        return q

proc conjugated*(q: Quaternion): Quaternion = newQuaternion(-q.x, -q.y, -q.z, q.w)

proc fromMatrix4*(mtx: Matrix4): Quaternion =
    var bigType: int32
    var quat: Quaternion

    # From the matrix diagonal element, calc (4q^2 - 1),
    # where q is each of the quaternion components: w, x, y & z.
    let fourWSqM1 =  mtx[0] + mtx[5] + mtx[10]
    let fourXSqM1 =  mtx[0] - mtx[5] - mtx[10]
    let fourYSqM1 = -mtx[0] + mtx[5] - mtx[10]
    let fourZSqM1 = -mtx[0] - mtx[5] + mtx[10]
    var bigFourSqM1: float32

    # // Determine the biggest quaternion component from the above options.
    bigType = 0
    bigFourSqM1 = fourWSqM1
    if fourXSqM1 > bigFourSqM1:
        bigFourSqM1 = fourXSqM1
        bigType = 1
    if fourYSqM1 > bigFourSqM1:
        bigFourSqM1 = fourYSqM1
        bigType = 2
    if fourZSqM1 > bigFourSqM1:
        bigFourSqM1 = fourZSqM1
        bigType = 3

    # // Isolate that biggest component value, q from the above formula
    # // (4q^2 - 1), and calculate the factor  (1 / 4q).
    let bigVal = sqrt(bigFourSqM1 + 1.0f) * 0.5f
    let oo4BigVal = 1.0f / (4.0f * bigVal)

    case bigType
    of 0:
        quat.w = bigVal
        quat.x = (mtx[6] - mtx[9]) * oo4BigVal
        quat.y = (mtx[8] - mtx[2]) * oo4BigVal
        quat.z = (mtx[1] - mtx[4]) * oo4BigVal

    of 1:
        quat.w = (mtx[6] - mtx[9]) * oo4BigVal
        quat.x = bigVal
        quat.y = (mtx[1] + mtx[4]) * oo4BigVal
        quat.z = (mtx[8] + mtx[2]) * oo4BigVal

    of 2:
        quat.w = (mtx[8] - mtx[2]) * oo4BigVal
        quat.x = (mtx[1] + mtx[4]) * oo4BigVal
        quat.y = bigVal
        quat.z = (mtx[6] + mtx[9]) * oo4BigVal

    of 3:
        quat.w = (mtx[1] - mtx[4]) * oo4BigVal
        quat.x = (mtx[8] + mtx[2]) * oo4BigVal
        quat.y = (mtx[6] + mtx[9]) * oo4BigVal
        quat.z = bigVal

    else:
        raise newException(Exception, "wrong quaternion big type")

    return normalized(quat)

 #     |  cycz + sxsysz   cxsz   cysxsz - czsy  |
 # M = |  czsxsy - cysz   cxcz   cyczsx + sysz  |
 #     |  cxsy            -sx    cxcy           |
proc Matrix4FromRotationYXZ*(aRotation: Vector3): Matrix4 =
    let rotRads = newVector3(degToRad(aRotation.x), degToRad(aRotation.y), degToRad(aRotation.z))

    let cx = cos(rotRads.x)
    let sx = sin(rotRads.x)
    let cy = cos(rotRads.y)
    let sy = sin(rotRads.y)
    let cz = cos(rotRads.z)
    let sz = sin(rotRads.z)

    result[0] = (cy * cz) + (sx * sy * sz)
    result[1] = cx * sz;
    result[2] = (cy * sx * sz) - (cz * sy)

    result[4] = (cz * sx * sy) - (cy * sz)
    result[5] = cx * cz
    result[6] = (cy * cz * sx) + (sy * sz)

    result[8] = cx * sy
    result[9] = -sx
    result[10] = cx * cy

    result[15] = 1.0f

# TODO Fix it. Looking like LeftHanded system
proc newQuaternionFromEulerYXZ_EX*(x, y, z: Coord): Quaternion =
    var rotMtx = Matrix4FromRotationYXZ(newVector3(x, y, z))
    return rotMtx.fromMatrix4()

proc eulerAngles*(q: Quaternion): Vector3 =
    # Derivation from http://www.geometrictools.com/Documentation/EulerAngles.pdf
    # Order of rotations: Z first, then X, then Y
    let check = 2.0f * (-q.y * q.z + q.w * q.x)

    if check < -0.995f:
        return newVector3(
            -90.0f,
            0.0f,
            radToDeg(-arctan2(2.0f * (q.x * q.z - q.w * q.y), 1.0f - 2.0f * (q.y * q.y + q.z * q.z)))
        )
    elif check > 0.995f:
        return newVector3(
            90.0f,
            0.0f,
            radToDeg(arctan2(2.0f * (q.x * q.z - q.w * q.y), 1.0f - 2.0f * (q.y * q.y + q.z * q.z)))
        )
    else:
        return newVector3(
            radToDeg(arcsin(check)),
            radToDeg(arctan2(2.0f * (q.x * q.z + q.w * q.y), 1.0f - 2.0f * (q.x * q.x + q.y * q.y))),
            radToDeg(arctan2(2.0f * (q.x * q.y + q.w * q.z), 1.0f - 2.0f * (q.x * q.x + q.z * q.z)))
        )

proc toPointTowards*(fwdDirection, upDirection: Vector3): Matrix4 =
     # where f is the normalized Forward vector (the direction being pointed to)
     # and u is the normalized Up vector in the rotated frame
     # and r is the normalized Right vector in the rotated frame
    var f = fwdDirection
    f.normalize()
    var r = cross(f, upDirection)
    r.normalize()
    var u = cross(r, f)

    result[0] = r.x;
    result[1] = r.y;
    result[2] = r.z;
    result[3] = 0.0;

    result[4] = u.x;
    result[5] = u.y;
    result[6] = u.z;
    result[7] = 0.0;

    result[8]  = -f.x;
    result[9]  = -f.y;
    result[10] = -f.z;
    result[11] = 0.0;

    result[12] = 0.0;
    result[13] = 0.0;
    result[14] = 0.0;
    result[15] = 1.0;

proc toLookAt*(targetLocation, eyeLocation, upDirection: Vector3): Matrix4 =
    var fwdDir = targetLocation - eyeLocation
    var pt = toPointTowards(fwdDir, upDirection)
    # pt.transpose()

    pt[12] += eyeLocation.x * pt[0] + eyeLocation.y * pt[4] + eyeLocation.z * pt[8];
    pt[13] += eyeLocation.x * pt[1] + eyeLocation.y * pt[5] + eyeLocation.z * pt[9];
    pt[14] += eyeLocation.x * pt[2] + eyeLocation.y * pt[6] + eyeLocation.z * pt[10];
    pt[15] += eyeLocation.x * pt[3] + eyeLocation.y * pt[7] + eyeLocation.z * pt[11];

    return pt

# proc StabilizeLength*(quat: var Quaternion) =
#    var cs = abs(quat.x) + abs(quat.y) + abs(quat.z) + abs(quat.w);
#    if cs > 0.0:
#        quat = newQuaternion(quat.x/cs, quat.y/cs, quat.z/cs, quat.w/cs)
#    else:
#        quat = newQuaternion()

# proc Norm*(quat: Quaternion): float32 =
#     return quat.x * quat.x + quat.y * quat.y + quat.z * quat.z + quat.w * quat.w

# proc Normalize(quat: var Quaternion) =
#     var m = sqrt(quat.Norm())
#     if m < 0.000001:
#         quat.StabilizeLength()
#         m = sqrt(quat.Norm())

#     quat.x = quat.x * (1.0 / m)
#     quat.y = quat.y * (1.0 / m)
#     quat.z = quat.z * (1.0 / m)
#     quat.w = quat.w * (1.0 / m)

# proc RotateVector*(quat: Quaternion, v: Vector3): Vector3 =
#     var q = newQuaternion(  v.x * quat.w + v.z * quat.y - v.y * quat.z,
#                             v.y * quat.w + v.x * quat.z - v.z * quat.x,
#                             v.z * quat.w + v.y * quat.x - v.x * quat.y,
#                             v.x * quat.x + v.y * quat.y + v.z * quat.z)
#     var s = 1.0 / quat.Norm()
#     result.x = (quat.w * q.x + quat.x * q.w + quat.y * q.z - quat.z * q.y) * s
#     result.y = (quat.w * q.y + quat.y * q.w + quat.z * q.x - quat.x * q.z) * s
#     result.z = (quat.w * q.z + quat.z * q.w + quat.x * q.y - quat.y * q.x) * s

# proc ShortestArc*(quat: var Quaternion, src, to: Vector3) =
#     var c = cross(src, to)
#     quat = newQuaternion(c.x, c.y, c.z, dot(src, to))
#     quat.Normalize()
#     quat.w += 1.0

#     if quat.w <= 0.00001:
#         if (src.z * src.z) > (src.x * src.x):
#             quat = newQuaternion(0, src.z, - src.y, quat.w)
#         else:
#             quat = newQuaternion(src.y, - src.x, 0, quat.w)

#     quat.Normalize()

