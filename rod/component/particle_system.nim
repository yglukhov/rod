import times
import math
import random
import json
import tables

import rod.quaternion

import rod.node
import rod.component
import rod.rod_types
import rod.viewport
import rod.component.particle_helpers
import rod.component.camera
import rod.material.shader
import rod.tools.serializer
import rod / utils / [property_desc, serialization_codegen ]

import nimx.matrixes
import nimx.animation
import nimx.context
import nimx.types
import nimx.portable_gl
import nimx.view
import nimx.image
import nimx.property_visitor

const ParticleVertexShader = """
attribute vec3 aPosition;
#ifdef ROTATION_3D
    attribute vec3 aRotation;
#else
    attribute float aRotation;
#endif
attribute vec3 aScale;
attribute float aAlpha;
attribute float aColor;
attribute float aID;
attribute float aLifeTime;

uniform mat4 modelViewProjectionMatrix;
uniform mat4 projMatrix;
uniform mat4 viewMatrix;
uniform mat4 worldMatrix;
uniform vec3 uNodeScale;

varying float vAlpha;
#ifdef TEXTURED
    varying vec2 texCoords;
#endif
#ifdef GL_ES
    varying highp vec3 vColor;
#else
    varying vec3 vColor;
#endif

#ifdef ANIMATED_TEXTURE
    uniform vec2 uFrameSize;
    uniform int uAnimColumns;
    uniform int uFramesCount;
    uniform float uFPS;
#endif

#ifdef ROTATION_3D
    mat4 getRotationMatrix(vec3 rot)
    {
        float angle = radians(rot.x);
        mat4 rMatrixX = mat4(
        1.0, 0.0,        0.0,         0.0,
        0.0, cos(angle), -sin(angle), 0.0,
        0.0, sin(angle), cos(angle) , 0.0,
        0.0, 0.0,        0.0,         1.0 );

        angle = radians(rot.y);
        mat4 rMatrixY = mat4(
        cos(angle),  0.0, sin(angle), 0.0,
        0.0, 1.0,    0.0,             0.0,
        -sin(angle), 0.0, cos(angle), 0.0,
        0.0,         0.0, 0.0,        1.0 );

        angle = radians(rot.z);
        mat4 rMatrixZ = mat4(
        cos(angle), -sin(angle), 0.0, 0.0,
        sin(angle), cos(angle),  0.0, 0.0,
        0.0,        0.0,         1.0, 0.0,
        0.0,        0.0,         0.0, 1.0 );

        return rMatrixX * rMatrixY * rMatrixZ;
    }
#else
    mat4 getRotationMatrix(float rot)
    {
        float angle = radians(rot);
        mat4 rMatrixZ = mat4(
        cos(angle), -sin(angle), 0.0, 0.0,
        sin(angle), cos(angle),  0.0, 0.0,
        0.0,        0.0,         1.0, 0.0,
        0.0,        0.0,         0.0, 1.0 );

        return rMatrixZ;
    }
#endif

vec3 encodeRgbFromFloat( float f )
{
    vec3 color;
    color.b = floor(f / (256.0 * 256.0));
    color.g = floor((f - color.b * 256.0 * 256.0) / 256.0);
    color.r = floor(f - color.b * 256.0 * 256.0 - color.g * 256.0);
    return color / 256.0;
}

void main()
{
    vAlpha = aAlpha;
    vec3 vertexOffset = vec3(0.0,0.0,0.0);
    vColor = encodeRgbFromFloat(aColor);

#ifdef ANIMATED_TEXTURE
    // calculate anim frame
    int currFrame = int( mod(aLifeTime * uFPS, float(uFramesCount - 1)) );
    int row = currFrame / uAnimColumns;
    int col = int(mod(float(currFrame) + 0.5, float(uAnimColumns)));
    vec2 fc = vec2(uFrameSize.x * float(col), uFrameSize.y * float(row));

    if (aID == 0.0) { vertexOffset = vec3(-0.5,  0.5,  0); texCoords = vec2(fc.x, fc.y);}
    if (aID == 1.0) { vertexOffset = vec3( 0.5,  0.5,  0); texCoords = vec2(fc.x + uFrameSize.x, fc.y);}
    if (aID == 2.0) { vertexOffset = vec3( 0.5,  -0.5, 0); texCoords = vec2(fc.x + uFrameSize.x, fc.y + uFrameSize.y);}
    if (aID == 3.0) { vertexOffset = vec3(-0.5,  -0.5, 0); texCoords = vec2(fc.x, fc.y + uFrameSize.y);}
#else
    if (aID == 0.0) { vertexOffset = vec3(-0.5,  0.5,  0); }
    if (aID == 1.0) { vertexOffset = vec3( 0.5,  0.5,  0); }
    if (aID == 2.0) { vertexOffset = vec3( 0.5,  -0.5, 0); }
    if (aID == 3.0) { vertexOffset = vec3(-0.5,  -0.5, 0); }

    #ifdef TEXTURED
        texCoords = vec2(vertexOffset.xy) + vec2(0.5, 0.5);
    #endif
#endif

    vertexOffset = vertexOffset * uNodeScale * aScale;

    mat4 rMatrix = getRotationMatrix(aRotation);
    vec4 rotatedVertexOffset = rMatrix * vec4(vertexOffset, 1.0);

    mat4 modelView = viewMatrix;// * worldMatrix;
    vec4 transformedPos = viewMatrix * vec4(aPosition, 1.0);

#ifndef ROTATION_3D
    modelView[0][0] = 1.0;    modelView[1][0] = 0.0;    modelView[2][0] = 0.0;
    modelView[0][1] = 0.0;    modelView[1][1] = 1.0;    modelView[2][1] = 0.0;
    modelView[0][2] = 0.0;    modelView[1][2] = 0.0;    modelView[2][2] = 1.0;
#endif
    // transformation already is in transformedPos
    modelView[3][0] = 0.0;    modelView[3][1] = 0.0;    modelView[3][2] = 0.0;

    vec4 P = modelView * vec4(rotatedVertexOffset.xyz + transformedPos.xyz, 1.0);
    gl_Position = projMatrix * P;
}
"""
const ParticleFragmentShader = """
#ifdef GL_ES
    #extension GL_OES_standard_derivatives : enable
    precision highp float;
    varying highp vec3 vColor;
#else
    varying vec3 vColor;
#endif

#ifdef TEXTURED
    varying vec2 texCoords;

    uniform sampler2D texUnit;
    uniform vec4 uTexUnitCoords;
#endif

varying float vAlpha;

void main()
{
#ifdef TEXTURED
    vec4 tex_color = texture2D(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * texCoords);
    gl_FragColor = tex_color * vec4(vColor.xyz, vAlpha);
#else
    gl_FragColor = vec4(vColor.xyz, vAlpha);
#endif
}
"""

