import json, strutils, tables, parseutils, logging
import nimx / [ types, matrixes, animation, property_visitor ]

import variant
import rod.node, rod.component, rod.animation.animation_sampler, rod.quaternion
import rod.utils.bin_deserializer

export animation

type
    AnimatedProperty* = ref object
        nodeName*, propName*: string
        compIndex*: int
        sampler*: AbstractAnimationSampler
        scale*: float
        progressSetter*: proc(p: float)

    PropertyAnimation* = ref object of Animation
        animatedProperties*: seq[AnimatedProperty]
        b: BinDeserializer # Used for holding the sampler buffers alive.

template elementFromJson(t: typedesc[Quaternion], jelem: JsonNode): Quaternion = Quaternion(newVector4(jelem[0].getFloat(), jelem[1].getFloat(), jelem[2].getFloat(), jelem[3].getFloat()))
template elementFromJson(t: typedesc[Coord], jelem: JsonNode): Coord = jelem.getFloat()
template elementFromJson(t: typedesc[Vector2], jelem: JsonNode): Vector2 = newVector2(jelem[0].getFloat(), jelem[1].getFloat())
template elementFromJson(t: typedesc[Vector3], jelem: JsonNode): Vector3 = newVector3(jelem[0].getFloat(), jelem[1].getFloat(), jelem[2].getFloat())
template elementFromJson(t: typedesc[Vector4], jelem: JsonNode): Vector4 = newVector4(jelem[0].getFloat(), jelem[1].getFloat(), jelem[2].getFloat(), jelem[3].getFloat())
template elementFromJson(t: typedesc[Color], jelem: JsonNode): Color = newColor(jelem[0].getFloat(), jelem[1].getFloat(), jelem[2].getFloat(), jelem[3].getFloat(1))
template elementFromJson(t: typedesc[int], jelem: JsonNode): int = jelem.getInt()
template elementFromJson(t: typedesc[int16], jelem: JsonNode): int16 = jelem.getInt().int16
template elementFromJson(t: typedesc[bool], jelem: JsonNode): bool = jelem.getBool()

proc splitPropertyName(name: string, nodeName: var string, compIndex: var int, propName: var string) =
    # A property name can one of the following:
    # nodeName.propName # looked up in node first, then in first met component
    # nodeName.compIndex.propName # looked up only in specified component
    propName = name
    compIndex = -1
    nodeName = nil
    let dotIdx2 = name.rfind('.')
    if dotIdx2 != -1:
        propName = name.substr(dotIdx2 + 1)
        let dotIdx1 = name.rfind('.', dotIdx2 - 1)
        if dotIdx1 == -1:
            nodeName = name.substr(0, dotIdx2 - 1)
        elif name[dotIdx1 + 1].isDigit:
            discard parseInt(name, compIndex, dotIdx1 + 1)
            nodeName = name.substr(0, dotIdx1 - 1)
        else:
            nodeName = name.substr(0, dotIdx2 - 1)

    propName = case propName
    of "Rotation": "rotation"
    of "X Position": "tX"
    of "Y Position": "tY"
    of "Position": "translation"
    of "Scale": "scale"
    of "Opacity": "alpha"
    of "Input White": "inWhite"
    of "Input Black": "inBlack"
    of "Gamma": "inGamma"
    of "Output White": "outWhite"
    of "Output Black": "outBlack"
    else: propName

when false:
    static:
        block:
            var nn, pn: string
            var ci: int
            splitPropertyName("myNode.12.myProp", nn, ci, pn)
            assert(nn == "myNode" and pn == "myProp" and ci == 12)

            splitPropertyName("myNode.png.myProp", nn, ci, pn)
            assert(nn == "myNode.png" and pn == "myProp" and ci == -1)

            splitPropertyName("myNode.myProp", nn, ci, pn)
            assert(nn == "myNode" and pn == "myProp" and ci == -1)

            splitPropertyName("myProp", nn, ci, pn)
            assert(nn == nil and pn == "myProp" and ci == -1)

proc newValueSampler[T](j: JsonNode, lerpBetweenFrames: bool, originalLen, cutFront: int): ArrayAnimationSampler[T] {.inline.} =
    var vals = newSeq[T](j.len)
    shallow(vals)
    var i = 0
    for v in j:
        vals[i] = elementFromJson(T, v)
        inc i
    result = newArrayAnimationSampler(vals, lerpBetweenFrames, originalLen, cutFront)

proc newValueSampler[T](b: BinDeserializer, numValues: int16, lerpBetweenFrames: bool, originalLen, cutFront: int): AbstractAnimationSampler {.inline.} =
    let buf = b.getBuffer(T, numValues)
    result = newBufferAnimationSampler[T, BufferView[T]](buf, lerpBetweenFrames, originalLen, cutFront)

