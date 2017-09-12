import tables, streams, json
import nimx / [image, types ]
import rod.quaternion

type
    BinSerializer* = ref object
        strTab*: Table[int16, string]
        revStrTab*: Table[string, int16]
        compsTable*: Table[string, int32]
        stream*: StringStream
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

proc write*(b: BinSerializer, id: int16) {.inline.} =
    b.align(sizeof(id))
    b.stream.write(id)

proc write*(b: BinSerializer, id: int32) {.inline.} =
    b.align(sizeof(id))
    b.stream.write(id)

proc write*(b: BinSerializer, v: int8) {.inline.} =
    b.stream.write(v)

proc write*(b: BinSerializer, v: float32) {.inline.} =
    b.align(sizeof(v))
    b.stream.write(v)

proc imageIndex*(b: BinSerializer, path: string): int16 =
    for j in b.images:
        if j["orig"].str == path:
            return
        inc result
    raise newException(Exception, "Image not found in index: " & path)

proc newString*(b: BinSerializer, s: string): int16 =
    if s in b.revStrTab:
        result = b.revStrTab[s]
    else:
        result = int16(b.strTab.len)
        b.strTab[result] = s
        b.revStrTab[s] = result

proc write*(b: BinSerializer, s: string) =
    if s.isNil:
        b.write(int16(-1))
    else:
        b.align(sizeof(int16))
        b.stringEntries.add(b.stream.getPosition().int32)
        let off = b.newString(s)
        #echo "writing str: ", s, ", off: ", s
        b.write(off)

proc write*(b: BinSerializer, v: Point) =
    b.write(v.x)
    b.write(v.y)

proc write*[T](b: BinSerializer, s: openarray[T]) =
    if s.len != 0:
        when T is array:
            b.align(sizeof(s[0][0]))
        else:
            b.align(sizeof(T))
        b.stream.writeData(unsafeAddr s[0], s.len * sizeof(s[0]))

proc visit*(b: BinSerializer, v: float32) {.inline.} =
    b.write(v)

proc visit*(b: BinSerializer, v: int16) {.inline.} =
    b.write(v)

proc visit*(b: BinSerializer, v: int32) {.inline.} =
    b.write(v)

proc visit*[T: enum](b: BinSerializer, v: T) {.inline.} =
    when ord(high(T)) < high(int8):
        b.write(ord(v).int8)
    else:
        b.write(ord(v).int16)

proc visit*(b: BinSerializer, v: bool) {.inline.} =
    b.write(int8(v))

proc visit*(b: BinSerializer, v: Size) =
    b.write(v.width)
    b.write(v.height)

proc visit*(b: BinSerializer, v: Point) {.inline.} =
    b.write(v)

proc visit*(b: BinSerializer, v: Color) =
    b.write(v.r)
    b.write(v.g)
    b.write(v.b)
    b.write(v.a)

proc visit*(b: BinSerializer, v: Rect) =
    b.write(v.x)
    b.write(v.y)
    b.write(v.width)
    b.write(v.height)

proc visit*(b: BinSerializer, v: Quaternion) =
    b.write(v.x)
    b.write(v.y)
    b.write(v.z)
    b.write(v.w)

proc visit*(b: BinSerializer, v: string) {.inline.} =
    b.write(v)

proc visit*(b: BinSerializer, v: Image) =
    if v.isNil:
        b.write(int16(-1))
    else:
        b.write(b.imageIndex(v.filePath))

proc visit*(b: BinSerializer, images: seq[Image], frameOffsets: seq[Point]) =
    let sz = images.len
    b.write(sz.int16)
    for i in 0 ..< sz:
        b.write(b.imageIndex(images[i].filePath()))

proc isPODType(T: typedesc): bool {.compileTime.} =
    when T is float32 | int16 | int8:
        true
    elif T is array:
        var dummy: T
        isPODType(type(dummy[0]))
    else:
        false

proc visit*[T](b: BinSerializer, v: seq[T]) =
    let sz = v.len.int16
    b.write(sz)
    if sz != 0:
        when isPODType(T):
            b.write(v)
        else:
            {.error: "Unknown element type".}

proc visit*[I: static[int], T](b: BinSerializer, v: array[I, T]) {.inline.} =
    when T is float32 | int16:
        b.write(v)
    else:
        {.error: "Unknown element type".}
