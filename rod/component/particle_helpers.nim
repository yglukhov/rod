import times
import math
import random
import json

import nimx.matrixes
import nimx.animation
import nimx.types
import nimx.property_visitor
import nimx.portable_gl
import nimx.context

import rod.quaternion
import rod.component
import rod.rod_types
import rod.tools.serializer
import rod / utils / [ property_desc, serialization_codegen ]
import rod.node
import rod.material.shader
import rod.tools.debug_draw
import rod.viewport
import rod.component.camera

type
    Particle* = object
        position*: Vector3
        rotation*, rotationVelocity*: Vector3 #deg per sec
        scale*: Vector3
        lifetime*: float32
        normalizedLifeTime*: float32
        color*: Color
        velocity*: Vector3
        randStartScale*: float32

    ParticleGenerationData* = object
        position*: Vector3
        direction*: Vector3

    PSGenShape* = ref object of Component
        is2D*: bool

    ConePSGenShape* = ref object of PSGenShape
        radius*: float32
        angle*: float32

    SpherePSGenShape* = ref object of PSGenShape
        radius*: float32
        isRandPos*: bool
        isRandDir*: bool

    BoxPSGenShape* = ref object of PSGenShape
        dimension*: Vector3

    PSModifier* = ref object of Component

    PSModifierWave* = ref object of PSModifier
        frequence*: float32
        forceValue*: float32

    PSModifierColor* = ref object of PSModifier
        distance: float32
        color: Color

    PSModifierSpiral* = ref object of PSModifier
        force: float32

    PSModifierRandWind* = ref object of PSModifier
        force: Vector3

ConePSGenShape.properties:
    radius
    angle
    is2D

SpherePSGenShape.properties:
    radius
    isRandPos
    isRandDir
    is2D

BoxPSGenShape.properties:
    dimension
    is2D

PSModifierRandWind.properties:
    force

PSModifierWave.properties:
    frequence
    forceValue

PSModifierColor.properties:
    distance
    color

PSModifierSpiral.properties:
    force

method generate*(pgs: PSGenShape): ParticleGenerationData {.base.} = discard

method getForceAtPoint*(attr: PSModifier, point: Vector3): Vector3 {.base.} = discard
method updateParticle*(attr: PSModifier, part: var Particle) {.base.} = discard

# -------------------- cone generator --------------------------
method init(pgs: ConePSGenShape) =
    pgs.angle = 45.0
    pgs.radius = 0.000001

method generate*(pgs: ConePSGenShape): ParticleGenerationData =
    if pgs.is2D:
        result.position = newVector3(rand(-pgs.radius .. pgs.radius), 0.0, 0.0)
        let dirAngle = degToRad(pgs.angle) * result.position.x / pgs.radius
        result.direction = newVector3(sin(dirAngle), cos(dirAngle), 0.0)

    else:
        let rand_angle = rand(2 * 3.14)
        let distance = rand(pgs.radius)

        let pos = newVector3(distance * cos(rand_angle), 0.0, distance * sin(rand_angle))

        let dirAngle = degToRad(pgs.angle) * distance/pgs.radius
        var dir: Vector3
        dir.y = cos(dirAngle)
        let dirXZ = sin(dirAngle)
        dir.x = dirXZ * cos(rand_angle)
        dir.z = dirXZ * sin(rand_angle)

        result.position = pos
        result.direction = dir

proc debugDraw(pgs: ConePSGenShape) =
    var dist = 5.0
    if pgs.node.sceneView.camera.projectionMode == cpOrtho:
        dist = 50.0
    let addRadius = sin(degToRad(pgs.angle)) * dist
    let height = cos(degToRad(pgs.angle)) * dist

    let gl = currentContext().gl
    gl.disable(gl.DEPTH_TEST)
    DDdrawCircle(newVector3(0.0), pgs.radius)
    DDdrawCircle(newVector3(0.0, height, 0.0), pgs.radius + addRadius)
    DDdrawArrow(dist)
    gl.disable(gl.DEPTH_TEST)

method draw*(pgs: ConePSGenShape) =
    if pgs.node.sceneView.editing:
        pgs.debugDraw()

method deserialize*(pgs: ConePSGenShape, j: JsonNode, s: Serializer) =
    if j.isNil:
        return

    s.deserializeValue(j, "angle", pgs.angle)
    s.deserializeValue(j, "radius", pgs.radius)
    s.deserializeValue(j, "is2D", pgs.is2D)

method serialize*(c: ConePSGenShape, s: Serializer): JsonNode =
    result = newJObject()
    result.add("angle", s.getValue(c.angle))
    result.add("radius", s.getValue(c.radius))
    result.add("is2D", s.getValue(c.is2D))

