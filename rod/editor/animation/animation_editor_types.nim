import nimx / [ types, matrixes, animation, property_visitor ]
import rod/animation/[animation_sampler, property_animation], rod / [ quaternion, rod_types ]
import rod / utils / [ json_deserializer, json_serializer ]
import rod / node
import algorithm
import variant, tables, json, math, strutils

type
    EInterpolationKind* = enum
        eiLinear
        eiBezier
        # eiDiscrete #should be in property
        eiPresampled

    EInterpolation* = object
        case kind*: EInterpolationKind
        of eiBezier:
            points*: array[4, float]
        else:
            discard

    EditedKey* = ref object
        property*: EditedProperty
        position*: Coord
        value*: Variant
        interpolation*: EInterpolation

    EditedProperty* = ref object
        duration: float 
        enabled*: bool
        rawName: string #nodeName.componentIndex.componentProperty, nodeName.nodeProperty, etc
        node: Node
        sng*: Variant
        keys*: seq[EditedKey]

    EditedAnimation* = ref object 
        fps*: int
        name*: string
        duration*: float
        properties*: seq[EditedProperty]

proc name*(e: EditedProperty): string =
    if not e.node.isNil:
        result = e.node.name
    result &= e.rawName

proc newEditedProperty*(n: Node, name: string, sng: Variant): EditedProperty =
    result.new()
    result.rawName = name
    result.sng = sng
    result.node = n
    result.enabled = true

proc sortKeys*(p: EditedProperty)=
    p.keys.sort() do(a, b: EditedKey) -> int:
        cmp(a.position, b.position)

proc addKeyAtPosition*(p: EditedProperty, pos: Coord) =
    var k = new(EditedKey)
    k.property = p
    k.position = pos

    template getKeyValue(T: typedesc) =
        let val = p.sng.get(SetterAndGetter[T]).getter()
        k.value = newVariant(val)
    template getSetterAndGetterTypeId(T: typedesc): TypeId = getTypeId(SetterAndGetter[T])
    switchAnimatableTypeId(p.sng.typeId, getSetterAndGetterTypeId, getKeyValue)
    p.keys.add(k)

    p.sortKeys()

proc keyAtIndex*(e: EditedProperty, ki: int): EditedKey =
    if ki >= 0 and ki < e.keys.len:
        return e.keys[ki]

proc propertyAtIndex*(e: EditedAnimation, pi: int): EditedProperty =
    if pi >= 0 and pi < e.properties.len:
        return e.properties[pi]

proc keyAtIndex*(e: EditedAnimation, pi, ki: int): EditedKey =
    let p = e.propertyAtIndex(pi)
    if p.isNil: return
    result = p.keyAtIndex(ki)
 
template keyValue(k: EditedKey, body: untyped) =
    template getKeyValueAUX(T: typedesc) =
        let value{.inject} = k.value.get(T)
        body
    switchAnimatableTypeId(k.value.typeId, getTypeId, getKeyValueAUX)

#todo: remove this serialization
proc `%`(q: Quaternion): JsonNode = 
    result = newJArray()
    result.add(%q.x)
    result.add(%q.y)
    result.add(%q.z)
    result.add(%q.w)

proc `%`(q: Color): JsonNode = 
    result = newJArray()
    result.add(%q.r)
    result.add(%q.g)
    result.add(%q.b)
    result.add(%q.a)

