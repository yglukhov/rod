import nimx.context
import nimx.types
import nimx.view
import nimx.matrixes
import nimx.image
import nimx.animation
import nimx.portable_gl
import nimx.render_to_image

import rod.node
import rod.property_visitor
import rod.viewport
import rod.quaternion
import rod.component
import rod.component.camera
import rod.component.mesh_component

const vertexShader = """
attribute vec4 aPosition;
void main() {
    gl_Position = vec4(aPosition.xyz, 1.0);
}
"""
const fragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;

uniform vec3 uWidthHeight;
uniform vec3 uRedMinRedMulSpanMax;

vec4 FXAA(vec2 uViewportSize, vec2 fragCoord, sampler2D tex) {
    vec4 color;
    vec2 inverseVP = vec2(1.0 / uViewportSize.x, 1.0 / uViewportSize.y);
    vec4 rgbNW = texture2D(tex, (fragCoord + vec2(-1.0, -1.0)) * inverseVP);
    vec4 rgbNE = texture2D(tex, (fragCoord + vec2(1.0, -1.0)) * inverseVP);
    vec4 rgbSW = texture2D(tex, (fragCoord + vec2(-1.0, 1.0)) * inverseVP);
    vec4 rgbSE = texture2D(tex, (fragCoord + vec2(1.0, 1.0)) * inverseVP);
    vec4 rgbM  = texture2D(tex, fragCoord  * inverseVP);
    vec4 luma = vec4(0.299, 0.587, 0.114, 1.0);
    float lumaNW = dot(rgbNW, luma);
    float lumaNE = dot(rgbNE, luma);
    float lumaSW = dot(rgbSW, luma);
    float lumaSE = dot(rgbSE, luma);
    float lumaM  = dot(rgbM,  luma);
    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

    vec2 dir;
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));

    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * uRedMinRedMulSpanMax.y), uRedMinRedMulSpanMax.x);

    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = min(vec2(uRedMinRedMulSpanMax.z, uRedMinRedMulSpanMax.z),
              max(vec2(-uRedMinRedMulSpanMax.z, -uRedMinRedMulSpanMax.z),
              dir * rcpDirMin)) * inverseVP;

    vec4 rgbA = 0.5 * (
        texture2D(tex, fragCoord * inverseVP + dir * (1.0 / 3.0 - 0.5)) +
        texture2D(tex, fragCoord * inverseVP + dir * (2.0 / 3.0 - 0.5)));
    vec4 rgbB = rgbA * 0.5 + 0.25 * (
        texture2D(tex, fragCoord * inverseVP + dir * -0.5) +
        texture2D(tex, fragCoord * inverseVP + dir * 0.5));

    float lumaB = dot(rgbB, luma);
    if ((lumaB < lumaMin) || (lumaB > lumaMax))
        color = vec4(rgbA);
    else
        color = vec4(rgbB);
    return color;
}

