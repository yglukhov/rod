import times
import math

import rod.quaternion
import rod.component
import rod.rod_types

import nimx.matrixes
import nimx.animation
import nimx.types

type
    ParticleGenerationData* = object
        position*: Vector3
        direction*: Vector3

    ParticleGenerationShape* = ref object of RootObj
        is2D: bool

    ConeParticleGenerationShape* = ref object of ParticleGenerationShape
        radius*: float32
        angle*: float32

proc newConeGenerationShape*(angle, radius: float32): ConeParticleGenerationShape =
    result.new()
    result.angle = angle
    if result.angle <= 0:
        result.angle = 0.000001
    result.radius = radius
    if result.radius <= 0:
        result.radius = 0.00001

method generate*(pgs: ParticleGenerationShape): ParticleGenerationData {.base.} = discard

method generate*(pgs: ConeParticleGenerationShape): ParticleGenerationData =
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