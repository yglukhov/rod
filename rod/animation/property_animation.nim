import json, strutils, tables, parseutils
import nimx.types, nimx.matrixes, nimx.system_logger
import nimx.animation
import nimx.property_visitor

import variant
import rod.node, rod.component, rod.animation.animation_sampler

export animation

type
    AnimatedProperty* = ref object
        name*: string
        sampler*: AbstractAnimationSampler
        progressSetter*: proc(p: float)

    PropertyAnimation* = ref object of Animation
        animatedProperties*: seq[AnimatedProperty]

template elementFromJson(t: typedesc[Coord], jelem: JsonNode): Coord = jelem.getFNum()
template elementFromJson(t: typedesc[Vector2], jelem: JsonNode): Vector2 = newVector2(jelem[0].getFNum(), jelem[1].getFNum())
template elementFromJson(t: typedesc[Vector3], jelem: JsonNode): Vector3 = newVector3(jelem[0].getFNum(), jelem[1].getFNum(), jelem[2].getFNum())
template elementFromJson(t: typedesc[Vector4], jelem: JsonNode): Vector4 = newVector4(jelem[0].getFNum(), jelem[1].getFNum(), jelem[2].getFNum(), jelem[3].getFNum())
template elementFromJson(t: typedesc[Color], jelem: JsonNode): Color = newColor(jelem[0].getFNum(), jelem[1].getFNum(), jelem[2].getFNum(), jelem[3].getFNum(1))
template elementFromJson(t: typedesc[int], jelem: JsonNode): int = jelem.getNum().int

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

proc newValueSampler[T](j: JsonNode, lerpBetweenFrames: bool): ArrayAnimationSampler[T] {.inline.} =
    var vals = newSeq[T](j.len)
    shallow(vals)
    var i = 0
    for v in j:
        vals[i] = elementFromJson(T, v)
        inc i
    result = newArrayAnimationSampler[T](vals, lerpBetweenFrames)

template switchAnimatableTypeId*(t: TypeId, clause: untyped, action: untyped): typed =
    ## This lists all animatable types
    case t:
    of clause(Coord): action(Coord)
    of clause(Vector2): action(Vector2)
    of clause(Vector3): action(Vector3)
    of clause(Vector4): action(Vector4)
    of clause(Color): action(Color)
    of clause(int): action(int)
    else:
        raise newException(Exception, "Unknown type id")

proc newValueSampler(t: TypeId, j: JsonNode, lerpBetweenFrames: bool): AbstractAnimationSampler =
    template makeSampler(T: typedesc) =
        result = newValueSampler[T](j, lerpBetweenFrames)
    switchAnimatableTypeId(t, getTypeId, makeSampler)

proc newKeyframeSampler[T](j: JsonNode): BezierKeyFrameAnimationSampler[T] {.inline.} =
    var keys = newSeq[BezierKeyFrame[T]](j.len)
    shallow(keys)
    var i = 0
    for v in j:
        keys[i].v = elementFromJson(T, v["v"])
        keys[i].p = v["p"].getFNum()
        let ie = v["ie"]
        keys[i].inX = ie[0].getFNum()
        keys[i].inY = ie[1].getFNum()
        let oe = v["oe"]
        keys[i].outX = oe[0].getFNum()
        keys[i].outY = oe[1].getFNum()
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

proc findAnimatablePropertyForSubtree*(n: Node, propName: string): Variant =
    var nodeName, rawPropName: string
    var compIndex: int
    splitPropertyName(propName, nodeName, compIndex, rawPropName)
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
        raise newException(Exception, "Animated property not found: " & propName)

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
        result.loopDuration = max(jp["duration"].getFNum(), result.loopDuration) # TODO: Hack - remove
        result.numberOfLoops = jp{"numberOfLoops"}.getNum(1).int # TODO: Hack - remove

        var ap: AnimatedProperty
        ap.new()
        ap.name = k
        let sng = findAnimatablePropertyForSubtree(n, k)
        var t: TypeId
        try:
            t = typeIdForSetterAndGetter(sng)
        except:
            logi "Wrong type of animated property ", k
            raise

        if "keys" in jp:
            ap.sampler = newKeyframeSampler(t, jp["keys"])
        else:
            ap.sampler = newValueSampler(t, jp["values"], jp{"frameLerp"}.getBVal(true))

        ap.progressSetter = makeProgressSetter(sng, ap.sampler)
        result.animatedProperties.add(ap)

    let res = result
    result.onAnimate = proc(p: float) =
        for ap in res.animatedProperties: ap.progressSetter(p)

proc attachToNode*(pa: PropertyAnimation, n: Node) =
    for ap in pa.animatedProperties:
        let sng = findAnimatablePropertyForSubtree(n, ap.name)
        ap.progressSetter = makeProgressSetter(sng, ap.sampler)

    pa.onAnimate = proc(p: float) =
        for ap in pa.animatedProperties: ap.progressSetter(p)

proc copyForNode*(pa: PropertyAnimation, n: Node): PropertyAnimation =
    result.new()
    result[] = pa[]
    result.attachToNode(n)
