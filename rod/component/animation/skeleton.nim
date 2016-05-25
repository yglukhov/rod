import times
import tables
import hashes

import nimx.matrixes
import nimx.types
import nimx.context

import rod.component
import rod.rod_types
import rod.property_visitor

type
    AnimationFrame* = ref object
        time*: float
        matrix*: Matrix4

    AnimationTrack* = ref object
        frames*: seq[AnimationFrame]

    Bone* = ref object
        id*: int
        children*: seq[Bone]
        matrix*: Matrix4
        animTrack*: AnimationTrack

    Skeleton* = ref object
        rootBone*: Bone
        startTime*: float
        animDuration*: float
        boneTable*: Table[int16, Bone]

proc newAnimationTrack(): AnimationTrack =
    result = AnimationTrack.new()
    result.frames = newSeq[AnimationFrame]()
    for i in 0..10:
        var frame = AnimationFrame.new()
        frame.matrix.loadIdentity()
        frame.matrix[12] = 5.Coord * i.Coord
        frame.time = 0.5 * i.float
        result.frames.add(frame)

#  ------------  Bones --------
proc newBone(): Bone =
    result = Bone.new()
    result.id = 0
    result.children = newSeq[Bone]()
    result.animTrack = newAnimationTrack()

proc update(b: Bone, time: float) =
    # get closest frame
    var cframe = b.animTrack.frames[0]
    var ctime = 10000.0
    for k, frame in b.animTrack.frames:
        if frame.time < ctime:
            ctime = frame.time
            cframe = frame

    b.matrix = cframe.matrix

    for k, v in b.children:
        v.update(time)

#  ------------  Skeleton --------
proc newSkeleton*(): Skeleton =
    result = Skeleton.new()
    result.rootBone = newBone()
    result.startTime = epochTime()

    result.bonetable = initTable[int16, Bone]()
    result.boneTable[0] = result.rootBone

proc getBone*(s: Skeleton, id: int16): Bone =
    result = s.boneTable[id]

proc update*(s: Skeleton) =
    var time = epochTime() - s.startTime
    if time > s.animDuration:
        time = 0
        s.startTime = epochTime()

    s.rootBone.update(time)
