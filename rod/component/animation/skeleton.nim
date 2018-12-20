import times
import tables
import hashes
import json

import nimx.matrixes
import nimx.types
import nimx.context
import nimx.portable_gl
import nimx.property_visitor

import rod.component
import rod.rod_types
import rod.node
import rod.material.shader
import rod.tools.serializer


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
    AnimationType* = enum
        Forward
        Reverse
        PingPong

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

        atachedNodes*: seq[Node]
        shader: Shader

    Skeleton* = ref object
        rootBone*: Bone
        startTime*: float
        animDuration*: float
        boneTable*: Table[string, Bone]
        boneIdTable*: Table[int16, Bone]
        nameToIdTable*: Table[string, int16]

        isPlayed*: bool
        isPaused: bool
        currAnimTime: float
        isLooped*: bool
        animType*: AnimationType

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
    result.atachedNodes = newSeq[Node]()

proc debugDraw(b: Bone, parent: Bone, parentMatrix: Matrix4) =
    let c = currentContext()
    let gl = c.gl
    var mat: Matrix4
    if not parent.isNil:
        if not b.currFrame.isNil:
            mat = parentMatrix * b.currFrame.matrix
        else:
            mat = parentMatrix * b.startMatrix
    else:
        mat = if not b.currFrame.isNil: b.currFrame.matrix else: b.matrix

    for k, v in b.children:
        v.debugDraw(b, mat)

    if parent.isNil:
        return

    var p1 = newVector3(0.0, 0.0, 0.0)
    var p2 = newVector3(0.0, 0.0, 0.0)

    parentMatrix.multiply(p1, p1)
    mat.multiply(p2, p2)

    c.vertexes[0] = p1.x
    c.vertexes[1] = p1.y
    c.vertexes[2] = p1.z
    c.vertexes[3] = p2.x
    c.vertexes[4] = p2.y
    c.vertexes[5] = p2.z

    b.shader.bindShader()
    b.shader.setTransformUniform()
    var col = newVector4(0.0, 0.0, 1.0, 1.0)
    b.shader.setUniform("uColor", col)

    gl.enableVertexAttribArray(0);
    c.bindVertexData(6)
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0)

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

    for node in b.atachedNodes:
        node.setBoneMatrix(newMat)

    for k, v in b.children:
        v.update(time, newMat)

#  ------------  Skeleton --------
proc newSkeleton*(): Skeleton =
    result = Skeleton.new()
    result.rootBone = newBone()
    result.startTime = epochTime()
    result.animDuration = 1.0

    result.animType = AnimationType.Forward
    result.currAnimTime = 0.0
    result.isPlayed = true

    result.bonetable = initTable[string, Bone]()
    result.nameToIdTable = initTable[string, int16]()
    result.boneIdTable = initTable[int16, Bone]()
    # result.boneTable[0] = result.rootBone

var gBoneID = int16(0)
proc prepareRecursive(s: Skeleton, bone: Bone) =
    s.boneTable[bone.name] = bone
    s.nameToIdTable[bone.name] = bone.id.int16
    s.boneIdTable[bone.id.int16] = bone

    for b in bone.children:
        s.prepareRecursive(b)

proc setBones*(s: Skeleton, bone: Bone) =
    gBoneID = 0.int16
    s.rootBone = bone
    s.prepareRecursive(s.rootBone)

    var mat: Matrix4
    mat.loadIdentity()
    s.rootBone.update(0.0, mat)

proc getBone*(s: Skeleton, name: string): Bone =
    result = s.boneTable[name]

proc getBone*(s: Skeleton, id: int16): Bone =
    result = s.boneIdTable[id]

proc getBoneIdByName*(s: Skeleton, name: string): int16 =
    result = s.nameToIdTable[name]

proc play(s: Skeleton) =
    if s.isPaused:
        s.startTime = epochTime() - s.currAnimTime
    else:
        s.currAnimTime = 0.0
        s.startTime = epochTime()

    s.isPlayed = true
    s.isPaused = false

proc stop(s: Skeleton) =
    s.isPlayed = false

