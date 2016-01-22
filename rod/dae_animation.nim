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

proc animationWithCollada*(node: Node3D, anim: ColladaAnimation) =
    ## Attach animation to node
    if anim.isComplex:
        for subanim in anim.children:
            animationWithCollada(node, subanim)
    else:
        ## General Animation object preperation
        var
            animProcSetters = newSeq[AnimProcSetter]()
            nodeToAttach = node.findNode(anim.channel.target)

        if nodeToAttach.isNil:
            echo "Could not find node to attach animation to: $#" % [anim.channel.target]
            return

        case anim.channel.kind
        # Animation of node's alpha value
        of ChannelKind.Visibility:
            let
                dataX = anim.sourceById(anim.sampler.input.source)
                dataY = anim.sourceById(anim.sampler.output.source)

            assert dataX.dataFloat.len == dataY.dataFloat.len

            for timeVisiblity in zip(dataX.dataFloat, dataY.dataFloat):
                let realAnimation = newAnimation()
                realAnimation.loopDuration = 0.0
                realAnimation.numberOfLoops = 1
                # TODO #1: add visibility animation progress setter here

        # Affine-transformations (linear) node parameters value
        of ChannelKind.Matrix:
            let
                dataX = anim.sourceById(anim.sampler.input.source)
                dataY = anim.sourceById(anim.sampler.output.source)

            assert dataX.dataFloat.len * 16 == dataY.dataFloat.len

            for i in 0 ..< dataX.dataFloat.len:
                var
                    transMatrix: seq[float32] = @[]
                    time = dataX.dataFloat[i]
                for j in i * 16 ..< (i + 1) * 16: transMatrix.add(dataY.dataFloat[i])
                let
                    translate = getAnimTranslation(transMatrix)
                    rotate = getAnimRotation(transMatrix)
                    scale = getAnimScale(transMatrix)
                # TODO #2: add affine transformations animation progress setter here
