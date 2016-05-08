import json, math, strutils, tables

import variant

import rod_types
import node
import component
import property_visitor

import nimx.matrixes
import nimx.types
import nimx.animation

proc rawPropertyNameFromPropertyName(name: string): string =
    var n = name
    let dotIdx = name.rfind('.')
    if dotIdx != -1:
        n = name.substr(dotIdx + 1)
    result = case n
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
    else: n

proc nodeNameFromPropertyName(name: string): string =
    let dotIdx = name.rfind('.')
    if dotIdx != -1:
        result = name.substr(0, dotIdx - 1)

template elementFromJson(t: typedesc[Coord], jelem: JsonNode): Coord = jelem.getFNum()
template elementFromJson(t: typedesc[Vector2], jelem: JsonNode): Vector2 = newVector2(jelem[0].getFNum(), jelem[1].getFNum())
template elementFromJson(t: typedesc[Vector3], jelem: JsonNode): Vector3 = newVector3(jelem[0].getFNum(), jelem[1].getFNum(), jelem[2].getFNum())
template elementFromJson(t: typedesc[Vector4], jelem: JsonNode): Vector4 = newVector4(jelem[0].getFNum(), jelem[1].getFNum(), jelem[2].getFNum(), jelem[3].getFNum())
template elementFromJson(t: typedesc[int], jelem: JsonNode): int = jelem.getNum().int

type AnimProcSetter = proc(progress: float)

proc findAnimatableProperty(n: Node, propName: string): Variant =
    var res : Variant
    var visitor : PropertyVisitor
    visitor.requireName = true
    visitor.requireSetter = true
    visitor.flags = { pfAnimatable }
    visitor.commit = proc() =
        if res.isEmpty:
            if visitor.name == propName:
                res = visitor.setterAndGetter

    n.visitProperties(visitor)

    if res.isEmpty and not n.components.isNil:
        for k, v in n.components:
            v.visitProperties(visitor)
            if not res.isEmpty: break

    result = res

proc createProgressSetterWithPropSetter[T](setter: proc(v: T), janim: JsonNode): AnimProcSetter =
    let jVals = janim["values"]
    var propValues = newSeq[T](jVals.len)
    for i in 0 ..< propValues.len:
        propValues[i] = elementFromJson(T, jVals[i])

    let fromValue = 0.0
    let toValue = (propValues.len - 1).float
    let doLerp = janim{"frameLerp"}.getBVal(true)

    result = proc(p: float) =
        let i = interpolate(fromValue, toValue, p)
        let index = floor(i).int
        if not doLerp or index == propValues.len - 1:
            #echo "i: ", index, " p: ", p
            setter(propValues[index])
        else:
            let m = i mod 1.0
            #echo "i: ", index, " m: ", m, " p: ", p
            setter(interpolate(propValues[index], propValues[index + 1], m))

proc createProgressSetter(propName: string, node: Node2D, janim: JsonNode): AnimProcSetter =
    let rawPropName = rawPropertyNameFromPropertyName(propName)
    let nodeName = nodeNameFromPropertyName(propName)
    let animatedNode = if nodeName.isNil: node else: node.findNode(nodeName)
    if animatedNode.isNil:
        raise newException(Exception, "Animated node " & nodeName & " not found")

    let ap = animatedNode.findAnimatableProperty(rawPropName)
    if ap.isEmpty:
        raise newException(Exception, "Property " & rawPropName & " not found in node " & animatedNode.name)

    variantMatch case ap as sng
    of SetterAndGetter[Coord]: result = createProgressSetterWithPropSetter(sng.setter, janim)
    of SetterAndGetter[Vector2]: result = createProgressSetterWithPropSetter(sng.setter, janim)
    of SetterAndGetter[Vector3]: result = createProgressSetterWithPropSetter(sng.setter, janim)
    of SetterAndGetter[Vector4]: result = createProgressSetterWithPropSetter(sng.setter, janim)
    of SetterAndGetter[int]: result = createProgressSetterWithPropSetter(sng.setter, janim)
    else:
        raise newException(Exception, "Wrong type for property " & rawPropName & " of node " & animatedNode.name)

proc animationWithAEJson*(n: Node2D, j: JsonNode): Animation =
    var animProgressSetters = newSeq[AnimProcSetter]()
    var maxDuration = 0.0
    var numberOfLoops = 1
    result = newAnimation()
    result.loopDuration = 0.0

    for k, v in j:
        result.loopDuration = max(v["duration"].getFNum(), result.loopDuration)
        result.numberOfLoops = v{"numberOfLoops"}.getNum(1).int
        let progressSetter = createProgressSetter(k, n, v)
        if not progressSetter.isNil:
            animProgressSetters.add(progressSetter)

    result.onAnimate = proc(progress: float) =
        for ps in animProgressSetters:
            ps(progress)
