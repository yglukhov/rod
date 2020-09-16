import json, streams, sequtils, sets, algorithm, tables, strutils, parseutils, os
import tree_traversal

import nimx / [ types, image, pathutils, class_registry ]
import ../../utils/[ bin_serializer, json_deserializer ]
import ../../rod_types
import ../../node
import ../../component
import ../../component/all_components
import ../../animation/property_animation
export bin_serializer

proc toScalarType[T](j: JsonNode, o: var T) {.inline.} =
    when T is float | float32 | float64:
        o = j.getFloat()
    elif T is int16 | int32 | int64:
        o = T(j.getInt)
    elif T is bool:
        o = j.getBool()
    else:
        {.error: "Unknown scalar type".}

proc toComponentType[T](j: JsonNode, o: var T) =
    when T is array:
        for i in 0 .. high(T):
            toScalarType(j[i], o[i])
    else:
        toScalarType(j, o)

proc align(s: Stream, sz: int) =
    doAssert(sz <= 4)
    let p = s.getPosition()
    let m = p mod sz
    if m != 0:
        for i in 0 ..< (sz - m):
            s.write(0xff'u8)
    doAssert(s.getPosition() mod sz == 0)

proc writeVec(b: BinSerializer, sz: static[int], T: typedesc, j: JsonNode) =
    var v: array[sz, T]
    toComponentType(j, v)
    b.write(v)

proc writeVecf(b: BinSerializer, sz: static[int], j: JsonNode) {.inline.} =
    b.writeVec(sz, float32, j)

proc writeColor(b: BinSerializer, j: JsonNode) {.inline.} =
    if j.len == 3: j.add(%1) # Add alpha
    doAssert(j.len == 4)
    b.writeVecf(4, j)

proc anyValue(j: JsonNode): JsonNode =
    for k, v in j: return v

proc writeSamplerValues(b: BinSerializer, propType: typedesc, v: JsonNode) =
    var values = newSeq[propType](v.len)
    for i in 0 ..< v.len:
        toComponentType(v[i], values[i])
    b.write(values)

# todo: fix this
template typeOfProperty(propName: string, body: untyped) =
    case propName
    of "tX", "tY", "tZ", "sX", "sY", "sZ", "alpha", "inWhite", "inBlack",
            "inGamma", "outWhite", "outBlack", "Tracking Amount", "lightness", "amount",
            "redInGamma", "blueInGamma", "greenInGamma", "redOutWhite", "greenOutWhite",
            "blueOutWhite", "redInWhite", "greenInWhite", "blueInWhite", "hue", "strokeWidth",
            "radius", "timeremap":
        body(float32)
    of "translation", "scale", "anchor": body(array[3, float32])
    of "rotation", "white", "black", "strokeColor", "color": body(array[4, float32])
    of "size": body(array[2, float32])
    of "curFrame": body(int16)
    of "enabled": body(bool)
    else: raise newException(Exception, "Unknown property type: " & propName)

proc writeSamplerValues(b: BinSerializer, propName: string, v: JsonNode) =
    template writeValues(T: typedesc) =
        writeSamplerValues(b, T, v)
    typeOfProperty(propName, writeValues)

proc writeBuiltInComponents[T](b: BinSerializer, typ: BuiltInComponentType, name: string, nodes: seq[JsonNode]) =
    var nodeIds = newSeqOfCap[int16](nodes.len)
    var components = newSeqOfCap[T](nodes.len)

    for n in nodes:
        let c = n{name}
        if not c.isNil:
            nodeIds.add(int16(n["_id"].getInt()))
            var v: T
            toComponentType(c, v)
            components.add(v)

    echo "comp: ", typ
    b.write($typ)
    b.write(nodeIds)
    b.writeArrayNoLen(components)

proc writeBuiltInComponents[T](b: BinSerializer, typ: BuiltInComponentType, name: string, nodes: seq[JsonNode], default: T) =
    var nodeIds = newSeqOfCap[int16](nodes.len)
    var components = newSeqOfCap[T](nodes.len)

    for n in nodes:
        let c = n{name}
        if not c.isNil:
            var v: T
            toComponentType(c, v)
            if v != default:
                nodeIds.add(int16(n["_id"].getInt()))
                components.add(v)

    b.write($typ)
    b.write(nodeIds)
    b.writeArrayNoLen(components)

proc writeFlagsComponents(b: BinSerializer, nodes: seq[JsonNode]) =
    var components = newSeqOfCap[uint8](nodes.len)

    for n in nodes:
        var flags: uint8 = 0
        for flag in NodeFlags:
            let val = n{$flag}.getBool(true).uint8
            flags = flags or (val shl flag.uint8)
        components.add(flags)

    b.write($bicFlags)
    b.writeArrayNoLen(components)

proc writeAlphaComponents(b: BinSerializer, nodes: seq[JsonNode]) =
    var components = newSeqOfCap[uint8](nodes.len)

    for n in nodes:
        components.add(uint8(n{"alpha"}.getFloat(1) * 255))

    b.write($bicAlpha)
    b.writeArrayNoLen(components)

proc writeNameComponents(b: BinSerializer, nodes: seq[JsonNode]) =
    b.write($bicName)
    for n in nodes:
        b.write(n{"name"}.getStr())

proc writeCompRefComponents(b: BinSerializer, nodes: seq[JsonNode], path: string) =
    var nodeIds = newSeqOfCap[int16](nodes.len)
    var components = newSeqOfCap[string](nodes.len)

    for n in nodes:
        let c = n{"compositionRef"}
        if not c.isNil:
            nodeIds.add(int16(n["_id"].getInt()))
            var p = changeFileExt(parentDir(path) & "/" & c.getStr(), "")
            normalizePath(p, false)
            components.add(p)

    b.write($bicCompRef)
    b.write(nodeIds)
    b.writeArrayNoLen(components)

proc imageDesc(b: BinSerializer, path: string): JsonNode =
    for j in b.images:
        if j["orig"].getStr() == path:
            return j

    doAssert(false, "Image desc not found: " & path)

proc writeSingleComponent(b: BinSerializer, className: string, j: JsonNode, compPath: string) =
    let n = newNode()
    let c = n.addComponent(className)
    let s = newJsonDeserializer()
    s.node = j
    s.disableAwake = true
    s.compPath = relativePathToPath(b.assetBundlePath, compPath)

    s.getImageForPath = proc(path: string, offset: var Point): Image =
        let desc = b.imageDesc(path)
        let sz = desc["size"]
        let joff = desc{"off"}
        if not joff.isNil:
            JsonDeserializer(nil).get(joff, offset)
        result = imageWithSize(newSize(sz[0].getFloat(), sz[1].getFloat()))
        result.setFilePath(path)

    let oldNodeRefTab = nodeLoadRefTable
    nodeLoadRefTable = newTable[string, seq[NodeRefResolveProc]]()
    defer: nodeLoadRefTable = oldNodeRefTab
    c.deserialize(s)

    # Resolve node refs
    for k, v in nodeLoadRefTable:
        if k.len != 0:
            let foundNode = newNode(k)
            for s in v:
                echo "Resolve node ref: ", k
                s(foundNode)

    c.serialize(b)
    n.children = @[] # Break cycle to let gc collect it faster

proc writeAECompositionComponent(b: BinSerializer, j: JsonNode, nodes: seq[JsonNode]) =
    let jbufs = j{"buffers"}
    var numBuffers = 0'i16
    if not jbufs.isNil:
        numBuffers = jbufs.len.int16

    b.write(numBuffers)
    if not jbufs.isNil:
        for k, v in jbufs:
            var nodeName, propName: string
            var compIdx: int
            splitPropertyName(k, nodeName, compIdx, propName)
            b.write(nodeName)
            b.write(propName)
            let frameLerp = v{"frameLerp"}.getBool(true)
            let len = v["len"].getInt()
            let cutf = v["cutf"].getInt()
            b.write(int8(frameLerp))
            b.write(int16(len))
            b.write(int16(cutf))
            let vals = v["values"]
            b.writeSamplerValues(propName, vals)

    let numMarkers = j["markers"].len.int16
    b.write(numMarkers)
    for k, v in j["markers"]:
        b.write(k)
        b.write(v["start"].getFloat())
        b.write(v["duration"].getFloat())


    let jlayers = j{"layers"}
    var numLayers = 0'i16
    if not jlayers.isNil:
        numLayers = jlayers.len.int16
    b.write(numLayers)
    if not jlayers.isNil:
        for la in jlayers:
            b.write(la.getStr())

proc writeUnknownComponent(b: BinSerializer, j: JsonNode) =
    # echo j
    let name = j["_c"]
    j.delete("_c")
    var s = ""
    toUgly(s, j)
    j["_c"] = name
    b.align(sizeof(int32))
    b.stream.write(s.len.int32)
    b.stream.write(s)

proc writeComponents(b: BinSerializer, nodes: seq[JsonNode], writer: proc(b: BinSerializer, node: JsonNode)) =
    for n in nodes:
        writer(b, n)

proc writeComponents(b: BinSerializer, nodes: seq[JsonNode], writer: proc(j: JsonNode)) =
    for n in nodes:
        writer(n)

proc writeComponents(b: BinSerializer, nodes: seq[JsonNode], className: string, compPath: string) =
    for n in nodes:
        writeSingleComponent(b, className, n, compPath)

proc writeComponents(b: BinSerializer, name: string, nodes: seq[JsonNode], compPath: string) =
    b.write(name)

    var nodeIds = newSeqOfCap[int16](nodes.len)
    var c = newSeqOfCap[JsonNode](nodes.len)

    for n in nodes:
        for s in n.componentNodesOfType(name):
            nodeIds.add(int16(n["_id"].getInt()))
            c.add(s)

    b.write(nodeIds)
    if isClassRegistered(name) and newObjectOfClass(name).Component.supportsNewSerialization():
        if name == "AEComposition":
            b.writeComponents(c) do(j: JsonNode):
                writeAECompositionComponent(b, j, nodes)
        else:
            b.writeComponents(c, name, compPath)
    else:
        echo "WARNING: Unknown component: ", name
        b.writeComponents(c, writeUnknownComponent)

# Bin format spec
# file -> stringTable + int16[compositionCount] + compositionTable + array[composition]
# stringTable -> int16[stringTableLen] + array[string]
# string -> int16[stringLength] + stringBytes
# compositionTable -> array[compositionTablePair]
# compositionTablePair -> stringId + int32[offsetToComposition]
# ... TODO: Complete this

proc writeAnimation(b: BinSerializer, anim: JsonNode) =
    const rodeditMeta = "rodedit$metadata"
    let propsCount = if rodeditMeta in anim: anim.len - 1 else: anim.len
    b.write(int16(propsCount))
    let anyProp = anim.anyValue
    b.write(anyProp["duration"].getFloat())
    b.write(anyProp{"numberOfLoops"}.getInt(1).int16)

    for k, v in anim:
        if k == rodeditMeta: continue
        var nodeName, propName: string
        var compIdx: int
        splitPropertyName(k, nodeName, compIdx, propName)
        b.write(nodeName)
        b.write(propName)
        let frameLerp = v{"frameLerp"}.getBool(true)
        b.write(int8(frameLerp))
        
        let vals = v{"values"}
        b.write(int8(vals.isNil)) #is key frame animation
        if vals.isNil:
            let keys = v["keys"]
            b.write(int16(keys.len))
            for k in keys:
                b.write(float32(k["p"].getFloat()))
                
                #todo: fix this
                template writeValues(T: typedesc) =
                    var v: T
                    toComponentType(k["v"], v)
                    b.write(v)
                typeOfProperty(propName, writeValues)

                let inter = parseEnum[KeyInterpolationKind](k["i"].getStr(""))
                b.write(inter)
                if inter == KeyInterpolationKind.eiBezier:
                    if k["f"].len != 4: 
                        raise newException(Exception, "Invalid timing function!")
                    
                    for fi in k["f"]: #write timing function
                        b.write(float32(fi.getFloat()))
        else:
            let vals = v["values"]
            b.writeSamplerValues(propName, vals)

proc writeAnimations(b: BinSerializer, comp: JsonNode) =
    let anims = comp{"animations"}
    if anims.isNil or anims.len == 0:
        b.write(int16(0))
        return

    b.write(int16(anims.len))
    for k, v in anims:
        b.write(k)
        b.writeAnimation(v)

proc isDefault[T](n: JsonNode, name: string, v: T): bool =
    let jv = n{name}
    result = true
    if not jv.isNil:
        var vv: T
        toComponentType(jv, vv)
        result = (v == vv)

proc orderComponents(c: HashSet[string]): seq[string] =
    result = @[]

    let componentPriority = [
        # Posteffect components should come first
        "VisualModifier",
        "ColorBalanceHLS",
        "Tint",
        "ChannelLevels",
        "ColorFill",
        "GradientFill",
        "Mask",

        "other", # Everything else

        "CompRef",
        "TileMap",
        "AEComposition" # Should be the last one
    ]

    var cpt = initTable[string, int]()
    for i, c in componentPriority: cpt[c] = i

    let defaultPriority = cpt["other"]
    template priority(a: string): int =
        if a in cpt:
            cpt[a]
        else:
            defaultPriority

    for comp in c: result.add(comp)
    result.sort() do(a, b: string) -> int:
        cmp(priority(a), priority(b))

proc writeComposition(b: BinSerializer, comp: JsonNode, path: string) =
    let nodes = toSeq(comp.allNodes)
    let nodesCount = nodes.len

    # Setup ids and parent ids
    for i in 0 ..< nodesCount:
        let n = nodes[i]
        let id = %i
        n["_id"] = id
        let ch = n{"children"}
        if not ch.isNil:
            for c in ch:
                c["_pid"] = id

    # Fill child-parent relationships
    var childParentRelations = newSeq[int16](nodesCount - 1)
    for i in 1 ..< nodesCount:
        let n = nodes[i]
        childParentRelations[i - 1] = int16(n["_pid"].getInt())

    b.write(int16(nodesCount))
    b.writeArrayNoLen(childParentRelations)
    childParentRelations = @[]

    var builtInComponents: set[BuiltInComponentType]

    var allCompNames = initHashSet[string]()
    for n in nodes:
        if not isDefault(n, "translation", [0.0, 0, 0]): builtInComponents.incl(bicTranslation)
        if not isDefault(n, "rotation", [0.0, 0, 0, 1.0]): builtInComponents.incl(bicRotation)
        if not isDefault(n, "anchor", [0.0, 0, 0]): builtInComponents.incl(bicAnchorPoint)
        if not isDefault(n, "scale", [1.0, 1, 1]): builtInComponents.incl(bicScale)
        if "alpha" in n: builtInComponents.incl(bicAlpha)
        if "name" in n: builtInComponents.incl(bicName)
        if "compositionRef" in n: builtInComponents.incl(bicCompRef)
        for flag in NodeFlags:
            if $flag in n:
                builtInComponents.incl(bicFlags)
                break

        for typ, c in n.componentNodes:
            allCompNames.incl(typ)

    let numComponents = allCompNames.len + builtInComponents.card()
    b.write(int16(numComponents))

    if bicTranslation in builtInComponents: writeBuiltInComponents[array[3, float32]](b, bicTranslation, "translation", nodes, [0'f32, 0, 0])
    if bicRotation in builtInComponents: writeBuiltInComponents[array[4, float32]](b, bicRotation, "rotation", nodes, [0.0'f32, 0.0, 0.0, 1.0])
    if bicAnchorPoint in builtInComponents: writeBuiltInComponents[array[3, float32]](b, bicAnchorPoint, "anchor", nodes, [0'f32, 0, 0])
    if bicScale in builtInComponents: writeBuiltInComponents[array[3, float32]](b, bicScale, "scale", nodes, [1'f32, 1, 1])
    if bicAlpha in builtInComponents: b.writeAlphaComponents(nodes)
    if bicFlags in builtInComponents: b.writeFlagsComponents(nodes)
    if bicName in builtInComponents: b.writeNameComponents(nodes)
    if bicCompRef in builtInComponents: b.writeCompRefComponents(nodes, path)

    let orderedComps = orderComponents(allCompNames)

    echo "COMP: ", path
    echo "COMPS: ", orderedComps, " + ", builtInComponents, ": ", numComponents

    for compName in orderedComps:
        b.writeComponents(compName, nodes, path)

    b.writeAnimations(comp)

proc writeStringTable(b: BinSerializer, toStream: Stream) =
    type StringTableElem = tuple[id: int16, s: string]
    let count = b.strTab.len
    var tab = newSeqOfCap[StringTableElem](count)
    for k, v in b.strTab:
        tab.add((k, v))
    tab.sort() do(a, b: StringTableElem) -> int:
        cmp(a.s, b.s)
    toStream.write(int16(count))

    for n in tab:
        toStream.align(sizeof(int16))
        toStream.write(int16(n.s.len))
        toStream.write(n.s)

    var patchEntriesTable = newSeq[int16](count)
    for i, t in tab:
        b.revStrTab[t.s] = int16(i)
        patchEntriesTable[t.id] = int16(i)

    let oldPos = b.stream.getPosition()
    for entry in b.stringEntries:
        b.stream.setPosition(entry)
        let id = b.stream.readInt16()
        b.stream.setPosition(entry)
        b.stream.write(patchEntriesTable[id])
        #echo "remap str from ", id, " to ", patchEntriesTable[id]
    b.stream.setPosition(oldPos)

proc writeCompsTable(b: BinSerializer, paths: openarray[string], s: Stream) =
    var spaths = @paths
    spaths.sort() do(a, b: string) -> int:
        cmp(a, b)

    # write offsets:
    s.align(sizeof(b.compsTable[""]))
    for p in spaths:
        s.write(b.compsTable[changeFileExt(p, "")])

    # Write names:
    for p in spaths:
        s.write(b.revStrTab[changeFileExt(p, "")])

proc writeCompositions(b: BinSerializer, comps: openarray[JsonNode], paths: openarray[string], s: Stream, images: JsonNode) =
    b.strTab = initTable[int16, string]()
    b.revStrTab = initTable[string, int16]()
    b.stream = newStringStream()
    b.stringEntries = newSeqOfCap[int32](256)
    b.compsTable = initTable[string, int32]()
    b.images = images

    for i, c in comps:
        let pathWithoutExt = changeFileExt(paths[i], "")
        discard b.newString(pathWithoutExt)
        b.align(sizeof(int16))
        b.compsTable[pathWithoutExt] = int32(b.stream.getPosition())
        b.writeComposition(c, pathWithoutExt)

    b.writeStringTable(s)
    s.align(sizeof(int16))
    s.write(int16(comps.len))
    b.writeCompsTable(paths, s)
    s.align(4)
    s.write(b.stream.data)
    b.stream = nil
    b.stringEntries = @[]

proc writeCompositions*(b: BinSerializer, comps: openarray[JsonNode], paths: openarray[string], file: string, images: JsonNode) =
    let s = newFileStream(file, fmWrite)
    b.writeCompositions(comps, paths, s, images)
    s.close()