type
    ParticleModeEnum* = enum
        BeetwenValue
        TimeSequence

    VertexDesc = object
        positionSize: int32
        rotationSize: int32
        scaleSize: int32
        alphaSize: int32
        colorSize: int32
        idSize: int32
        lifeTimeSize: int32

    ParticleSystem* = ref object of Component
        animation*: Animation
        count: int32

        # Number of particles that should have been generated on previous frame,
        # according to its dt. This value is always < 1, but should be considered
        # for current frame.
        fractionOfParticlesToGenerate: float32

        vertexBuffer: BufferRef
        indexBuffer: BufferRef
        particlesVertexBuff: seq[float32]
        indexBufferSize: int
        particles: seq[Particle]
        vertexDesc: VertexDesc
        worldTransform: Matrix4
        shader*: Shader

        birthRate*: float32
        lifetime*: float32
        texture*: Image
        isTextureAnimated*: bool
        frameSize*: Size
        animColumns*: int16
        framesCount*: int16
        fps*: float32

        startColor*, dstColor*: Color
        startScale*, dstScale*: Vector3
        randScaleFrom*, randScaleTo*: float32
        startVelocity*, randVelocityFrom*, randVelocityTo*: float32
        startRotation*: Vector3
        randRotVelocityFrom*, randRotVelocityTo*: Vector3 # deg
        gravity*: Vector3
        airDensity*: float32

        duration*: float32
        remainingDuration: float32
        isLooped*: bool
        isPlayed*: bool
        is3dRotation*: bool

        modifierNode*: Node
        modifier*: PSModifier

        genShapeNode*: Node
        genShape: PSGenShape
        isInited: bool

        lastPos, curPos: Vector3 # data to interpolate particle generation

        scaleMode*: ParticleModeEnum
        colorMode*: ParticleModeEnum
        scaleSeq*: seq[TVector[4, Coord]] # time, scale
        colorSeq*: seq[TVector[5, Coord]] # time, color

        isBlendAdd*: bool
        hasDepthTest*: bool

ParticleSystem.properties:
    duration
    birthRate
    lifetime
    startVelocity
    randVelocityFrom
    randVelocityTo
    startRotation
    randRotVelocityFrom
    randRotVelocityTo
    startScale
    dstScale
    randScaleFrom
    randScaleTo
    startColor
    dstColor
    gravity
    airDensity
    texture
    frameSize:
        serializationKey: "texSize"
    animColumns
    framesCount
    fps
    genShapeNode:
        phantom: string
    modifierNode:
        phantom: string
    scaleMode
    colorMode
    scaleSeq
    colorSeq
    hasDepthTest
    isLooped
    isPlayed
    is3dRotation
    isBlendAdd
    isTextureAnimated

# -------------------- Particle System --------------------------
proc randomBetween(fromV, toV: float32): float32 {.inline.} =
    result = rand(fromV .. toV)

proc randomBetween(fromV, toV: Vector3): Vector3 =
    result.x = randomBetween(fromV.x, toV.x)
    result.y = randomBetween(fromV.y, toV.y)
    result.z = randomBetween(fromV.z, toV.z)

proc getVertexSize(ps: ParticleSystem): int =
    result = ps.vertexDesc.positionSize +
        ps.vertexDesc.rotationSize +
        ps.vertexDesc.scaleSize +
        ps.vertexDesc.alphaSize +
        ps.vertexDesc.idSize +
        ps.vertexDesc.colorSize +
        ps.vertexDesc.lifeTimeSize

proc getVertexSizeof(ps: ParticleSystem): int {.inline.} =
    result = ps.getVertexSize() * sizeof(float32)

proc newVertexDesc(posSize, rotSize, scSize, aSize, colorSize, idSize, lifeTimeSize: int32): VertexDesc =
    result.positionSize = posSize
    result.rotationSize = rotSize
    result.scaleSize = scSize
    result.alphaSize = aSize
    result.colorSize = colorSize
    result.idSize = idSize
    result.lifeTimeSize = lifeTimeSize

proc calculateVertexDesc(ps: ParticleSystem): VertexDesc =
    let lifeTimeSize = if ps.isTextureAnimated: 1.int32
                                          else: 0.int32
    let rotationSize = if ps.is3dRotation: 3.int32
                                     else: 1.int32
    result = newVertexDesc(3, rotationSize, 2, 1, 1, 1, lifeTimeSize)

