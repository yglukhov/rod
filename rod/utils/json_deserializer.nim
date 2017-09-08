import json, strutils

import nimx / [ image, types ]

type JsonDeserializer* = ref object
    node*: JsonNode
    images*: JsonNode
    disableAwake*: bool
    
proc newJsonDeserializer*(): JsonDeserializer =
    result.new()

proc setLenX[T](s: var seq[T], sz: int) =
    if s.isNil:
        s = newSeq[T](sz)
    else:
        s.setLen(sz)

proc get[T](j: JsonNode, v: var T) {.inline.} =
    when T is float | float32 | float64:
        v = j.getFNum()
    elif T is int | int32 | int64 | int16:
        v = T(j.num)
    elif T is string:
        v = j.str
    elif T is Point:
        v.x = j[0].getFNum()
        v.y = j[1].getFNum()
    elif T is Size:
        v.width = j[0].getFNum()
        v.height = j[1].getFNum()
    elif T is array:
        for i in 0 ..< v.len:
            get(j[i], v[i])
    else:
        {.error: "unknown type".}

proc imageDesc(b: JsonDeserializer, path: string): JsonNode =
    for j in b.images:
        if j["orig"].str == path:
            return j

    assert(false, "Image desc not found: " & path)
            
proc imagePath(jimage: JsonNode): string =
    case jimage.kind
    of JString: result = jimage.str
    of JObject: result = jimage["orig"].str
    else: assert(false)

proc deserializeImage(b: JsonDeserializer, j: JsonNode, offset: var Point): Image =
    let path = j.imagePath
    let desc = b.imageDesc(path)
    let sz = desc["size"]
    let joff = desc{"off"}
    if not joff.isNil:
        get(joff, offset)
    result = imageWithSize(newSize(sz[0].getFNum(), sz[1].getFNum()))
    result.setFilePath(path)

proc visit*(b: JsonDeserializer, v: var float32, key: string) =
    let j = b.node{key}
    if not j.isNil:
        v = j.getFNum()

proc visit*(b: JsonDeserializer, v: var int16, key: string) =
    let j = b.node{key}
    if not j.isNil:
        v = int16(j.getNum())

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
        v = j.getBVal()

proc visit*(b: JsonDeserializer, v: var Color, key: string) =
    let j = b.node{key}
    if not j.isNil:
        v = newColor(j[0].getFNum(), j[1].getFNum(), j[2].getFNum())
        if j.len > 3:
            v.a = j[3].getFNum()

proc visit*(b: JsonDeserializer, v: var Size, key: string) =
    let j = b.node{key}
    if not j.isNil:
        get(j, v)

proc visit*(b: JsonDeserializer, v: var Point, key: string) =
    let j = b.node{key}
    if not j.isNil:
        get(j, v)

proc visit*(b: JsonDeserializer, v: var Rect, key: string) =
    let j = b.node{key}
    if not j.isNil:
        v = newRect(j[0].getFNum(), j[1].getFNum(), j[2].getFNum(), j[3].getFNum())

proc visit*(b: JsonDeserializer, v: var string, key: string) {.inline.} =
    let j = b.node{key}
    if not j.isNil:
        v = j.getStr()

proc visit*(b: JsonDeserializer, v: var Image, key: string) =
    let j = b.node{key}
    if not j.isNil:
        var p: Point
        v = b.deserializeImage(j, p)

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
            get(j[i], v[i])

proc visit*[I: static[int], T](b: JsonDeserializer, v: var array[I, T], key: string) =
    let j = b.node{key}
    if not j.isNil:
        for i in 0 ..< I:
            get(j[i], v[i])
