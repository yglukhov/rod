import math
import sequtils
import strutils

import nimasset.collada

import nimx.matrixes
import nimx.types
import nimx.animation

import component
import node
import property_visitor
import quaternion
import rod_types
import variant

type AnimProcSetter = proc(progress: float)

proc getAnimTranslation(m: var seq[float32]): Vector3 =
    newVector3(m[3], m[7], m[11])

proc getAnimRotation(m: var seq[float32]): Quaternion =
    ## Return quaternion from transform matrix
    template w: float32 =
        bind m
        sqrt(1 + m[0] + m[5] + m[10]) / 2
    return newQuaternion(
        (m[9] - m[6]) / (4 * w()),
        (m[2] - m[8]) / (4 * w()),
        (m[4] - m[1]) / (4 * w()),
        w()
    )

proc getAnimScale(m: var seq[float32]): Vector3 =
    newVector3(
        newVector3(m[0], m[4], m[8]).length().float32,
        newVector3(m[1], m[5], m[9]).length().float32,
        newVector3(m[2], m[6], m[10]).length().float32
    )

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

proc createProgressSetterWithPropSetter[T](setter: proc(v: T), numSamples: int, parsedValues: seq[T]): AnimProcSetter =
    let
        fromValue = 0.0
        toValue = (parsedValues.len - 1).float
        propValues = parsedValues

    result = proc(p: float) =
        let i = interpolate(fromValue, toValue - 1, p)
        let index = floor(i).int
        setter(propValues[index])

proc createProgressSetter[T](propName: string, node: Node3D, parsedValues: seq[T]): AnimProcSetter =
    let ap = node.findAnimatableProperty(propName)
    if ap.isEmpty:
        raise newException(Exception, "Property " & propName & " not found in node " & node.name)

    variantMatch case ap as sng
    of SetterAndGetter[float32]: result = createProgressSetterWithPropSetter(sng.setter, parsedValues)
    of SetterAndGetter[Vector3]: result = createProgressSetterWithPropSetter(sng.setter, parsedValues)
    of SetterAndGetter[Quaternion]: result = createProgressSetterWithPropSetter(sng.setter, parsedValue)
    else:
        raise newException(Exception, "Wrong type for property " & rawPropName & " of node " & animatedNode.name)

proc animationAttach(node: Node3D, anim: ColladaAnimation): seq[AnimProcSetter] =
    ## Attach single animation to node
    ## General Animation object preperation
    case anim.channel.kind
    # Animation of node's alpha value
    of ChannelKind.Visibility:
        let
            dataX = anim.sourceById(anim.sampler.input.source)
            dataY = anim.sourceById(anim.sampler.output.source)

        assert dataX.dataFloat.len == dataY.dataFloat.len

        var parsedValues: seq[float32] = newSeq[float32](dataY.dataFloat.len)
        for i, val in dataY.dataFloat: parsedValues[i] = val

        let progressSetter = createProgressSetter[float32]("alpha", node, parsedValues)
        if not progressSetter.isNil:
            return @[progressSetter]

    # Affine-transformations (linear) node parameters value
    of ChannelKind.Matrix:
        let
            dataX = anim.sourceById(anim.sampler.input.source)
            dataY = anim.sourceById(anim.sampler.output.source)

        assert dataX.dataFloat.len * 16 == dataY.dataFloat.len

        var
            parsedTranslations: seq[Vector3] = @[]
            parsedRotations: seq[Quaternion] = @[]
            parsedScales: seq[Vector3] = @[]

        for i in 0 ..< dataX.dataFloat.len:
            var
                transMatrix: seq[float32] = @[]
                time = dataX.dataFloat[i]
            for j in i * 16 ..< (i + 1) * 16:
                transMatrix.add(dataY.dataFloat[i])
            parsedTranslations.add(getAnimTranslation(transMatrix))
            parsedRotations.add(getAnimRotation(transMatrix))
            parsedScales.add(getAnimScale(transMatrix))

        return @[
            createProgressSetter[Vector3]("translation", node, parsedTranslations),
            createProgressSetter[Quaternion]("rotation", node, parsedRotations),
            createProgressSetter[Vector3]("scale", node, parsedScales)
        ]

proc animationWithCollada*(root: Node3D, anim: ColladaAnimation): Animation =
    ## Attach animation to node
    result = newAnimation()
    var animProgressSetters: seq[AnimProcSetter] = @[]

    if anim.isComplex:
        for subanim in anim.children:
            let nodeToAttach = root.findNode(anim.channel.target)
            if nodeToAttach.isNil:
                echo "Could not find node to attach animation to: $#" % [anim.channel.target]
                continue
            animProgressSetters.add(animationAttach(root, subanim))
    else:
        let nodeToAttach = root.findNode(anim.channel.target)
        if nodeToAttach.isNil:
            echo "Could not find node to attach animation to: $#" % [anim.channel.target]
            return
        else:
            animProgressSetters.add(animationAttach(root, anim))

    result.loopDuration = 1    # TODO: GET REAL DURATION
    result.numberOfLoops = 100

    result.onAnimate = proc(progress: float) =
        for ps in animProgressSetters:
            ps(progress)