proc pause(s: Skeleton) =
    s.isPaused = true

proc update*(s: Skeleton) =
    if s.isPlayed == false or s.isPaused == true:
        return

    var time = epochTime() - s.startTime
    if s.isLooped == false:
        if s.animType == AnimationType.Forward:
            s.currAnimTime = time
            if s.currAnimTime > s.animDuration:
                s.stop()

        if s.animType == AnimationType.Reverse:
            s.currAnimTime = s.animDuration - time
            if s.currAnimTime < 0.0:
                s.stop()

    elif s.isLooped:
        if s.animType == AnimationType.Forward:
            s.currAnimTime = time
            if s.currAnimTime > s.animDuration:
                s.startTime = epochTime()

        if s.animType == AnimationType.Reverse:
            s.currAnimTime = s.animDuration - time
            if s.currAnimTime < 0.0:
                s.startTime = epochTime()

    var mat: Matrix4
    mat.loadIdentity()
    s.rootBone.update(s.currAnimTime, mat)

proc debugDraw*(s: Skeleton) =
    var mat: Matrix4
    mat.loadIdentity()
    s.rootBone.debugDraw(nil, mat)


proc deserialize*(track: var AnimationTrack, j: JsonNode, s: Serializer) =
    for i in 0 ..< j.len:
        var frame = AnimationFrame.new()
        s.deserializeValue(j[i], "time", frame.time)
        s.deserializeValue(j[i], "matrix", frame.matrix)
        track.frames.add(frame)

proc serialize*(track: AnimationTrack, s: Serializer): JsonNode =
    result = newJArray()
    for frame in track.frames:
        var frameNode = newJObject()
        frameNode.add("time", s.getValue(frame.time))
        frameNode.add("matrix", s.getValue(frame.matrix))
        result.add(frameNode)

proc deserialize*(b: var Bone, j: JsonNode, s: Serializer) =
    s.deserializeValue(j, "name", b.name)
    s.deserializeValue(j, "id", b.id)
    s.deserializeValue(j, "startMatrix", b.startMatrix)
    s.deserializeValue(j, "invMatrix", b.invMatrix)

    var v = j{"animTrack"}
    if not v.isNil:
        b.animTrack = newAnimationTrack()
        b.animTrack.deserialize(v, s)

    v = j{"children"}
    if not v.isNil:
        for i in 0 ..< v.len:
            var nBone = newBone()
            nBone.deserialize(v[i], s)
            b.children.add(nBone)

proc serialize*(bone: Bone, s: Serializer): JsonNode =
    result = newJObject()
    result.add("name", s.getValue(bone.name))
    result.add("id", s.getValue(bone.id))
    result.add("startMatrix", s.getValue(bone.startMatrix))
    result.add("invMatrix", s.getValue(bone.invMatrix))
    result.add("animTrack", bone.animTrack.serialize(s))

    var childrenNode = newJArray()
    result.add("children", childrenNode)
    for child in bone.children:
        childrenNode.add( child.serialize(s) )

proc deserialize*(s: var Skeleton, j: JsonNode, serializer: Serializer) =
    if j.isNil:
        return

    serializer.deserializeValue(j, "animDuration", s.animDuration)
    serializer.deserializeValue(j, "isPlayed", s.isPlayed)
    serializer.deserializeValue(j, "isLooped", s.isLooped)
    serializer.deserializeValue(j, "animType", s.animType)

    var jNode = j{"rootBone"}
    if not jNode.isNil:
        s.rootBone = newBone()
        s.rootBone.deserialize(jNode, serializer)

        s.prepareRecursive(s.rootBone)

proc serialize*(skeleton: Skeleton, s: Serializer): JsonNode =
    result = newJObject()
    result.add("animDuration", s.getValue(skeleton.animDuration))
    result.add("isPlayed", s.getValue(skeleton.isPlayed))
    result.add("isLooped", s.getValue(skeleton.isLooped))
    result.add("animType", s.getValue(skeleton.animType))
    result.add("rootBone", skeleton.rootBone.serialize(s))
