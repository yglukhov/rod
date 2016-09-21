import json

import nimx.types
import nimx.context
import nimx.image
import nimx.composition
import nimx.property_visitor

import rod.rod_types
import rod.node
import rod.tools.serializer
import rod.component
import rod.viewport

var angleCutComposition = newComposition """
uniform Image uImage;
uniform vec4 uFromRect;
uniform float uLightPos;
uniform float uWhiteLineSie;

void compose() {
    vec2 destuv = (vPos - bounds.xy) / bounds.zw;
    vec2 duv = uImage.texCoords.zw - uImage.texCoords.xy;
    vec2 srcxy = uImage.texCoords.xy + duv * uFromRect.xy;
    vec2 srczw = uImage.texCoords.xy + duv * uFromRect.zw;
    vec2 uv = srcxy + (srczw - srcxy) * destuv;

    vec4 image = texture2D(uImage.tex, uv);
    float y = abs(uv.x - duv.x / 2.0) + uLightPos;
    y = uv.y - y;
    float y_white = y + uWhiteLineSie;
    y = smoothstep(0.0, 0.02, y);
    y_white = smoothstep(0.0, 0.02, y_white);

    gl_FragColor = (image.rgba + vec4(0.8, 0.8, 0.8, 0.0)) * y_white + image.rgba * (1.0 - y_white);
    gl_FragColor.a = image.a * (1.0 - y);
}
"""

type AngleCut* = ref object of Component
    image: Image
    currLightPos: float
    speed: float
    started: bool
    onFinish*: proc()
    whiteLineSize*: float

method init(ac: AngleCut) =
    ac.speed = 1.0
    ac.whiteLineSize = 20.0
    ac.currLightPos = -500.0

proc start*(ac: AngleCut) =
    ac.started = true
    ac.currLightPos = -ac.image.size.width / 2.0

method draw*(ac: AngleCut) =
    if ac.image.isNil:
        return

    let c = currentContext()
    var r: Rect
    r.size = ac.image.size
    var fr = newRect(0, 0, 1, 1)
    if ac.started:
        ac.currLightPos += ac.speed * getDeltaTime()

    if ac.currLightPos > ac.image.size.height:
        ac.started = false

    if not ac.onFinish.isNil and ac.currLightPos > ac.image.size.height:
        ac.onFinish()

    angleCutComposition.draw r:
        setUniform("uImage", ac.image)
        setUniform("uFromRect", fr)
        setUniform("uLightPos", ac.currLightPos / ac.image.size.height)
        setUniform("uWhiteLineSie", ac.whiteLineSize / ac.image.size.height)

method getBBox*(ac: AngleCut): BBox =
    let img = ac.image
    if not img.isNil:
        result.maxPoint = newVector3(0, 0, 0.0)
        result.minPoint = newVector3(img.size.width, img.size.height, 0.01)

method deserialize*(c: AngleCut, j: JsonNode, serealizer: Serializer) =
    serealizer.deserializeValue(j, "image", c.image)
    serealizer.deserializeValue(j, "speed", c.speed)

method serialize*(c: AngleCut, serealizer: Serializer): JsonNode =
    result = newJObject()
    if c.image.filePath().len > 0:
        result.add("image", serealizer.getValue(serealizer.getRelativeResourcePath(c.image.filePath())))

    result.add("speed", serealizer.getValue(c.speed))

method visitProperties*(c: AngleCut, p: var PropertyVisitor) =
    proc onPlayedChange() =
            c.start()

    p.visitProperty("image", c.image)
    p.visitProperty("speed", c.speed)
    p.visitProperty("started", c.started, onPlayedChange)
    p.visitProperty("LineSize", c.whiteLineSize)

registerComponent(AngleCut)