void main() {
    gl_FragColor = FXAA(vec2(uWidthHeight.x, uWidthHeight.y), uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * gl_FragCoord.xy, texUnit);
}
"""

let width = 1.GLfloat
let height = 1.GLfloat
let indexData = [0.GLushort, 1, 2, 2, 3, 0]
let vertexData = [
        -width,  height, 0.0, 0.0, 1.0,
        -width, -height, 0.0, 0.0, 0.0,
         width, -height, 0.0, 1.0, 0.0,
         width,  height, 0.0, 1.0, 1.0
        ]

var FXAAPostSharedIndexBuffer: BufferRef
var FXAAPostSharedVertexBuffer: BufferRef
var FXAAPostSharedNumberOfIndexes: GLsizei
var FXAAPostSharedShader: ProgramRef

type FXAAPost* = ref object of Component
    image: SelfContainedImage
    resolution: Vector3
    reduceMin*: float32
    reduceMul*: float32
    spanMax*: float32
    fixedSize*: bool

proc createVBO() =
    let c = currentContext()
    let gl = c.gl

    FXAAPostSharedIndexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, FXAAPostSharedIndexBuffer)
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

    FXAAPostSharedVertexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, FXAAPostSharedVertexBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, vertexData, gl.STATIC_DRAW)
    FXAAPostSharedNumberOfIndexes = indexData.len.GLsizei

proc checkResolution*(r: FXAAPost) =
    let vp = r.node.sceneView
    let currWidth = vp.bounds.width
    let currHeight = vp.bounds.height

    if currWidth != r.resolution[0] or currHeight != r.resolution[1]:
        r.resolution = newVector3(currWidth, currHeight, 0.0)

        if not r.image.isNil and not r.fixedSize:
            let c = currentContext()
            let gl = c.gl
            gl.deleteFramebuffer(r.image.framebuffer)
            gl.deleteTexture(r.image.texture)
            r.image.framebuffer = invalidFrameBuffer
            r.image.texture = invalidTexture
            r.image = nil

        if r.image.isNil:
            r.image = imageWithSize(newSize(r.resolution[0], r.resolution[1]))

method init*(r: FXAAPost) =
    procCall r.Component.init()
    r.fixedSize = false
    r.reduceMin = 128.0
    r.reduceMul = 8.0
    r.spanMax = 8.0

method draw*(r: FXAAPost) =
    if r.node.isNil:
        return

    let vp = r.node.sceneView
    let c = currentContext()
    let gl = c.gl

    if FXAAPostSharedIndexBuffer == invalidBuffer:
        createVBO()
        if FXAAPostSharedIndexBuffer == invalidBuffer:
            return
    if FXAAPostSharedShader == invalidProgram:
        FXAAPostSharedShader = gl.newShaderProgram(vertexShader, fragmentShader, [(0.GLuint, $0)])
        if FXAAPostSharedShader == invalidProgram:
            return

    r.checkResolution()

    var projTransform : Transform3D
    vp.camera.getProjectionMatrix(newRect(0,0, r.resolution[0], r.resolution[1]), projTransform)

    r.image.flipVertically()
    r.image.draw do():
        c.withTransform projTransform*vp.viewMatrix()*r.node.worldTransform:
            for n in r.node.children: n.recursiveDraw()

    gl.bindBuffer(gl.ARRAY_BUFFER, FXAAPostSharedVertexBuffer)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, FXAAPostSharedIndexBuffer)

    gl.enableVertexAttribArray(0.GLuint)
    gl.vertexAttribPointer(0.GLuint, 3.GLint, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei, 0)

    gl.useProgram(FXAAPostSharedShader)

    gl.uniform3fv(gl.getUniformLocation(FXAAPostSharedShader, "uWidthHeight"), r.resolution)

    let redMinRedMulSpanMax = newVector3(1.0/r.reduceMin, 1.0/r.reduceMul, r.spanMax)
    gl.uniform3fv(gl.getUniformLocation(FXAAPostSharedShader, "uRedMinRedMulSpanMax"), redMinRedMulSpanMax)

    if not r.image.isNil:
        var theQuad {.noinit.}: array[4, GLfloat]
        gl.activeTexture(gl.TEXTURE0)
        gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(r.image, gl, theQuad))
        gl.uniform4fv(gl.getUniformLocation(FXAAPostSharedShader, "uTexUnitCoords"), theQuad)
        gl.uniform1i(gl.getUniformLocation(FXAAPostSharedShader, "texUnit"), 0)

    gl.drawElements(gl.TRIANGLES, FXAAPostSharedNumberOfIndexes, gl.UNSIGNED_SHORT)

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)

method visitProperties*(r: FXAAPost, p: var PropertyVisitor) =
    p.visitProperty("reduce_min", r.reduceMin)
    p.visitProperty("reduce_mul", r.reduceMul)
    p.visitProperty("span_max", r.spanMax)
    p.visitProperty("fixed_size", r.fixedSize)

method isPosteffectComponent*(r: FXAAPost): bool = true

registerComponent[FXAAPost]()
