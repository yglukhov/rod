import nimx / [ types, image ]
import rod/quaternion
import hashes

type SerializationHashCalculator* = ref object
    hash*: Hash

proc newSerializationHashCalculator*(): SerializationHashCalculator =
    result.new()

type ValueType = enum
    tyFloat32
    tyInt16
    tyInt32
    tyEnum
    tyBool
    tyString
    tyImage
    tySeq
    tyArray
    tyTuple
    tyQuaternion

proc mix(b: SerializationHashCalculator, t: int) =
    b.hash = b.hash !& t

proc mix(b: SerializationHashCalculator, t: ValueType) {.inline.} =
    b.mix(int(t))

proc mix(b: SerializationHashCalculator, k: string) =
    b.hash = b.hash !& hash(k)

proc mixValueType(b: SerializationHashCalculator, T: typedesc) =
    when T is int16:
        b.mix(tyInt16)
    elif T is int32:
        b.mix(tyInt32)
    elif T is float32:
        b.mix(tyFloat32)
    elif T is bool:
        b.mix(tyBool)
    elif T is string:
        b.mix(tyString)
    elif T is Image:
        b.mix(tyImage)
    elif T is seq:
        b.mix(tySeq)
        var v: T
        b.mixValueType(type(v[0]))
    elif T is array:
        b.mix(tyArray)
        var v: T
        b.mixValueType(type(v[0]))
        b.mix(v.len)
    elif T is enum:
        b.mix(tyEnum)
        b.mix(sizeof(T))
    elif T is tuple:
        b.mix(tyTuple)
        var v: T
        for k, vv in fieldPairs(v):
            b.mixValueType(type(vv))

proc mix[T](b: SerializationHashCalculator, v: T, k: string) {.inline.} =
    b.mixValueType(T)
    b.mix(k)

proc visit*(b: SerializationHashCalculator, images: seq[Image], imagesKey: string, frameOffsets: seq[Point], frameOffsetsKey: string) =
    b.mix(tyImage, imagesKey)
    b.mix(tySeq, frameOffsetsKey)
    b.mix(111)

proc visit*(b: SerializationHashCalculator, v: Quaternion, key: string) =
    b.mix(tyQuaternion, key)

proc visit*[T](b: SerializationHashCalculator, v: T, key: string) =
    b.mix(v, key)
