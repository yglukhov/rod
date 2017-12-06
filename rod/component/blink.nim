import json

import nimx.types
import nimx.context
import nimx.image
import nimx.composition
import nimx.property_visitor

import rod.rod_types
import rod.node
import rod.tools.serializer
import rod / utils / [ property_desc, serialization_codegen ]
import rod.component
import rod.viewport

var blinkComposition = newComposition """
uniform Image uMask;
uniform Image uLight;
uniform vec2 uLightSize;
uniform vec4 uFromRect;
uniform float uLightPos;
uniform float uScale;

void compose() {
    vec2 destuv = (vPos - bounds.xy) / bounds.zw;
    vec2 duv = uMask.texCoords.zw - uMask.texCoords.xy;
    vec2 srcxy = uMask.texCoords.xy + duv * uFromRect.xy;
    vec2 srczw = uMask.texCoords.xy + duv * uFromRect.zw;
    vec2 uv = srcxy + (srczw - srcxy) * destuv;
    vec4 mask = texture2D(uMask.tex, uv);

    vec2 lightdestuv = (vPos - vec2(uLightPos, 0.0)) / uLightSize;
    vec2 lightduv = uLight.texCoords.zw - uLight.texCoords.xy;
    vec2 lightsrcxy = uLight.texCoords.xy + lightduv * uFromRect.xy;
    vec2 lightsrczw = uLight.texCoords.xy + lightduv * uFromRect.zw;
    vec2 lightuv = lightsrcxy + (lightsrczw - lightsrcxy) * lightdestuv;

    float rect_alpha = 1.0;
    if (lightuv.x < uLight.texCoords.x || lightuv.x > uLight.texCoords.z || lightuv.y < uLight.texCoords.y || lightuv.y > uLight.texCoords.w) {
        rect_alpha = 0.0;
    }    
    vec4 light = texture2D(uLight.tex, lightuv);

    gl_FragColor = light;
    gl_FragColor.a *= mask.a * step(0.0, lightuv.x) * step(0.0, uLight.texCoords.z - lightuv.x) * rect_alpha;
}
"""

type Blink* = ref object of Component
    mask: Image
    light: Image
    currLightPos: float
    remainingTime: float
    period: float32
    speed: float32

Blink.properties:
    mask
    light
    period
    speed

method init(b: Blink) =
    b.speed = 1.0
    b.period = 2.0
    b.remainingTime = b.period

method draw*(b: Blink) =
    if b.mask.isNil or b.light.isNil:
        return

    let c = currentContext()
    var r: Rect
    r.size = b.mask.size
    var fr = newRect(0, 0, 1, 1)
    let scale = b.mask.size.width / b.light.size.width

    let dt = getDeltaTime()
    b.currLightPos += b.speed * dt
    b.remainingTime -= dt
    if b.remainingTime <= 0.0:
        b.remainingTime = b.period
        b.currLightPos = 0.0
    
    blinkComposition.draw r:
        setUniform("uMask", b.mask)
        setUniform("uLight", b.light)
        setUniform("uLightSize", b.light.size)
        setUniform("uFromRect", fr)
        setUniform("uLightPos", b.currLightPos )
        setUniform("uScale", scale)

method getBBox*(b: Blink): BBox =
    let img = b.mask
    if not img.isNil:
        result.maxPoint = newVector3(0, 0, 0.0)
        result.minPoint = newVector3(img.size.width, img.size.height, 0.0)

method deserialize*(b: Blink, j: JsonNode, serealizer: Serializer) =
    deserializeImage(j{"mask"}, serealizer) do(img: Image, err: string):
        b.mask = img
    deserializeImage(j{"light"}, serealizer) do(img: Image, err: string):
        b.light = img

    serealizer.deserializeValue(j, "speed", b.speed)
    serealizer.deserializeValue(j, "period", b.period)

genSerializationCodeForComponent(Blink)

method serialize*(c: Blink, serealizer: Serializer): JsonNode =
    result = newJObject()
    if c.mask.filePath().len > 0:
        result.add("mask", serealizer.getValue(serealizer.getRelativeResourcePath(c.mask.filePath())))

    if c.light.filePath().len > 0:
        result.add("light", serealizer.getValue(serealizer.getRelativeResourcePath(c.light.filePath())))

    result.add("speed", serealizer.getValue(c.speed))
    result.add("period", serealizer.getValue(c.period))

method visitProperties*(b: Blink, p: var PropertyVisitor) =
    p.visitProperty("mask", b.mask)
    p.visitProperty("light", b.light)
    p.visitProperty("speed", b.speed)
    p.visitProperty("period", b.period)

registerComponent(Blink)
