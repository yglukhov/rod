import nimx/[types, context, image, composition, property_visitor]
import rod/[rod_types, viewport, component ]
import rod / utils / [ property_desc, serialization_codegen ]
import json

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

type Blink* = ref object of RenderComponent
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

genSerializationCodeForComponent(Blink)

method visitProperties*(b: Blink, p: var PropertyVisitor) =
    p.visitProperty("mask", b.mask)
    p.visitProperty("light", b.light)
    p.visitProperty("speed", b.speed)
    p.visitProperty("period", b.period)

registerComponent(Blink)
