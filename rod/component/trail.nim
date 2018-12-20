import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.image
import nimx.matrixes
import nimx.property_visitor
import nimx.view

import rod.component
import rod.quaternion
import rod.component.mesh_component
import rod.component.material
import rod.component.light
import rod.component.camera
import rod.component.sprite
import rod.node
import rod.viewport
import rod.tools.serializer

import rod / utils / [property_desc, serialization_codegen ]

import math
import opengl
import json

const vertexShader = """
attribute vec3 aPosition;
attribute vec2 aTexCoord;

varying vec2 vTexCoord;
varying vec3 vNormal;
varying vec3 vPosition;

uniform mat4 mvpMatrix;
uniform mat4 mvMatrix;
uniform mat3 normalMatrix;

void main() {
    gl_Position = mvpMatrix * vec4(aPosition.xyz, 1.0);

    vTexCoord = aTexCoord;

    vec4 pos = mvMatrix * vec4(aPosition.xyz, 1.0);
    vPosition = pos.xyz;
}
"""

const vertexShaderWithNormal = """
attribute vec3 aPosition;
attribute vec3 aNormal;
attribute vec2 aTexCoord;

varying vec2 vTexCoord;
varying vec3 vNormal;
varying vec3 vPosition;

uniform mat4 mvpMatrix;
uniform mat4 mvMatrix;
uniform mat3 normalMatrix;

void main() {
    gl_Position = mvpMatrix * vec4(aPosition.xyz, 1.0);

    vTexCoord = aTexCoord;

    vec4 pos = mvMatrix * vec4(aPosition.xyz, 1.0);
    vPosition = pos.xyz;

    vNormal = normalize(normalMatrix * aNormal.xyz);
}
"""
const fragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

varying vec3 vPosition;
varying vec2 vTexCoord;

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;

uniform vec4 uColor;
uniform float uLength;
uniform float uCropOffset;
uniform float uAlpha;
uniform float uAlphaCut;

void main() {
    vec2 uv = vec2(vTexCoord.x-uCropOffset , vTexCoord.y);
    if (uv.x < 0.0) {
        discard;
    }
    vec4 color = uColor * uAlpha;
    gl_FragColor.rgb = color.rgb;
    gl_FragColor.a = color.a * (uv.x/(1.0+uAlphaCut));
}
"""
const fragmentShaderTexture = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

varying vec3 vPosition;
varying vec2 vTexCoord;

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;
uniform float uImagePercent;

uniform vec4 uColor;
uniform float uLength;
uniform float uCropOffset;
uniform float uAlpha;
uniform float uAlphaCut;

void main() {
    vec2 uv = vec2(vTexCoord.x-uCropOffset , vTexCoord.y);
    if (uv.x < 0.0) {
        //uv.x = 0.0;
        discard;
    }

    uv.x = uv.x / (uLength-uCropOffset);

    vec4 col = texture2D(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * uv) * uImagePercent;
    if (col.a < 0.01) {
        discard;
    }

    gl_FragColor = col * uColor * uAlpha;
}
"""

const fragmentShaderTextureTiled = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

varying vec3 vPosition;
varying vec2 vTexCoord;

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;
uniform float uImagePercent;

uniform vec4 uColor;
uniform float uLength;
uniform float uCropOffset;
uniform float uAlpha;
uniform float uAlphaCut;
uniform float uTiles;

void main() {
    vec2 uv = vec2(vTexCoord.x-uCropOffset , vTexCoord.y);
    if (uv.x < 0.0) {
        discard;
    }

    uv.x = fract(uv.x / uTiles);

    uv = uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * uv;

    gl_FragColor = texture2D(texUnit, uv, -1000.0) * uImagePercent * uColor * uAlpha;
}
"""

const fragmentShaderMatcap = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

varying vec2 vTexCoord;
varying vec3 vPosition;
varying vec3 vNormal;

uniform sampler2D matcapUnit;
uniform vec4 uMatcapUnitCoords;
uniform float uMatcapPercent;

uniform vec4 uColor;
uniform float uLength;
uniform float uCropOffset;
uniform float uAlpha;
uniform float uAlphaCut;

void main() {
    vec2 uv = vec2(vTexCoord.x-uCropOffset , vTexCoord.y);
    if (uv.x < 0.0) {
        discard;
    }
    uv.x = uv.x / (uLength-uCropOffset);

    vec3 matcapL = normalize(-vPosition.xyz);
    vec3 matcapReflected = normalize(-reflect(matcapL, vNormal.xyz));
    float mtcp = 2.0 * sqrt( pow(matcapReflected.x, 2.0) + pow(matcapReflected.y, 2.0) + pow(matcapReflected.z + 1.0, 2.0) );
    vec2 matcapUV = matcapReflected.xy / mtcp + 0.5;
    matcapUV = vec2(matcapUV.x, 1.0 - matcapUV.y);
    vec4 matcap = texture2D(matcapUnit, uMatcapUnitCoords.xy + (uMatcapUnitCoords.zw - uMatcapUnitCoords.xy) * matcapUV) * uMatcapPercent;

    vec4 color = matcap * uColor * uAlpha;
    gl_FragColor.rgb = color.rgb;
    gl_FragColor.a = color.a * (uv.x/(1.0+uAlphaCut));
}
"""

