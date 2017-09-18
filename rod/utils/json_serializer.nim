import json
import nimx / [ types, image ]

type JsonSerializer* = ref object
    node*: JsonNode

proc visit*[T](b: JsonSerializer, v: T, key: string) =
    b.node[key] = %v

proc visit*(b: JsonSerializer, v: Rect, key: string) =
    b.node[key] = %[v.x, v.y, v.width, v.height]

proc visit*(b: JsonSerializer, v: Image, key: string) =
    doAssert(false)

proc visit*(b: JsonSerializer, images: seq[Image], imagesKey: string, frameOffsets: seq[Point], frameOffsetsKey: string) =
    doAssert(false)
