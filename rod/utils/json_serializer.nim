import json, os, strutils
import nimx / [ types, image, pathutils ]

type JsonSerializer* = ref object
    node*: JsonNode
    url*: string

proc newJsonSerializer*(): JsonSerializer =
    result.new()
    result.node = newJObject()

proc getRelativeResourcePath(b: JsonSerializer, path: string): string =
    var resourcePath = path
    when not defined(js) and not defined(android) and not defined(ios):
        resourcePath = urlParentDir(b.url)
        resourcePath.removePrefix("file://")

    var fixedPath = path
    fixedPath.removePrefix("file://")
    result = relativePathToPath(resourcePath, fixedPath)
    echo "save path = ", resourcePath, "  relative = ", result, " url ", b.url

proc writePath(b: JsonSerializer, data: string): JsonNode =
    %b.getRelativeResourcePath(data)

proc write[T](b: JsonSerializer, data: T): JsonNode =
    when T is Rect:
        result = %[data.x, data.y, data.width, data.height]
    elif T is tuple:
        result = newJArray()
        for k, v in fieldPairs(data):
            result.add(b.write(v))
    elif T is seq | openarray:
        result = newJArray()
        for v in data:
            result.add(b.write(v))
    elif T is Image:
        if data.isNil:
            result = %""
        else:
            result = b.writePath(filePath(data))
    else:
        result = %data

proc visit*(b: JsonSerializer, v: Image, key: string) =
    if not v.isNil:
        b.node[key] = b.writePath(filePath(v))

proc visit*[T](b: JsonSerializer, v: seq[T], key: string) =
    if v.len > 0:
        b.node[key] = b.write(v)

proc visit*[T](b: JsonSerializer, v: T, key: string) =
    b.node[key] = b.write(v)

proc visit*(b: JsonSerializer, images: seq[Image], imagesKey: string, frameOffsets: seq[Point], frameOffsetsKey: string) =
    let jImages = newJArray()
    let jOffs = newJArray()
    var haveNonZeroOffset = false

    for i in 0 ..< images.len:
        jImages.add(b.write(images[i]))

    for i in 0 ..< frameOffsets.len:
        if frameOffsets[i] != zeroPoint:
            haveNonZeroOffset = true
        jOffs.add(b.write(frameOffsets[i]))

    if jImages.len != 0:
        b.node[imagesKey] = jImages
        if haveNonZeroOffset:
            b.node[frameOffsetsKey] = jOffs
