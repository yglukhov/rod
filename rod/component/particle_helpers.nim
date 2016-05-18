import times
import math
import json

import rod.quaternion
import rod.component
import rod.rod_types
import rod.property_visitor
import rod.tools.serializer_helpers

import nimx.matrixes
import nimx.animation
import nimx.types

type
    ParticleGenerationData* = object
        position*: Vector3
        direction*: Vector3

    PSGenShape* = ref object of Component
        is2D*: bool

    ConePSGenShape* = ref object of PSGenShape
        radius*: float
        angle*: float

    SpherePSGenShape* = ref object of PSGenShape
        radius*: float
        isRandPos*: bool
        isRandDir*: bool

    BoxPSGenShape* = ref object of PSGenShape
        dimension*: Vector3

    PSAttractor* = ref object of Component
        position*: Vector3
        forceValue*: float

    WavePSAttractor* = ref object of PSAttractor
        frequence*: float32

method generate*(pgs: PSGenShape): ParticleGenerationData {.base.} = discard
method getForceAtPoint*(attr: PSAttractor, point: Vector3): Vector3 {.base.} = discard


# -------------------- cone generator --------------------------
method init(pgs: ConePSGenShape) =
    pgs.angle = 45.0
    pgs.radius = 0.000001

method generate*(pgs: ConePSGenShape): ParticleGenerationData =
    if pgs.is2D:
        result.position = newVector3(random(-pgs.radius .. pgs.radius), 0.0, 0.0)
        let dirAngle = degToRad(pgs.angle) * result.position.x / pgs.radius
        result.direction = newVector3(sin(dirAngle), cos(dirAngle), 0.0)

    else:
        let rand_angle = random(2 * 3.14)
        let distance = random(pgs.radius)

        let pos = newVector3(distance * cos(rand_angle), 0.0, distance * sin(rand_angle))

        let dirAngle = degToRad(pgs.angle) * distance/pgs.radius
        var dir: Vector3
        dir.y = cos(dirAngle)
        let dirXZ = sin(dirAngle)
        dir.x = dirXZ * cos(rand_angle)
        dir.z = dirXZ * sin(rand_angle)

        result.position = pos
        result.direction = dir

method deserialize*(pgs: ConePSGenShape, j: JsonNode) =
    if j.isNil:
        return

    j.getSerializedValue("angle", pgs.angle)
    j.getSerializedValue("radius", pgs.radius)
    j.getSerializedValue("is2D", pgs.is2D)

method visitProperties*(pgs: ConePSGenShape, p: var PropertyVisitor) =
    p.visitProperty("angle", pgs.angle)
    p.visitProperty("radius", pgs.radius)
    p.visitProperty("is2D", pgs.is2D)


# -------------------- spherical generator --------------------------
method init(pgs: SpherePSGenShape) =
    pgs.radius = 0.0

template generateRandDir(pd: var ParticleGenerationData, is2D: bool) =
    if is2D:
        pd.direction = newVector3(random(-1.0..1.0), random(-1.0..1.0), 0.0)
        pd.direction.normalize()

    else:
        pd.direction = newVector3(random(-1.0..1.0), random(-1.0..1.0), random(-1.0..1.0))
        pd.direction.normalize()

method generate*(pgs: SpherePSGenShape): ParticleGenerationData =
    if pgs.isRandPos:
        if pgs.is2D:
            let angle = random(2 * 3.14)
            let r = random(pgs.radius)

            result.position.x = r * cos(angle)
            result.position.y = r * sin(angle)

        else:
            let theta = random(2 * 3.14)
            let phi = random((-3.14/2) .. (3.14/2))
            let r = random(pgs.radius)

            result.position.x = r * cos(theta) * cos(phi)
            result.position.y = r * sin(phi)
            result.position.z = r * sin(theta) * cos(phi)

        if pgs.isRandDir:
            result.generateRandDir(pgs.is2D)
        else:
            result.direction = result.position
            result.direction.normalize()

    else:
        result.generateRandDir(pgs.is2D)

method deserialize*(pgs: SpherePSGenShape, j: JsonNode) =
    if j.isNil:
        return

    j.getSerializedValue("radius", pgs.radius)
    j.getSerializedValue("is2D", pgs.is2D)
    j.getSerializedValue("isRandPos", pgs.isRandPos)
    j.getSerializedValue("isRandDir", pgs.isRandDir)

method visitProperties*(pgs: SpherePSGenShape, p: var PropertyVisitor) =
    p.visitProperty("radius", pgs.radius)
    p.visitProperty("is2D", pgs.is2D)
    p.visitProperty("isRandPos", pgs.isRandPos)
    p.visitProperty("isRandDir", pgs.isRandDir)

# -------------------- box generator --------------------------
method init(pgs: BoxPSGenShape) =
    pgs.dimension = newVector3(10.0, 10.0, 10.0)

method generate*(pgs: BoxPSGenShape): ParticleGenerationData =
    let d = pgs.dimension / 2.0
    if pgs.is2D:
        result.position = newVector3(random(-d.x .. d.x), random(-d.y .. d.y), 0.0)
    else:
        result.position = newVector3(random(-d.x .. d.x), random(-d.y .. d.y), random(-d.z .. d.z))

method deserialize*(pgs: BoxPSGenShape, j: JsonNode) =
    if j.isNil:
        return

    j.getSerializedValue("dimension", pgs.dimension)
    j.getSerializedValue("is2D", pgs.is2D)

method visitProperties*(pgs: BoxPSGenShape, p: var PropertyVisitor) =
    p.visitProperty("dimension", pgs.dimension)
    p.visitProperty("is2D", pgs.is2D)

# -------------------- wave attractor --------------------------
method init(attr: WavePSAttractor) =
    attr.forceValue = 0.1
    attr.frequence = 1

method getForceAtPoint*(attr: WavePSAttractor, point: Vector3): Vector3 =
    # result.y = -point.y * attr.forceValue
    result.y = cos(point.x / attr.frequence) * attr.forceValue

method deserialize*(attr: WavePSAttractor, j: JsonNode) =
    if j.isNil:
        return

    j.getSerializedValue("forceValue", attr.forceValue)
    j.getSerializedValue("frequence", attr.frequence)


method visitProperties*(attr: WavePSAttractor, p: var PropertyVisitor) =
    p.visitProperty("forceValue", attr.forceValue)
    p.visitProperty("frequence", attr.frequence)



registerComponent[ConePSGenShape]()
registerComponent[SpherePSGenShape]()
registerComponent[BoxPSGenShape]()

registerComponent[WavePSAttractor]()