proc maxParticlesCount(ps: ParticleSystem): int =
    result = int(ceil(ps.birthRate) * ceil(ps.lifetime))

proc initParticle(ps: ParticleSystem, result: var Particle, index, count: int, dt: float) =
    if ps.genShape.isNil:
        result.position = newVector3()
        result.velocity = newVector3()
    else:
        var interpolatePos: Vector3
        var interpolateDt: float
        if count > 0:
            let ic = float(index) / float(count)
            interpolatePos = (ps.curPos - ps.lastPos) * ic
            interpolateDt = dt * ic

        let gData = ps.genShape.generate()
        result.position = ps.worldTransform * (gData.position) - interpolatePos
        result.velocity = ps.worldTransform.transformDirection(gData.direction) * (ps.startVelocity + randomBetween(ps.randVelocityFrom, ps.randVelocityTo))
        result.position += result.velocity * interpolateDt

    result.scale = ps.startScale
    result.randStartScale = randomBetween(ps.randScaleFrom, ps.randScaleTo)
    result.rotation = ps.startRotation
    result.rotationVelocity = randomBetween(ps.randRotVelocityFrom, ps.randRotVelocityTo)
    result.lifetime = ps.lifetime

proc fillIBuffer(ps: ParticleSystem) =
    let gl = currentContext().gl
    var ib = newSeq[GLushort]()

    ps.indexBufferSize = ps.maxParticlesCount() * 6

    for i in 0 ..< ps.indexBufferSize:
        let start = GLushort(4 * i)
        ib.add(start + 0)
        ib.add(start + 1)
        ib.add(start + 2)

        ib.add(start + 0)
        ib.add(start + 2)
        ib.add(start + 3)

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ps.indexBuffer)
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, ib, gl.STATIC_DRAW)

var particleShader: Shader

proc initSystem(ps: ParticleSystem) =
    let gl = currentContext().gl
    ps.animation = newAnimation()
    ps.animation.numberOfLoops = -1

    ps.vertexDesc = ps.calculateVertexDesc()
    ps.particlesVertexBuff = newSeq[float32]( ps.maxParticlesCount() * ps.getVertexSize() )
    ps.vertexBuffer = gl.createBuffer()
    ps.indexBuffer = gl.createBuffer()
    ps.fillIBuffer()

    ps.particles = newSeq[Particle]( ps.maxParticlesCount() )

    if particleShader.isNil:
        particleShader = newShader(ParticleVertexShader, ParticleFragmentShader,
            @[(0.GLuint, "aPosition"),
            (1.GLuint, "aRotation"),
            (2.GLuint, "aScale"),
            (3.GLuint, "aAlpha"),
            (4.GLuint, "aColor"),
            (5.GLuint, "aID")])

    ps.shader = particleShader
    ps.genShapeNode = ps.node

    ps.remainingDuration = ps.duration
    ps.fractionOfParticlesToGenerate = 0

    if not ps.node.isNil:
        ps.lastPos = ps.node.worldPos
        ps.curPos = ps.node.worldPos

    ps.isInited = true

proc cleanup*(ps: ParticleSystem) =
    let c = currentContext()
    let gl = c.gl
    if ps.indexBuffer != invalidBuffer:
        gl.deleteBuffer(ps.indexBuffer)
        ps.indexBuffer = invalidBuffer
    if ps.vertexBuffer != invalidBuffer:
        gl.deleteBuffer(ps.vertexBuffer)
        ps.vertexBuffer = invalidBuffer

method init(ps: ParticleSystem) =
    ps.isInited = false
    procCall ps.Component.init()

    ps.count = 0
    ps.birthRate = 100
    ps.lifetime = 8.0

    ps.startVelocity = 8
    ps.randVelocityFrom = 0.0
    ps.randVelocityTo = 0.0
    ps.randRotVelocityFrom = newVector3(0.0, 0.0, 0.0)
    ps.randRotVelocityTo = newVector3(0.0, 0.0, 0.0)
    ps.startColor = newColor(1.0, 1.0, 1.0, 1.0)
    ps.dstColor = newColor(1.0, 1.0, 1.0, 1.0)
    ps.startScale = newVector3(3.0, 3.0, 3.0)
    ps.dstScale = newVector3(0.0, 0.0, 0.0)
    ps.randScaleFrom = 0.0
    ps.randScaleTo = 0.0
    ps.gravity = newVector3(0.0, -1.5, 0.0)

    ps.isLooped = true
    ps.duration = 3.0
    ps.isPlayed = true

    ps.is3dRotation = false

    ps.isTextureAnimated = false
    ps.framesCount = 1
    ps.animColumns = 1
    ps.frameSize = newSize(1.0, 1.0)
    ps.fps = 1.0

    ps.isBlendAdd = false
    ps.hasDepthTest = true

    ps.scaleMode = ParticleModeEnum.BeetwenValue
    ps.colorMode = ParticleModeEnum.BeetwenValue
    ps.scaleSeq = newSeq[TVector[4, Coord]]()
    ps.colorSeq = newSeq[TVector[5, Coord]]()
    # ps.initSystem()

proc start*(ps: ParticleSystem) =
    ps.isPlayed = true

    ps.fractionOfParticlesToGenerate = 0
    ps.remainingDuration = ps.duration

    ps.lastPos = ps.node.worldPos
    ps.curPos = ps.node.worldPos

proc stop*(ps: ParticleSystem) =
    ps.isPlayed = false