method visitProperties*(pgs: ConePSGenShape, p: var PropertyVisitor) =
    p.visitProperty("angle", pgs.angle)
    p.visitProperty("radius", pgs.radius)
    p.visitProperty("is2D", pgs.is2D)


# -------------------- spherical generator --------------------------
method init(pgs: SpherePSGenShape) =
    pgs.radius = 0.0

template generateRandDir(pd: var ParticleGenerationData, is2D: bool) =
    if is2D:
        pd.direction = newVector3(rand(-1.0..1.0), rand(-1.0..1.0), 0.0)
        pd.direction.normalize()

    else:
        pd.direction = newVector3(rand(-1.0..1.0), rand(-1.0..1.0), rand(-1.0..1.0))
        pd.direction.normalize()

method generate*(pgs: SpherePSGenShape): ParticleGenerationData =
    if pgs.isRandPos:
        if pgs.is2D:
            let angle = rand(2 * 3.14)
            let r = rand(pgs.radius)

            result.position.x = r * cos(angle)
            result.position.y = r * sin(angle)

        else:
            let theta = rand(2 * 3.14)
            let phi = rand((-3.14/2) .. (3.14/2))
            let r = rand(pgs.radius)

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

proc debugDraw*(pgs: SpherePSGenShape) =
    let gl = currentContext().gl
    gl.disable(gl.DEPTH_TEST)
    DDdrawCircle(newVector3(0.0), pgs.radius)
    DDdrawCircleX(newVector3(0.0), pgs.radius)
    DDdrawCircleZ(newVector3(0.0), pgs.radius)
    gl.disable(gl.DEPTH_TEST)


method draw*(pgs: SpherePSGenShape) =
    if pgs.node.sceneView.editing:
        pgs.debugDraw()

method deserialize*(pgs: SpherePSGenShape, j: JsonNode, s: Serializer) =
    if j.isNil:
        return

    s.deserializeValue(j, "radius", pgs.radius)
    s.deserializeValue(j, "is2D", pgs.is2D)
    s.deserializeValue(j, "isRandPos", pgs.isRandPos)
    s.deserializeValue(j, "isRandDir", pgs.isRandDir)

method serialize*(c: SpherePSGenShape, s: Serializer): JsonNode =
    result = newJObject()
    result.add("radius", s.getValue(c.radius))
    result.add("isRandPos", s.getValue(c.isRandPos))
    result.add("isRandDir", s.getValue(c.isRandDir))
    result.add("is2D", s.getValue(c.is2D))

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
        result.position = newVector3(rand(-d.x .. d.x), rand(-d.y .. d.y), 0.0)
    else:
        result.position = newVector3(rand(-d.x .. d.x), rand(-d.y .. d.y), rand(-d.z .. d.z))

proc debugDraw(pgs: BoxPSGenShape) =
    let gl = currentContext().gl
    gl.disable(gl.DEPTH_TEST)
    DDdrawBox(pgs.dimension)
    gl.disable(gl.DEPTH_TEST)

method draw*(pgs: BoxPSGenShape) =
    if pgs.node.sceneView.editing:
        pgs.debugDraw()

method deserialize*(pgs: BoxPSGenShape, j: JsonNode, s: Serializer) =
    if j.isNil:
        return

    s.deserializeValue(j, "dimension", pgs.dimension)
    s.deserializeValue(j, "is2D", pgs.is2D)

method serialize*(c: BoxPSGenShape, s: Serializer): JsonNode =
    result = newJObject()
    result.add("dimension", s.getValue(c.dimension))
    result.add("is2D", s.getValue(c.is2D))

method visitProperties*(pgs: BoxPSGenShape, p: var PropertyVisitor) =
    p.visitProperty("dimension", pgs.dimension)
    p.visitProperty("is2D", pgs.is2D)

# -------------------- wave Modifier --------------------------
method init(attr: PSModifierWave) =
    attr.forceValue = 0.1
    attr.frequence = 1

method updateParticle*(attr: PSModifierWave, part: var Particle) =
    part.position.y += cos( (part.position.x + attr.node.position.x) / attr.frequence) * attr.forceValue

method deserialize*(attr: PSModifierWave, j: JsonNode, s: Serializer) =
    if j.isNil:
        return
    s.deserializeValue(j, "forceValue", attr.forceValue)
    s.deserializeValue(j, "frequence", attr.frequence)

method serialize*(c: PSModifierWave, s: Serializer): JsonNode =
    result = newJObject()
    result.add("forceValue", s.getValue(c.forceValue))
    result.add("frequence", s.getValue(c.frequence))

