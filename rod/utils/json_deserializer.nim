import nimx / [ image, types, pathutils, assets/asset_manager ]
import rod/quaternion
import json, strutils, os, strutils


type JsonDeserializer* = ref object
    node*: JsonNode
    disableAwake*: bool
    compPath*: string # Path relative to bundle root
    getImageForPath*: proc(path: string, offset: var Point): Image

proc newJsonDeserializer*(): JsonDeserializer =
    result.new()

proc deserializeImage(b: JsonDeserializer, j: JsonNode): Image

proc get*[T](b: JsonDeserializer, j: JsonNode, v: var T) =
    when T is float | float32 | float64:
        v = j.getFloat()
    elif T is int | int32 | int64 | int16 | uint64 | uint32 | uint16:
        v = T(j.getBiggestInt())
    elif T is string:
        v = j.getStr()
    elif T is bool:
        v = j.getBool()
    elif T is Rect:
        v = newRect(j[0].getFloat(), j[1].getFloat(), j[2].getFloat(), j[3].getFloat())
    elif T is Quaternion:
        v = newQuaternion(j[0].getFloat(), j[1].getFloat(), j[2].getFloat(), j[3].getFloat())
    elif T is Color:
        v = newColor(j[0].getFloat(), j[1].getFloat(), j[2].getFloat())
        if j.len > 3:
            v.a = j[3].getFloat()
    elif T is tuple:
        var i = 0
        for k, vv in fieldPairs(v):
            b.get(j[i], vv)
            inc i
    elif T is object:
        for k, vv in fieldPairs(v):
            b.get(j[k], vv)
    elif T is Image:
        v = b.deserializeImage(j)

    elif T is array:
        for i in 0 ..< v.len:
            b.get(j[i], v[i])

    elif T is enum:
        case j.kind
        of JString:
            v = parseEnum[T](j.str)
        of JInt:
            v = cast[T](j.num)
        else:
            discard

    elif T is seq:
        let sz = j.len
        v.setLen(sz)
        for i in 0 ..< sz:
            b.get(j[i], v[i])
    else:
        {.error: "unknown type " & $T .}

proc imagePath(b: JsonDeserializer, jimage: JsonNode): string =
    case jimage.kind
    of JString:
        if jimage.str.len == 0:
            result = ""
        else:
            result = b.compPath.parentDirEx & "/" & jimage.str
            normalizePath(result, false)
    of JObject:
        result = jimage["orig"].getStr()
    else: doAssert(false)

proc deserializeImage(b: JsonDeserializer, j: JsonNode, offset: var Point): Image =
    let path = b.imagePath(j)
    b.getImageForPath(path, offset)

proc deserializeImage(b: JsonDeserializer, j: JsonNode): Image =
    var path = b.imagePath(j)
    if path.len == 0:
        return nil

    when not defined(rodplugin):
        var p = newPoint(0,0)
        result = b.getImageForPath(path, p)

    if result.isNil:
        result = imageWithSize(newSize(1.0, 1.0))
        result.setFilePath(path)

proc visit*[T](b: JsonDeserializer, v: var T, key: string) =
    let j = b.node{key}
    if not j.isNil:
        b.get(j, v)

proc visit*[T](b: JsonDeserializer, v: var T, key: string, default: T) =
    let j = b.node{key}
    if not j.isNil:
        b.get(j, v)
    else:
        v = default

proc visit*(b: JsonDeserializer, images: var seq[Image], imagesKey: string, frameOffsets: var seq[Point], frameOffsetsKey: string) =
    let jimages = b.node[imagesKey]
    let sz = jimages.len
    images.setLen(sz)
    frameOffsets.setLen(sz)

    for i in 0 ..< sz:
        images[i] = b.deserializeImage(jimages[i], frameOffsets[i])
