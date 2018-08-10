import nimx / [ types, context, image, animation, property_visitor ]
import nimx / assets / asset_manager

import json, strutils, logging

import rod.rod_types
import rod.node
import rod.ray
import rod.tools.serializer
import rod.component

import rod / utils / [ property_desc, serialization_codegen ]

type NinePartMargine*  = tuple[left, right, top, bottom: float32]

type NinePart* = ref object of Component
    size*: Size
    image*: Image
    margine*: NinePartMargine

NinePart.properties:
    size
    image
    margine

method init*(c: NinePart) =
    c.size = newSize(50, 20)
    c.margine.left = 5
    c.margine.right = 5
    c.margine.top = 5
    c.margine.bottom = 5

proc calculatedSize(s: NinePart): Size =
    if s.size == zeroSize:
        let i = s.image
        if not i.isNil:
            result = i.size
    else:
        result = s.size

method getBBox*(s: NinePart): BBox =
    let sz = s.calculatedSize()
    result.maxPoint = newVector3(sz.width, sz.height, 0.0)
    result.minPoint = newVector3(0.0, 0.0, 0.0)

method draw*(s: NinePart) =
    let c = currentContext()
    let i = s.image

    if not i.isNil:
        var r: Rect
        r.size = s.calculatedSize()
        c.drawNinePartImage(i, r, s.margine.left, s.margine.top, s.margine.right, s.margine.bottom)

genSerializationCodeForComponent(NinePart)

method visitProperties*(t: NinePart, p: var PropertyVisitor) =
    var r = t
    p.visitProperty("img", r)
    p.visitProperty("size", t.size)

registerComponent(NinePart, "Primitives")
