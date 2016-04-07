import json
import times
import math

import rod.quaternion

import rod.node
import rod.component
import rod.rod_types
import rod.property_visitor

import nimx.matrixes
import nimx.animation
import nimx.context
import nimx.types

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
        center*: Vector3
        hole: float
        gravity*: float
        radius: float

method init(pa: ParticleAttractor)=
    procCall pa.Component.init()

method setRadius*(pa: ParticleAttractor, rad: float, hol: float = 0.1) =
    pa.radius = rad
    pa.hole = hol

method applyGravity(pa: ParticleAttractor, particle_pos: Vector3) : tuple [upd_velocity: Vector3, need_reset: bool] =
    var destination = pa.center - particle_pos
    const rad = 1.0.float
    let rad_m_hole = 1.01
    var dest_len = destination.length
    var dist = if dest_len > 0: dest_len / pa.radius
                          else: 0.0
    result.need_reset =  dist < pa.hole

    if dist <= rad:
        var force = (rad_m_hole - dist) * pa.gravity
        destination.normalize()
        result.upd_velocity = destination * force
    else:
        result.upd_velocity = newVector3(0, 0, 0)

type
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

method setAttractor*(pe: ParticleEmitter, pa: ParticleAttractor) =
    if pe.attractor != pa:
        pe.attractor = pa

template stop*(e: ParticleEmitter) = e.birthRate = 999999999.0

template pmRandom(r: float): float = random(r * 2) - r
template randomSign(): float =
    if random(2) == 1: 1.0 else: -1.0

template createParticle(p: ParticleEmitter, part: var ParticleData) =
    part.coord = newVector3(0, 0)
    part.scale = newVector3(1, 1, 1)
    part.rotation = newQuaternion()
    part.pid = random(1.0)

    let velocityLen = p.velocity + p.velocity * pmRandom(p.velocityRandom)
    part.velocity = aroundZ(p.direction + p.direction * pmRandom(p.directionRandom)) * newVector3(velocityLen, 0, 0)
    part.initialLifetime = p.lifetime + p.lifetime * pmRandom(0.1)
    part.remainingLifetime = part.initialLifetime
    part.rotVelocity = newQuaternion(pmRandom(3.0), ForwardVector)

template updateParticle(p: ParticleEmitter, part: var ParticleData, timeDiff: float) =
    part.remainingLifetime -= timeDiff
    
    if p.attractor != nil:
        var (upd_velocity, need_reset) = p.attractor.applyGravity(part.coord)

        if need_reset:
            part.remainingLifetime = -1
        
        if upd_velocity.length == 0 :
            upd_velocity = p.gravity
        else:
            part.velocity *= 0.9

        part.velocity += upd_velocity

    else:    
        part.velocity += p.gravity

    let velDiff = (part.velocity * timeDiff) / 0.01
    part.coord += velDiff

    let newRotation = (part.rotation * part.rotVelocity).normalized() * timeDiff / 0.01
    part.rotation = newRotation

template drawParticle(p: ParticleEmitter, part: ParticleData) =
    let proto = p.particlePrototype
    proto.translation = part.coord
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

method draw*(p: ParticleEmitter) =
    if p.particlePrototype.isNil: return
    if p.particles.isNil:
        p.particles = newSeq[ParticleData](p.numberOfParticles)
    elif p.particles.len != p.numberOfParticles:
        p.particles.setLen(p.numberOfParticles)
        p.currentParticles = 0

    if not p.oneShot:
        p.currentParticles = 0

    let curTime = epochTime()
    let timeDiff = curTime - p.lastDrawTime

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
            p.updateParticle(p.particles[i], timeDiff)
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
    p.visitProperty("center", pa.center)
    p.visitProperty("hole", pa.hole)
    p.visitProperty("gravity", pa.gravity)
    p.visitProperty("radius", pa.radius)

registerComponent[ParticleEmitter]()
registerComponent[Particle]()
registerComponent[ParticleAttractor]()

