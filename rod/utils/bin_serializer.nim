import tables, streams, json, ospaths, strutils
import nimx / [image, types, pathutils ]
import rod.quaternion
import serialization_helpers

when not defined(js):
    import os

type
    BinSerializer* = ref object
        strTab*: Table[int16, string]
        revStrTab*: Table[string, int16]
        compsTable*: Table[string, int32]
        stream*: (when defined(js): Stream else: StringStream)
        stringEntries*: seq[int32]
        images*: JsonNode
        totalAlignBytes*: int
        assetBundlePath*: string

proc newBinSerializer*(): BinSerializer =
    result.new()

proc align*(b: BinSerializer, sz: int) =
    doAssert(sz <= 4)
    let p = b.stream.getPosition()
    let m = p mod sz
    if m != 0:
        inc(b.totalAlignBytes, sz - m)
        for i in 0 ..< (sz - m):
            b.stream.write(0xff'u8)

proc newString*(b: BinSerializer, s: string): int16 =
    doAssert(not s.endsWith(".json"))
    if s in b.revStrTab:
        result = b.revStrTab[s]
    else:
        result = int16(b.strTab.len)
        b.strTab[result] = s
        b.revStrTab[s] = result


type Serializable =
    array | openarray | tuple | seq | string | int8 | int16 | int32 | bool | enum | uint8 | Image

proc write*(b: BinSerializer, data: float32) =
    b.align(sizeof(data))
    b.stream.write(data)

proc write*[T: Serializable](b: BinSerializer, data: T)

proc writeArrayNoLen*[T](b: BinSerializer, data: openarray[T]) =
    when isPODType(T):
        if data.len != 0:
            b.align(alignsize(type(data[0])))
            b.stream.writeData(unsafeAddr data[0], data.len * sizeof(data[0]))
    else:
        for i in 0 ..< data.len:
            b.write(data[i])

proc getNeighbourImageBundlePath(b: BinSerializer, p2: string):tuple[asset:string, bundle:string]=
    when not defined(js):
        var curDir = getCurrentDir() / "res"
        var path = curDir / b.assetBundlePath / p2

        normalizePath(path, false)
        var dir = path.splitFile().dir

        for p in parentDirs(dir):
            if p == curDir: break

            if fileExists(p / "config.rab"):
                var p3 = path.substr(p.len + 1)
                path = p.subStr(curDir.len + 1)

                return (asset:p3, bundle: path)

    raise newException(Exception, "Neighbour assetbundle not found for " & p2 )

proc write*[T: Serializable](b: BinSerializer, data: T) =
    when T is array:
        b.writeArrayNoLen(data)

    elif T is tuple:
        when isPODType(T):
            b.align(alignsize(type(data[0])))
            b.stream.write(data)
        else:
            for k, v in fieldPairs(data):
                b.write(v)

    elif T is seq or T is openarray:
        b.write(data.len.int16)
        if data.len != 0:
            b.writeArrayNoLen(data)

    elif T is string:
        if data.isNil:
            b.write(int16(-1))
        else:
            b.align(sizeof(int16))
            b.stringEntries.add(b.stream.getPosition().int32)
            let off = b.newString(data)
            b.write(off)

    elif T is int16 | int32:
        b.align(sizeof(data))
        b.stream.write(data)

    elif T is int8 | uint8:
        b.stream.write(data)

    elif T is bool:
        b.stream.write(data.uint8)

    elif T is enum:
        var v = (when ord(high(T)) < high(int8): int8 else: int16)data
        b.write(v)

    elif T is Image:
        if data.isNil:
            b.write(int16(-1))
        else:
            var idx = 0
            let path = filePath(data)

            for j in b.images:
                if j["orig"].str == path:
                    break
                inc idx

            if idx == b.images.len:
                b.write(int16(-2))
                var (asset, bundle) = b.getNeighbourImageBundlePath(path)
                b.write(asset)
                b.write(bundle)
            else:
                b.write(idx.int16)

    elif T is int | int64:
        {.error: "int and int64 not supported " .}
    else:
        {.error: "Unknown type " .}

proc visit*(b: BinSerializer, v: float32) {.inline.} =
    b.write(v)

proc visit*[T: Serializable](b: BinSerializer, v: T) {.inline.} =
    b.write(v)

proc visit*(b: BinSerializer, v: Quaternion) =
    b.write(v.x)
    b.write(v.y)
    b.write(v.z)
    b.write(v.w)

proc visit*(b: BinSerializer, images: seq[Image], frameOffsets: seq[Point]) =
    let sz = images.len
    b.write(sz.int16)
    for i in 0 ..< sz:
        b.write(images[i])
