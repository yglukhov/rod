import json
import node
import math
import strutils

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
    else: nil

proc nodeNameFromPropertyName(name: string): string =
    let dotIdx = name.rfind('.')
    if dotIdx != -1:
        result = name.substr(0, dotIdx - 1)

proc numberOfComponentsInPropertyAnimation(janim: JsonNode): int =
    let firstVal = janim["values"][0]
    if firstVal.kind == JArray:
        result = firstVal.len
    else:
        result = 1

proc createElementFromJson(componentsCount: static[int], jelem: JsonNode): auto {.inline.} =
    when componentsCount == 1:
        return jelem.getFNum()
    elif componentsCount == 2:
        return newVector2(jelem[0].getFNum(), jelem[1].getFNum())
    elif componentsCount == 3:
        return newVector3(jelem[0].getFNum(), jelem[1].getFNum(), jelem[2].getFNum())
    elif componentsCount == 4:
        return newVector4(jelem[0].getFNum(), jelem[1].getFNum(), jelem[2].getFNum(), jelem[3].getFNum())

type AnimProcSetter = proc(progress: float)

proc createProgressSetter(componentsCount: static[int], propName: string, node: Node2D, janim: JsonNode): AnimProcSetter =
    let rawPropName = rawPropertyNameFromPropertyName(propName)
    if rawPropName.isNil:
        echo "Unknown property name: ", propName
        return

    let nodeName = nodeNameFromPropertyName(propName)
    let animatedNode = if nodeName.isNil: node else: node.findNode(nodeName)
    if animatedNode.isNil:
        raise newException(Exception, "Animated node " & nodeName & " not found")

    when componentsCount == 1:
        let setter = animatedNode.animatableProperty1(rawPropName)
        type ElementType = Coord
    elif componentsCount == 2:
        let setter = animatedNode.animatableProperty2(rawPropName)
        type ElementType = Vector2
    elif componentsCount == 3:
        let setter = animatedNode.animatableProperty3(rawPropName)
        type ElementType = Vector3
    elif componentsCount == 4:
        let setter = animatedNode.animatableProperty4(rawPropName)
        type ElementType = Vector4

    if setter.isNil: return

    var propValues = newSeq[ElementType](janim["values"].len)
    for i in 0 ..< propValues.len:
        let p = createElementFromJson(componentsCount, janim["values"][i])
        propValues[i] = p

    let fromValue = 0.0
    let toValue = (propValues.len - 1).float

    result = proc(p: float) =
        let i = interpolate(fromValue, toValue, p)
        let index = floor(i).int
        var doInter = true
        if not doInter or index == propValues.len - 1:
            #echo "i: ", index, " p: ", p
            setter(propValues[index])
        else:
            let m = i mod 1.0
            #echo "i: ", index, " m: ", m, " p: ", p
            setter(interpolate(propValues[index], propValues[index + 1], m))

proc animationWithAEJson*(n: Node2D, j: JsonNode): Animation =
    var animProgressSetters = newSeq[AnimProcSetter]()
    var maxDuration = 0.0
    var numberOfLoops = 1
    result = newAnimation()

    for k, v in j:
        let numComponents = numberOfComponentsInPropertyAnimation(v)
        result.loopDuration = max(v["duration"].getFNum(), result.loopDuration)
        result.numberOfLoops = v["numberOfLoops"].getNum(1).int

        let progressSetter = case numComponents
            of 1: createProgressSetter(1, k, n, v)
            of 2: createProgressSetter(2, k, n, v)
            of 3: createProgressSetter(3, k, n, v)
            of 4: createProgressSetter(4, k, n, v)
            else: nil
        if not progressSetter.isNil:
            animProgressSetters.add(progressSetter)

    result.onAnimate = proc(progress: float) =
        for ps in animProgressSetters:
            ps(progress)

when isMainModule:
    const animationDesc = """
    {"Rotation":
        [{"startTime":0,"duration":0.16666666666667,"fromVal":0,"toVal":92.9539584341366,"curve":[0.3333333296019,0,0.6666666662038,0.79667353251109]},{"startTime":0.16666666666667,"duration":0.16666666666667,"fromVal":92.9539584341366,"toVal":180,"curve":[0.33333333514219,0.21712647403433,0.34473542612829,0.60945983926938]},{"startTime":0.33333333333333,"duration":0.16666666666667,"fromVal":180,"toVal":270,"curve":[0.33333333,0,0.83333333333,1]}],"Y Position":[{"startTime":0,"duration":0.16666666666667,"fromVal":119.169956414826,"toVal":427.629326523066,"curve":[0.16666666667,0.16666666667,0.47421546190059,0.98856700061538]},{"startTime":0.16666666666667,"duration":0.16666666666667,"fromVal":427.629326523066,"toVal":179.999996984884,"curve":[0.75861955683165,-0.02054812928642,0.69528072524973,1.0001519218422]},{"startTime":0.33333333333333,"duration":0.16666666666667,"fromVal":179.999996984884,"toVal":450.359375,"curve":[1,0.00045664734309,0.50793092234762,1.69733528354543]},{"startTime":0.5,"duration":0.1,"fromVal":450.359375,"toVal":303.679139100691,"curve":[0.26922176021717,0.42193622652763,0.76915224392875,0.97993295555754]}],"Scale":[{"startTime":0,"duration":0.16666666666667,"fromVal":[100,100,100],"toVal":[25,25,100],"curve":[0.3333593250757,0.00163831807799,0.66666667,1]}],"Opacity":[{"startTime":0,"duration":0.16666666666667,"fromVal":0,"toVal":100,"curve":[0.16666666667,0,0.66666667,1]}],"X Position":[{"startTime":0,"duration":0.16666666666667,"fromVal":230,"toVal":303.679155101503,"curve":[0.16666666667,0.16666666667,0.94,1]},{"startTime":0.16666666666667,"duration":0.16666666666667,"fromVal":303.679155101503,"toVal":446.574668811681,"curve":[0.06,0,0.94,1]},{"startTime":0.33333333333333,"duration":0.16666666666667,"fromVal":446.574668811681,"toVal":568,"curve":[0.06,0,0.83333333333,0.83333333333]},{"startTime":0.5,"duration":0.1,"fromVal":568,"toVal":588,"curve":[0.16666666667,0.16666666667,0.83333333333,0.83333333333]}]}
    """
