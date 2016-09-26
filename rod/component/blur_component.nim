import streams
import tables

import nimx.types
import nimx.context
import nimx.portable_gl
import nimx.render_to_image
import nimx.matrixes
import nimx.view
import nimx.image
import nimx.resource
import nimx.property_visitor

import rod.node
import rod.viewport
import rod.component
import rod.component.camera
import rod.component.mesh_component
import rod.postprocess_context

type BlurComponent* = ref object of Component
    motionMap: SelfContainedImage
    postMap: SelfContainedImage

    motionShader: ProgramRef
    postShader: ProgramRef

    vbo, ibo: BufferRef

    bShowMotionMap*: bool
    velocityScale*: float32
    frameShift*: int
    frameCounter: int


type Attrib = enum
    aPosition
    aTexCoord

let vertexShaderMotion = """
attribute vec4 aPosition;
uniform mat4 modelViewProjectionMatrix;
uniform mat4 uCurrMVPMatrix;
uniform mat4 uPrevMVPMatrix;
varying vec4 vPrevPos;
varying vec4 vCurrPos;
void main() {
    vPrevPos = uCurrMVPMatrix * vec4(aPosition.xyz, 1.0);
    vCurrPos = uPrevMVPMatrix * vec4(aPosition.xyz, 1.0);
    gl_Position = modelViewProjectionMatrix * vec4(aPosition.xyz, 1.0);
}
"""
let fragmentShaderMotion = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif
varying vec4 vPrevPos;
varying vec4 vCurrPos;
uniform float uVelocityScale;
void main() {
    vec2 a = (vCurrPos.xy / vCurrPos.w) * 0.5 + 0.5;
    vec2 b = (vPrevPos.xy / vPrevPos.w) * 0.5 + 0.5;
    vec2 velocity = a - b;
    // velocity *= uVelocityScale;
    velocity.x = pow(abs(a.x - b.x), 1.0 / 3.0);
    velocity.y = pow(abs(a.y - b.y), 1.0 / 3.0);
    velocity = velocity * sign(a - b) * 0.5 + 0.5;
    gl_FragColor = vec4(velocity, 0, 1);
}
"""
let vertexShaderPost = """
attribute vec4 aPosition;
attribute vec2 aTexCoord;
uniform mat4 modelViewProjectionMatrix;
varying vec2 vTexCoord;
void main() {
    vTexCoord = aTexCoord;
    gl_Position = modelViewProjectionMatrix * vec4(aPosition.xyz, 1.0);
}
"""
let fragmentShaderPost = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif
uniform sampler2D motionUnit;
uniform vec4 uMotionUnitCoords;
uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;
uniform vec4 uResolution;
varying vec2 vTexCoord;
void main() {
    vec2 texelSize = vec2(1.0/uResolution.x, 1.0/uResolution.y);
    vec2 screenTexCoords = gl_FragCoord.xy * texelSize;
    vec2 velocity = texture2D(motionUnit, uMotionUnitCoords.xy + (uMotionUnitCoords.zw - uMotionUnitCoords.xy) * screenTexCoords).rg;
    velocity.x = pow(velocity.x * 2.0 - 1.0, 3.0);
    velocity.y = pow(velocity.y * 2.0 - 1.0, 3.0);
    float speed = length(velocity / texelSize);
    int MAX_SAMPLES = 16;
    int nSamples = int(clamp(speed, 1.0, float(MAX_SAMPLES)));
    vec4 oResult = texture2D(texUnit, screenTexCoords);

    #ifdef GL_ES
        const int SAMPLES = 16;
        for (int i = 1; i < SAMPLES; ++i) {
            vec2 offset = velocity * (float(i) / float(nSamples - 1) - 0.5);
            oResult += texture2D(texUnit, screenTexCoords + offset);
        }
        oResult /= float(MAX_SAMPLES);
    #else
        for (int i = 1; i < nSamples; ++i) {
            vec2 offset = velocity * (float(i) / float(nSamples - 1) - 0.5);
            oResult += texture2D(texUnit, screenTexCoords + offset);
        }
        oResult /= float(nSamples);
    #endif
    gl_FragColor = oResult;
}
"""

