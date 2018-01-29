import json, strutils, ospaths, strutils

import nimx / [ image, types, pathutils, assets/asset_manager ]
import rod.quaternion

type JsonDeserializer* = ref object
    node*: JsonNode
    disableAwake*: bool
    compPath*: string # Path relative to bundle root
    getImageForPath*: proc(path: string, offset: var Point): Image

proc newJsonDeserializer*(): JsonDeserializer =
    result.new()

proc setLenX[T](s: var seq[T], sz: int) =
    if s.isNil:
        s = newSeq[T](sz)
    else:
        s.setLen(sz)

proc deserializeImage(b: JsonDeserializer, j: JsonNode): Image

proc get*[T](b: JsonDeserializer, j: JsonNode, v: var T) {.inline.} =
    when T is float | float32 | float64:
        v = j.getFloat()
    elif T is int | int32 | int64 | int16:
        v = T(j.getBiggestInt())
    elif T is string:
        v = if j.kind == JNull: nil else: j.str
    elif T is Rect:
        v = newRect(j[0].getFloat(), j[1].getFloat(), j[2].getFloat(), j[3].getFloat())
    elif T is tuple:
        var i = 0
        for k, vv in fieldPairs(v):
            b.get(j[i], vv)
            inc i

    elif T is Image:
        v = b.deserializeImage(j)

    elif T is array:
        for i in 0 ..< v.len:
            b.get(j[i], v[i])

    elif T is enum:
        v = parseEnum[T](j.str)

    elif T is seq:
        v.setLenX(j.len)
        for i in 0 ..< j.len:
            b.get(j[i], v[i])
    else:
        {.error: "unknown type".}

proc imagePath(b: JsonDeserializer, jimage: JsonNode): string =
    case jimage.kind
    of JString:
        result = b.compPath.parentDir / jimage.str
        normalizePath(result, false)
    of JObject: result = jimage["orig"].str
    else: doAssert(false)

proc deserializeImage(b: JsonDeserializer, j: JsonNode, offset: var Point): Image =
    var path = b.imagePath(j)
    result = b.getImageForPath(path, offset)

proc deserializeImage(b: JsonDeserializer, j: JsonNode): Image =
    var path = b.imagePath(j)
    if path.len == 0:
        return nil

    result = imageWithSize(newSize(1.0, 1.0))
    result.setFilePath(path)

proc visit*[T: tuple](b: JsonDeserializer, v: var T, key: string) =
    let j = b.node{key}
    if not j.isNil:
        b.get(j, v)

proc visit*(b: JsonDeserializer, v: var float32, key: string) =
    let j = b.node{key}
    if not j.isNil:
        v = j.getFloat()

proc visit*(b: JsonDeserializer, v: var int16, key: string) =
    let j = b.node{key}
    if not j.isNil:
        v = int16(j.getInt())

proc visit*(b: JsonDeserializer, v: var int32, key: string) =
    let j = b.node{key}
    if not j.isNil:
        v = int32(j.getInt())

proc visit*[T: enum](b: JsonDeserializer, v: var T, key: string) =
    let j = b.node{key}
    if not j.isNil:
        case j.kind
        of JString:
            v = parseEnum[T](j.str)
        of JInt:
            v = cast[T](j.num)
        else:
            discard

proc visit*(b: JsonDeserializer, v: var bool, key: string) =
    let j = b.node{key}
    if not j.isNil:
        v = j.getBool()

proc visit*(b: JsonDeserializer, v: var Color, key: string) =
    let j = b.node{key}
    if not j.isNil:
        v = newColor(j[0].getFloat(), j[1].getFloat(), j[2].getFloat())
        if j.len > 3:
            v.a = j[3].getFloat()

proc visit*(b: JsonDeserializer, v: var string, key: string) {.inline.} =
    let j = b.node{key}
    if not j.isNil:
        v = j.getStr()

proc visit*(b: JsonDeserializer, v: var Image, key: string) =
    let j = b.node{key}
    if not j.isNil:
        v = b.deserializeImage(j)

proc visit*(b: JsonDeserializer, images: var seq[Image], imagesKey: string, frameOffsets: var seq[Point], frameOffsetsKey: string) =
    let jimages = b.node[imagesKey]
    let sz = jimages.len
    images.setLenX(sz)
    frameOffsets.setLenX(sz)

    for i in 0 ..< sz:
        images[i] = b.deserializeImage(jimages[i], frameOffsets[i])

proc visit*[T](b: JsonDeserializer, v: var seq[T], key: string) =
    let j = b.node{key}
    if not j.isNil:
        let sz = j.len
        v.setLenX(sz)
        for i in 0 ..< sz:
            b.get(j[i], v[i])

proc visit*[I: static[int], T](b: JsonDeserializer, v: var array[I, T], key: string) =
    let j = b.node{key}
    if not j.isNil:
        for i in 0 ..< I:
            b.get(j[i], v[i])

proc visit*(b: JsonDeserializer, v: var Quaternion, key: string) =
    let j = b.node{key}
    if not j.isNil:
        v = newQuaternion(j[0].getFloat(), j[1].getFloat(), j[2].getFloat(), j[3].getFloat())