proc `*`(c: Color, f: float): Color =
    result.r = c.r * f
    result.g = c.g * f
    result.b = c.b * f
    result.a = c.a * f

proc `+`(c1, c2: Color): Color =
    result.r = c1.r + c2.r
    result.g = c1.g + c2.g
    result.b = c1.b + c2.b
    result.a = c1.a + c2.a

proc rgbToFloat(c: Color): float32 =
    let c0 = clamp(c[0], 0.0, 1.0)
    let c1 = clamp(c[1], 0.0, 1.0)
    let c2 = clamp(c[2], 0.0, 1.0)
    float32((int(c0 * 254.0) + int(c1 * 254.0) * 256 + int(c2 * 254.0) * 256 * 256))

template setVector3ToBuffer(buff: var seq[float32], offset: int, vec: Vector3) =
    buff[offset + 0] = vec.x
    buff[offset + 1] = vec.y
    buff[offset + 2] = vec.z

proc getValueAtTime[T](s: seq[T], time: float): T =
    var frame1, frame2: T
    const vecLen = high(T) + 1
    var val: T

    for i in 0 ..< s.len:
        if s[i][0] >= time:
            frame2 = s[i]
            if i == 0:
                return frame2
            else:
                frame1 = s[i-1]
            break
        else:
            frame1 = s[i]
            frame2 = s[i]

    let startTime = frame1[0]
    let endTime = frame2[0]
    if startTime == endTime:
        return frame2

    let t = (time - startTime) / (endTime - startTime)
    for i in 1 ..< vecLen:
        val[i] = frame1[i] * (1 - t) + frame2[i] * t

    return val

proc getGravityYDirection(ps: ParticleSystem): float32 {.inline.} =
    let view = ps.node.sceneView
    var projMatrix : Matrix4
    view.camera.getProjectionMatrix(view.bounds, projMatrix)
    result = abs(projMatrix[5]) / projMatrix[5]

proc numberOfParticlesToGenerate(ps: ParticleSystem, dt: float32): int {.inline.} =
    # Warning: this is not pure.
    if (ps.remainingDuration > 0 or ps.isLooped) and ps.isPlayed:
        ps.remainingDuration -= dt
        let toGenerate = dt * ps.birthRate + ps.fractionOfParticlesToGenerate
        result = int(toGenerate)
        ps.fractionOfParticlesToGenerate = toGenerate - float32(result)

