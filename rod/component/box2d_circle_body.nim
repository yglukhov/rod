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

type Box2DCircleBody* = ref object of Component
    radius*: float32
    body*: Box2DBody

method init*(b: Box2DCircleBody) =
    b.radius = 50.0
    b.body = g_box2dWorld.newBox2DCircleBody(50.0)
    b.body.setSleepingAllowed(false)
    b.body.setTransform(0.0, 0.0, 0.0)

method draw*(b: Box2DCircleBody) =
    let c = currentContext()

    if b.node.sceneView.simulatePhysic:
        let pos = b.body.getPosition()
        let angle = radToDeg(b.body.getAngle())
        let rotation = newQuaternionFromEulerYXZ(0.0, 0.0, angle)

        b.node.position = newVector3(pos.x, pos.y, 0.0)
        b.node.rotation = rotation
    else:
        let angle = b.node.rotation.eulerAngles().z
        b.body.setTransform(b.node.positionX, b.node.positionY, degToRad(angle))

method serialize*(c: Box2DCircleBody, s: Serializer): JsonNode =
    echo "serialize circle body"
    result = newJObject()
    result.add("radius", s.getValue(c.radius))

method visitProperties*(c: Box2DCircleBody, p: var PropertyVisitor) =
    p.visitProperty("radius", c.radius)

registerComponent(Box2DCircleBody, "Box2D")
