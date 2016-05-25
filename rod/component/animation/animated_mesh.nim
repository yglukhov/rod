import strutils
import algorithm

import nimasset.collada

import nimx.matrixes
import nimx.types
import nimx.context
import nimx.portable_gl

import rod.component
import rod.rod_types
import rod.property_visitor
import rod.dae_animation
import rod.quaternion
import rod.material.shader

import skeleton

const AMVertexShader = """
attribute vec3 aPosition;

uniform mat4 modelViewProjectionMatrix;

void main()
{
    gl_Position = modelViewProjectionMatrix * vec4(aPosition, 1.0);
}
"""
const AMFragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

void main()
{
    gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
}
"""

type
    VertexWeight = object
        weight: float32
        boneID: int16

    VertexPrototype = object
        position*: Vector3
        texcoords*: Vector2
        normal*: Vector3
        weights*: seq[VertexWeight]

    AnimatedMesh* = ref object of Component
        skeleton*: Skeleton

        initVertixes: seq[VertexPrototype]
        vertexBuffer: BufferRef
        indexBuffer: BufferRef
        numberOfIndices: int32
        shader: Shader

method init*(am: AnimatedMesh) =
    let gl = currentContext().gl
    am.vertexBuffer = gl.createBuffer()
    am.indexBuffer = gl.createBuffer()
    am.initVertixes = newSeq[VertexPrototype]()

    am.shader = newShader(AMVertexShader, AMFragmentShader, @[(0.GLuint, "aPosition")])
    am.skeleton = newSkeleton()

proc parseVector4(source: string): Vector4 =
  var i = 0
  for it in split(source):
    result[i] = parseFloat(it)
    inc(i)

proc parseMatrix4(source: string): Matrix4 =
    var nodeMarix: array[16, float32]
    var i = 0
    for it in split(source):
        nodeMarix[i] = parseFloat(it)
        inc(i)
    result = nodeMarix

proc parseArray4(source: string): array[0 .. 3, float32] =
    var i = 0
    for it in split(source):
        result[i] = parseFloat(it)
        inc(i)

proc parseArray3(source: string): array[0 .. 2, float32] =
    var i = 0
    for it in split(source):
        result[i] = parseFloat(it)
        inc(i)

proc setupFromColladaNode*(am: AnimatedMesh, cn: ColladaNode, colladaScene: ColladaScene): Node =
    result = am.node
    var childColladaMaterial: ColladaMaterial
    var childColladaGeometry: ColladaGeometry

    if cn.matrix != nil:
        let modelMatrix = parseMatrix4(cn.matrix)

        var translation: Vector3
        var scale: Vector3
        var rotation: Vector4

        if modelMatrix.tryGetTranslationFromModel(translation) and modelMatrix.tryGetScaleRotationFromModel(scale, rotation):
            result.scale = scale
            result.translation = translation
            result.rotation = newQuaternion(rotation[0], rotation[1], rotation[2], rotation[3])
    else:
        if cn.scale != nil:
            let scale = parseArray3(cn.scale)
            result.scale = newVector3(scale[0], scale[1], scale[2])

        if cn.translation != nil:
            let translation = parseArray3(cn.translation)
            result.translation = newVector3(translation[0], translation[1], translation[2])

        var finalRotation = newQuaternion(0, 0, 0, 1)

        if cn.rotationX != nil:
            let rotationX = parseArray4(cn.rotationX)
            finalRotation *= aroundX(rotationX[3])
        if cn.rotationY != nil:
            let rotationY = parseArray4(cn.rotationY)
            finalRotation *= aroundY(rotationY[3])
        if cn.rotationZ != nil:
            let rotationZ = parseArray4(cn.rotationZ)
            finalRotation *= aroundZ(rotationZ[3])

        result.rotation = finalRotation

    # if cn.geometry != nil:
    for geom in colladaScene.childNodesGeometry:
        if cn.geometry.contains(geom.name) or geom.name.contains(cn.geometry):
            childColladaGeometry = geom

    var vertexProt: VertexPrototype
    var indexData = newSeq[GLushort]()

    for v in 0 ..< int(childColladaGeometry.vertices.len / 3):
        vertexProt.position = newVector3( childColladaGeometry.vertices[3*v + 0], childColladaGeometry.vertices[3*v + 1], childColladaGeometry.vertices[3*v + 2] )
        var w: VertexWeight
        w.weight = 0.0
        w.boneID = 0
        vertexProt.weights = newSeq[VertexWeight]()
        vertexProt.weights.add( w )
        am.initVertixes.add(vertexProt)

    var i = 0
    while i < int(childColladaGeometry.triangles.len / 3):
        indexData.add( childColladaGeometry.triangles[3 * i + 0].GLushort )
        i += 1

    am.numberOfIndices = int16(childColladaGeometry.triangles.len / 3)

    echo "vertices ", repr am.initVertixes
    echo "indices ", repr indexData
    echo "ind count ", repr am.numberOfIndices

    let gl = currentContext().gl
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, am.indexBuffer)
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

method draw*(am: AnimatedMesh) =
    let gl = currentContext().gl

    let offset = int(sizeof(VertexPrototype) / sizeof(float32))
    let vSize = am.initVertixes.len * offset
    var vertData = newSeq[GLfloat](vSize)

    for i in 0 ..< am.initVertixes.len:
        vertData[offset * i + 0] = am.initVertixes[i].position.x
        vertData[offset * i + 1] = am.initVertixes[i].position.y
        vertData[offset * i + 2] = am.initVertixes[i].position.z

    echo "offset  ", offset
    echo "am.initVertixes  ", repr am.initVertixes
    echo "vertData  ", repr vertData
    gl.bindBuffer(gl.ARRAY_BUFFER, am.vertexBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, vertData, gl.STATIC_DRAW)

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, am.indexBuffer)

    let stride = int(sizeof(VertexPrototype))
    gl.enableVertexAttribArray(0)
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, stride.GLsizei , 0)

    am.shader.bindShader()
    am.shader.setTransformUniform()

    gl.drawElements(gl.TRIANGLES, am.numberOfIndices, gl.UNSIGNED_SHORT)

    #TODO to default settings
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
    gl.disable(gl.DEPTH_TEST)
    gl.activeTexture(gl.TEXTURE0)
    gl.enable(gl.BLEND)


registerComponent[AnimatedMesh]()