proc updateParticlesBuffer(ps: ParticleSystem, dt: float32) =
    var particlesToGenerate = ps.numberOfParticlesToGenerate(dt)
    let newParticlesCount = particlesToGenerate
    ps.count = 0

    var newI = 0
    var v1, v2, v3, v4: int
    let vertexSize = ps.getVertexSize()

    var gravity = ps.gravity * dt
    gravity.y *= ps.getGravityYDirection()

    let maxParticlesCount = ps.maxParticlesCount
    
    for i in 0 ..< ps.particles.len:
        # if we have dead particle than we create a new one
        if ps.particles[i].lifetime <= 0.0:
            if particlesToGenerate > 0:
                dec particlesToGenerate
                ps.initParticle(ps.particles[i], newI, newParticlesCount, dt)
                inc newI
            else:
                continue

        if ps.particlesVertexBuff.len <= (ps.count + 1) * 4 * vertexSize:
            for j in 0 .. 4 * vertexSize:
                ps.particlesVertexBuff.add(0.0)

        ps.particles[i].lifetime -= dt
        ps.particles[i].normalizedLifeTime = ps.particles[i].lifetime / ps.lifetime
        let oneMinusNormLifeTime = 1.0 - ps.particles[i].normalizedLifeTime

        v1 = vertexSize* (4 * ps.count + 0) # vertexSize (vertexCount * index + vertexNum)
        v2 = vertexSize* (4 * ps.count + 1)
        v3 = vertexSize* (4 * ps.count + 2)
        v4 = vertexSize* (4 * ps.count + 3)

        # positions
        if ps.airDensity != 0.0:
            var density_vec = ps.particles[i].velocity
            density_vec.normalize()
            ps.particles[i].velocity -= density_vec * ps.airDensity * dt

        ps.particles[i].velocity += gravity
        ps.particles[i].position += ps.particles[i].velocity * dt

        # rotation
        if ps.is3dRotation:
            ps.particles[i].rotation += ps.particles[i].rotationVelocity * dt
        else:
            ps.particles[i].rotation.z += ps.particles[i].rotationVelocity.z * dt

        # scale
        if ps.scaleMode == ParticleModeEnum.TimeSequence:
            let sc = ps.scaleSeq.getValueAtTime(oneMinusNormLifeTime)
            ps.particles[i].scale.x = sc[1]
            ps.particles[i].scale.y = sc[2]
        else:
            ps.particles[i].scale.x = (ps.startScale.x + ps.particles[i].randStartScale) * ps.particles[i].normalizedLifeTime + ps.dstScale.x * oneMinusNormLifeTime
            ps.particles[i].scale.y = (ps.startScale.y + ps.particles[i].randStartScale) * ps.particles[i].normalizedLifeTime + ps.dstScale.y * oneMinusNormLifeTime

        # alpha and color
        if ps.colorMode == ParticleModeEnum.TimeSequence:
            let sc = ps.colorSeq.getValueAtTime(oneMinusNormLifeTime)
            ps.particles[i].color.r = sc[1]
            ps.particles[i].color.g = sc[2]
            ps.particles[i].color.b = sc[3]
            ps.particles[i].color.a = sc[4]
        else:
            ps.particles[i].color = ps.startColor * ps.particles[i].normalizedLifeTime + ps.dstColor * oneMinusNormLifeTime

        # Modifiers
        if not ps.modifier.isNil:
            ps.modifier.updateParticle(ps.particles[i])

        var offset = 0
        # position
        ps.particlesVertexBuff.setVector3ToBuffer(v1 + offset, ps.particles[i].position)
        ps.particlesVertexBuff.setVector3ToBuffer(v2 + offset, ps.particles[i].position)
        ps.particlesVertexBuff.setVector3ToBuffer(v3 + offset, ps.particles[i].position)
        ps.particlesVertexBuff.setVector3ToBuffer(v4 + offset, ps.particles[i].position)
        offset += ps.vertexDesc.positionSize

        # rotation
        if ps.is3dRotation:
            ps.particlesVertexBuff.setVector3ToBuffer(v1 + offset, ps.particles[i].rotation)
            ps.particlesVertexBuff.setVector3ToBuffer(v2 + offset, ps.particles[i].rotation)
            ps.particlesVertexBuff.setVector3ToBuffer(v3 + offset, ps.particles[i].rotation)
            ps.particlesVertexBuff.setVector3ToBuffer(v4 + offset, ps.particles[i].rotation)
        else:
            ps.particlesVertexBuff[v1 + offset] = ps.particles[i].rotation.z
            ps.particlesVertexBuff[v2 + offset] = ps.particles[i].rotation.z
            ps.particlesVertexBuff[v3 + offset] = ps.particles[i].rotation.z
            ps.particlesVertexBuff[v4 + offset] = ps.particles[i].rotation.z
        offset += ps.vertexDesc.rotationSize

        # scale
        ps.particlesVertexBuff[v1 + offset + 0] = ps.particles[i].scale.x
        ps.particlesVertexBuff[v1 + offset + 1] = ps.particles[i].scale.y
        ps.particlesVertexBuff[v2 + offset + 0] = ps.particles[i].scale.x
        ps.particlesVertexBuff[v2 + offset + 1] = ps.particles[i].scale.y
        ps.particlesVertexBuff[v3 + offset + 0] = ps.particles[i].scale.x
        ps.particlesVertexBuff[v3 + offset + 1] = ps.particles[i].scale.y
        ps.particlesVertexBuff[v4 + offset + 0] = ps.particles[i].scale.x
        ps.particlesVertexBuff[v4 + offset + 1] = ps.particles[i].scale.y
        offset += ps.vertexDesc.scaleSize

        # color
        let alpha = ps.particles[i].color.a * currentContext().alpha
        ps.particlesVertexBuff[v1 + offset] = alpha
        ps.particlesVertexBuff[v2 + offset] = alpha
        ps.particlesVertexBuff[v3 + offset] = alpha
        ps.particlesVertexBuff[v4 + offset] = alpha
        offset += ps.vertexDesc.alphaSize

        let encoded_color = rgbToFloat(ps.particles[i].color)
        ps.particlesVertexBuff[v1 + offset] = encoded_color
        ps.particlesVertexBuff[v2 + offset] = encoded_color
        ps.particlesVertexBuff[v3 + offset] = encoded_color
        ps.particlesVertexBuff[v4 + offset] = encoded_color
        offset += ps.vertexDesc.colorSize

        # ID
        ps.particlesVertexBuff[v1 + offset] = 0.0
        ps.particlesVertexBuff[v2 + offset] = 1.0
        ps.particlesVertexBuff[v3 + offset] = 2.0
        ps.particlesVertexBuff[v4 + offset] = 3.0
        offset += ps.vertexDesc.idSize

        # lifeTime
        if ps.isTextureAnimated:
            let lf = ps.lifeTime - ps.particles[i].lifeTime
            ps.particlesVertexBuff[v1 + offset] = lf
            ps.particlesVertexBuff[v2 + offset] = lf
            ps.particlesVertexBuff[v3 + offset] = lf
            ps.particlesVertexBuff[v4 + offset] = lf

        ps.count.inc()

        if ps.count > maxParticlesCount:
            return

    # if we have new particles
    if particlesToGenerate > 0:
        let oldLen = ps.particles.len
        let newLen = oldLen + particlesToGenerate
        ps.particles.setLen(newLen)
        for i in oldLen ..< newLen:
            ps.initParticle(ps.particles[i], newI, newParticlesCount, dt)
            inc newI

proc update(ps: ParticleSystem, dt: float) =
    ps.worldTransform = ps.node.worldTransform()
    ps.lastPos = ps.curPos
    ps.curPos = ps.node.worldPos

    if not ps.genShapeNode.isNil:
        ps.genShape = ps.genShapeNode.getComponent(PSGenShape)

    if not ps.modifierNode.isNil:
        ps.modifier = ps.modifierNode.getComponent(PSModifier)

    # chek IB size (need for runtime property editing)
    if ps.indexBufferSize < ps.maxParticlesCount():
        ps.fillIBuffer()

    ps.updateParticlesBuffer(dt)

