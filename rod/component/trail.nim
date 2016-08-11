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

import math
import opengl
import json

const vertexShader = """
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
varying vec3 vNormal;
varying vec2 vTexCoord;

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;

uniform vec4 uColor;
uniform float uLength;
uniform float uCropOffset;
uniform float uAlpha;

void main() {
    vec2 uv = vec2(vTexCoord.x-uCropOffset , vTexCoord.y);
    if (uv.x < 0.0) {
        discard;
    }
    gl_FragColor = uColor * uAlpha;
}
"""
const fragmentShaderTexture = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

varying vec3 vPosition;
varying vec3 vNormal;
varying vec2 vTexCoord;

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;
uniform float uImagePercent;

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

    vec4 col = texture2D(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * uv) * uImagePercent;
    if (col.a < 0.01) {
        discard;
    }
    gl_FragColor = col * uColor * uAlpha;
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
    gl_FragColor = matcap * uColor * uAlpha;
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


    //vec4 diffuse = texture2D(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * uv);
    //vec4 specular = vec4(1.0, 1.0, 1.0, 1.0);
    //vec3 lightPosition = vec3(0,0,500);
    //vec3 L = normalize(lightPosition.xyz - vPosition.xyz);
    //vec3 E = normalize(-vPosition.xyz);
    //vec3 R = normalize(-reflect(L, vNormal));
    //diffuse.rgb *= max(dot(vNormal, L), 0.0);
    //specular.rgb *= pow(max(dot(R, E), 0.0), 16.0);
    //gl_FragColor = diffuse + specular;
}
"""

var TrailShader: ProgramRef
var TrailTextureShader: ProgramRef
var TrailMatcapShader: ProgramRef
var TrailMatcapShaderMask: ProgramRef

const initialIndicesCount = 500
const initialVerticesCount = 5 * initialIndicesCount
const SINGLE_VERTEX_DATA_ELEMENTS = 16
type
    Attrib = enum
        aPosition
        aNormal
        aTexCoord

    DataInBuffer = enum
        First
        Second
        FirstSecond
        SecondFirst
        NotInited
        Skip

    Buffer = ref object of RootObj
        vertexBuffer: BufferRef
        indexBuffer: BufferRef

        vertices: tuple[curr: int, max: int]
        indices: tuple[curr: int, max: int]

        bActive: bool
        bValidData: bool

    Trail* = ref object of Component
        color*: Color

        numberOfIndexes: GLushort
        quadsToDraw*: int

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

        buffers: seq[Buffer]
        currBuff: DataInBuffer
        drawMode: DataInBuffer

        shader*: ProgramRef

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
        isWireframe: bool

proc cleanup(b: Buffer) =
    let c = currentContext()
    let gl = c.gl
    if b.indexBuffer != invalidBuffer:
        gl.bindBuffer(gl.ARRAY_BUFFER, b.indexBuffer)
        gl.deleteBuffer(b.indexBuffer)
        b.indexBuffer = invalidBuffer

    if b.vertexBuffer != invalidBuffer:
        gl.bindBuffer(gl.ARRAY_BUFFER, b.vertexBuffer)
        gl.deleteBuffer(b.vertexBuffer)
        b.vertexBuffer = invalidBuffer

proc bufferWithSize(gl: GL, indices, vertices: int): Buffer =
    new( result, proc(b: Buffer) = b.cleanup() )

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

template bindBuffer(b: Buffer) =
    #TODO manager of buffers
    # if not b.bActive:
    currentContext().gl.bindBuffer(currentContext().gl.ARRAY_BUFFER, b.vertexBuffer)
    currentContext().gl.bindBuffer(currentContext().gl.ELEMENT_ARRAY_BUFFER, b.indexBuffer)
    b.bActive = true

template releaseBuffer(b: Buffer) =
    if b.bActive:
        b.bActive = false

proc tryAdd(b: Buffer, vertices: seq[GLfloat], indices: seq[GLushort]): bool =
    let indcLen = indices.len()
    if (b.indices.curr + indcLen) > b.indices.max:
        return false
    let vertLen = vertices.len()
    if (b.vertices.curr + vertLen) > b.vertices.max:
        return false

    let gl = currentContext().gl

    b.bindBuffer()

    gl.bufferSubData(gl.ARRAY_BUFFER, (b.vertices.curr*sizeof(GLfloat)).int32, vertices)
    b.vertices.curr += vertLen

    gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER, (b.indices.curr*sizeof(GLushort)).int32, indices)
    b.indices.curr += indcLen

    return true

proc tryFill(b: Buffer, vertices: seq[GLfloat], indices: seq[GLushort]): bool =
    let indcLen = indices.len()
    if indcLen > b.indices.max:
        return false
    let vertLen = vertices.len()
    if vertLen > b.vertices.max:
        return false

    let gl = currentContext().gl

    b.bindBuffer()

    gl.bufferSubData(gl.ARRAY_BUFFER, 0.int32, vertices)
    b.vertices.curr = vertLen

    gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0.int32, indices)
    b.indices.curr = indcLen

    return true

proc newTrail(): Trail =
    new(result, proc(t: Trail) =
        for b in t.buffers: b.cleanup()
    )

template checkShader(t: Trail) =
    if not t.image.isNil:
        t.shader = TrailTextureShader
    else:
        t.shader = TrailShader
    if not t.matcap.isNil:
        t.shader = TrailMatcapShader
    if not t.matcap.isNil and not t.image.isNil:
        t.shader = TrailMatcapShaderMask

    currentContext().gl.useProgram(t.shader)

proc vertexData(t: Trail): seq[GLfloat] =
    var worldMat = t.node.worldTransform
    worldMat[12] = t.currPos[0]
    worldMat[13] = t.currPos[1]
    worldMat[14] = t.currPos[2]

    var left = worldMat * newVector3(0, -t.heightOffset/2.0, 0)
    var right = worldMat * newVector3(0, t.heightOffset/2.0, 0)

    result = @[
        left[0], left[1], left[2],
        t.totalLen, 1.0,
        right[0], right[1], right[2],
        t.totalLen, 0.0
    ]

proc vertexDataWithNormal(t: Trail): seq[GLfloat] =
    var worldMat = t.node.worldTransform
    worldMat[12] = t.currPos[0]
    worldMat[13] = t.currPos[1]
    worldMat[14] = t.currPos[2]

    var left = worldMat * newVector3(0, -t.heightOffset/2.0, 0)
    var right = worldMat * newVector3(0, t.heightOffset/2.0, 0)

    var A = newVector3(t.prevVertexData[0], t.prevVertexData[1], t.prevVertexData[2])
    var B = newVector3(t.prevVertexData[8], t.prevVertexData[9], t.prevVertexData[10])
    var C = newVector3(left[0], left[1], left[2])
    var normal = cross((A-B), (C-A))
    normal.normalize()

    result = @[
        left[0], left[1], left[2],
        normal[0], normal[1], normal[2],
        t.totalLen, 1.0,
        right[0], right[1], right[2],
        normal[0], normal[1], normal[2],
        t.totalLen, 0.0
    ]

proc indexData(t: Trail): seq[GLushort] =
    result = @[
        t.numberOfIndexes,
        t.numberOfIndexes+1
    ]
    t.numberOfIndexes += 2

proc reset*(t: Trail) =
    t.totalLen = 0.0
    t.cropOffset = 0.0
    t.currLength = 0.0

    t.numberOfIndexes = 0

    t.drawMode = First
    t.currBuff = First

    t.prevRotation = newQuaternion(0,0,0,1)
    t.directRotation = newQuaternion(0,0,0,1)
    t.gravityDirection = newVector3(0,0,0)

    t.imagePercent = 1.0
    t.matcapPercent = 1.0

    t.currPos = t.node.worldPos() - t.gravityDirection
    t.prevPos = t.currPos
    t.prevRotation = t.node.rotation
    t.prevVertexData = if not t.matcap.isNil: t.vertexDataWithNormal() else: t.vertexData()

    t.buffers[First.int].bValidData = false
    t.buffers[First.int].indices.curr = 0
    t.buffers[First.int].vertices.curr = 0
    t.buffers[Second.int].bValidData = false
    t.buffers[Second.int].indices.curr = 0
    t.buffers[Second.int].vertices.curr = 0

    var vertexData = if not t.matcap.isNil: t.vertexDataWithNormal() else: t.vertexData()
    var initialIndexData = t.indexData()
    var offsetIndexData = t.indexData()

    if t.buffers[t.currBuff.int].tryAdd(t.prevVertexData, initialIndexData) and t.buffers[t.currBuff.int].tryAdd(vertexData, offsetIndexData):
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

method init*(t: Trail) =
    procCall t.Component.init()

    t.color = newColor(1, 1, 1, 1)

    t.buffers = @[]
    t.currBuff = NotInited
    t.drawMode = NotInited

    t.numberOfIndexes = 0.GLushort

    t.widthOffset = 100.0
    t.heightOffset = 10.0

    t.angleThreshold = 0.01
    t.quadsToDraw = 150

    t.prevVertexData = newSeq[GLfloat](SINGLE_VERTEX_DATA_ELEMENTS)

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

    if not ( (t.node.rotation[0] >= t.prevRotation[0] - t.angleThreshold and t.node.rotation[0] <= t.prevRotation[0] + t.angleThreshold) and
             (t.node.rotation[1] >= t.prevRotation[1] - t.angleThreshold and t.node.rotation[1] <= t.prevRotation[1] + t.angleThreshold) and
             (t.node.rotation[2] >= t.prevRotation[2] - t.angleThreshold and t.node.rotation[2] <= t.prevRotation[2] + t.angleThreshold) and
             (t.node.rotation[3] >= t.prevRotation[3] - t.angleThreshold and t.node.rotation[3] <= t.prevRotation[3] + t.angleThreshold) ):

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

    var vertexData = if not t.matcap.isNil: t.vertexDataWithNormal() else: t.vertexData()
    var indexData = t.indexData()

    if t.buffers[t.currBuff.int].tryAdd(vertexData, indexData):
        t.buffers[t.currBuff.int].bValidData = true
    else:
        if t.currBuff == First:
            t.currBuff = Second
        else:
            t.currBuff = First

        t.buffers[t.currBuff.int].indices.curr = 0
        t.buffers[t.currBuff.int].vertices.curr = 0

        t.numberOfIndexes = 0

        var initialIndexData = t.indexData()
        var offsetIndexData = t.indexData()

        if t.buffers[t.currBuff.int].tryAdd(t.prevVertexData, initialIndexData) and t.buffers[t.currBuff.int].tryAdd(vertexData, offsetIndexData):
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

method draw*(t: Trail) =
    let c = currentContext()
    let gl = c.gl

    # init
    if TrailShader == invalidProgram:
        TrailShader = gl.newShaderProgram(vertexShader, fragmentShader, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])
        TrailTextureShader = gl.newShaderProgram(vertexShader, fragmentShaderTexture, [(aPosition.GLuint, $aPosition), (aNormal.GLuint, $aNormal), (aTexCoord.GLuint, $aTexCoord)])
        TrailMatcapShader = gl.newShaderProgram(vertexShader, fragmentShaderMatcap, [(aPosition.GLuint, $aPosition), (aNormal.GLuint, $aNormal), (aTexCoord.GLuint, $aTexCoord)])
        TrailMatcapShaderMask = gl.newShaderProgram(vertexShader, fragmentShaderMatcapMask, [(aPosition.GLuint, $aPosition), (aNormal.GLuint, $aNormal), (aTexCoord.GLuint, $aTexCoord)])
        if TrailShader == invalidProgram or TrailTextureShader == invalidProgram or TrailMatcapShader == invalidProgram or TrailMatcapShaderMask == invalidProgram:
            return
        t.checkShader()

    if t.currBuff == NotInited:
        t.currPos = t.node.worldPos() - t.gravityDirection
        t.prevPos = t.currPos

        var firstBuffer = gl.bufferWithSize(initialIndicesCount,initialVerticesCount)
        var secondBuffer = gl.bufferWithSize(initialIndicesCount,initialVerticesCount)
        t.buffers.add(firstBuffer)
        t.buffers.add(secondBuffer)

        t.currBuff = First
        t.drawMode = First

        t.buffers[t.currBuff.int].bindBuffer()
        t.emitQuad()
        t.checkShader()

    # check transform
    t.gravityDirection += t.gravity

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
        gl.uniform4fv(gl.getUniformLocation(t.shader, "uTexUnitCoords"), theQuad)
        gl.uniform1i(gl.getUniformLocation(t.shader, "texUnit"), 0.GLint)
        gl.uniform1f(gl.getUniformLocation(t.shader, "uImagePercent"), t.imagePercent)

    if not t.matcap.isNil and t.matcap.isLoaded :
        var theQuad {.noinit.}: array[4, GLfloat]
        gl.activeTexture(GLenum(int(gl.TEXTURE0)+1))
        gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(t.matcap, gl, theQuad))
        gl.uniform4fv(gl.getUniformLocation(t.shader, "uMatcapUnitCoords"), theQuad)
        gl.uniform1i(gl.getUniformLocation(t.shader, "matcapUnit"), 1.GLint)
        gl.uniform1f(gl.getUniformLocation(t.shader, "uMatcapPercent"), t.matcapPercent)


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
    gl.uniformMatrix3fv(gl.getUniformLocation(t.shader, "normalMatrix"), false, normalMatrix)

    gl.uniformMatrix4fv(gl.getUniformLocation(t.shader, "mvpMatrix"), false, mvpMatrix)

    gl.uniformMatrix4fv(gl.getUniformLocation(t.shader, "mvMatrix"), false, mvMatrix)

    gl.uniform1f(gl.getUniformLocation(t.shader, "uAlpha"), c.alpha)

    c.setColorUniform(t.shader, "uColor", t.color)

    var drawVertices = t.quadsToDraw * 2

    template setupAttribArray() =
        if not t.matcap.isNil:
            var attribArrayOffset: int = 0
            gl.enableVertexAttribArray(aPosition.GLuint)
            gl.vertexAttribPointer(aPosition.GLuint, 3, gl.FLOAT, false, (8 * sizeof(GLfloat)).GLsizei, attribArrayOffset)
            attribArrayOffset += 3 * sizeof(GLfloat)
            gl.enableVertexAttribArray(aNormal.GLuint)
            gl.vertexAttribPointer(aNormal.GLuint, 3, gl.FLOAT, false, (8 * sizeof(GLfloat)).GLsizei, attribArrayOffset)
            attribArrayOffset += 3 * sizeof(GLfloat)
            gl.enableVertexAttribArray(aTexCoord.GLuint)
            gl.vertexAttribPointer(aTexCoord.GLuint, 2, gl.FLOAT, false, (8 * sizeof(GLfloat)).GLsizei, attribArrayOffset)
        else:
            var attribArrayOffset: int = 0
            gl.enableVertexAttribArray(aPosition.GLuint)
            gl.vertexAttribPointer(aPosition.GLuint, 3, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei, attribArrayOffset)
            attribArrayOffset += 3 * sizeof(GLfloat)
            gl.enableVertexAttribArray(aTexCoord.GLuint)
            gl.vertexAttribPointer(aTexCoord.GLuint, 2, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei, attribArrayOffset)

    template updateLastVertex(currBuff: DataInBuffer) =
        t.currLength = distance(t.currPos, t.prevPos)
        t.totalLen += t.currLength

        if t.totalLen > t.widthOffset and not t.bStretch:
            t.cropOffset += t.currLength
        var vertexData = if not t.matcap.isNil: t.vertexDataWithNormal() else: t.vertexData()

        if t.buffers[currBuff.int].vertices.curr > vertexData.len:
            gl.bindBuffer(gl.ARRAY_BUFFER, t.buffers[currBuff.int].vertexBuffer)
            gl.bufferSubData(gl.ARRAY_BUFFER, ((t.buffers[currBuff.int].vertices.curr - vertexData.len) * sizeof(GLfloat)).int32, vertexData)
        else:
            gl.bindBuffer(gl.ARRAY_BUFFER, t.buffers[currBuff.int].vertexBuffer)
            gl.bufferSubData(gl.ARRAY_BUFFER, 0.int32, vertexData)
        t.prevVertexData = vertexData

    template setupUniforms() =
        gl.uniform1f(gl.getUniformLocation(t.shader, "uCropOffset"), t.cropOffset)
        gl.uniform1f(gl.getUniformLocation(t.shader, "uLength"), t.totalLen)

    template singleBufferDraw(currBuff: DataInBuffer) =
        t.buffers[currBuff.int].bindBuffer()
        updateLastVertex(currBuff)
        setupAttribArray()
        setupUniforms()

        var offset = t.buffers[currBuff.int].indices.curr - drawVertices
        if offset < 0:
            gl.drawElements(gl.TRIANGLE_STRIP, t.buffers[currBuff.int].indices.curr.GLsizei, gl.UNSIGNED_SHORT, 0.int )
        else:
            gl.drawElements(gl.TRIANGLE_STRIP, drawVertices.GLsizei, gl.UNSIGNED_SHORT, (offset*sizeof(GLushort)).int )

    template multiplyBuffersDraw(currBuff, nextBuff: DataInBuffer) =
        var indicesCount =  t.buffers[currBuff.int].indices.curr - t.buffers[nextBuff.int].indices.curr

        if indicesCount <= 0:
            t.buffers[currBuff.int].bValidData = false
        else:
            t.buffers[currBuff.int].bindBuffer()
            setupAttribArray()
            setupUniforms()
            let indicesOffset = t.buffers[currBuff.int].indices.curr - indicesCount
            gl.drawElements(gl.TRIANGLE_STRIP, indicesCount.GLsizei, gl.UNSIGNED_SHORT, (indicesOffset*sizeof(GLushort)).int )

        t.buffers[nextBuff.int].bindBuffer()
        updateLastVertex(nextBuff)
        setupAttribArray()
        setupUniforms()
        gl.drawElements(gl.TRIANGLE_STRIP, t.buffers[nextBuff.int].indices.curr.GLsizei, gl.UNSIGNED_SHORT, 0.int )

    if t.drawMode == First:
        singleBufferDraw(First)
    elif t.drawMode == FirstSecond:
        multiplyBuffersDraw(First, Second)
    elif t.drawMode == Second:
        singleBufferDraw(Second)
    elif t.drawMode == SecondFirst:
        multiplyBuffersDraw(Second, First)
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
    s.deserializeValue(j, "isWireframe", t.isWireframe)
    s.deserializeValue(j, "imagePercent", t.imagePercent)
    s.deserializeValue(j, "matcapPercent", t.matcapPercent)

    proc getTexture(name: string): Image =
        let jNode = j{name}
        if not jNode.isNil:
            result = imageWithResource(jNode.getStr())

    t.trailImage = getTexture("trailImage")
    t.trailMatcap = getTexture("trailMatcap")

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
    result.add("isWireframe", s.getValue(t.isWireframe))
    result.add("imagePercent", s.getValue(t.imagePercent))
    result.add("matcapPercent", s.getValue(t.matcapPercent))

    if not t.image.isNil:
        result.add("trailImage", s.getValue(s.getRelativeResourcePath(t.trailImage.filePath())))
    if not t.image.isNil:
        result.add("trailMatcap", s.getValue(s.getRelativeResourcePath(t.trailMatcap.filePath())))

method visitProperties*(t: Trail, p: var PropertyVisitor) =
    # art props
    p.visitProperty("color", t.color)
    p.visitProperty("image", (t.trailImage, t.imagePercent))
    p.visitProperty("matcap", (t.trailMatcap, t.matcapPercent))
    p.visitProperty("height", t.heightOffset)
    p.visitProperty("width", t.trailWidth)
    p.visitProperty("gravity", t.gravity)
    p.visitProperty("rotation", t.directRotation)
    p.visitProperty("depth", t.bDepth)
    p.visitProperty("stretch", t.bStretch)

    # dev props
    p.visitProperty("threshold", t.angleThreshold)
    p.visitProperty("quads", t.quadsToDraw)
    p.visitProperty("wireframe", t.isWireframe)

registerComponent[Trail](proc(): Component =
    result = newTrail()
    )
