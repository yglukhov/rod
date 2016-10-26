import json, math

import nimx.types
import nimx.context
import nimx.matrixes
import nimx.property_visitor

import rod.node
import rod.component
import rod.tools.serializer
import rod.viewport
import rod.box2d
import rod.quaternion

type Box2DRectBody* = ref object of Component
    size*: Size
    body*: Box2DBody

method init*(b: Box2DRectBody) =
    b.size = newSize(50, 50)
    b.body = g_box2dWorld.newBox2DRectBody(50.0, 50.0)
    b.body.setSleepingAllowed(false)
    b.body.setTransform(0.0, 0.0, 0.0)

method draw*(b: Box2DRectBody) =
    let c = currentContext()

    if b.node.sceneView.simulatePhysic:
        let pos = b.body.getPosition()
        let angle = radToDeg(b.body.getAngle())
        let rotation = newQuaternionFromEulerYXZ(0.0, 0.0, angle)

        b.node.position = newVector3(pos.x, pos.y, 0.0)
        b.node.rotation = rotation
        echo "pos ", pos, "  angle  ", angle
    else:
        let angle = b.node.rotation.eulerAngles().z
        b.body.setTransform(b.node.positionX, b.node.positionY, degToRad(angle))

method serialize*(c: Box2DRectBody, s: Serializer): JsonNode =
    result = newJObject()
    result.add("size", s.getValue(c.size))

method visitProperties*(c: Box2DRectBody, p: var PropertyVisitor) =
    p.visitProperty("size", c.size)

registerComponent(Box2DRectBody, "Box2D")
