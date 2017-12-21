import streams, tables, json, strutils, ospaths

import nimx / [ image, types, assets/asset_manager ]
import rod / utils / [ property_desc, serialization_helpers ]
import rod.quaternion
type
    BinDeserializer* = ref object
        strtab: seq[string]
        stream*: Stream
        compsTable: Table[string, int32]
        basePath*: string
        images*: JsonNode
        curCompPath*: string
        disableAwake*: bool

    UncheckedArr {.unchecked.} [T] = array[0, T]

    BufferView*[T] = object
        mData*: ptr UncheckedArr[T]
        len*: int

template `[]`*[T](v: BufferView[T], idx: int): T =
    assert(idx < v.len)
    v.mData[idx]

proc align(b: BinDeserializer, sz: int) {.inline.} =
    let p = b.stream.getPosition()
    let m = p mod sz
    assert(sz <= 4)
    if m != 0:
        b.stream.setPosition(p + sz - m)

proc readInt16*(b: BinDeserializer): int16 {.inline.} =
    b.align(sizeof(result))
    b.stream.readInt16()

proc readInt32*(b: BinDeserializer): int32 {.inline.} =
    b.align(sizeof(result))
    b.stream.readInt32()

proc readFloat32*(b: BinDeserializer): float32 {.inline.} =
    b.align(sizeof(result))
    b.stream.readFloat32()

proc getStr*(b: BinDeserializer, id: int16): string =
    if id != -1: result = b.strtab[id]

proc readStr*(b: BinDeserializer): string {.inline.} =
    let i = b.readInt16()
    if i != -1:
        result = b.getStr(i)

proc readStrNoLen*(b: BinDeserializer, str: var string) {.inline.} =
    if str.len != 0:
        discard b.stream.readData(addr str[0], str.len)

proc getPosition*(b: BinDeserializer): int {.inline.} = b.stream.getPosition()
proc setPosition*(b: BinDeserializer, p: int) {.inline.} = b.stream.setPosition(p)

proc getBuffer*(b: BinDeserializer, T: typedesc, len: int): BufferView[T] =
    when T is array:
        var dummy: T
        b.align(sizeof(dummy[0]))
    when T is tuple:
        var dummy: T
        b.align(sizeof(dummy[0]))
    else:
        b.align(alignsize(T))
    when defined(js):
        raise newException(Exception, "Not implemented")
    else:
        let s = StringStream(b.stream)
        let offset = b.getPosition()
        assert(s.data.len > offset + len)
        result.mData = cast[ptr UncheckedArr[T]](cast[pointer](addr s.data[offset]))
        result.len = len
        b.setPosition(offset + len * sizeof(T))

proc init(b: BinDeserializer) =
    var strtabLen = b.readInt16()
    # echo "strtabLen: ", strtabLen
    b.strtab = newSeq[string](strtabLen)
    for i in 0 ..< strtabLen:
        let strLen = b.readInt16()
        # echo "len:", strLen
        b.strtab[i] = b.stream.readStr(strLen)
        # echo "str ", i, ": ", b.strtab[i]
        shallow(b.strtab[i])

    b.compsTable = initTable[string, int32]()
    let compsLen = b.readInt16()
    if compsLen > 0:
        let offsets = b.getBuffer(int32, compsLen)
        let names = b.getBuffer(int16, compsLen)

        # echo "numComps: ", compsLen
        b.align(4)
        let compsStartOffset = b.stream.getPosition().int32# + compsLen * 8

        for i in 0 ..< compsLen:
            let s = b.strtab[names[i]]
            let off = offsets[i]
            b.compsTable[s] = off + compsStartOffset
        # echo "START OFF: ", compsStartOffset
        # for k, v in b.compsTable.mpairs:
        #     v = compsStartOffset + v


proc newBinDeserializer*(s: Stream): BinDeserializer =
    result.new()
    result.stream = s
    result.init()

proc offsetToComposition(b: BinDeserializer, name: string): int32 =
    result = b.compsTable.getOrDefault(name)
    if result == 0:
        if name.endsWith(".json"):
            # if name ends with ".json" try find a composition without extension
            result = b.compsTable.getOrDefault(changeFileExt(name, ""))
        elif name.searchExtPos() == -1:
            # if name doesn't have any extension, try append ".json", maybe we have
            # an old pack format.
            result = b.compsTable.getOrDefault(name & ".json")