template switchAnimatableTypeId*(t: TypeId, clause: untyped, action: untyped): typed =
    ## This lists all animatable types
    case t:
    of clause(Coord): action(Coord)
    of clause(Vector2): action(Vector2)
    of clause(Vector3): action(Vector3)
    of clause(Vector4): action(Vector4)
    of clause(Quaternion): action(Quaternion)
    of clause(Color): action(Color)
    of clause(int): action(int)
    of clause(int16): action(int16)
    of clause(bool): action(bool)
    else:
        raise newException(Exception, "Unknown type id")

proc newValueSampler(t: TypeId, j: JsonNode, lerpBetweenFrames: bool): AbstractAnimationSampler =
    template makeSampler(T: typedesc) =
        result = newValueSampler[T](j, lerpBetweenFrames, -1, -1)
    switchAnimatableTypeId(t, getTypeId, makeSampler)

proc newValueSampler(t: TypeId, b: BinDeserializer, numValues: int16, lerpBetweenFrames: bool): AbstractAnimationSampler =
    template makeSampler(T: typedesc) =
        result = newValueSampler[T](b, numValues, lerpBetweenFrames, -1, -1)
    switchAnimatableTypeId(t, getTypeId, makeSampler)

proc newValueSampler(t: TypeId, b: BinDeserializer, numValues: int16, lerpBetweenFrames: bool, originalLen, cutFront: int): AbstractAnimationSampler =
    template makeSampler(T: typedesc) =
        result = newValueSampler[T](b, numValues, lerpBetweenFrames, originalLen, cutFront)
    switchAnimatableTypeId(t, getTypeId, makeSampler)

proc newValueSampler(t: TypeId, j:JsonNode, lerpBetweenFrames: bool, originalLen, cutFront: int): AbstractAnimationSampler=
    template makeSampler(T: typedesc) =
        result = newValueSampler[T](j, lerpBetweenFrames, originalLen, cutFront)

    switchAnimatableTypeId(t, getTypeId, makeSampler)

proc newKeyframeSampler[T](j: JsonNode): BezierKeyFrameAnimationSampler[T] {.inline.} =
    var keys = newSeq[BezierKeyFrame[T]](j.len)
    shallow(keys)
    var i = 0
    for v in j:
        keys[i].v = elementFromJson(T, v["v"])
        keys[i].p = v["p"].getFloat()
        let ie = v["ie"]
        keys[i].inX = ie[0].getFloat()
        keys[i].inY = ie[1].getFloat()
        let oe = v["oe"]
        keys[i].outX = oe[0].getFloat()
        keys[i].outY = oe[1].getFloat()
        inc i
    result = newBezierKeyFrameAnimationSampler[T](keys)

proc newKeyframeSampler(t: TypeId, j: JsonNode): AbstractAnimationSampler =
    template makeSampler(T: typedesc) =
        result = newKeyframeSampler[T](j)
    switchAnimatableTypeId(t, getTypeId, makeSampler)

proc typeIdForSetterAndGetter(ap: Variant): TypeId =
    template getSetterAndGetterTypeId(T: typedesc): TypeId = getTypeId(SetterAndGetter[T])
    template action(T: typedesc) = result = getTypeId(T)
    switchAnimatableTypeId(ap.typeId, getSetterAndGetterTypeId, action)

template findAnimatablePropertyAux(body: untyped) =
    var res {.inject.} : Variant
    var visitor {.inject.} : PropertyVisitor
    visitor.requireName = true
    visitor.requireSetter = true
    visitor.flags = { pfAnimatable }
    visitor.commit = proc() =
        if res.isEmpty:
            if visitor.name == propName:
                res = visitor.setterAndGetter

    body

    result = res

proc findAnimatableProperty*(n: Node, propName: string): Variant =
    findAnimatablePropertyAux:
        n.visitProperties(visitor)

        if res.isEmpty and not n.components.isNil:
            for k, v in n.components:
                v.visitProperties(visitor)
                if not res.isEmpty: break

proc findAnimatableProperty(n: Node, compIndex: int, propName: string): Variant =
    findAnimatablePropertyAux:
        if not n.components.isNil and n.components.len > compIndex:
            n.components[compIndex].visitProperties(visitor)

proc findAnimatablePropertyForSubtree*(n: Node, nodeName: string, compIndex: int, rawPropName: string): Variant =
    var animatedNode = n
    if not nodeName.isNil:
        animatedNode = n.findNode(nodeName)
        if animatedNode.isNil:
            raise newException(Exception, "Animated node " & nodeName & " not found")

    if compIndex == -1:
        result = findAnimatableProperty(animatedNode, rawPropName)
    else:
        result = findAnimatableProperty(animatedNode, compIndex, rawPropName)
    if result.isEmpty:
        raise newException(Exception, "Animated property not found: " & nodeName & "." & $compIndex & "." & rawPropName)

proc makeProgressSetter*(sng: Variant, s: AbstractAnimationSampler): proc(p: float) =
    template makeSetter(T: typedesc) =
        let setter = sng.get(SetterAndGetter[T]).setter
        let sampler = AnimationSampler[T](s)
        result = proc(p: float) =
            setter(sampler.sample(p))
    template getSetterAndGetterTypeId(T: typedesc): TypeId = getTypeId(SetterAndGetter[T])
    switchAnimatableTypeId(sng.typeId, getSetterAndGetterTypeId, makeSetter)

