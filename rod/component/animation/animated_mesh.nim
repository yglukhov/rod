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
import rod.node

import skeleton

const AMVertexShader = """
attribute vec3 aPosition;
attribute vec3 aNormal;

uniform mat4 modelViewProjectionMatrix;

varying vec3 vNormal;

void main()
{   vNormal = aNormal;
    gl_Position = modelViewProjectionMatrix * vec4(aPosition, 1.0);
}
"""
const AMFragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

varying vec3 vNormal;

void main()
{
    gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
}
"""

type
    VertexWeight = object
        weight: float32
        boneID: int16
        boneName: string

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
        bindShapeMatrix: Matrix4

method init*(am: AnimatedMesh) =
    let gl = currentContext().gl
    am.vertexBuffer = gl.createBuffer()
    am.indexBuffer = gl.createBuffer()
    am.initVertixes = newSeq[VertexPrototype]()

    am.shader = newShader(AMVertexShader, AMFragmentShader, @[(0.GLuint, "aPosition"), (1.GLuint, "aNormal")])
    am.skeleton = newSkeleton()

proc parseVector4(source: string): Vector4 =
  var i = 0
  for it in split(source):
    result[i] = parseFloat(it)
    inc(i)

proc parseMatrix4(source: openarray[float32]): Matrix4 =
    var i = 0
    while i < result.len:
        result[i] = source[i]
        inc i

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

proc getAnimationSourceByName(anim: ColladaAnimation, name: string): ColladaSource =
    for source in anim.sources:
        if source.id.contains(name):
            return source

    for animation in anim.children:
        return animation.getAnimationSourceByName(name)


proc loadBones(bone: var Bone, cn: ColladaNode, colladaScene: ColladaScene) =
    var skinController: ColladaSkinController
    skinController = colladaScene.skinControllers[0]

    bone = newBone()
    bone.name = cn.name
    bone.startMatrix = parseMatrix4(cn.matrix)
    bone.startMatrix.transpose()
    var invMat = skinController.boneInvMatrix(bone.name)
    if not invMat.isNil:
        bone.invMatrix = parseMatrix4( skinController.boneInvMatrix(bone.name) )
        bone.invMatrix.transpose()
        echo "bone name  ", bone.name,  "inverted matrix  ", bone.invMatrix
    else:
        bone.invMatrix = bone.startMatrix.inversed()

    var source: ColladaSource
    for anim in colladaScene.animations:
        let s = anim.getAnimationSourceByName(bone.name & "-Matrix-animation-output-transform")
        if not s.isNil:
            source = s

    if not source.isNil:
        var animTrack = newAnimationTrack()
        var matData = newSeq[float32](16)
        bone.animTrack = animTrack

        for i in 0 ..< int(source.dataFloat.len / 16):
            for j in 0 .. 15:
                matData[j] = source.dataFloat[16*i + j]

            var frame = AnimationFrame.new()
            frame.matrix = parseMatrix4(matData)
            frame.matrix.transpose()
            frame.time = 0.1 * i.float
            animTrack.frames.add(frame)

        # bone.startMatrix = animTrack.frames[0].matrix

    for joint in cn.children:
        var b: Bone
        b.loadBones(joint, colladaScene)
        if not b.isNil:
            bone.children.add(b)

proc setupFromColladaNode*(am: AnimatedMesh, cn: ColladaNode, colladaScene: ColladaScene): Node =
    result = am.node
    var childColladaMaterial: ColladaMaterial
    var childColladaGeometry: ColladaGeometry

    var bones: Bone
    for joint in cn.children:
        if joint.kind == NodeKind.Joint:
            bones.loadBones(joint, colladaScene)

    # echo "bones ", repr bones
    am.skeleton.setBones(bones)

    # am.node.translation.x = 5
    if cn.matrix != nil:
        let modelMatrix = parseMatrix4(cn.matrix)

        var translation: Vector3
        var scale: Vector3
        var rotation: Vector4

        if modelMatrix.tryGetTranslationFromModel(translation) and modelMatrix.tryGetScaleRotationFromModel(scale, rotation):
            am.node.scale = scale
            am.node.translation = translation
            am.node.rotation = newQuaternion(rotation[0], rotation[1], rotation[2], rotation[3])
    else:
        if cn.scale != nil:
            let scale = parseArray3(cn.scale)
            am.node.scale = newVector3(scale[0], scale[1], scale[2])

        if cn.translation != nil:
            let translation = parseArray3(cn.translation)
            am.node.translation = newVector3(translation[0], translation[1], translation[2])

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

        am.node.rotation = finalRotation

    # if cn.geometry != nil:
    for geom in colladaScene.childNodesGeometry:
        if cn.geometry.contains(geom.name) or geom.name.contains(cn.geometry):
            childColladaGeometry = geom

    var vertexProt: VertexPrototype
    var indexData = newSeq[GLushort]()

    var skinController: ColladaSkinController
    skinController = colladaScene.skinControllers[0]

    if not skinController.bindShapeMatrix.isNil:
        am.bindShapeMatrix = parseMatrix4(skinController.bindShapeMatrix)
        am.bindShapeMatrix.transpose()

        echo "am.bindShapeMatrix  ", am.bindShapeMatrix

    # vertices
    for v in 0 ..< int(childColladaGeometry.vertices.len / 3):
        vertexProt.position = newVector3( childColladaGeometry.vertices[3*v + 0], childColladaGeometry.vertices[3*v + 1], childColladaGeometry.vertices[3*v + 2] )
        vertexProt.normal = newVector3( childColladaGeometry.normals[3*v + 0], childColladaGeometry.normals[3*v + 1], childColladaGeometry.normals[3*v + 2] )
        vertexProt.weights = newSeq[VertexWeight]()

        for j in 0 ..< skinController.weightsPerVertex:
            var w: VertexWeight
            var bData: tuple[bone: string, weight: float32]
            bData = skinController.boneAndWeightForVertex(v, j)
            echo "v  ", v, " j  ", j,  "  bdata ", repr bData
            w.weight = bData.weight
            w.boneID = 0
            w.boneName = bData.bone
            vertexProt.weights.add( w )

        am.initVertixes.add(vertexProt)

    for i in 0 ..< int(childColladaGeometry.triangles.len / 3):
        let ind = childColladaGeometry.triangles[3 * i + 0]
        indexData.add(ind.GLushort)

    am.numberOfIndices = int16(childColladaGeometry.triangles.len / 3)

    let gl = currentContext().gl
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, am.indexBuffer)
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

method draw*(am: AnimatedMesh) =
    let gl = currentContext().gl

    am.skeleton.update()

    let offset = int(sizeof(VertexPrototype) / sizeof(float32))
    let vSize = am.initVertixes.len * offset
    var vertData = newSeq[GLfloat](vSize)

    for i in 0 ..< am.initVertixes.len:
        var pos: Vector3
        # echo "vertex ", i, "  w len ", am.initVertixes[i].weights.len
        for j in 0 ..< am.initVertixes[i].weights.len:
            if not am.initVertixes[i].weights[j].boneName.isNil:
                let bone = am.skeleton.getBone( am.initVertixes[i].weights[j].boneName )
                let resMatrix = bone.matrix * bone.invMatrix * am.bindShapeMatrix
                pos += resMatrix.transformPoint( am.initVertixes[i].position ) * am.initVertixes[i].weights[j].weight

            # echo "vertID ", i, " boneName  ", am.initVertixes[i].weights[j].boneName, " weight  ", am.initVertixes[i].weights[j].weight, "  vert pos = ", pos

        vertData[offset * i + 0] = pos.x
        vertData[offset * i + 1] = pos.y
        vertData[offset * i + 2] = pos.z

    # echo "offset  ", offset
    # echo "am.initVertixes  ", repr am.initVertixes
    # echo "vertData  ", repr vertData
    gl.bindBuffer(gl.ARRAY_BUFFER, am.vertexBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, vertData, gl.STATIC_DRAW)

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, am.indexBuffer)

    let stride = int(sizeof(VertexPrototype))
    gl.enableVertexAttribArray(0)
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, stride.GLsizei , 0)

    gl.enableVertexAttribArray(1)
    gl.vertexAttribPointer(1, 3, gl.FLOAT, false, stride.GLsizei , 3 * sizeof(GLfloat))

    am.shader.bindShader()
    am.shader.setTransformUniform()

    gl.drawElements(gl.TRIANGLES, am.numberOfIndices, gl.UNSIGNED_SHORT)

    #TODO to default settings
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
    gl.disable(gl.DEPTH_TEST)
    gl.activeTexture(gl.TEXTURE0)
    gl.enable(gl.BLEND)

    am.skeleton.debugDraw()


registerComponent[AnimatedMesh]()
