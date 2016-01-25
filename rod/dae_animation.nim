import tables
import math
import sequtils
import strutils

import variant

import nimasset.collada

import nimx.animation
import nimx.types
import nimx.matrixes

import rod_types
import node
import component
import property_visitor
import quaternion

type AnimProcSetter = proc(progress: float)

proc getAnimTranslation(m: var seq[float32]): Vector3 =
    newVector3(m[3], m[7], m[11])

proc getAnimRotation(m: var seq[float32]): Quaternion =
    ## Return quaternion from transform matrix
    let w = sqrt(1 + m[0] + m[5] + m[10]) / 2
    return newQuaternion(
        (m[9] - m[6]) / (4 * w),
        (m[2] - m[8]) / (4 * w),
        (m[4] - m[1]) / (4 * w),
        w
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

proc createProgressSetterWithPropSetter[T](setter: proc(v: T), parsedValues: seq[T]): AnimProcSetter =
    let
        fromValue = 0.0
        toValue = (parsedValues.len - 1).float
    var propValues = parsedValues

    result = proc(p: float) =
        let i = interpolate(fromValue, toValue - 1, p)
        let index = floor(i).int
        setter(propValues[index])

proc createProgressSetter[T](propName: string, node: Node3D, parsedValues: seq[T]): AnimProcSetter =
    let ap = node.findAnimatableProperty(propName)
    if ap.isEmpty:
        raise newException(Exception, "Property " & propName & " not found in node " & node.name)

    when T is float32:
        result = createProgressSetterWithPropSetter(ap.get(SetterAndGetter[float32]).setter, parsedValues)
    elif T is Vector3:
        result = createProgressSetterWithPropSetter(ap.get(SetterAndGetter[Vector3]).setter, parsedValues)
    elif T is Quaternion:
        result = createProgressSetterWithPropSetter(ap.get(SetterAndGetter[Quaternion]).setter, parsedValues)
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

        let progressSetter = createProgressSetter("alpha", node, parsedValues)
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
                transMatrix.add(dataY.dataFloat[j])

            parsedTranslations.add(getAnimTranslation(transMatrix))
            parsedRotations.add(getAnimRotation(transMatrix))
            parsedScales.add(getAnimScale(transMatrix))

        return @[
            createProgressSetter("translation", node, parsedTranslations),
            createProgressSetter("rotation", node, parsedRotations),
            createProgressSetter("scale", node, parsedScales)
        ]

proc animationWithCollada*(root: Node3D, anim: ColladaAnimation): Animation =
    ## Attach animation to node
    result = newAnimation()
    var animProgressSetters = newSeq[AnimProcSetter]()

    if anim.isComplex():
        for subanim in anim.children:
            let nodeToAttach = root.findNode(subanim.channel.target)
            if nodeToAttach.isNil:
                echo "Could not find node to attach animation to: $#" % [anim.channel.target]
                continue
            let progressSetter = animationAttach(root, subanim)
            if not isNil(progressSetter):
                animProgressSetters.add(progressSetter)
    else:
        let nodeToAttach = root.findNode(anim.channel.target)
        if nodeToAttach.isNil:
            echo "Could not find node to attach animation to: $#" % [anim.channel.target]
            return
        else:
            let progressSetter = animationAttach(root, anim)
            if not isNil(progressSetter):
                animProgressSetters.add(progressSetter)

    result.onAnimate = proc(progress: float) =
        for ps in animProgressSetters:
            ps(progress)