method visitProperties*(attr: PSModifierWave, p: var PropertyVisitor) =
    p.visitProperty("forceValue", attr.forceValue)
    p.visitProperty("frequence", attr.frequence)

# -------------------- Color Modifier --------------------------
method init(attr: PSModifierColor) =
    attr.distance = 1
    attr.color = newColor(1.0, 1.0, 1.0, 1.0)

method updateParticle*(attr: PSModifierColor, part: var Particle) =
    let distance_vec = attr.node.position - part.position
    var distance = distance_vec.length()
    distance = min(distance / attr.distance, 1.0)
    part.color = part.color * distance + attr.color * (1.0 - distance)

method deserialize*(attr: PSModifierColor, j: JsonNode, s: Serializer) =
    if j.isNil:
        return
    s.deserializeValue(j, "distance", attr.distance)
    s.deserializeValue(j, "color", attr.color)

method serialize*(c: PSModifierColor, s: Serializer): JsonNode =
    result = newJObject()
    result.add("distance", s.getValue(c.distance))
    result.add("color", s.getValue(c.color))

method visitProperties*(attr: PSModifierColor, p: var PropertyVisitor) =
    p.visitProperty("distance", attr.distance)
    p.visitProperty("color", attr.color)

# -------------------- Spiral Modifier --------------------------
method init(attr: PSModifierSpiral) =
    attr.force = 100

method updateParticle*(attr: PSModifierSpiral, part: var Particle) =
    var distance_vec = newVector3()
    # distance_vec.x = part.position.x - attr.node.worldPos.x
    # distance_vec.y = part.position.z - attr.node.worldPos.z
    # let distance = distance_vec.length()
    # var angle = arctan2(distance_vec.y, distance_vec.x)
    # let speed_rad = degToRad(attr.speed)
    # part.position.x = distance * cos(angle + speed_rad) + attr.node.position.x
    # part.position.z = distance * sin(angle + speed_rad) + attr.node.position.z

    distance_vec = part.position - attr.node.worldPos
    distance_vec.y = 0.0
    let distance = distance_vec.length()
    distance_vec.normalize()
    let force = distance_vec * (attr.force * getDeltaTime()) / (distance * distance)
    part.velocity -= force


method deserialize*(attr: PSModifierSpiral, j: JsonNode, s: Serializer) =
    if j.isNil:
        return
    s.deserializeValue(j, "speed", attr.force) # deprecated
    s.deserializeValue(j, "force", attr.force)

method serialize*(c: PSModifierSpiral, s: Serializer): JsonNode =
    result = newJObject()
    result.add("force", s.getValue(c.force))

method visitProperties*(attr: PSModifierSpiral, p: var PropertyVisitor) =
    p.visitProperty("force", attr.force)


# -------------------- rand Wind Modifier --------------------------
method init(attr: PSModifierRandWind) =
    attr.force = newVector3(1,1,1)

method updateParticle*(attr: PSModifierRandWind, part: var Particle) =
    var force: Vector3
    force.x = rand(-attr.force.x .. attr.force.x)
    force.y = rand(-attr.force.y .. attr.force.y)
    force.z = rand(-attr.force.z .. attr.force.z)
    part.velocity += force / 60.0

method deserialize*(attr: PSModifierRandWind, j: JsonNode, s: Serializer) =
    if j.isNil:
        return
    s.deserializeValue(j, "force", attr.force)

method serialize*(c: PSModifierRandWind, s: Serializer): JsonNode =
    result = newJObject()
    result.add("force", s.getValue(c.force))

method visitProperties*(attr: PSModifierRandWind, p: var PropertyVisitor) =
    p.visitProperty("force", attr.force)

genSerializationCodeForComponent(ConePSGenShape)
genSerializationCodeForComponent(SpherePSGenShape)
genSerializationCodeForComponent(BoxPSGenShape)
genSerializationCodeForComponent(PSModifierRandWind)
genSerializationCodeForComponent(PSModifierWave)
genSerializationCodeForComponent(PSModifierColor)
genSerializationCodeForComponent(PSModifierSpiral)

registerComponent(ConePSGenShape, "ParticleSystem")
registerComponent(SpherePSGenShape, "ParticleSystem")
registerComponent(BoxPSGenShape, "ParticleSystem")

registerComponent(PSModifierWave, "ParticleSystem")
registerComponent(PSModifierColor, "ParticleSystem")
registerComponent(PSModifierSpiral, "ParticleSystem")
registerComponent(PSModifierRandWind, "ParticleSystem")