proc createAndSetup(bc: BlurComponent, width, height: float32) =
    let c = currentContext()
    let gl = c.gl

    if bc.motionShader == invalidProgram:
        bc.motionShader = c.gl.newShaderProgram(vertexShaderMotion, fragmentShaderMotion, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])
    if bc.postShader == invalidProgram:
        bc.postShader = c.gl.newShaderProgram(vertexShaderPost, fragmentShaderPost, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])
    if bc.vbo == invalidBuffer:
        let frameWidth = width/2.0
        let frameHeight = height/2.0
        let frameZ = 0.0
        let vertexData = [
            -frameWidth.GLfloat, frameHeight, frameZ, 0.0, 1.0,
            -frameWidth, -frameHeight, frameZ, 0.0, 0.0,
            frameWidth, -frameHeight, frameZ, 1.0, 0.0,
            frameWidth, frameHeight, frameZ, 1.0, 1.0
            ]

        bc.vbo = gl.createBuffer()
        gl.bindBuffer(gl.ARRAY_BUFFER, bc.vbo)
        gl.bufferData(gl.ARRAY_BUFFER, vertexData, gl.STATIC_DRAW)

    if bc.ibo == invalidBuffer:
        let indexData = [0.GLushort, 1, 2, 2, 3, 0]

        bc.ibo = gl.createBuffer()
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, bc.ibo)
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

    if bc.motionMap.isNil:
        bc.motionMap = imageWithSize(newSize(width, height))

    if bc.postMap.isNil:
        bc.postMap = imageWithSize(newSize(width, height))

    if bc.node.sceneView.postprocessContext.isNil:
        bc.node.sceneView.postprocessContext = newPostprocessContext()

        bc.node.sceneView.postprocessContext.drawProc = proc(c: Component) =

            let m = c.node.componentIfAvailable(MeshComponent)
            if not m.isNil:
                let postprocShader = m.node.sceneView.postprocessContext.shader
                if m.material.shader == invalidProgram or m.material.bShaderNeedUpdate:
                    m.setupAndDraw()
                let oldShader = m.material.shader

                let vp = m.node.sceneView
                let cam = vp.camera
                var projTransform : Transform3D
                cam.getProjectionMatrix(vp.bounds, projTransform)

                let mvpMatrix = projTransform * vp.viewMatrixCached * m.node.worldTransform

                if postprocShader != invalidProgram:
                    m.material.shader = postprocShader

                gl.useProgram(m.material.shader)
                gl.uniformMatrix4fv(gl.getUniformLocation(m.material.shader, "uCurrMVPMatrix"), false, mvpMatrix)
                gl.uniformMatrix4fv(gl.getUniformLocation(m.material.shader, "uPrevMVPMatrix"), false, m.prevTransform)

                gl.uniform1f(gl.getUniformLocation(m.material.shader, "uVelocityScale"), bc.velocityScale)

                m.prevTransform = mvpMatrix

                m.setupAndDraw()
                m.material.shader = oldShader

method init*(bc: BlurComponent) =
    procCall bc.Component.init()
    bc.velocityScale = 20.0
    bc.frameShift = 3

proc recursiveDrawPost(n: Node) =
    if n.alpha < 0.0000001: return
    let c = currentContext()
    var tr = c.transform
    let oldAlpha = c.alpha
    c.alpha *= n.alpha
    n.getTransform(tr)
    c.withTransform tr:
        var hasPosteffectComponent = false
        if not n.components.isNil:
            # for v in values(n.components):
            let v = n.component(MeshComponent)
            if not v.isNil:
                v.draw()
                hasPosteffectComponent = hasPosteffectComponent or v.isPosteffectComponent()
        if not hasPosteffectComponent:
            for c in n.children: c.recursiveDrawPost()
    c.alpha = oldAlpha

