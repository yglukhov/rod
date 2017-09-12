import streams, tables, json

import nimx / [ image, types, assets/asset_manager ]
import rod.utils.property_desc
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

proc getPosition*(b: BinDeserializer): int {.inline.} = b.stream.getPosition()
proc setPosition*(b: BinDeserializer, p: int) {.inline.} = b.stream.setPosition(p)

template alignsize(t: typedesc): int =
    if sizeof(t) > 4:
        4
    else:
        sizeof(t)

proc getBuffer*(b: BinDeserializer, T: typedesc, len: int): BufferView[T] =
    when T is array:
        var dummy: T
        b.align(sizeof(dummy[0]))
    when T is tuple:
        var dummy: T
        b.align(sizeof(dummy[0]))
    else:
        b.align(alignsize(T))
    let s = StringStream(b.stream)
    let offset = b.getPosition()
    assert(s.data.len > offset + len)
    result.mData = cast[ptr UncheckedArr[T]](cast[pointer](addr s.data[offset]))
    result.len = len
    b.setPosition(offset + len * sizeof(T))

proc init(b: BinDeserializer) =
    var strtabLen = b.readInt16()
    echo "strtabLen: ", strtabLen
    b.strtab = newSeq[string](strtabLen)
    for i in 0 ..< strtabLen:
        let strLen = b.readInt16()
        # echo "len:", strLen
        b.strtab[i] = b.stream.readStr(strLen)
        echo "str ", i, ": ", b.strtab[i]
        shallow(b.strtab[i])

    b.compsTable = initTable[string, int32]()
    let compsLen = b.readInt16()
    if compsLen > 0:
        let offsets = b.getBuffer(int32, compsLen)
        let names = b.getBuffer(int16, compsLen)

        echo "numComps: ", compsLen
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

proc hasComposition*(b: BinDeserializer, name: string): bool {.inline.} =
    name in b.compsTable

proc rewindToComposition*(b: BinDeserializer, name: string) =
    try:
        b.stream.setPosition(b.compsTable[name])
    except:
        echo "COULD NOT REWIND TO COMP: ", name
        for k in b.compsTable.keys:
            echo "COMP: ", k
        raise

proc read*[T](b: BinDeserializer, data: var openarray[T]) =
    when T is array:
        b.align(sizeof(data[0][0]))
    when T is tuple:
        b.align(sizeof(data[0][0]))
    else:
        b.align(alignsize(T))
    discard b.stream.readData(addr data[0], data.len * sizeof(T))

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

proc getImageForIndex(b: BinDeserializer, idx: int16, im: var Image, frameOffset: var Point) =
    if idx != -1:
        var path: string
        b.getImageInfoForIndex(idx, path, frameOffset)
        im = sharedAssetManager().cachedAsset(Image, path)

proc setLenX[T](s: var seq[T], sz: int) =
    if s.isNil:
        s = newSeq[T](sz)
    else:
        s.setLen(sz)

proc visit*[T](b: BinDeserializer, v: var openarray[T]) {.inline.} =
    b.read(v)

proc visit*[T](b: BinDeserializer, v: var seq[T]) =
    let sz = b.readInt16()
    if sz == 0:
        v = nil
    else:
        v.setLenX(sz)
        b.read(v)

proc visit*(b: BinDeserializer, v: var float32) {.inline.} =
    v = b.readFloat32()

proc visit*(b: BinDeserializer, v: var int16) {.inline.} =
    v = b.readInt16()

proc visit*(b: BinDeserializer, v: var int32) {.inline.} =
    v = b.readInt32()

proc visit*[T: enum](b: BinDeserializer, v: var T) {.inline.} =
    when ord(high(T)) < high(int8):
        v = cast[T](b.readInt8())
    else:
        v = cast[T](b.readInt16())

proc visit*(b: BinDeserializer, v: var bool) {.inline.} =
    v = b.readInt8().bool

proc visit*(b: BinDeserializer, c: var Color) =
    let buf = b.getBuffer(float32, 4)
    c = newColor(buf[0], buf[1], buf[2], buf[3])

proc visit*(b: BinDeserializer, v: var Size) =
    v.width = b.readFloat32()
    v.height = b.readFloat32()

proc visit*(b: BinDeserializer, v: var Point) =
    v.x = b.readFloat32()
    v.y = b.readFloat32()

proc visit*(b: BinDeserializer, v: var Rect) =
    let buf = b.getBuffer(float32, 4)
    v = newRect(buf[0], buf[1], buf[2], buf[3])

proc visit*(b: BinDeserializer, v: var Quaternion) =
    let buf = b.getBuffer(float32, 4)
    v = newQuaternion(buf[0], buf[1], buf[2], buf[3])

proc visit*(b: BinDeserializer, v: var string) {.inline.} =
    v = b.readStr()

proc visit*(b: BinDeserializer, v: var Image) =
    let idx = b.readInt16()
    var p: Point
    b.getImageForIndex(idx, v, p)

proc visit*(b: BinDeserializer, images: var seq[Image], frameOffsets: var seq[Point]) =
    let sz = b.readInt16()
    images.setLenX(sz)
    frameOffsets.setLenX(sz)
    let buf = b.getBuffer(int16, sz)
    for i in 0 ..< sz:
        b.getImageForIndex(buf[i], images[i], frameOffsets[i])
