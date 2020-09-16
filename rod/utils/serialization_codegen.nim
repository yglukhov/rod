import nimx/class_registry
import macros, tables
import property_desc

proc genPhantomTypeSection(typdesc: NimNode): NimNode =
    let fields = newNimNode(nnkRecList)
    for p in typdesc.propertyDescs:
        if p.hasAttr("phantom"):
            fields.add(newIdentDefs(newIdentNode(p.name), p.attributes["phantom"]))
    if fields.len > 0:
        result = newNimNode(nnkTypeSection).add(newNimNode(nnkTypeDef).add(newIdentNode("Phantom"), newEmptyNode(),
            newNimNode(nnkObjectTy).add(newEmptyNode(), newEmptyNode(), fields)))

iterator serializablePropertyDescs(typdesc: NimNode): PropertyDesc =
    for p in typdesc.propertyDescs:
        if not p.hasAttr("noserialize"):
            yield p

proc serializationKey(p: PropertyDesc): NimNode =
    if p.hasAttr("serializationKey"):
        result = copyNimTree(p.attributes["serializationKey"])
    else:
        result = newLit(p.name)

proc actualReference(p: PropertyDesc, v: NimNode): NimNode =
    let o = if p.hasAttr("phantom"): newIdentNode("phantom") else: v
    newNimNode(nnkDotExpr).add(o, newIdentNode(p.name))

proc propertyDescWithName(typdesc: NimNode, name: string): PropertyDesc =
    for p in typdesc.propertyDescs:
        if p.name == name: return p

    # TODO: The following is a hack. Instead we should get property descs from the typdesc itself
    result.name = name
    result.attributes = initTable[string, NimNode]()

macro genSerializerProc(typdesc: typed{nkSym}, serTyp: typed{nkSym}, v: typed, s: typed,
        keyed: static[bool], serialize: static[bool],
        bin: static[bool], skipPhantom: static[bool]): untyped =
    let phantomIdent = newIdentNode("phantom")

    let phantomTyp = genPhantomTypeSection(typdesc)

    var paramTyp = typdesc

    let impl = getImpl(typdesc)

    # echo treeRepr(getImpl(typdesc.symbol))

    if not serialize and impl.kind == nnkTypeDef and impl.len >= 3 and impl[2].kind != nnkRefTy:
        paramTyp = newNimNode(nnkVarTy).add(paramTyp)

    result = newNimNode(nnkStmtList)

    if not phantomTyp.isNil and phantomTyp.kind != nnkEmpty:
        result.add(phantomTyp)
        let pv = quote do:
            var `phantomIdent`: Phantom
        result.add(pv)

        if serialize and not skipPhantom:
            result.add(newCall("toPhantom", v, phantomIdent))

    for p in typdesc.serializablePropertyDescs:
        let visitCall = newCall(ident("visit"), s, actualReference(p, v))
        if keyed: visitCall.add(p.serializationKey())

        if p.hasAttr("combinedWith"):
            let p1 = typdesc.propertyDescWithName($p.attributes["combinedWith"])
            visitCall.add(actualReference(p1, v))
            if keyed: visitCall.add(p1.serializationKey())

        # if keyed and not serialize and not bin and p.hasAttr("default"):
        #     visitCall.add(p.attributes["default"])

        result.add(visitCall)
        # let echoPrefix = newLit($serTyp & " " & p.name & ": ")
        # let echoValue = actualReference(p, v)
        # result.add quote do:
        #     when compiles(echo(`echoPrefix`, `echoValue`)):
        #         echo `echoPrefix`, `echoValue`
        #     else:
        #         echo `echoPrefix`, "..."

    if not phantomTyp.isNil and phantomTyp.kind != nnkEmpty:
        if not serialize and not skipPhantom:
            result.add(newCall("fromPhantom", v, phantomIdent))

    if not serialize:
        result.add quote do:
            when compiles(awake(`v`)):
                if not `s`.disableAwake:
                    awake(`v`)

    # echo repr(result)

template genSerializationCodeForComponent*(c: typed) =
    import rod / utils / [ bin_deserializer ]

    when defined(rodplugin):
        import rod / utils / [ json_deserializer, json_serializer,
                bin_serializer, serialization_hash_calculator ]

        bind className
        method deserialize*(v: c, b: JsonDeserializer) =
            genSerializerProc(c, JsonDeserializer, v, b, true, false, false, false)

        method serialize*(v: c, b: JsonSerializer) =
            b.visit(className(v), "_c")
            genSerializerProc(c, JsonSerializer, v, b, true, true, false, false)

        method serialize*(v: c, b: BinSerializer) =
            genSerializerProc(c, BinSerializer, v, b, false, true, true, false)

        method serializationHash*(v: c, b: SerializationHashCalculator) =
            genSerializerProc(c, SerializationHashCalculator, v, b, true, true, false, true)

    method supportsNewSerialization*(cm: c): bool = true

    method deserialize*(v: c, b: BinDeserializer) =
        genSerializerProc(c, BinDeserializer, v, b, false, false, true, false)

template genJsonSerializationrFor*(c: typed) =
    import rod / utils / [ json_deserializer, json_serializer ]

    proc toJson*(v: c): JsonNode=
        var b = newJsonSerializer()
        genSerializerProc(c, JsonSerializer, v, b, true, true, false, false)
        result = b.node

    proc `to c`*(jn: JsonNode): c =
        var b = newJsonDeserializer()
        b.node = jn
        when c is ref:
            result.new()
        genSerializerProc(c, JsonDeserializer, result, b, true, false, false, false)