const fragmentShaderMatcapMask = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

varying vec2 vTexCoord;
varying vec3 vPosition;
varying vec3 vNormal;

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;
uniform float uImagePercent;

uniform sampler2D matcapUnit;
uniform vec4 uMatcapUnitCoords;
uniform float uMatcapPercent;

uniform vec4 uColor;
uniform float uLength;
uniform float uCropOffset;
uniform float uAlpha;

void main() {
    vec2 uv = vec2(vTexCoord.x-uCropOffset , vTexCoord.y);
    if (uv.x < 0.0) {
        //uv.x = 0.0;
        discard;
    }

    uv.x = uv.x / (uLength-uCropOffset);

    float alpha = texture2D(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * uv).a * uImagePercent;
    if (alpha < 0.01) {
        discard;
    }

    vec3 matcapL = normalize(-vPosition.xyz);
    vec3 matcapReflected = normalize(-reflect(matcapL, vNormal.xyz));
    float mtcp = 2.0 * sqrt( pow(matcapReflected.x, 2.0) + pow(matcapReflected.y, 2.0) + pow(matcapReflected.z + 1.0, 2.0) );
    vec2 matcapUV = matcapReflected.xy / mtcp + 0.5;
    matcapUV = vec2(matcapUV.x, 1.0 - matcapUV.y);
    vec4 matcap = texture2D(matcapUnit, uMatcapUnitCoords.xy + (uMatcapUnitCoords.zw - uMatcapUnitCoords.xy) * matcapUV) * uMatcapPercent;
    gl_FragColor = matcap * uColor * uAlpha;
}
"""

var TrailShader: ProgramRef
var TrailTextureShader: ProgramRef
var TrailMatcapShader: ProgramRef
var TrailMatcapShaderMask: ProgramRef
var TrailTextureShaderTiled: ProgramRef

const initialIndicesCount = 500
const initialVerticesCount = 5 * initialIndicesCount
const POS_NORMAL_UV_ELEMENTS = 16
const POS_UV_ELEMENTS = 10
const IND_ELEMENTS = 2

type
    Attrib = enum
        aPosition
        aNormal
        aTexCoord

    DataInBuffer = enum
        First = 0
        Second
        FirstSecond
        SecondFirst
        NotInited
        Skip

    Buffer = object
        vertexBuffer: BufferRef
        indexBuffer: BufferRef

        vertices: tuple[curr: int, max: int]
        indices: tuple[curr: int, max: int]

        bActive: bool
        bValidData: bool

    Trail* = ref object of Component
        color*: Color

        numberOfIndexes: GLushort
        quadsToDraw*: int32

        gravityDirection: Vector3
        gravity*: Vector3
        directRotation*: Quaternion

        currPos: Vector3
        prevPos: Vector3
        directionVector: Vector3
        prevRotation: Quaternion

        widthOffset: float32
        heightOffset: float32

        angleThreshold*: float32

        buffers: array[2, Buffer]
        currBuff: DataInBuffer
        drawMode: DataInBuffer

        shader*: ProgramRef

        currVertexData: seq[GLfloat]
        prevVertexData: seq[GLfloat]

        image*: Image
        matcap*: Image

        imagePercent*: float32
        matcapPercent*: float32

        totalLen: float32
        currLength: float32
        cropOffset: float32

        bDepth*: bool
        bStretch*: bool
        bCollapsible*: bool
        isWireframe: bool

        uniformLocationCache*: seq[UniformLocation]
        iUniform: int

        cutSpeed*: float32
        alphaCut: float32

        bIsTiled: bool
        tiles: float32


Trail.properties:
    image:
        serializationKey: "trailImage"
    matcap:
        serializationKey: "trailMatcap"

    directRotation #quaternion
    color #color
    gravity #vector
    quadsToDraw #int
    widthOffset #float
    heightOffset #float
    angleThreshold #float
    imagePercent #float
    matcapPercent #float
    tiles #float
    cutSpeed #float
    bDepth #bool
    bStretch #bool
    bCollapsible #bool
    isWireframe #bool
    bIsTiled #bool

template getUniformLocation(gl: GL, t: Trail, name: cstring): UniformLocation =
    inc t.iUniform
    if t.uniformLocationCache.len - 1 < t.iUniform:
        t.uniformLocationCache.add(gl.getUniformLocation(t.shader, name))
    t.uniformLocationCache[t.iUniform]

template setColorUniform(c: GraphicsContext, t: Trail, name: cstring, col: Color) =
    c.setColorUniform(c.gl.getUniformLocation(t, name), col)

proc cleanup(b: var Buffer) =
    let c = currentContext()
    let gl = c.gl
    if b.indexBuffer != invalidBuffer:
        gl.deleteBuffer(b.indexBuffer)
        b.indexBuffer = invalidBuffer

    if b.vertexBuffer != invalidBuffer:
        gl.deleteBuffer(b.vertexBuffer)
        b.vertexBuffer = invalidBuffer

    b.bActive = false
    b.bValidData = false

proc bufferWithSize(gl: GL, indices, vertices: int): Buffer =
    result.vertices.curr = 0
    result.indices.curr = 0
    result.vertices.max = vertices
    result.indices.max = indices
    result.bActive = false

    result.vertexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, result.vertexBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, (result.vertices.max * sizeof(GLfloat)).int32, gl.STREAM_DRAW)

    result.indexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, result.indexBuffer)
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, (result.indices.max * sizeof(GLushort)).int32, gl.STREAM_DRAW)

proc tryAdd(b: var Buffer, vertices: openarray[GLfloat], indices: openarray[GLushort]): bool =
    let indcLen = indices.len
    if (b.indices.curr + indcLen) > b.indices.max:
        return false
    let vertLen = vertices.len
    if (b.vertices.curr + vertLen) > b.vertices.max:
        return false

    let gl = currentContext().gl

    gl.bindBuffer(gl.ARRAY_BUFFER, b.vertexBuffer)
    gl.bufferSubData(gl.ARRAY_BUFFER, (b.vertices.curr*sizeof(GLfloat)).int32, vertices)
    b.vertices.curr += vertLen

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, b.indexBuffer)
    gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER, (b.indices.curr*sizeof(GLushort)).int32, indices)
    b.indices.curr += indcLen

    return true

proc tryFill(b: var Buffer, vertices: seq[GLfloat], indices: seq[GLushort]): bool =
    let indcLen = indices.len()
    if indcLen > b.indices.max:
        return false
    let vertLen = vertices.len()
    if vertLen > b.vertices.max:
        return false

    let gl = currentContext().gl

    gl.bindBuffer(gl.ARRAY_BUFFER, b.vertexBuffer)
    gl.bufferSubData(gl.ARRAY_BUFFER, 0.int32, vertices)
    b.vertices.curr = vertLen

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, b.indexBuffer)
    gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0.int32, indices)
    b.indices.curr = indcLen

    return true

proc cleanup*(t: Trail) =
    t.currBuff = NotInited
    t.drawMode = NotInited
    t.buffers[First.int].cleanup()
    t.buffers[Second.int].cleanup()

proc newTrail(): Trail =
    new(result, cleanup)

proc checkShader(t: Trail) =
    if not t.image.isNil:
        if t.bIsTiled:
            t.shader = TrailTextureShaderTiled
        else:
            t.shader = TrailTextureShader
    else:
        t.shader = TrailShader
    if not t.matcap.isNil:
        t.shader = TrailMatcapShader
    if not t.matcap.isNil and not t.image.isNil:
        t.shader = TrailMatcapShaderMask

    currentContext().gl.useProgram(t.shader)
    t.uniformLocationCache = @[]

proc getVertexData(t: Trail, data: var openarray[GLfloat]) =
    var worldMat = t.node.worldTransform
    worldMat[12] = t.currPos[0]
    worldMat[13] = t.currPos[1]
    worldMat[14] = t.currPos[2]

    var left = worldMat * newVector3(0, -t.heightOffset/2.0, 0)
    var right = worldMat * newVector3(0, t.heightOffset/2.0, 0)

    var i = 0
    template set(v: GLfloat) = data[i] = v; inc i

    if not t.matcap.isNil:
        var A = newVector3(t.prevVertexData[0], t.prevVertexData[1], t.prevVertexData[2])
        var B = newVector3(t.prevVertexData[8], t.prevVertexData[9], t.prevVertexData[10])
        var C = newVector3(left[0], left[1], left[2])
        var normal = cross((A-B), (C-A))
        normal.normalize()

        set left[0]
        set left[1]
        set left[2]
        set normal[0]
        set normal[1]
        set normal[2]
        set t.totalLen
        set 1.0
        set right[0]
        set right[1]
        set right[2]
        set normal[0]
        set normal[1]
        set normal[2]
        set t.totalLen
        set 0.0
    else:
        set left[0]
        set left[1]
        set left[2]
        set t.totalLen
        set 1.0
        set right[0]
        set right[1]
        set right[2]
        set t.totalLen
        set 0.0

proc getIndexData(t: Trail, data: var openarray[GLushort]) =
    data[0] = t.numberOfIndexes
    data[1] = t.numberOfIndexes+1
    t.numberOfIndexes += 2

proc reset*(t: Trail) =
    var vertexDataLen = if not t.matcap.isNil: POS_NORMAL_UV_ELEMENTS else: POS_UV_ELEMENTS
    t.currVertexData = newSeq[GLfloat](vertexDataLen)
    t.prevVertexData = newSeq[GLfloat](vertexDataLen)

    t.totalLen = 0.0
    t.cropOffset = 0.0
    t.currLength = 0.0

    t.numberOfIndexes = 0

    t.drawMode = First
    t.currBuff = First

    t.prevRotation = newQuaternion(0,0,0,1)
    t.directRotation = newQuaternion(0,0,0,1)
    t.gravityDirection = newVector3(0,0,0)

    t.currPos = t.node.worldPos() - t.gravityDirection
    t.prevPos = t.currPos
    t.prevRotation = t.node.rotation

    t.getVertexData(t.currVertexData)
    t.prevVertexData = t.currVertexData

    t.buffers[First.int].bValidData = false
    t.buffers[First.int].indices.curr = 0
    t.buffers[First.int].vertices.curr = 0
    t.buffers[Second.int].bValidData = false
    t.buffers[Second.int].indices.curr = 0
    t.buffers[Second.int].vertices.curr = 0

    var initialIndexData {.noinit.}: array[IND_ELEMENTS, GLushort]
    t.getIndexData(initialIndexData)
    var offsetIndexData {.noinit.}: array[IND_ELEMENTS, GLushort]
    t.getIndexData(offsetIndexData)

    if t.buffers[t.currBuff.int].tryAdd(t.prevVertexData, initialIndexData) and t.buffers[t.currBuff.int].tryAdd(t.currVertexData, offsetIndexData):
        t.buffers[t.currBuff.int].bValidData = true

    t.checkShader()

proc trailImage*(t: Trail): Image =
    result = t.image

proc `trailImage=`*(t: Trail, i: Image) =
    t.image = i
    t.drawMode = Skip
    t.checkShader()

proc trailMatcap*(t: Trail): Image =
    result = t.matcap

proc `trailMatcap=`*(t: Trail, i: Image) =
    t.matcap = i
    t.drawMode = Skip
    t.checkShader()

proc trailWidth*(t: Trail): float32 =
    result = t.widthOffset

proc `trailWidth=`*(t: Trail, v: float32) =
    t.widthOffset = v
    t.reset()

proc trailHeight*(t: Trail): float32 =
    result = t.heightOffset

proc `trailHeight=`*(t: Trail, v: float32) =
    t.heightOffset = v

method init*(t: Trail) =
    procCall t.Component.init()

    t.color = newColor(1, 1, 1, 1)

    t.currBuff = NotInited
    t.drawMode = NotInited

    t.numberOfIndexes = 0.GLushort

    t.widthOffset = 100.0
    t.heightOffset = 10.0
    t.imagePercent = 1.0
    t.matcapPercent = 1.0

    t.angleThreshold = 0.01
    t.quadsToDraw = 150

    t.currVertexData = newSeq[GLfloat](POS_NORMAL_UV_ELEMENTS)
    t.prevVertexData = newSeq[GLfloat](POS_NORMAL_UV_ELEMENTS)

    t.gravityDirection = newVector3(0,0,0)
    t.directRotation = newQuaternion(0,0,0,1)

    t.prevRotation = newQuaternion(0,0,0,1)

    t.shader = TrailShader

    t.totalLen = 0.0
    t.currLength = 0.0
    t.cropOffset = 0.0

proc distance(first, second: Vector3): float =
    result = sqrt(pow(first.x-second.x, 2)+pow(first.y-second.y, 2)+pow(first.z-second.z, 2))

proc needEmit(t: Trail): bool =
    var currDirection = t.currPos - t.prevPos
    currDirection.normalize()

    if currDirection.x == 0 and currDirection.y == 0 and currDirection.z == 0 :
        return false

    if not ( (currDirection[0] >= t.directionVector[0] - t.angleThreshold and currDirection[0] <= t.directionVector[0] + t.angleThreshold) and
             (currDirection[1] >= t.directionVector[1] - t.angleThreshold and currDirection[1] <= t.directionVector[1] + t.angleThreshold) and
             (currDirection[2] >= t.directionVector[2] - t.angleThreshold and currDirection[2] <= t.directionVector[2] + t.angleThreshold) ):

        t.prevRotation = t.node.rotation
        t.directionVector = currDirection
        return true

    if not ( (t.node.rotation.x >= t.prevRotation.x - t.angleThreshold and t.node.rotation.x <= t.prevRotation.x + t.angleThreshold) and
             (t.node.rotation.y >= t.prevRotation.y - t.angleThreshold and t.node.rotation.y <= t.prevRotation.y + t.angleThreshold) and
             (t.node.rotation.z >= t.prevRotation.z - t.angleThreshold and t.node.rotation.z <= t.prevRotation.z + t.angleThreshold) and
             (t.node.rotation.w >= t.prevRotation.w - t.angleThreshold and t.node.rotation.w <= t.prevRotation.w + t.angleThreshold) ):

        t.prevRotation = t.node.rotation
        t.directionVector = currDirection
        return true

    return false

proc emitQuad(t: Trail) =
    let c = currentContext()
    let gl = c.gl

    t.currLength = distance(t.currPos, t.prevPos)

    t.totalLen += t.currLength
    if t.currLength > t.widthOffset:
        t.reset()

    if t.totalLen > t.widthOffset and not t.bStretch:
        t.cropOffset += t.currLength

    t.getVertexData(t.currVertexData)

    var indexData {.noinit.}: array[IND_ELEMENTS, GLushort]
    t.getIndexData(indexData)

    if t.buffers[t.currBuff.int].tryAdd(t.currVertexData, indexData):
        t.buffers[t.currBuff.int].bValidData = true
    else:
        if t.currBuff == First:
            t.currBuff = Second
        else:
            t.currBuff = First

        t.buffers[t.currBuff.int].indices.curr = 0
        t.buffers[t.currBuff.int].vertices.curr = 0

        t.numberOfIndexes = 0

        var initialIndexData {.noinit.}: array[IND_ELEMENTS, GLushort]
        t.getIndexData(initialIndexData)
        var offsetIndexData {.noinit.}: array[IND_ELEMENTS, GLushort]
        t.getIndexData(offsetIndexData)

        if t.buffers[t.currBuff.int].tryAdd(t.prevVertexData, initialIndexData) and
           t.buffers[t.currBuff.int].tryAdd(t.currVertexData, offsetIndexData):
            t.buffers[t.currBuff.int].bValidData = true

    if t.currBuff == First:
        if t.buffers[Second.int].bValidData:
            t.drawMode = SecondFirst
        else:
            t.drawMode = First
    else:
        if t.buffers[First.int].bValidData:
            t.drawMode = FirstSecond
        else:
            t.drawMode = Second

proc setupAttribArray(t: Trail, gl: GL) =
    var attribArrayOffset = 0
    if not t.matcap.isNil:
        gl.enableVertexAttribArray(aPosition.GLuint)
        gl.vertexAttribPointer(aPosition.GLuint, 3, gl.FLOAT, false, (8 * sizeof(GLfloat)).GLsizei, attribArrayOffset)
        attribArrayOffset += 3 * sizeof(GLfloat)
        gl.enableVertexAttribArray(aNormal.GLuint)
        gl.vertexAttribPointer(aNormal.GLuint, 3, gl.FLOAT, false, (8 * sizeof(GLfloat)).GLsizei, attribArrayOffset)
        attribArrayOffset += 3 * sizeof(GLfloat)
        gl.enableVertexAttribArray(aTexCoord.GLuint)
        gl.vertexAttribPointer(aTexCoord.GLuint, 2, gl.FLOAT, false, (8 * sizeof(GLfloat)).GLsizei, attribArrayOffset)
    else:
        gl.enableVertexAttribArray(aPosition.GLuint)
        gl.vertexAttribPointer(aPosition.GLuint, 3, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei, attribArrayOffset)
        attribArrayOffset += 3 * sizeof(GLfloat)
        gl.enableVertexAttribArray(aTexCoord.GLuint)
        gl.vertexAttribPointer(aTexCoord.GLuint, 2, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei, attribArrayOffset)

proc setupUniforms(t: Trail, gl: GL) =
    gl.uniform1f(gl.getUniformLocation(t, "uCropOffset"), t.cropOffset)
    gl.uniform1f(gl.getUniformLocation(t, "uLength"), t.totalLen)
    gl.uniform1f(gl.getUniformLocation(t, "uAlphaCut"), t.alphaCut)

proc updateLastVertex(t: Trail, gl: GL, currBuff: DataInBuffer) =
    t.currLength = distance(t.currPos, t.prevPos)

    t.totalLen += t.currLength

    if t.totalLen > t.widthOffset and not t.bStretch:
        t.cropOffset += t.currLength

    if t.bCollapsible:
        if t.cutSpeed > 0:
            t.cropOffset += t.cutSpeed * getDeltaTime()

    t.getVertexData(t.prevVertexData)

    gl.bindBuffer(gl.ARRAY_BUFFER, t.buffers[currBuff.int].vertexBuffer)
    if t.buffers[currBuff.int].vertices.curr > t.prevVertexData.len:
        gl.bufferSubData(gl.ARRAY_BUFFER, ((t.buffers[currBuff.int].vertices.curr - t.prevVertexData.len) * sizeof(GLfloat)).int32, t.prevVertexData)
    else:
        gl.bufferSubData(gl.ARRAY_BUFFER, 0.int32, t.prevVertexData)

proc singleBufferDraw(t: Trail, gl: GL, drawVertices: int, currBuff: DataInBuffer) {.inline.} =
    gl.bindBuffer(gl.ARRAY_BUFFER, t.buffers[currBuff.int].vertexBuffer)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, t.buffers[currBuff.int].indexBuffer)
    t.updateLastVertex(gl, currBuff)
    t.setupAttribArray(gl)
    t.setupUniforms(gl)

    var offset = t.buffers[currBuff.int].indices.curr - drawVertices
    if offset < 0:
        gl.drawElements(gl.TRIANGLE_STRIP, t.buffers[currBuff.int].indices.curr.GLsizei, gl.UNSIGNED_SHORT, 0.int )
    else:
        gl.drawElements(gl.TRIANGLE_STRIP, drawVertices.GLsizei, gl.UNSIGNED_SHORT, (offset*sizeof(GLushort)).int )

proc multipleBuffersDraw(t: Trail, gl: GL, drawVertices: int, currBuff, nextBuff: DataInBuffer) =
    var indicesCount = t.buffers[currBuff.int].indices.curr

    if (t.buffers[currBuff.int].indices.curr + t.buffers[nextBuff.int].indices.curr) > drawVertices:
        indicesCount -= t.buffers[nextBuff.int].indices.curr

    if indicesCount <= 0:
        t.buffers[currBuff.int].bValidData = false
    else:
        gl.bindBuffer(gl.ARRAY_BUFFER, t.buffers[currBuff.int].vertexBuffer)
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, t.buffers[currBuff.int].indexBuffer)
        t.setupAttribArray(gl)
        t.setupUniforms(gl)
        let indicesOffset = t.buffers[currBuff.int].indices.curr - indicesCount
        gl.drawElements(gl.TRIANGLE_STRIP, indicesCount.GLsizei, gl.UNSIGNED_SHORT, (indicesOffset*sizeof(GLushort)).int )

    t.updateLastVertex(gl, nextBuff)
    gl.bindBuffer(gl.ARRAY_BUFFER, t.buffers[nextBuff.int].vertexBuffer)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, t.buffers[nextBuff.int].indexBuffer)

    t.setupAttribArray(gl)
    t.setupUniforms(gl)
    gl.drawElements(gl.TRIANGLE_STRIP, t.buffers[nextBuff.int].indices.curr.GLsizei, gl.UNSIGNED_SHORT, 0.int )

method draw*(t: Trail) =
    let c = currentContext()
    let gl = c.gl

    t.iUniform = -1

    # init
    if TrailShader == invalidProgram:
        TrailShader = gl.newShaderProgram(vertexShader, fragmentShader, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])
        TrailTextureShader = gl.newShaderProgram(vertexShader, fragmentShaderTexture, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])
        TrailTextureShaderTiled = gl.newShaderProgram(vertexShader, fragmentShaderTextureTiled, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])
        TrailMatcapShader = gl.newShaderProgram(vertexShaderWithNormal, fragmentShaderMatcap, [(aPosition.GLuint, $aPosition), (aNormal.GLuint, $aNormal), (aTexCoord.GLuint, $aTexCoord)])
        TrailMatcapShaderMask = gl.newShaderProgram(vertexShaderWithNormal, fragmentShaderMatcapMask, [(aPosition.GLuint, $aPosition), (aNormal.GLuint, $aNormal), (aTexCoord.GLuint, $aTexCoord)])
        if TrailShader == invalidProgram or TrailTextureShader == invalidProgram or TrailMatcapShader == invalidProgram or TrailMatcapShaderMask == invalidProgram or TrailTextureShaderTiled == invalidProgram:
            return
        t.checkShader()

    if t.currBuff == NotInited:
        t.currPos = t.node.worldPos() - t.gravityDirection
        t.prevPos = t.currPos

        t.buffers[First.int] = gl.bufferWithSize(initialIndicesCount,initialVerticesCount)
        t.buffers[Second.int] = gl.bufferWithSize(initialIndicesCount,initialVerticesCount)

        t.currBuff = First
        t.drawMode = First

        t.emitQuad()
        t.checkShader()

        t.reset()

    # check transform
    t.gravityDirection += t.gravity * getDeltaTime()

    t.prevPos = t.currPos
    t.currPos = t.node.worldPos() - t.gravityDirection

    if t.needEmit():
        t.emitQuad()

    # set gl states
    if t.bDepth:
        gl.enable(gl.DEPTH_TEST)

    gl.disable(gl.CULL_FACE)

    when not defined(ios) and not defined(android) and not defined(js) and not defined(emscripten):
        if t.isWireframe:
            glPolygonMode(GL_FRONT_AND_BACK, GL_LINE)

    # set uniforms
    gl.useProgram(t.shader)

    if not t.image.isNil and t.image.isLoaded :
        var theQuad {.noinit.}: array[4, GLfloat]
        gl.activeTexture(GLenum(int(gl.TEXTURE0)))
        gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(t.image, gl, theQuad))
        gl.uniform4fv(gl.getUniformLocation(t, "uTexUnitCoords"), theQuad)
        gl.uniform1i(gl.getUniformLocation(t, "texUnit"), 0.GLint)
        gl.uniform1f(gl.getUniformLocation(t, "uImagePercent"), t.imagePercent)

    if not t.matcap.isNil and t.matcap.isLoaded :
        var theQuad {.noinit.}: array[4, GLfloat]
        gl.activeTexture(GLenum(int(gl.TEXTURE0)+1))
        gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(t.matcap, gl, theQuad))
        gl.uniform4fv(gl.getUniformLocation(t, "uMatcapUnitCoords"), theQuad)
        gl.uniform1i(gl.getUniformLocation(t, "matcapUnit"), 1.GLint)
        gl.uniform1f(gl.getUniformLocation(t, "uMatcapPercent"), t.matcapPercent)

    if t.bIsTiled:
        gl.uniform1f(gl.getUniformLocation(t, "uTiles"), t.tiles)


    var modelMatrix = t.directRotation.toMatrix4
    modelMatrix[12] = t.gravityDirection[0]
    modelMatrix[13] = t.gravityDirection[1]
    modelMatrix[14] = t.gravityDirection[2]

    let vp = t.node.sceneView
    let cam = vp.camera
    var viewMatrix = vp.viewMatrixCached

    var projMatrix : Matrix4
    cam.getProjectionMatrix(vp.bounds, projMatrix)

    let mvMatrix = viewMatrix * modelMatrix

    let mvpMatrix = projMatrix * mvMatrix

    var normalMatrix: Matrix3
    if t.node.scale[0] != 0 and t.node.scale[1] != 0 and t.node.scale[2] != 0:
        mvMatrix.toInversedMatrix3(normalMatrix)
        normalMatrix.transpose()
    else:
        normalMatrix.loadIdentity()

    gl.uniformMatrix3fv(gl.getUniformLocation(t, "normalMatrix"), false, normalMatrix)
    gl.uniformMatrix4fv(gl.getUniformLocation(t, "mvpMatrix"), false, mvpMatrix)
    gl.uniformMatrix4fv(gl.getUniformLocation(t, "mvMatrix"), false, mvMatrix)
    gl.uniform1f(gl.getUniformLocation(t, "uAlpha"), c.alpha)
    c.setColorUniform(t, "uColor", t.color)

    var drawVertices = t.quadsToDraw * 2

    if t.drawMode == First or t.drawMode == Second:
        t.singleBufferDraw(gl, drawVertices, t.drawMode)
    elif t.drawMode == FirstSecond:
        t.multipleBuffersDraw(gl, drawVertices, First, Second)
    elif t.drawMode == SecondFirst:
        t.multipleBuffersDraw(gl, drawVertices, Second, First)
    elif t.drawMode == Skip:
        t.reset()

    when not defined(ios) and not defined(android) and not defined(js) and not defined(emscripten):
        glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)

    # to default settings
    gl.disable(gl.DEPTH_TEST)

method deserialize*(t: Trail, j: JsonNode, s: Serializer) =
    if j.isNil:
        return

    s.deserializeValue(j, "color", t.color)
    s.deserializeValue(j, "quadsToDraw", t.quadsToDraw)
    s.deserializeValue(j, "gravity", t.gravity)
    s.deserializeValue(j, "directRotation", t.directRotation)
    s.deserializeValue(j, "widthOffset", t.widthOffset)
    s.deserializeValue(j, "heightOffset", t.heightOffset)
    s.deserializeValue(j, "angleThreshold", t.angleThreshold)
    s.deserializeValue(j, "bDepth", t.bDepth)
    s.deserializeValue(j, "bStretch", t.bStretch)
    s.deserializeValue(j, "bCollapsible", t.bCollapsible)
    s.deserializeValue(j, "cutSpeed", t.cutSpeed)
    s.deserializeValue(j, "isWireframe", t.isWireframe)
    s.deserializeValue(j, "imagePercent", t.imagePercent)
    s.deserializeValue(j, "matcapPercent", t.matcapPercent)
    s.deserializeValue(j, "bIsTiled", t.bIsTiled)
    s.deserializeValue(j, "tiles", t.tiles)

    deserializeImage(j{"trailImage"}, s) do(img: Image, err: string):
        t.trailImage = img

    deserializeImage(j{"trailMatcap"}, s) do(img: Image, err: string):
        t.trailMatcap = img

method serialize*(t: Trail, s: Serializer): JsonNode =
    result = newJObject()

    result.add("color", s.getValue(t.color))
    result.add("quadsToDraw", s.getValue(t.quadsToDraw))
    result.add("gravity", s.getValue(t.gravity))
    result.add("directRotation", s.getValue(t.directRotation))
    result.add("widthOffset", s.getValue(t.widthOffset))
    result.add("heightOffset", s.getValue(t.heightOffset))
    result.add("angleThreshold", s.getValue(t.angleThreshold))
    result.add("bDepth", s.getValue(t.bDepth))
    result.add("bStretch", s.getValue(t.bStretch))
    result.add("bCollapsible", s.getValue(t.bCollapsible))
    result.add("isWireframe", s.getValue(t.isWireframe))
    result.add("cutSpeed", s.getValue(t.cutSpeed))
    result.add("bIsTiled", s.getValue(t.bIsTiled))
    result.add("tiles", s.getValue(t.tiles))
    if not t.image.isNil:
        result.add("imagePercent", s.getValue(t.imagePercent))
    if not t.trailMatcap.isNil:
        result.add("matcapPercent", s.getValue(t.matcapPercent))
    if not t.image.isNil:
        result.add("trailImage", s.getValue(s.getRelativeResourcePath(t.trailImage.filePath())))
    if not t.trailMatcap.isNil:
        result.add("trailMatcap", s.getValue(s.getRelativeResourcePath(t.trailMatcap.filePath())))

proc collapse*(t: Trail): bool =
    result = t.bCollapsible

proc `collapse=`*(t: Trail, v: bool) =
    if t.bCollapsible and not v:
        t.reset()

    t.bCollapsible = v

proc tiled*(t: Trail): bool =
    result = t.bIsTiled

proc `tiled=`*(t: Trail, v: bool) =
    t.bIsTiled = v
    t.checkShader()

method visitProperties*(t: Trail, p: var PropertyVisitor) =
    # art props
    p.visitProperty("color", t.color)
    p.visitProperty("image", (t.trailImage, t.imagePercent))
    p.visitProperty("matcap", (t.trailMatcap, t.matcapPercent))
    p.visitProperty("height", t.trailHeight)
    p.visitProperty("width", t.trailWidth)
    p.visitProperty("gravity", t.gravity)
    p.visitProperty("rotation", t.directRotation)
    p.visitProperty("depth", t.bDepth)
    p.visitProperty("stretch", t.bStretch)
    p.visitProperty("collapsible", t.collapse)
    p.visitProperty("cutSpeed", t.cutSpeed)
    p.visitProperty("alphaCut", t.alphaCut)
    p.visitProperty("tiled", t.tiled)
    p.visitProperty("tiles", t.tiles)

    # dev props
    p.visitProperty("threshold", t.angleThreshold)
    p.visitProperty("quads", t.quadsToDraw)
    p.visitProperty("wireframe", t.isWireframe)

proc creator(): RootRef =
    result = newTrail()

genSerializationCodeForComponent(Trail)
registerComponent(Trail, creator)