method draw*(ps: ParticleSystem) =
    let dt = getDeltaTime() #ps.currentTime - ps.lastTime
    let gl = currentContext().gl

    if not ps.isInited:
        ps.initSystem()

    ps.update(dt)

    if ps.count < 1:
        return

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ps.indexBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, ps.vertexBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, ps.particlesVertexBuff, gl.STATIC_DRAW)

    var offset: int = 0
    let stride = ps.getVertexSizeof()

    gl.enableVertexAttribArray(0)
    gl.vertexAttribPointer(0, ps.vertexDesc.positionSize, gl.FLOAT, false, stride.GLsizei , offset)
    offset += ps.vertexDesc.positionSize * sizeof(GLfloat)

    gl.enableVertexAttribArray(1)
    gl.vertexAttribPointer(1, ps.vertexDesc.rotationSize, gl.FLOAT, false, stride.GLsizei , offset)
    offset += ps.vertexDesc.rotationSize * sizeof(GLfloat)

    gl.enableVertexAttribArray(2)
    gl.vertexAttribPointer(2, ps.vertexDesc.scaleSize, gl.FLOAT, false, stride.GLsizei , offset)
    offset += ps.vertexDesc.scaleSize * sizeof(GLfloat)

    gl.enableVertexAttribArray(3)
    gl.vertexAttribPointer(3, ps.vertexDesc.alphaSize, gl.FLOAT, false, stride.GLsizei , offset)
    offset += ps.vertexDesc.alphaSize * sizeof(GLfloat)

    gl.enableVertexAttribArray(4)
    gl.vertexAttribPointer(4, ps.vertexDesc.colorSize, gl.FLOAT, false, stride.GLsizei , offset)
    offset += ps.vertexDesc.colorSize * sizeof(GLfloat)

    gl.enableVertexAttribArray(5)
    gl.vertexAttribPointer(5, ps.vertexDesc.idSize, gl.FLOAT, false, stride.GLsizei , offset)
    offset += ps.vertexDesc.idSize * sizeof(GLfloat)

    if ps.isTextureAnimated:
        ps.shader.bindAttribLocation(6, "aLifeTime")

        gl.enableVertexAttribArray(6)
        gl.vertexAttribPointer(6, ps.vertexDesc.lifeTimeSize, gl.FLOAT, false, stride.GLsizei , offset)

    if ps.is3dRotation:
        ps.shader.addDefine("ROTATION_3D")
    else:
        ps.shader.removeDefine("ROTATION_3D")

    var theQuad {.noinit.}: array[4, GLfloat]
    if not ps.texture.isNil:
        gl.activeTexture(gl.TEXTURE0)
        gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(ps.texture, gl, theQuad))
        ps.shader.addDefine("TEXTURED")

        if ps.isTextureAnimated:
            ps.shader.addDefine("ANIMATED_TEXTURE")
        else:
            ps.shader.removeDefine("ANIMATED_TEXTURE")
    else:
        ps.shader.removeDefine("TEXTURED")
        ps.shader.removeDefine("ANIMATED_TEXTURE")

    ps.shader.bindShader()

    if not ps.texture.isNil:
        ps.shader.setUniform("uTexUnitCoords", theQuad)
        ps.shader.setUniform("texUnit", 0)
        if ps.isTextureAnimated:
            var fs = newSize(ps.frameSize.width / ps.texture.size.width, ps.frameSize.height / ps.texture.size.height)
            ps.shader.setUniform("uFrameSize", fs)
            ps.shader.setUniform("uAnimColumns", ps.animColumns)
            ps.shader.setUniform("uFramesCount", ps.framesCount)
            ps.shader.setUniform("uFPS", ps.fps)

    ps.shader.setTransformUniform()

    let sv = ps.node.sceneView
    let viewMatrix = sv.viewMatrix
    var projMatrix : Matrix4
    sv.camera.getProjectionMatrix(sv.bounds, projMatrix)

    ps.shader.setUniform("projMatrix", projMatrix)
    ps.shader.setUniform("viewMatrix", viewMatrix)
    ps.shader.setUniform("uNodeScale", ps.node.scale)

    if ps.hasDepthTest:
        gl.depthMask(false)
        gl.enable(gl.DEPTH_TEST)

    if ps.isBlendAdd:
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE)
    else:
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    gl.drawElements(gl.TRIANGLES, ps.count * 6, gl.UNSIGNED_SHORT)

    #TODO to default settings
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
    gl.activeTexture(gl.TEXTURE0)
    gl.enable(gl.BLEND)
    if ps.hasDepthTest:
        gl.disable(gl.DEPTH_TEST)
        gl.depthMask(true)

    for i in 1 .. 6:
        gl.disableVertexAttribArray(GLuint(i))

method getBBox*(ps: ParticleSystem): BBox =
    result.minPoint = newVector3(-3, -3, -3)
    result.maxPoint = newVector3(3, 3, 3)

