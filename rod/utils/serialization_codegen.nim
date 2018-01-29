import macros, tables
import property_desc
import nimx.class_registry

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

proc actualReference(p: PropertyDesc): NimNode =
    let o = if p.hasAttr("phantom"): newIdentNode("phantom") else: newIdentNode("v")
    newNimNode(nnkDotExpr).add(o, newIdentNode(p.name))

proc propertyDescWithName(typdesc: NimNode, name: string): PropertyDesc =
    for p in typdesc.propertyDescs:
        if p.name == name: return p

    # TODO: The following is a hack. Instead we should get property descs from the typdesc itself
    result.name = name
    result.attributes = initTable[string, NimNode]()

macro genSerializerProc*(typdesc: typed{nkSym}, name: untyped{nkIdent},
        serTyp: typed{nkSym}, keyed: static[bool], serialize: static[bool],
        bin: static[bool], skipPhantom: static[bool]): untyped =
    let v = newIdentNode("v")
    let s = newIdentNode("s")
    let phantomIdent = newIdentNode("phantom")

    let phantomTyp = genPhantomTypeSection(typdesc)

    var paramTyp = typdesc

    let impl = getImpl(typdesc.symbol)

    # echo treeRepr(getImpl(typdesc.symbol))

    if not serialize and impl.kind == nnkTypeDef and impl.len >= 3 and impl[2].kind != nnkRefTy:
        paramTyp = newNimNode(nnkVarTy).add(paramTyp)

    result = newProc(name, [newEmptyNode(), newIdentDefs(v, paramTyp), newIdentDefs(s, serTyp)])

    if not phantomTyp.isNil and phantomTyp.kind != nnkEmpty:
        result.body.add(phantomTyp)
        let pv = quote do:
            var `phantomIdent`: Phantom
        result.body.add(pv)

        if serialize and not skipPhantom:
            result.body.add(newCall("toPhantom", v, phantomIdent))

    for p in typdesc.serializablePropertyDescs:
        let visitCall = newCall(!"visit", s, actualReference(p))
        if keyed: visitCall.add(p.serializationKey())

        if p.hasAttr("combinedWith"):
            let p1 = typdesc.propertyDescWithName($p.attributes["combinedWith"])
            visitCall.add(actualReference(p1))
            if keyed: visitCall.add(p1.serializationKey())

        # if keyed and not serialize and not bin and p.hasAttr("default"):
        #     visitCall.add(p.attributes["default"])

        result.body.add(visitCall)
        # let echoPrefix = newLit($serTyp & " " & p.name & ": ")
        # let echoValue = actualReference(p)
        # result.body.add quote do:
        #     when compiles(echo(`echoPrefix`, `echoValue`)):
        #         echo `echoPrefix`, `echoValue`
        #     else:
        #         echo `echoPrefix`, "..."

    if not phantomTyp.isNil and phantomTyp.kind != nnkEmpty:
        if not serialize and not skipPhantom:
            result.body.add(newCall("fromPhantom", v, phantomIdent))

    if not serialize:
        result.body.add quote do:
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
        genSerializerProc(c, serializeAux, BinSerializer, false, true, true, false)
        genSerializerProc(c, deserializeAux, JsonDeserializer, true, false, false, false)
        genSerializerProc(c, serializeAux, JsonSerializer, true, true, false, false)
        genSerializerProc(c, calcSerializationHashAux, SerializationHashCalculator, true, true, false, true)

        method deserialize*(cm: c, b: JsonDeserializer) =
            deserializeAux(cm, b)

        method serialize*(cm: c, b: JsonSerializer) =
            b.visit(className(cm), "_c")
            serializeAux(cm, b)

        method serialize*(cm: c, b: BinSerializer) =
            serializeAux(cm, b)

        method serializationHash*(cm: c, b: SerializationHashCalculator) =
            calcSerializationHashAux(cm, b)

    method supportsNewSerialization*(cm: c): bool = true

    genSerializerProc(c, deserializeAux, BinDeserializer, false, false, true, false)

    method deserialize*(cm: c, b: BinDeserializer) =
        deserializeAux(cm, b)

template genJsonSerializationrFor*(c: typed) =
    import rod / utils / [ json_deserializer, json_serializer, serialization_hash_calculator ]

    genSerializerProc(c, deserializeAux, JsonDeserializer, true, false, false, false)
    genSerializerProc(c, serializeAux, JsonSerializer, true, true, false, false)

    proc toJson*(cm: c): JsonNode=
        var b = newJsonSerializer()
        serializeAux(cm, b)
        result = b.node

    proc `to c`*(jn: JsonNode): c =
        var b = newJsonDeserializer()
        b.node = jn
        when c is ref:
            result.new()
        deserializeAux(result, b)
