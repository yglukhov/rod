import math
import strutils

import nimx.matrixes
import nimx.types
import nimx.animation

import rod_types
import node
import quaternion

import nimasset.collada

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

proc animationWithCollada*(node: Node, anim: ColladaAnimation) =
    ## Attach animation to node
    if anim.isComplex:
        for subanim in anim.children:
            animationWithCollada(node, subanim)
    else:
        ## General Animation object preperation
        let
            realAnimation = newAnimation()
        var
            animProcSetters = newSeq[AnimProcSetter]()
            nodeToAttach = node.findNode(anim.channel.target)

        if nodeToAttach.isNil:
            echo "Could not find node to attach animation to: $#" % [anim.channel.target]
            return

        case anim.channel.kind
        # Animation of node's alpha value
        of ChannelKind.Visibility:
            realAnimation.loopDuration = 0.0
            realAnimation.numberOfLoops = 1
        # Affine-transformations (linear) node parameters value
        of ChannelKind.Matrix:
            discard
