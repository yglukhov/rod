import times
import tables
import hashes

import nimx.matrixes
import nimx.types
import nimx.context
import nimx.portable_gl

import rod.component
import rod.rod_types
import rod.property_visitor
import rod.material.shader


const BoneVertexShader = """
attribute vec3 aPosition;

uniform mat4 modelViewProjectionMatrix;

void main()
{
    gl_Position = modelViewProjectionMatrix * vec4(aPosition, 1.0);
}
"""
const BoneFragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform vec4 uColor;

void main()
{
    gl_FragColor = uColor;
}
"""

type
    AnimationFrame* = ref object
        time*: float
        matrix*: Matrix4

    AnimationTrack* = ref object
        frames*: seq[AnimationFrame]

    Bone* = ref object
        name*: string
        id*: int
        children*: seq[Bone]
        startMatrix*: Matrix4
        matrix*: Matrix4
        currFrame: AnimationFrame
        invMatrix*: Matrix4
        animTrack*: AnimationTrack
        shader: Shader

    Skeleton* = ref object
        rootBone*: Bone
        startTime*: float
        animDuration*: float
        boneTable*: Table[string, Bone]
        boneIdTable*: Table[int16, Bone]
        nameToIdTable*: Table[string, int16]

proc newAnimationTrack*(): AnimationTrack =
    result = AnimationTrack.new()
    result.frames = newSeq[AnimationFrame]()
    # for i in 0..10:
    #     var frame = AnimationFrame.new()
    #     frame.matrix.loadIdentity()
    #     frame.matrix[13] = 2.Coord * i.Coord
    #     frame.time = 0.5 * i.float
    #     result.frames.add(frame)

#  ------------  Bones --------
proc newBone*(): Bone =
    result = Bone.new()
    result.id = 0
    result.children = newSeq[Bone]()
    result.shader = newShader(BoneVertexShader, BoneFragmentShader, @[(0.GLuint, "aPosition")])
    result.invMatrix.loadIdentity()

    # result.animTrack = newAnimationTrack()

proc debugDraw(b: Bone, parent: Bone, parentMatrix: Matrix4) =
    let gl = currentContext().gl
    var mat: Matrix4
    if not parent.isNil:
        if not b.currFrame.isNil:
            mat = parentMatrix * b.currFrame.matrix
        else:
            mat = parentMatrix * b.startMatrix
    else:
        mat = b.currFrame.matrix

    for k, v in b.children:
        v.debugDraw(b, mat)

    if parent.isNil:
        return

    var p1 = newVector3(0.0, 0.0, 0.0)
    var p2 = newVector3(0.0, 0.0, 0.0)

    parentMatrix.multiply(p1, p1)
    mat.multiply(p2, p2)

    var points: array[6, float32]
    points[0] = p1.x
    points[1] = p1.y
    points[2] = p1.z
    points[3] = p2.x
    points[4] = p2.y
    points[5] = p2.z

    b.shader.bindShader()
    b.shader.setTransformUniform()
    var col = newVector4(0.0, 0.0, 1.0, 1.0)
    b.shader.setUniform("uColor", col)

    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, false, 0, points)

    gl.depthMask(false)
    gl.disable(gl.DEPTH_TEST)
    gl.drawArrays(gl.LINES, 0, 2)

    gl.disable(gl.DEPTH_TEST)
    gl.depthMask(true)

proc update(b: Bone, time: float, mat: Matrix4) =
    # get closest frame
    var newMat: Matrix4
    if not b.animTrack.isNil:
        b.currFrame = b.animTrack.frames[0]
        var ctime = 10000.0
        for k, frame in b.animTrack.frames:
            if abs(time - frame.time) < ctime:
                ctime = abs(time - frame.time)
                b.currFrame = frame

        newMat = mat * b.currFrame.matrix
        b.matrix = newMat * b.invMatrix
        # echo "name          ", $b.name
        # echo "invMatrix     ", $b.invMatrix
        # echo "parent mat    ", $mat
        # echo "cframe.matrix ", $b.currFrame.matrix
        # echo "b.matrix      ", $b.matrix
    else:
        newMat = b.startMatrix
        b.matrix = newMat * b.invMatrix

    for k, v in b.children:
        v.update(time, newMat)

#  ------------  Skeleton --------
proc newSkeleton*(): Skeleton =
    result = Skeleton.new()
    result.rootBone = newBone()
    result.startTime = epochTime()
    result.animDuration = 1.0

    result.bonetable = initTable[string, Bone]()
    result.nameToIdTable = initTable[string, int16]()
    result.boneIdTable = initTable[int16, Bone]()
    # result.boneTable[0] = result.rootBone

var gBoneID = int16(0)
proc prepareRecursive(s: Skeleton, bone: Bone) =
    s.boneTable[bone.name] = bone
    s.nameToIdTable[bone.name] = gBoneID
    s.boneIdTable[gBoneID] = bone
    bone.id = gBoneID
    gBoneID.inc()

    for b in bone.children:
        s.prepareRecursive(b)

proc setBones*(s: Skeleton, bone: Bone) =
    gBoneID = 0.int16
    s.rootBone = bone
    s.prepareRecursive(s.rootBone)

proc getBone*(s: Skeleton, name: string): Bone =
    result = s.boneTable[name]

proc getBone*(s: Skeleton, id: int16): Bone =
    result = s.boneIdTable[id]

proc getBoneIdByName*(s: Skeleton, name: string): int16 =
    result = s.nameToIdTable[name]

proc update*(s: Skeleton) =
    var time = epochTime() - s.startTime
    if time > s.animDuration:
        time = 0
        s.startTime = epochTime()

    var mat: Matrix4
    mat.loadIdentity()
    s.rootBone.update(time, mat)

proc debugDraw*(s: Skeleton) =
    var mat: Matrix4
    mat.loadIdentity()
    s.rootBone.debugDraw(nil, mat)

