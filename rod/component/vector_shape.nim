import json

import nimx.types
import nimx.context
import nimx.matrixes
import nimx.property_visitor

import rod.node
import rod.rod_types
import rod.component
import rod.tools.serializer
import rod / utils / [ property_desc, serialization_codegen ]

type VectorShapeType* = enum
    vsRectangle
    vsEllipse
    vsStar

type VectorShape* = ref object of Component
    size*: Size
    color*: Color
    strokeWidth*: float32
    strokeColor*: Color
    radius*: float32
    shapeType*: VectorShapeType

VectorShape.properties:
    size
    color
    strokeWidth
    strokeColor
    radius
    shapeType

genSerializationCodeForComponent(VectorShape)

method init*(vs: VectorShape) =
    vs.color = whiteColor()
    vs.size = newSize(100, 100)
    vs.strokeWidth = 0
    vs.strokeColor = whiteColor()
    vs.radius = 0

method serialize*(vs: VectorShape, s: Serializer): JsonNode =
    result = newJObject()
    result.add("size", s.getValue(vs.size))
    result.add("color", s.getValue(vs.color))
    result.add("strokeWidth", s.getValue(vs.strokeWidth))
    result.add("strokeColor", s.getValue(vs.strokeColor))
    result.add("radius", s.getValue(vs.radius))
    result.add("shapeType", s.getValue(vs.shapeType))

method deserialize*(vs: VectorShape, j: JsonNode, serializer: Serializer) =
    serializer.deserializeValue(j, "color", vs.color)
    serializer.deserializeValue(j, "size", vs.size)
    serializer.deserializeValue(j, "strokeWidth", vs.strokeWidth)
    serializer.deserializeValue(j, "strokeColor", vs.strokeColor)
    serializer.deserializeValue(j, "radius", vs.radius)
    serializer.deserializeValue(j, "shapeType", vs.shapeType)

method getBBox*(vs: VectorShape): BBox =
    result.minPoint = newVector3(-vs.size.width/2.0, -vs.size.height/2.0, 0.0)
    result.maxPoint = newVector3(vs.size.width/2.0, vs.size.height/2.0, 0.0)

method visitProperties*(vs: VectorShape, p: var PropertyVisitor) =
    p.visitProperty("size", vs.size)
    p.visitProperty("color", vs.color)
    p.visitProperty("strokeWidth", vs.strokeWidth)
    p.visitProperty("strokeColor", vs.strokeColor)
    p.visitProperty("radius", vs.radius)
    p.visitProperty("shapeType", vs.shapeType)

method beforeDraw*(vs: VectorShape, index: int): bool =
    let c = currentContext()
    c.fillColor = vs.color
    c.strokeWidth = vs.strokeWidth
    c.strokeColor = vs.strokeColor
    let strokedWidth = vs.size.width + vs.strokeWidth
    let strokedHeight = vs.size.height + vs.strokeWidth
    let r = newRect(-strokedWidth/2.0, -strokedHeight/2.0, strokedWidth, strokedHeight)

    case vs.shapeType:
    of vsRectangle:
        if vs.radius > 0:
            c.drawRoundedRect(r, vs.radius)
        else:
            c.drawRect(r)
    of vsEllipse:
        c.drawEllipseInRect(r)
    else: discard

registerComponent(VectorShape)
