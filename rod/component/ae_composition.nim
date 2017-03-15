import nimx/[types, context, image, animation, property_visitor, system_logger]

import json, strutils, tables

import rod/[ rod_types, node, ray, component, viewport ]
import rod.tools.serializer
import rod.utils.image_serialization
import rod.animation.property_animation
import nimx.property_editors.standard_editors
import rod.property_editors.propedit_registry

const aeAllCompositionAnimation = "aeAllCompositionAnimation"

type AEMarker = object
    start: float
    duration: float
    name: string

type AELayer* = ref object of Component
    inPoint*: float
    outPoint*: float
    animScale*: float
    startTime*: float
    duration*: float

type AEComposition* = ref object of Component
    layers*: seq[AELayer]
    markers*: seq[AEMarker]
    duration*: float
    animScale*: float
    buffers: JsonNode
    testPlay: bool

proc setCompositionMarker(c: AEComposition, m: AEMarker): Animation=
    let pStart = m.start / c.duration
    let pEnd = m.duration / c.duration

    var prop = newPropertyAnimation(c.node, c.buffers)
    prop.loopDuration = m.duration
    let propOnAnimate = prop.onAnimate
    prop.animate prog in pStart..pEnd:
        propOnAnimate(prog)
    result = prop

proc compositionNamed*(c: AEComposition, marker_name: string, exceptions: seq[string] = nil): Animation

proc applyLayerSettings*(c: AEComposition, cl: AELayer, marker: AEMarker): ComposeMarker=
    let layerIn = cl.inPoint / c.duration
    let layerOut = cl.outPoint / c.duration

    let layerComposition = cl.node.componentIfAvailable(AEComposition)
    if not layerComposition.isNil:

        let lduration = cl.duration * cl.animScale
        let skip = if cl.startTime < 0.0: abs(cl.startTime/lduration) else: 0.0
        let pIn = cl.inPoint/lduration + skip
        var pOut = cl.outPoint/lduration + skip

        if c.duration < cl.duration:
            pOut *= c.duration / cl.duration

        let prop = layerComposition.compositionNamed(aeAllCompositionAnimation)
        prop.loopDuration = lduration
        let oldCompAnimate = prop.onAnimate
        prop.animate prog in pIn..pOut:
            oldCompAnimate(prog)

        result = newComposeMarker(layerIn, layerOut, prop)

proc compositionNamed*(c: AEComposition, marker_name: string, exceptions: seq[string] = nil): Animation =
    var marker: AEMarker
    for m in c.markers:
        if m.name == marker_name:
            marker = m
            break

    if marker.name.len > 0:
        var prop = c.setCompositionMarker(marker)
        var composeMarkers = newSeq[ComposeMarker]()
        composeMarkers.add(newComposeMarker(0.0, 1.0, prop))

        if not exceptions.isNil:
            for ael in c.layers:
                if ael.node.name notin exceptions:
                    let cm = c.applyLayerSettings(ael, marker)
                    if not cm.isNil:
                        composeMarkers.add(cm)
        else:
            for ael in c.layers:
                let cm = c.applyLayerSettings(ael, marker)
                if not cm.isNil:
                    composeMarkers.add(cm)

        result = newCompositAnimation(c.duration, composeMarkers)
        result.numberOfLoops = 1

method deserialize*(c: AEComposition, j: JsonNode, serealizer: Serializer) =
    c.layers = @[]
    if "layers" in j:
        for jln in j["layers"]:
            let ch = c.node.findNode(jln.str)
            if not ch.isNil:
                let ael = ch.componentIfAvailable(AELayer)
                if not ael.isNil:
                    c.layers.add(ael)
            else:
                echo "AEComposition : ", jln.str , " not found in ", c.node.name, " !!!"

    if "markers" in j:
        let markers = j["markers"]
        c.markers = @[]
        for k, jm in markers:
            var m: AEMarker
            m.start = jm["start"].getFNum()
            m.duration = jm["duration"].getFNum()
            m.name = k
            if k == aeAllCompositionAnimation:
                c.duration = m.duration
            c.markers.add(m)

    if "buffers" in j:
        c.buffers = j["buffers"]
        if c.node.animations.isNil:
            c.node.animations = newTable[string, Animation]()

        for m in c.markers:
            c.node.animations[m.name] = c.setCompositionMarker(m)

method serialize*(c: AEComposition, s: Serializer): JsonNode=
    result = newJObject()
    result.add("buffers", c.buffers)

    let markers = newJObject()
    for m in c.markers:
        markers[m.name] = newJObject()
        markers[m.name]["start"] = %m.start
        markers[m.name]["duration"] = %m.duration

    result["markers"] = markers

    let layers = newJArray()
    for l in c.layers:
        layers.add(%l.node.name)
    result["layers"] = layers

method componentNodeWasAddedToSceneView*(c: AEComposition) =
    let allCompAnim = c.compositionNamed(aeAllCompositionAnimation)
    if not allCompAnim.isNil:
        allCompAnim.onProgress(0.0)

proc debugPlayAllComposition*(c: AEComposition): bool = c.testPlay

proc `debugPlayAllComposition=`*(c: AEComposition, val:bool)=
    c.testPlay = val
    if val:
        let anim = c.compositionNamed(aeAllCompositionAnimation)
        c.node.sceneView.addAnimation(anim)
        anim.onComplete do():
            c.debugPlayAllComposition = false

method visitProperties*(t: AEComposition, p: var PropertyVisitor) =
    var ll = t.layers.len
    var ml = t.markers.len
    p.visitProperty("markers", ml)
    p.visitProperty("layers",  ll)
    p.visitProperty("duration", t.duration)
    p.visitProperty("playAll", t.debugPlayAllComposition)

method deserialize*(c: AELayer, j: JsonNode, serealizer: Serializer) =
    serealizer.deserializeValue(j, "inPoint", c.inPoint)
    serealizer.deserializeValue(j, "outPoint", c.outPoint)
    serealizer.deserializeValue(j, "scale", c.animScale)
    serealizer.deserializeValue(j, "startTime", c.startTime)
    serealizer.deserializeValue(j, "duration", c.duration)

method serialize*(c: AELayer, s: Serializer): JsonNode=
    result = newJObject()
    result.add("inPoint", s.getValue(c.inPoint))
    result.add("outPoint", s.getValue(c.outPoint))
    result.add("scale", s.getValue(c.animScale))
    result.add("startTime", s.getValue(c.startTime))
    result.add("duration", s.getValue(c.duration))

method visitProperties*(t: AELayer, p: var PropertyVisitor) =
    p.visitProperty("inPoint",   t.inPoint)
    p.visitProperty("outPoint",  t.outPoint)
    p.visitProperty("animScale",   t.animScale)
    p.visitProperty("startTime", t.startTime)
    p.visitProperty("duration",  t.duration)

registerComponent(AELayer, "AE support")
registerComponent(AEComposition, "AE support")