method deserialize*(ps: ParticleSystem, j: JsonNode, s: Serializer) =
    if j.isNil:
        return

    s.deserializeValue(j, "duration", ps.duration)
    s.deserializeValue(j, "isLooped", ps.isLooped)
    s.deserializeValue(j, "isPlayed", ps.isPlayed)
    s.deserializeValue(j, "birthRate", ps.birthRate)
    s.deserializeValue(j, "lifetime", ps.lifetime)
    s.deserializeValue(j, "startVelocity", ps.startVelocity)
    s.deserializeValue(j, "randVelocityFrom", ps.randVelocityFrom)
    s.deserializeValue(j, "randVelocityTo", ps.randVelocityTo)
    s.deserializeValue(j, "is3dRotation", ps.is3dRotation)
    s.deserializeValue(j, "startRotation", ps.startRotation)
    s.deserializeValue(j, "randRotVelocityFrom", ps.randRotVelocityFrom)
    s.deserializeValue(j, "randRotVelocityTo", ps.randRotVelocityTo)
    s.deserializeValue(j, "startScale", ps.startScale)
    s.deserializeValue(j, "dstScale", ps.dstScale)
    s.deserializeValue(j, "randScaleFrom", ps.randScaleFrom)
    s.deserializeValue(j, "randScaleTo", ps.randScaleTo)
    s.deserializeValue(j, "startColor", ps.startColor)
    s.deserializeValue(j, "dstColor", ps.dstColor)
    s.deserializeValue(j, "isBlendAdd", ps.isBlendAdd)
    s.deserializeValue(j, "gravity", ps.gravity)
    s.deserializeValue(j, "airDensity", ps.airDensity)


    deserializeImage(j{"texture"}, s) do(img: Image, err: string):
        ps.texture = img

    s.deserializeValue(j, "isTextureAnimated", ps.isTextureAnimated)
    s.deserializeValue(j, "texSize", ps.frameSize)
    s.deserializeValue(j, "animColumns", ps.animColumns)
    s.deserializeValue(j, "framesCount", ps.framesCount)
    s.deserializeValue(j, "fps", ps.fps)

    var genShapeName, modifierName: string
    s.deserializeValue(j, "genShapeNode", genShapeName)
    s.deserializeValue(j, "modifierNode", modifierName)
    addNodeRef(ps.genShapeNode, genShapeName)
    addNodeRef(ps.modifierNode, modifierName)

    s.deserializeValue(j, "scaleMode", ps.scaleMode)
    s.deserializeValue(j, "colorMode", ps.colorMode)
    s.deserializeValue(j, "scaleSeq", ps.scaleSeq)
    s.deserializeValue(j, "colorSeq", ps.colorSeq)
    s.deserializeValue(j, "hasDepthTest", ps.hasDepthTest)

proc toPhantom(c: ParticleSystem, p: var object) =
    if not c.genShapeNode.isNil: p.genShapeNode = c.genShapeNode.name
    if not c.modifierNode.isNil: p.modifierNode = c.modifierNode.name

proc fromPhantom(c: ParticleSystem, p: object) =
    if not p.genShapeNode.len != 0:
        addNodeRef(c.genShapeNode, p.genShapeNode)
    if not p.modifierNode.len != 0:
        addNodeRef(c.modifierNode, p.modifierNode)

genSerializationCodeForComponent(ParticleSystem)

method serialize*(c: ParticleSystem, s: Serializer): JsonNode =
    result = newJObject()
    result.add("duration", s.getValue(c.duration))
    result.add("isLooped", s.getValue(c.isLooped))
    result.add("isPlayed", s.getValue(c.isPlayed))
    result.add("birthRate", s.getValue(c.birthRate))
    result.add("lifetime", s.getValue(c.lifetime))
    result.add("startVelocity", s.getValue(c.startVelocity))
    result.add("randVelocityFrom", s.getValue(c.randVelocityFrom))
    result.add("randVelocityTo", s.getValue(c.randVelocityTo))
    result.add("is3dRotation", s.getValue(c.is3dRotation))
    result.add("startRotation", s.getValue(c.startRotation))
    result.add("randRotVelocityFrom", s.getValue(c.randRotVelocityFrom))
    result.add("randRotVelocityTo", s.getValue(c.randRotVelocityTo))
    result.add("startScale", s.getValue(c.startScale))
    result.add("dstScale", s.getValue(c.dstScale))
    result.add("randScaleFrom", s.getValue(c.randScaleFrom))
    result.add("randScaleTo", s.getValue(c.randScaleTo))
    result.add("startColor", s.getValue(c.startColor))
    result.add("dstColor", s.getValue(c.dstColor))
    result.add("isBlendAdd", s.getValue(c.isBlendAdd))
    result.add("gravity", s.getValue(c.gravity))
    result.add("airDensity", s.getValue(c.airDensity))

    result.add("scaleMode", s.getValue(c.scaleMode))
    result.add("colorMode", s.getValue(c.colorMode))
    result.add("scaleSeq", s.getValue(c.scaleSeq))
    result.add("colorSeq", s.getValue(c.colorSeq))

    if not c.texture.isNil and c.texture.filePath().len > 0:
        result.add("texture", s.getValue(s.getRelativeResourcePath(c.texture.filePath())))
        result.add("isTextureAnimated", s.getValue(c.isTextureAnimated))
        result.add("texSize", s.getValue(c.frameSize))
        result.add("animColumns", s.getValue(c.animColumns))
        result.add("framesCount", s.getValue(c.framesCount))
        result.add("fps", s.getValue(c.fps))

    result.add("modifierNode", s.getValue(c.modifierNode))
    result.add("genShapeNode", s.getValue(c.genShapeNode))
    result.add("hasDepthTest", s.getValue(c.hasDepthTest))

