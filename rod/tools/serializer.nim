import json
import tables
import typetraits
import streams
when not defined(js) and not defined(android) and not defined(ios):
    import os

import nimx.image
import nimx.types
import nimx.pathutils
import nimx.matrixes
import nimx.portable_gl

import rod.rod_types
import rod.quaternion

type Serializer* = ref object
    savePath*: string

proc vectorToJNode[T](vec: T): JsonNode =
    result = newJArray()
    for k, v in vec:
        result.add(%v)

proc `%`*(n: Node): JsonNode =
    if not n.isNil:
        result = newJString(n.name)
    else:
        result = newJString("")

proc `%`*[T: enum](v: T): JsonNode =
    result = newJInt(v.ord)

proc `%`*[I: static[int], T](vec: TVector[I, T]): JsonNode =
    result = vectorToJNode(vec)

proc `%`*(v: Size): JsonNode =
    result = vectorToJNode(newVector2(v.width, v.height))

proc `%`*(v: Color): JsonNode =
    result = newJArray()
    for k, val in v.fieldPairs:
        result.add( %val )

proc getRelativeResourcePath*(s: Serializer, path: string): string =
    var resourcePath = path
    when not defined(js) and not defined(android) and not defined(ios):
        resourcePath = parentDir(s.savePath)

    result = relativePathToPath(resourcePath, path)
    echo "save path = ", resourcePath, "  relative = ", result


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

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var Size) =
    let jN = j{name}
    if not jN.isNil:
        val = newSize(jN[0].getFnum(), jN[1].getFnum())

proc getDeserialized(s: Serializer, j: JsonNode, name: string, val: var Image) =
    let jN = j{name}
    if not jN.isNil:
        val = imageWithResource(jN.getStr())

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
    result = %v

template deserializeValue*(s: Serializer, j: JsonNode, name: string, val: untyped) =
    let jN = j{name}
    if not jN.isNil:
        var tmp = val
        s.getDeserialized(j, name, tmp)
        val = tmp

proc save*(s: Serializer, n: JsonNode, path: string) =
    when not defined(js) and not defined(android) and not defined(ios):
        s.savePath = path
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