proc `%`*(a: EditedAnimation): JsonNode = 
    result = newJObject()
    var meta = newJObject()

    var ser = newJsonSerializer()
    ser.node = meta
    ser.visit(a.duration, "duration")
    ser.visit(a.name, "name")
    ser.visit(a.fps, "fps")
    # meta["duration"] = %a.duration
    # meta["name"] = %a.name
    # meta["fps"] = %a.fps
    result["rodedit$metadata"] = meta

    for prop in a.properties:
        if not prop.enabled: continue
        var jp = newJObject()

        jp["duration"] = %a.duration
        var keys = newJArray()
        
        # dye to backward compatibility
        # we should save presampled buffers
        # by `values` key
        var isPresampled: bool 
        for k in prop.keys: 
            if k.interpolation.kind == eiPresampled:
                isPresampled = true
                break
        
        if not isPresampled:
            for k in prop.keys:
                var jk = newJobject()
                ser.node = jk
                ser.visit(k.position, "p")
                # jk["p"] = %k.position
                k.keyValue:
                    ser.visit(value, "v")
                    # jk["v"] = %value
                ser.visit(k.interpolation.kind, "i")
                # jk["i"] = %($k.interpolation.kind)
                if k.interpolation.kind == eiBezier:
                    ser.visit(k.interpolation.points, "f")
                    # jk["f"] = %k.interpolation.points
                keys.add(jk)

            jp["keys"] = keys
        else:
            var values = newJArray()
            for k in prop.keys:
                k.keyValue:
                    values.add(%value)
            jp["values"] = values
        result[prop.name] = jp

proc sampleRate*(a: EditedAnimation): int =
    ceil(a.fps.float * a.duration).int

proc toEditedProperty(n: Node, k:string, j: JsonNode): EditedProperty =
    var nodeName, rawPropName: string
    var compIndex: int
    splitPropertyName(k, nodeName, compIndex, rawPropName)
    let sng = findAnimatablePropertyForSubtree(n, nodeName, compIndex, rawPropName)

    var pname = k
    pname.removePrefix(nodeName)
    result = newEditedProperty(n.findNode(nodeName), pname, sng)
    var des = newJsonDeserializer()
    if "keys" in j:
        for jk in j["keys"]:
            des.node = jk
            var key = new(EditedKey)
            key.property = result
            key.position = jk["p"].getFloat(0.0)
            key.interpolation = EInterpolation(
                kind: parseEnum[EInterpolationKind](jk["i"].getStr(""))
                )
            if key.interpolation.kind == eiBezier:
                key.interpolation.points = to(jk["f"], array[4, float])
            result.keys.add(key)

            template getKeyValue(T: typedesc) =
                # var val : (when T is int: int32 else: T)
                var val: T
                des.visit(val, "v")
                key.value = newVariant(T(val)) #disable ConvFromXtoItselfNotNeeded
            template getSetterAndGetterTypeId(T: typedesc): TypeId = getTypeId(SetterAndGetter[T])
            switchAnimatableTypeId(sng.typeId, getSetterAndGetterTypeId, getKeyValue)
    elif "values" in j:
        des.node = j
        template getKeyValue(T: typedesc) =
            # var values: (when T is int: seq[int32] else: seq[T])
            var values: seq[T]
            des.visit(values, "values")
            for i, v in values:
                var k = new(EditedKey)
                k.value = newVariant(T(v)) #disable ConvFromXtoItselfNotNeeded
                k.position = i / values.len
                k.interpolation = EInterpolation(kind: eiPresampled)
                k.property = result
                result.keys.add(k)
            var dur: float32
            des.visit(dur, "duration")
            result.duration = dur
        template getSetterAndGetterTypeId(T: typedesc): TypeId = getTypeId(SetterAndGetter[T])
        switchAnimatableTypeId(sng.typeId, getSetterAndGetterTypeId, getKeyValue)

proc toEditedAnimation*(n: Node, j: JsonNode): EditedAnimation =
    var a = new(EditedAnimation)
    for k, v in j:
        if k == "rodedit$metadata":
            a.fps = v{"fps"}.getInt(25)
            a.name = v{"name"}.getStr("")
            a.duration = v{"duration"}.getFloat(1.0)
            continue
        echo "toEditedAnimation ", k, " " , v
        a.properties.add(n.toEditedProperty(k, v))
    if a.fps == 0 and a.properties.len > 0:
        a.duration = a.properties[0].duration
        a.fps = int(a.properties[0].keys.len.float / a.duration)
    result = a