proc newPropertyAnimation*(n: Node, j: JsonNode): PropertyAnimation =
    result.new()
    result.init()
    result.animatedProperties = @[]
    shallow(result.animatedProperties)

    result.loopDuration = 0.0 # TODO: Hack - remove
    for k, jp in j:
        result.loopDuration = max(jp["duration"].getFloat(), result.loopDuration) # TODO: Hack - remove
        result.numberOfLoops = jp{"numberOfLoops"}.getInt(1) # TODO: Hack - remove
        var animScale = 1.0
        if "animScale" in jp:
            animScale = 1.0 / jp["animScale"].getFloat()

        var ap: AnimatedProperty
        ap.new()

        var nodeName, rawPropName: string
        var compIndex: int
        splitPropertyName(k, nodeName, compIndex, rawPropName)

        ap.nodeName = nodeName
        ap.propName = rawPropName
        ap.compIndex = compIndex
        ap.scale = animScale
        let sng = findAnimatablePropertyForSubtree(n, nodeName, compIndex, rawPropName)
        var t: TypeId
        try:
            t = typeIdForSetterAndGetter(sng)
        except:
            warn "Wrong type of animated property ", k
            raise

        if "keys" in jp:
            ap.sampler = newKeyframeSampler(t, jp["keys"])
        elif "cutf" in jp:
            let lerp = jp{"frameLerp"}.getBool(true)
            let olen = jp{"len"}.getInt(-1)
            let cutf = jp{"cutf"}.getInt(-1)
            ap.sampler = newValueSampler(t, jp["values"], lerp, olen, cutf)
        else:
            ap.sampler = newValueSampler(t, jp["values"], jp{"frameLerp"}.getBool(true))

        ap.progressSetter = makeProgressSetter(sng, ap.sampler)

        result.animatedProperties.add(ap)

    let res = result
    result.onAnimate = proc(p: float) =
        for ap in res.animatedProperties:
            ap.progressSetter(p * ap.scale)

proc newPropertyAnimation*(n: Node, b: BinDeserializer, aeComp: bool): PropertyAnimation =
    result.new()
    result.init()
    result.b = b # Used for holding the sampler buffers alive.

    let propsCount = b.readInt16()
    result.animatedProperties = newSeq[AnimatedProperty](propsCount)
    shallow(result.animatedProperties)

    if not aeComp:
        result.loopDuration = b.readFloat32()
        result.numberOfLoops = b.readInt16()

    for i in 0 ..< propsCount:
        # TODO: Handle animScale
        let nodeName = b.readStr()
        let propName = b.readStr()

        var ap: AnimatedProperty
        ap.new()
        ap.nodeName = nodeName
        ap.propName = propName
        # echo "k: ", nodeName, ".", propName
        ap.compIndex = -1
        ap.scale = 1.0
        let sng = findAnimatablePropertyForSubtree(n, nodeName, -1, propName)
        var t: TypeId
        try:
            t = typeIdForSetterAndGetter(sng)
        except:
            warn "Wrong type of animated property ", nodeName, ".", propName
            raise

        let frameLerp = bool(b.readUint8())

        var cutf = -1
        var olen = -1

        if aeComp:
            olen = b.readInt16()
            cutf = b.readInt16()

        let numValues = b.readInt16()

        # if "keys" in jp:
        #     ap.sampler = newKeyframeSampler(t, jp["keys"])
        # elif "cutf" in jp:
        #     let lerp = jp{"frameLerp"}.getBool(true)
        #     let olen = jp{"len"}.getInt(-1).int
        #     let cutf = jp{"cutf"}.getInt(-1).int
        #     ap.sampler = newValueSampler(t, jp["values"], lerp, olen, cutf)
        # else:

        if aeComp:
            ap.sampler = newValueSampler(t, b, numValues, frameLerp, olen, cutf)
        else:
            ap.sampler = newValueSampler(t, b, numValues, frameLerp)

        ap.progressSetter = makeProgressSetter(sng, ap.sampler)

        result.animatedProperties[i] = ap

    let res = result
    result.onAnimate = proc(p: float) =
        for ap in res.animatedProperties:
            ap.progressSetter(p * ap.scale)

proc attachToNode*(pa: PropertyAnimation, n: Node) =
    for ap in pa.animatedProperties:
        let sng = findAnimatablePropertyForSubtree(n, ap.nodeName, ap.compIndex, ap.propName)
        ap.progressSetter = makeProgressSetter(sng, ap.sampler)

    pa.onAnimate = proc(p: float) =
        for ap in pa.animatedProperties: ap.progressSetter(p)

proc copyForNode*(pa: PropertyAnimation, n: Node): PropertyAnimation =
    result.new()
    result[] = pa[]
    result.attachToNode(n)
