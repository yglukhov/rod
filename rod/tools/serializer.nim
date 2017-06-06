import json, tables, typetraits, streams, logging, strutils, ospaths

import nimx.image
import nimx.types
import nimx.pathutils
import nimx.matrixes
import nimx.portable_gl
import nimx.assets.asset_loading

import rod.rod_types
import rod.quaternion

type Serializer* = ref object
    url*: string
    asyncOps: int
    onComplete*: proc()
    finished: bool

proc `%`*(n: Node): JsonNode =
    if not n.isNil:
        result = newJString(n.name)
    else:
        result = newJString("")

proc `%`*(v: Size): JsonNode = %[v.width, v.height]
proc `%`*(v: Point): JsonNode = %[v.x, v.y]
proc `%`*(v: Color): JsonNode = %[v.r, v.g, v.b, v.a]
proc `%`*(v: Rect): JsonNode = %[v.x, v.y, v.width, v.height]
template `%`*(v: Quaternion): JsonNode = %(TVector4[Coord](v))

proc getRelativeResourcePath*(s: Serializer, path: string): string =
    var resourcePath = path
    when not defined(js) and not defined(android) and not defined(ios):
        resourcePath = parentDir(s.url)

    result = relativePathToPath(resourcePath, path)
    echo "save path = ", resourcePath, "  relative = ", result

template isAbsoluteUrl(u: string): bool =
    # TODO: make it smarter
    u.find("://") != -1

proc toAbsoluteUrl*(s: Serializer, relativeOrAbsoluteUrl: string): string =
    if isAbsolute(relativeOrAbsoluteUrl):
        return "file://" & relativeOrAbsoluteUrl

    if isAbsoluteUrl(relativeOrAbsoluteUrl): return relativeOrAbsoluteUrl

    result = parentDir(s.url) & '/' & relativeOrAbsoluteUrl
    normalizePath(result, false)

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var string) =
    let jN = j{name}
    if not jN.isNil:
        val = jN.getStr(nil)

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var int) =
    let jN = j{name}
    if not jN.isNil:
        val = jN.getNum().int

proc getDeserialized[T: enum](s: Serializer, j: JsonNode, name: string, val: var T) =
    let jN = j{name}
    if not jN.isNil:
        val = T(jN.getNum().int)

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var float32) =
    let jN = j{name}
    if not jN.isNil:
        val = jN.getFnum()

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var float) =
    let jN = j{name}
    if not jN.isNil:
        val = jN.getFnum()

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var Vector3) =
    let jN = j{name}
    if not jN.isNil:
        val = newVector3(jN[0].getFnum(), jN[1].getFnum(), jN[2].getFnum())

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var Quaternion) =
    let jN = j{name}
    if not jN.isNil:
        val = newQuaternion(jN[0].getFnum(), jN[1].getFnum(), jN[2].getFnum(), jN[3].getFnum())

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var Rect) =
    let jN = j{name}
    if not jN.isNil:
        val = newRect(jN[0].getFnum(), jN[1].getFnum(), jN[2].getFnum(), jN[3].getFnum())

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var Size) =
    let jN = j{name}
    if not jN.isNil:
        val = newSize(jN[0].getFnum(), jN[1].getFnum())

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var Point) =
    let jN = j{name}
    if not jN.isNil:
        val = newPoint(jN[0].getFnum(), jN[1].getFnum())

proc toResourcePath(s: Serializer, path: string): string =
    let url = s.toAbsoluteUrl(path)
    const prefix = "res://"
    assert(url.startsWith(prefix))
    return url.substr(prefix.len)

proc deserializeImage*(j: JsonNode, s: Serializer): Image {.deprecated.} =
    if j.isNil:
        discard
    elif j.kind == JString:
        let name = j.getStr()
        if name.endsWith(".sspart"):
            let parts1 = name.split(" - ")
            let parts = parts1[1].split('.')
            let rect = newRect(parts[^5].parseFloat(), parts[^4].parseFloat(), parts[^3].parseFloat(), parts[^2].parseFloat())
            let realName = parts1[0]
            let ss = imageWithResource(s.toResourcePath(realName))
            result = ss.subimageWithRect(rect)
            warn "sspart images are deprecated"
        else:
            result = imageWithResource(s.toResourcePath(name))
    else:
        let realName = j["file"].getStr()
        let uv = j["tex"]
        let sz = j["size"]
        let ss = imageWithResource(s.toResourcePath(realName))
        result = ss.subimageWithTexCoords(
                        newSize(sz[0].getFNum(), sz[1].getFNum()),
                        [uv[0].getFNum().float32, uv[1].getFNum(), uv[2].getFNum(), uv[3].getFNum()]
                        )

