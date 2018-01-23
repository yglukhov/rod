import json
import nimx / [ types, image ]

type JsonSerializer* = ref object
    node*: JsonNode
    resourcePath*: string

proc newJsonSerializer*(): JsonSerializer =
    result.new()
    result.node = newJObject()

proc write[T](data: T): JsonNode =
    when T is Rect:
        result = %[data.x, data.y, data.width, data.height]
    elif T is tuple:
        result = newJArray()
        for k, v in fieldPairs(data):
            result.add(write(v))
    elif T is seq | openarray:
        result = newJArray()
        for v in data:
            result.add(write(v))
    elif T is Image:
        if data.isNil:
            result = %""
        else:
            result = %filePath(data)
    else:
        result = %data

# proc visit*(b: JsonSerializer, r: Rect, key: string) =
#     b.node[key] = write(r)

# proc visit*(b: JsonSerializer, s: Size, key: string) =
#     b.node[key] = write(s)

# proc visit*(b: JsonSerializer, p: Point, key: string) =
#     b.node[key] = write(p)

# proc visit*(b: JsonSerializer, c: Color, key: string) =
#     b.node[key] = write(c)

proc visit*(b: JsonSerializer, v: Image, key: string) =
    if not v.isNil:
        b.node[key] = %filePath(v)

proc visit*[T](b: JsonSerializer, v: seq[T], key: string) =
    if not v.isNil:
        b.node[key] = write(v)

proc visit*[T](b: JsonSerializer, v: T, key: string) =
    b.node[key] = write(v)

proc visit*(b: JsonSerializer, images: seq[Image], imagesKey: string, frameOffsets: seq[Point], frameOffsetsKey: string) =
    let jImages = newJArray()
    let jOffs = newJArray()
    var haveNonZeroOffset = false

    for i in 0 ..< images.len:
        jImages.add(write(images[i]))

    for i in 0 ..< frameOffsets.len:
        if frameOffsets[i] != zeroPoint:
            haveNonZeroOffset = true
        jOffs.add(write(frameOffsets[i]))

    if jImages.len != 0:
        b.node[imagesKey] = jImages
        if haveNonZeroOffset:
            b.node[frameOffsetsKey] = jOffs