method visitProperties*(ps: ParticleSystem, p: var PropertyVisitor) =
    template isLoopedAux(ps: ParticleSystem): bool = ps.isLooped
    template `isLoopedAux=`(ps: ParticleSystem, f: bool) =
        ps.isLooped = f
        ps.remainingDuration = ps.duration
        ps.fractionOfParticlesToGenerate = 0

    template isPlayedAux(ps: ParticleSystem): bool = ps.isLooped
    template `isPlayedAux=`(ps: ParticleSystem, f: bool) =
        ps.isPlayed = f
        if ps.isPlayed:
            ps.start()
        else:
            ps.stop()

    template textureAux(ps: ParticleSystem): Image = ps.texture
    template `textureAux=`(ps: ParticleSystem, t: Image) =
        ps.texture = t
        if not ps.texture.isNil:
            ps.frameSize = ps.texture.size

    template is3dRotationAux(ps: ParticleSystem): bool = ps.is3dRotation
    template `is3dRotationAux=`(ps: ParticleSystem, f: bool) =
        ps.is3dRotation = f
        ps.vertexDesc = ps.calculateVertexDesc()

    template isTextureAnimatedAux(ps: ParticleSystem): bool = ps.isTextureAnimated
    template `isTextureAnimatedAux=`(ps: ParticleSystem, f: bool) =
        ps.isTextureAnimated = f
        ps.vertexDesc = ps.calculateVertexDesc()

    p.visitProperty("scaleMode", ps.scaleMode)
    if ps.scaleMode == ParticleModeEnum.BeetwenValue:
        p.visitProperty("startScale", ps.startScale)
        p.visitProperty("dstScale", ps.dstScale)
    else:
        p.visitProperty("scaleSeq", ps.scaleSeq)

    p.visitProperty("colorMode", ps.colorMode)
    if ps.colorMode == ParticleModeEnum.BeetwenValue:
        p.visitProperty("startColor", ps.startColor)
        p.visitProperty("dstColor", ps.dstColor)
    else:
        p.visitProperty("colorSeq", ps.colorSeq)
    p.visitProperty("duration", ps.duration)
    p.visitProperty("isLooped", ps.isLoopedAux)
    p.visitProperty("isPlayed", ps.isPlayedAux)
    p.visitProperty("genShapeNode", ps.genShapeNode)
    p.visitProperty("modifierNode", ps.modifierNode)
    p.visitProperty("birthRate", ps.birthRate)
    p.visitProperty("lifetime", ps.lifetime)
    p.visitProperty("startVelocity", ps.startVelocity)
    p.visitProperty("randVelFrom", ps.randVelocityFrom)
    p.visitProperty("randVelTo", ps.randVelocityTo)
    p.visitProperty("is3dRotation", ps.is3dRotationAux)
    p.visitProperty("startRotation", ps.startRotation)
    p.visitProperty("randRotVelFrom", ps.randRotVelocityFrom)
    p.visitProperty("randRotVelTo", ps.randRotVelocityTo)
    p.visitProperty("randScaleFrom", ps.randScaleFrom)
    p.visitProperty("randScaleTo", ps.randScaleTo)
    p.visitProperty("isBlendAdd", ps.isBlendAdd)
    p.visitProperty("gravity", ps.gravity)
    p.visitProperty("airDensity", ps.airDensity)
    p.visitProperty("texture", ps.textureAux)
    p.visitProperty("isTexAnim", ps.isTextureAnimatedAux)
    p.visitProperty("texSize", ps.frameSize)
    p.visitProperty("animColumns", ps.animColumns)
    p.visitProperty("framesCount", ps.framesCount)
    p.visitProperty("fps", ps.fps)
    p.visitProperty("hasDepthTest", ps.hasDepthTest)

# -------------------- PSHolder --------------------------
type
    PSHolder* = ref object of Component
        played*: bool
        oldValue: bool

        # debug data
        isMove*: bool
        amplitude*, frequency*, distance*, speed*: float32

PSHolder.properties:
    amplitude
    frequency
    distance
    speed
    played
    isMove

method init(h: PSHolder) =
    h.played = true
    h.oldValue = true

    h.isMove = false
    h.amplitude = 5.0
    h.frequency = 0.4
    h.distance = 40.0
    h.speed = 9.0

proc recursiveDoProc(n: Node, pr: proc(ps: ParticleSystem) ) =
    let ps = n.getComponent(ParticleSystem)
    if not ps.isNil:
        ps.pr()

    for child in n.children:
        child.recursiveDoProc(pr)

method draw*(h: PSHolder) =
    if h.isMove:
        h.node.positionX = h.node.positionX + h.speed * getDeltaTime()
        h.node.positionY = h.amplitude * cos(h.node.positionX * h.frequency)
        if h.node.positionX > h.distance / 2.0:
            h.node.positionX = -h.distance / 2.0;

    if h.played != h.oldValue:
        if h.played:
            h.node.recursiveDoProc(start)
        else:
            h.node.recursiveDoProc(stop)

    h.oldValue = h.played

method deserialize*(h: PSHolder, j: JsonNode, s: Serializer) =
    if j.isNil:
        return
    s.deserializeValue(j, "played", h.played)

    s.deserializeValue(j, "isMove", h.isMove)
    s.deserializeValue(j, "amplitude", h.amplitude)
    s.deserializeValue(j, "frequency", h.frequency)
    s.deserializeValue(j, "distance", h.distance)
    s.deserializeValue(j, "speed", h.speed)

method serialize*(h: PSHolder, s: Serializer): JsonNode =
    result = newJObject()
    result.add("played", s.getValue(h.played))

    result.add("isMove", s.getValue(h.isMove))
    result.add("amplitude", s.getValue(h.amplitude))
    result.add("frequency", s.getValue(h.frequency))
    result.add("distance", s.getValue(h.distance))
    result.add("speed", s.getValue(h.speed))

method visitProperties*(h: PSHolder, p: var PropertyVisitor) =
    p.visitProperty("played", h.played)

    p.visitProperty("isMove", h.isMove)
    p.visitProperty("amplitude", h.amplitude)
    p.visitProperty("frequency", h.frequency)
    p.visitProperty("distance", h.distance)
    p.visitProperty("speed", h.speed)

genSerializationCodeForComponent(PSHolder)
registerComponent(PSHolder, "ParticleSystem")

proc creator(): RootRef =
    var p: ParticleSystem
    p.new(cleanup)
    return p

registerComponent(ParticleSystem, creator, "ParticleSystem")
