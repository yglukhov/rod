import tables
import math
import strutils

import variant

import nimasset/collada

import nimx/[animation, types, matrixes, property_visitor]

import rod_types
import node
import component
import quaternion

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

    if res.isEmpty:
        for v in n.components:
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
        let m = i mod 1.0
        setter(interpolate(propValues[index], propValues[index + 1], m))

proc createProgressSetter[T](propName: string, node: Node, parsedValues: seq[T]): AnimProcSetter =
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

proc animationAttach(node: Node, anim: ColladaAnimation, duration: var float32): seq[AnimProcSetter] =
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

        duration = dataX.dataFloat[^1] - dataX.dataFloat[0]

        assert dataX.dataFloat.len * 16 == dataY.dataFloat.len

        var
            parsedTranslations: seq[Vector3] = @[]
            parsedRotations: seq[Quaternion] = @[]
            parsedScales: seq[Vector3] = @[]

        for i in 0 ..< dataX.dataFloat.len:
            var
                model: Matrix4
                time = dataX.dataFloat[i]
                index = 0
                scale, translation: Vector3
                rotation: Vector4

            for j in i * 16 ..< (i + 1) * 16:
                model[index] = dataY.dataFloat[j]
                inc index

            model.transpose()
            discard model.tryGetTranslationFromModel(translation)
            discard model.tryGetScaleRotationFromModel(scale, rotation)

            parsedTranslations.add(translation)
            parsedRotations.add(newQuaternion(rotation[0], rotation[1], rotation[2], rotation[3]))
            parsedScales.add(scale)

        return @[
            createProgressSetter("translation", node, parsedTranslations),
            createProgressSetter("rotation", node, parsedRotations),
            createProgressSetter("scale", node, parsedScales)
        ]

proc animationWithCollada*(root: Node, anim: ColladaAnimation): Animation =
    ## Attach animation to node
    result = newAnimation()

    var animDuration: float32

    var animProgressSetters = newSeq[AnimProcSetter]()

    var nodeToAttach: Node = nil

    if anim.isComplex():
        for subanim in anim.children:
            nodeToAttach = root.findNode(subanim.channel.target)
            if nodeToAttach.isNil and not anim.channel.isNil:
                echo "Could not find node to attach animation to: $#" % [anim.channel.target]
                continue
            let progressSetter = animationAttach(nodeToAttach, subanim, animDuration)
            if progressSetter.len > 0:
                animProgressSetters.add(progressSetter)
    else:
        if anim.channel.isNil:
            return
        nodeToAttach = root.findNode(anim.channel.target)
        if nodeToAttach.isNil:
            echo "Could not find node to attach animation to: $#" % [anim.channel.target]
            return
        else:
            let progressSetter = animationAttach(nodeToAttach, anim, animDuration)
            if progressSetter.len > 0:
                animProgressSetters.add(progressSetter)

    result.onAnimate = proc(progress: float) =
        for ps in animProgressSetters:
                ps(progress)

    if anim.id != "" and not nodeToAttach.isNil:
        # echo "Attaching $# to $#" % [anim.id, nodeToAttach.name]
        nodeToAttach.registerAnimation(anim.id, result)

    result.loopDuration = animDuration