proc hasComposition*(b: BinDeserializer, name: string): bool {.inline.} =
    b.offsetToComposition(name) != 0

proc rewindToComposition*(b: BinDeserializer, name: string) =
    let pos = b.offsetToComposition(name)
    if pos == 0:
        for k in b.compsTable.keys:
            echo "COMP: ", k
        raise newException(Exception, "Could not rewind to " & name)
    b.stream.setPosition(pos)

proc setLenX[T](s: var seq[T], sz: int) =
    if s.isNil:
        s = newSeq[T](sz)
    else:
        s.setLen(sz)

proc readUint8*(b: BinDeserializer): uint8 {.inline.} =
    cast[uint8](b.stream.readInt8())

proc readInt8*(b: BinDeserializer): int8 {.inline.} =
    b.stream.readInt8()

proc getImageInfoForIndex(b: BinDeserializer, idx: int16, path: var string, frameOffset: var Point) =
    let j = b.images[idx]
    path = b.basePath & "/" & j["orig"].str
    let joff = j{"off"}
    if not joff.isNil:
        frameOffset.x = joff[0].getFNum()
        frameOffset.y = joff[1].getFNum()

proc getImageForIndex(b: BinDeserializer, idx: int16, im: var Image) =
    if idx == -2:
        var asset = b.readStr()
        var bundle = b.readStr()
        im = sharedAssetManager().cachedAsset(Image, bundle & '/' & asset)

    elif idx != -1:
        var path: string
        var p: Point
        b.getImageInfoForIndex(idx, path, p)
        im = sharedAssetManager().cachedAsset(Image, path)

proc getImageForIndex(b: BinDeserializer, idx: int16, im: var Image, frameOffset: var Point) =
    assert(idx != -2, "Internal error")

    if idx != -1:
        var path: string
        b.getImageInfoForIndex(idx, path, frameOffset)
        im = sharedAssetManager().cachedAsset(Image, path)

proc read*[T](b: BinDeserializer, data: var T) =
    when T is array or T is openarray:
        when isPODType(T):
            if data.len != 0:
                b.align(alignsize(type(data[0])))
                discard b.stream.readData(addr data[0], data.len * sizeof(data[0]))
        else:
            for i in 0 ..< data.len:
                b.read(data[i])

    elif T is tuple:
        when isPODType(T):
            b.align(alignsize(type(data[0])))
            discard b.stream.readData(addr data, sizeof(data))
        else:
            for k, v in fieldPairs(data):
                b.read(v)

    elif T is seq:
        let sz = b.readInt16()
        if sz == 0:
            data = nil
        else:
            data.setLenX(sz)
            b.read(openarray[type(data[0])](data))

    elif T is string:
        data = b.readStr()

    elif T is int16 | int32 | float32:
        b.align(sizeof(data))
        discard b.stream.readData(addr data, sizeof(T))

    elif T is int8 | uint8:
        discard b.stream.readData(addr data, sizeof(T))

    elif T is bool:
        var tb: uint8
        discard b.stream.readData(addr tb, sizeof(tb))
        data = tb.bool

    elif T is Image:
        let idx = b.readInt16()

        b.getImageForIndex(idx, data)

    elif T is enum:
        var v: (when ord(high(T)) < high(int8): int8 else: int16)
        b.read(v)
        data = cast[T](v)

    elif T is int | int64:
        {.error: "int and int64 not supported " .}
    else:
        {.error: "Unknown type " .}


proc visit*[T](b: BinDeserializer, v: var T) {.inline.} =
    b.read(v)

proc visit*(b: BinDeserializer, v: var Quaternion) =
    let buf = b.getBuffer(float32, 4)
    v = newQuaternion(buf[0], buf[1], buf[2], buf[3])

proc visit*(b: BinDeserializer, v: var Image) =
    let idx = b.readInt16()
    b.getImageForIndex(idx, v)

proc visit*(b: BinDeserializer, images: var seq[Image], frameOffsets: var seq[Point]) =
    let sz = b.readInt16()
    images.setLenX(sz)
    frameOffsets.setLenX(sz)
    let buf = b.getBuffer(int16, sz)
    for i in 0 ..< sz:
        b.getImageForIndex(buf[i], images[i], frameOffsets[i])

proc `@`*[T](b: BufferView[T]): seq[T] =
    result = newSeqOfCap[T](b.len)
    for i in 0 ..< b.len:
        result.add(b[i])