proc startAsyncOp*(s: Serializer) {.inline.} =
    inc s.asyncOps

proc endAsyncOp*(s: Serializer) =
    dec s.asyncOps
    if s.finished and s.asyncOps == 0 and not s.onComplete.isNil:
        s.onComplete()

proc finish*(s: Serializer) =
    s.finished = true
    if s.asyncOps == 0 and not s.onComplete.isNil:
        s.onComplete()

proc deserializeImage*(j: JsonNode, s: Serializer, clbck: proc(img: Image, err: string)) =
    if j.isNil:
        discard
    elif j.kind == JString:
        let name = j.getStr()
        s.startAsyncOp()
        if name.endsWith(".sspart"):
            let parts1 = name.split(" - ")
            let parts = parts1[1].split('.')
            let rect = newRect(parts[^5].parseFloat(), parts[^4].parseFloat(), parts[^3].parseFloat(), parts[^2].parseFloat())
            let realName = parts1[0]
            warn "sspart images are deprecated"
            loadAsset(s.toAbsoluteUrl(realName)) do(ss: Image, err: string):
                # TODO: Error handling
                let img = ss.subimageWithRect(rect)
                clbck(img, err)
                s.endAsyncOp()
        else:
            loadAsset(s.toAbsoluteUrl(name)) do(img: Image, err: string):
                clbck(img, err)
                s.endAsyncOp()
    else:
        let realName = j["file"].getStr()
        s.startAsyncOp()
        loadAsset(s.toAbsoluteUrl(realName)) do(ss: Image, err: string):
            # TODO: Error handling
            let uv = j["tex"]
            let sz = j["size"]
            let img = ss.subimageWithTexCoords(
                        newSize(sz[0].getFNum(), sz[1].getFNum()),
                        [uv[0].getFNum().float32, uv[1].getFNum(), uv[2].getFNum(), uv[3].getFNum()]
                        )
            clbck(img, err)
            s.endAsyncOp()

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var Image) {.deprecated.} =
    val = deserializeImage(j{name}, s)

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var bool) =
    let jN = j{name}
    if not jN.isNil:
        val = jN.getBVal()

# proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var Node) =
#     let jN = j{name}
    # if not jN.isNil and jN.getStr().len > 0:
    #     val = newNode(jN.getStr())

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var Color) =
    let jN = j{name}
    if not jN.isNil:
        val.r = jN[0].getFNum()
        val.g = jN[1].getFNum()
        val.b = jN[2].getFNum()
        if jN.len > 3: #TODO: new format should always have 4 components for color.
            val.a = jN[3].getFNum()
        else:
            val.a = 1.0

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var Matrix4) =
    let jN = j{name}
    if not jN.isNil:
        for i in 0 ..< jN.len:
            val[i] = jN[i].getFnum()

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var seq[Glfloat]) =
    let jN = j{name}
    if not jN.isNil:
        for i in 0 ..< jN.len:
            val.add( jN[i].getFnum() )

proc getDeserialized[T: TVector](s: Serializer, j: JsonNode, name: string, val: var seq[T]) =
    let jN = j{name}
    if not jN.isNil:
        for i in 0 ..< jN.len:
            var seqVal: T
            const vecLen = high(T) + 1
            for j in 0 ..< vecLen:
                seqVal[j] = jN[i][j].getFnum()

            val.add( seqVal )

proc getValue*[T](s: Serializer, v: T): JsonNode =
    when T is enum:
        result = %(int(v))
    else:
        result = %v

template deserializeValue*(s: Serializer, j: JsonNode, name: string, val: untyped) =
    let jN = j{name}
    if not jN.isNil:
        var tmp = val
        s.getDeserialized(j, name, tmp)
        val = tmp

proc save*(s: Serializer, n: JsonNode, path: string) =
    when not defined(js) and not defined(android) and not defined(ios):
        s.url = "file://" & path
        var nd = n #s.getNodeData(n)
        var str = nd.pretty()

        var fs = newFileStream(path, fmWrite)
        if fs.isNil:
            echo "WARNING: Resource can not open: ", path
        else:
            fs.write(str)
            fs.close()
            echo "save at path ", path
    else:
        echo "serializer::save don't support js"

