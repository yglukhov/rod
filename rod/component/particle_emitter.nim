import json
import times
import math
import random

import rod.quaternion

import rod.node
import rod.component
import rod.rod_types

import nimx.matrixes
import nimx.animation
import nimx.context
import nimx.types
import nimx.property_visitor

type ParticleData = tuple
    coord: Vector3
    rotation: Quaternion
    scale: Vector3
    velocity: Vector3
    rotVelocity: Quaternion
    initialLifetime, remainingLifetime: float
    pid: float

type
    Particle* = ref object of Component
        initialLifetime*, remainingLifetime*: float
        pid*: float

    ParticleAttractor* = ref object of Component
        radius*: float
        gravity*: float
        resetRadius*: float

    ParticleEmitter* = ref object of Component
        lifetime*: float
        birthRate*: float
        particlePrototype*: Node2D
        numberOfParticles*: int
        currentParticles: int
        gravity*: Vector3
        particles: seq[ParticleData]
        drawDebug*: bool
        oneShot: bool
        direction*: Coord
        directionRandom*: float

        velocity*: Coord
        velocityRandom*: float

        lastDrawTime: float
        lastBirthTime: float
        animation*: Animation
        attractor: ParticleAttractor

method init(p: ParticleEmitter) =
    procCall p.Component.init()
    p.gravity = newVector3(0, 0.5, 0)
    p.animation = newAnimation()
    p.animation.numberOfLoops = -1
    p.drawDebug = false
    p.attractor = nil
    p.currentParticles = 0
    p.oneShot = false

method setAttractor*(pe: ParticleEmitter, pa: ParticleAttractor) {.base.}=
    if pe.attractor != pa:
        pe.attractor = pa

template stop*(e: ParticleEmitter) = e.birthRate = 999999999.0

template pmRandom(r: float): float = random(r * 2) - r
template randomSign(): float =
    if random(2) == 1: 1.0 else: -1.0

template createParticle(p: ParticleEmitter, part: var ParticleData) =
    part.coord = p.node.worldPos
    part.scale = newVector3(1, 1, 1)
    part.rotation = newQuaternion()
    part.pid = random(1.0)

    let velocityLen = p.velocity + p.velocity * pmRandom(p.velocityRandom)
    part.velocity = aroundZ(p.direction + p.direction * pmRandom(p.directionRandom)) * newVector3(velocityLen, 0, 0)
    part.initialLifetime = p.lifetime + p.lifetime * pmRandom(0.1)
    part.remainingLifetime = part.initialLifetime
    part.rotVelocity = newQuaternion(pmRandom(3.0), ForwardVector)

template updateParticle(p: ParticleEmitter, part: var ParticleData, timeDiff: float, origin: Vector3) =
    part.remainingLifetime -= timeDiff

    if p.attractor != nil:
        var destination = origin - part.coord
        const rad = 1.0.float
        let rad_m_resetRadius = 1.01
        var dest_len = destination.length
        var dist = if dest_len > 0: dest_len / p.attractor.radius
                              else: 0.0

        if dist <= rad:
            if dist < p.attractor.resetRadius:
                part.remainingLifetime = -1
            else:
                var force = (rad_m_resetRadius - dist) * p.attractor.gravity
                destination.normalize()
                var upd_velocity = destination * force
                part.velocity *= 0.9
                part.velocity += upd_velocity
        else:
            part.velocity += p.gravity

    else:
        part.velocity += p.gravity

    let velDiff = (part.velocity * timeDiff) / 0.01
    part.coord += velDiff

    let newRotation = (part.rotation * part.rotVelocity).normalized() * timeDiff / 0.01
    part.rotation = newRotation

template drawParticle(p: ParticleEmitter, part: ParticleData) =
    let proto = p.particlePrototype
    proto.position = part.coord
    proto.rotation = part.rotation
    proto.scale = part.scale
    let pc = proto.component(Particle)
    pc.remainingLifetime = part.remainingLifetime
    pc.initialLifetime = part.initialLifetime
    pc.pid = part.pid
    proto.recursiveUpdate()
    proto.recursiveDraw()

method `oneShot=`*(p:ParticleEmitter, value: bool) {.inline.}=
    if value != p.oneShot:
        p.oneShot = value
        p.currentParticles = 0

proc recursiveSetViewToPrototype(n: Node, v: SceneView) =
    n.mSceneView = v
    for child in n.children:
        child.recursiveSetViewToPrototype(v)

method draw*(p: ParticleEmitter) =
    if p.particlePrototype.isNil: return
    if p.particles.isNil:
        p.particles = newSeq[ParticleData](p.numberOfParticles)
    elif p.particles.len != p.numberOfParticles:
        p.particles.setLen(p.numberOfParticles)
        p.currentParticles = 0

    var attractorOrigin : Vector3
    if p.attractor != nil and p.node != nil:
        attractorOrigin = p.attractor.node.worldPos()

    if not p.oneShot:
        p.currentParticles = 0

    let curTime = epochTime()
    let timeDiff = curTime - p.lastDrawTime

    if p.particlePrototype.mSceneView.isNil:
        p.particlePrototype.recursiveSetViewToPrototype(p.node.mSceneView)

    for i in 0 ..< p.particles.len:
        var needsToDraw = false
        if p.particles[i].remainingLifetime <= 0:
            if curTime - p.lastBirthTime >= p.birthRate:
                # Create new particle
                if p.currentParticles < p.numberOfParticles:
                    needsToDraw = true
                    p.currentParticles.inc()
                    p.lastBirthTime = curTime
                    p.createParticle(p.particles[i])
        else:
            p.updateParticle(p.particles[i], timeDiff, attractorOrigin)
            needsToDraw = true

        if needsToDraw:
            p.drawParticle(p.particles[i])
            if p.drawDebug:
                let c = currentContext()
                c.fillColor = newColor(1, 0, 0)
                c.strokeWidth = 0
                c.drawEllipseInRect(newRect(p.particles[i].coord.x - 10, p.particles[i].coord.y - 10, 20, 20))

    p.lastDrawTime = curTime

method visitProperties*(pe: ParticleEmitter, p: var PropertyVisitor) =
    p.visitProperty("lifetime", pe.lifetime)
    p.visitProperty("birthRate", pe.birthRate)
    p.visitProperty("particlePrototype", pe.particlePrototype)
    p.visitProperty("numberOfParticles", pe.numberOfParticles)
    p.visitProperty("currentParticles", pe.currentParticles)
    p.visitProperty("gravity", pe.gravity)
    p.visitProperty("oneShot", pe.oneShot)
    p.visitProperty("direction", pe.direction)
    p.visitProperty("directionRandom", pe.directionRandom)
    p.visitProperty("velocity", pe.velocity)
    p.visitProperty("velocityRandom", pe.velocityRandom)
    p.visitProperty("particleAttractor", pe.attractor)


method visitProperties*(pa:ParticleAttractor, p: var PropertyVisitor) =
    p.visitProperty("resetRadius", pa.resetRadius)
    p.visitProperty("gravity", pa.gravity)
    p.visitProperty("radius", pa.radius)

registerComponent[ParticleEmitter]()
registerComponent[Particle]()
registerComponent[ParticleAttractor]()

