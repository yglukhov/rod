import hashes
import nimx / [ types, image ]
import rod.quaternion

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
    tyColor
    tySize
    tyPoint
    tyRect
    tyString
    tyImage
    tySeq
    tyArray
    tyQuaternion

proc mix(b: SerializationHashCalculator, t: int) =
    b.hash = b.hash !& t

proc mix(b: SerializationHashCalculator, t: ValueType) {.inline.} =
    b.mix(int(t))

proc mix(b: SerializationHashCalculator, k: string) =
    b.hash = b.hash !& hash(k)

proc mix(b: SerializationHashCalculator, t: ValueType, k: string) =
    b.mix(t)
    b.mix(k)

proc visit*(b: SerializationHashCalculator, v: float32, key: string) =
    b.mix(tyFloat32, key)

proc visit*(b: SerializationHashCalculator, v: int16, key: string) =
    b.mix(tyInt16, key)

proc visit*(b: SerializationHashCalculator, v: int32, key: string) =
    b.mix(tyInt32, key)

proc visit*[T: enum](b: SerializationHashCalculator, v: T, key: string) =
    b.mix(tyEnum, key)
    b.mix(sizeof(T))

proc visit*(b: SerializationHashCalculator, v: bool, key: string) =
    b.mix(tyBool, key)

proc visit*(b: SerializationHashCalculator, v: Color, key: string) =
    b.mix(tyColor, key)

proc visit*(b: SerializationHashCalculator, v: Size, key: string) =
    b.mix(tySize, key)

proc visit*(b: SerializationHashCalculator, v: Point, key: string) =
    b.mix(tyPoint, key)

proc visit*(b: SerializationHashCalculator, v: Rect, key: string) =
    b.mix(tyRect, key)

proc visit*(b: SerializationHashCalculator, v: string, key: string) {.inline.} =
    b.mix(tyString, key)

proc visit*(b: SerializationHashCalculator, v: Image, key: string) =
    b.mix(tyImage, key)

proc visit*(b: SerializationHashCalculator, images: seq[Image], imagesKey: string, frameOffsets: seq[Point], frameOffsetsKey: string) =
    b.mix(tyImage, imagesKey)
    b.mix(tySeq, frameOffsetsKey)
    b.mix(111)

proc visit*[T](b: SerializationHashCalculator, v: seq[T], key: string) =
    b.mix(tySeq, key)
    b.mix(222)

proc visit*[I: static[int], T](b: SerializationHashCalculator, v: array[I, T], key: string) =
    b.mix(tyArray, key)
    b.mix(I)
    b.mix(333)

proc visit*(b: SerializationHashCalculator, v: Quaternion, key: string) =
    b.mix(tyQuaternion, key)
