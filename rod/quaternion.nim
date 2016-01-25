import math

import nimx.types
import nimx.matrixes

const ForwardVector* = newVector3(0, 0, -1)
const UpVector* = newVector3(0, 1, 0)
const DownVector* = -UpVector
const LeftVector* = newVector3(-1, 0, 0)
const RightVector* = -LeftVector

type Quaternion* = TVector4[Coord]

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
    let rangle = degToRad(angle) / 2
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
    let qVec = lhs.xyz
    let cross1 = qVec.cross(rhs)
    let cross2 = qVec.cross(cross1)
    return rhs + (cross1 * lhs.w + cross2) * 2

proc newQuaternionFromEulerZXY*(x, y, z: Coord): Quaternion = aroundZ(z) * aroundX(x) * aroundY(y)
proc newQuaternionFromEulerXYZ*(x, y, z: Coord): Quaternion = aroundX(x) * aroundY(y) * aroundZ(z)
proc newQuaternionFromEulerYXZ*(x, y, z: Coord): Quaternion = aroundY(y) * aroundX(x) * aroundZ(z)

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

proc fromMatrix4*(mat: Matrix4): Quaternion = 
    var s, x, y, z, w: Coord
    if mat[0] > mat[5] and mat[0] > mat[10]:
        s = sqrt(1.0 + mat[0] - mat[5] - mat[10]) * 2.0
        x = 0.25 * s
        y = (mat[4] + mat[1]) / s
        z = (mat[2] + mat[8]) / s
        w = (mat[9] - mat[6]) / s
    elif mat[5] > mat[10]:
        s = sqrt(1.0 + mat[5] - mat[0] - mat[10]) * 2.0
        x = (mat[4] + mat[1]) / s
        y = 0.25 * s
        z = (mat[9] + mat[6]) / s
        w = (mat[2] - mat[8]) / s
    else:
        s = sqrt(1.0 + mat[10] - mat[0] - mat[5]) * 2.0
        x = (mat[2] + mat[8]) / s
        y = (mat[9] + mat[6]) / s
        z = 0.25 * s
        w = (mat[4] - mat[1]) / s
    result = newQuaternion(x, y, z, w)

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

proc conjugated*(q: Quaternion): Quaternion = [-q.x, -q.y, -q.z, q.w]

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