method draw*(bc: BlurComponent) =
    let vp = bc.node.sceneView
    let c = currentContext()
    let gl = c.gl
    let cam = vp.camera.node
    let scrWidth = vp.bounds.width
    let scrHeight = vp.bounds.height
    let texWidth = 2048.0
    let texHeight = 1024.0

    bc.createAndSetup(texWidth, texHeight)

    # var projTransform : Transform3D
    # vp.camera.getProjectionMatrix(vp.bounds, projTransform)
    # var mvpMatrix = projTransform * vp.viewMatrixCached

    let mvpMatrix = vp.getViewProjectionMatrix() * bc.node.worldTransform

    if bc.motionShader != invalidProgram:


        if bc.frameCounter == bc.frameShift:
            bc.frameCounter = 0

            bc.node.sceneView.postprocessContext.shader = bc.motionShader # bind
            gl.useProgram(bc.motionShader)
            bc.motionMap.flipVertically()
            bc.motionMap.draw( proc() =
                c.withTransform mvpMatrix:
                    for n in bc.node.children: n.recursiveDrawPost()
            )
            bc.node.sceneView.postprocessContext.shader = invalidProgram # release
            gl.useProgram(invalidProgram)

        bc.frameCounter += 1


        bc.postMap.flipVertically()
        bc.postMap.draw( proc() =
            c.withTransform mvpMatrix:
                for n in bc.node.children: n.recursiveDraw()
        )

    if bc.postShader != invalidProgram:
        gl.useProgram(bc.postShader)
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, bc.ibo)
        gl.bindBuffer(gl.ARRAY_BUFFER, bc.vbo)
        var offset: int = 0
        gl.enableVertexAttribArray(aPosition.GLuint)
        gl.vertexAttribPointer(aPosition.GLuint, 3, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei, offset)
        offset += 3 * sizeof(GLfloat)
        gl.enableVertexAttribArray(aTexCoord.GLuint)
        gl.vertexAttribPointer(aTexCoord.GLuint, 2, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei, offset)

        var theQuad {.noinit.}: array[4, GLfloat]
        var textureIndex : GLint = 0
        gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
        gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(bc.motionMap, gl, theQuad))
        gl.uniform4fv(gl.getUniformLocation(bc.postShader, "uMotionUnitCoords"), theQuad)
        gl.uniform1i(gl.getUniformLocation(bc.postShader, "motionUnit"), textureIndex)

        inc textureIndex

        gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
        gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(bc.postMap, gl, theQuad))
        gl.uniform4fv(gl.getUniformLocation(bc.postShader, "uTexUnitCoords"), theQuad)
        gl.uniform1i(gl.getUniformLocation(bc.postShader, "texUnit"), textureIndex)

        c.setTransformUniform(bc.postShader) # setup modelViewProjectionMatrix

        let resolution = newVector4(scrWidth, scrHeight, 0, 0)
        gl.uniform4fv(gl.getUniformLocation(bc.postShader, "uResolution"), resolution)

        gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT)
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
        gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
        gl.useProgram(invalidProgram)

    if bc.bShowMotionMap:
        # c: GraphicsContext, i: Image, toRect: Rect, fromRect: Rect = zeroRect, alpha: ColorComponent = 1.0
        # type Rect* = tuple[origin: Point, size: Size]
        let r = vp.bounds
        c.drawImage(bc.motionMap, newRect(newPoint(-r.size.width,-r.size.height), newSize(r.size.width,r.size.height)) )

method isPosteffectComponent*(bc: BlurComponent): bool = true

method visitProperties*(bc: BlurComponent, p: var PropertyVisitor) =
    p.visitProperty("shift", bc.frameShift)
    p.visitProperty("velo_scale", bc.velocityScale)
    p.visitProperty("show_motion", bc.bShowMotionMap)

registerComponent(BlurComponent, "Effects")
