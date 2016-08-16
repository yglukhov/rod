import nimx.context
import nimx.types
import nimx.image
import nimx.render_to_image
import nimx.portable_gl
import nimx.animation
import nimx.window
import nimx.view_event_handling
import nimx.view_event_handling_new
import nimx.notification_center

import times
import tables
import rod_types
import node
import component.camera
import rod.material.shader

import ray
export Viewport
export SceneView

const GridVertexShader = """
attribute vec3 aPosition;

uniform mat4 modelViewProjectionMatrix;

void main()
{
    gl_Position = modelViewProjectionMatrix * vec4(aPosition, 1.0);
}
"""
const GridFragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

void main()
{
    gl_FragColor = vec4(0.0, 0.0, 0.0, 0.3);
}
"""

var gridShader: Shader
var deltaTime = 0.0
var oldTime = 0.0

proc getDeltaTime*(): float =
    return deltaTime

proc `camera=`*(v: SceneView, c: Camera) =
    v.mCamera = c

template rootNode*(v: SceneView): Node2D = v.mRootNode

proc `rootNode=`*(v: SceneView, n: Node2D) =
    if not v.mRootNode.isNil:
        v.mRootNode.nodeWillBeRemovedFromSceneView()
    v.mRootNode = n
    if not n.isNil:
        n.nodeWasAddedToSceneView(v)

proc camera*(v: SceneView): Camera =
    if v.mCamera.isNil:
        let nodeWithCamera = v.rootNode.findNode(proc (n: Node2D): bool = not n.componentIfAvailable(Camera).isNil)
        if not nodeWithCamera.isNil:
            v.mCamera = nodeWithCamera.componentIfAvailable(Camera)
    result = v.mCamera

template viewMatrix*(v: SceneView): Matrix4 = v.mCamera.node.worldTransform.inversed

proc prepareFramebuffer(v: SceneView, i: var SelfContainedImage, sz: Size) =
    if i.isNil:
        echo "Creating buffer"
        i = imageWithSize(sz)
        i.flipVertically()
    elif i.size != sz:
        echo "Recreating buffer"
        i = imageWithSize(sz)
        i.flipVertically()

proc prepareFramebuffers(v: SceneView) =
    v.numberOfNodesWithBackCompositionInCurrentFrame = v.numberOfNodesWithBackComposition
    if v.numberOfNodesWithBackComposition > 0:
        let gl = currentContext().gl
        let vp = gl.getViewport()
        let sz = newSize(vp[2].Coord, vp[3].Coord)
        v.prepareFramebuffer(v.mActiveFrameBuffer, sz)
        v.prepareFramebuffer(v.mBackupFrameBuffer, sz)
        v.mScreenFramebuffer = gl.boundFramebuffer()
        gl.bindFramebuffer(v.mActiveFrameBuffer, false)
        gl.clearWithColor(0, 0, 0, 0)

proc getProjectionMatrix*(v: SceneView): Matrix4 =
    v.camera.getProjectionMatrix(v.bounds, result)

proc getViewProjectionMatrix*(v: SceneView): Matrix4 =
    let cam = v.camera
    doAssert(not cam.isNil)
    v.viewMatrixCached = v.viewMatrix
    var projTransform : Transform3D
    cam.getProjectionMatrix(v.bounds, projTransform)
    result = projTransform * v.viewMatrixCached

proc worldToScreenPoint*(v: SceneView, point: Vector3): Vector3 =
    let clipSpacePos = v.viewProjMatrix * newVector4(point.x, point.y, point.z, 1.0)
    var ndcSpacePos: Vector3
    if clipSpacePos[3] > 0:
        ndcSpacePos = newVector3(clipSpacePos[0] / clipSpacePos[3], clipSpacePos[1] / clipSpacePos[3], clipSpacePos[2] / clipSpacePos[3])
    else:
        ndcSpacePos = newVector3(clipSpacePos[0], clipSpacePos[1], clipSpacePos[2])

    result.x = ((ndcSpacePos.x + 1.0) / 2.0) * v.bounds.width
    result.y = ((1.0 - ndcSpacePos.y) / 2.0) * v.bounds.height
    result.z = (1.0 + ndcSpacePos.z) * 0.5

proc screenToWorldPoint*(v: SceneView, point: Vector3): Vector3 =
    let matViewProj = v.viewProjMatrix
    var matInverse: Matrix4
    if tryInverse (matViewProj, matInverse) == false:
        return

    var oIn: Vector4

    oIn[0] = point.x / v.bounds.width * 2.0 - 1.0
    oIn[1] = 1.0 - point.y / v.bounds.height * 2.0
    oIn[2] = 2.0 * point.z - 1.0
    oIn[3] = 1.0

    let vIn = newVector4(oIn[0], oIn[1], oIn[2], oIn[3])
    var pos = matInverse * vIn
    pos[3] = 1.0 / pos[3]

    result.x = pos.x * pos[3]
    result.y = pos.y * pos[3]
    result.z = pos.z * pos[3]

template getViewMatrix*(v: SceneView): Matrix4 {.deprecated.} = v.getViewProjectionMatrix()

proc swapCompositingBuffers*(v: SceneView)

const gridLineCount = 10
var gridPoints: array[6 * gridLineCount * 2, float32]
proc drawGrid(v: SceneView) =
    let gl = currentContext().gl

    for i in 0 .. gridLineCount-1:
        var p1 = newVector3(10.0 * i.float, 0.0, 45.0)
        var p2 = newVector3(10.0 * i.float, 0.0, -45.0)
        p1.x -= gridLineCount / 2.0 * 10.0 - 5
        p2.x -= gridLineCount / 2.0 * 10.0 - 5
        gridPoints[6 * i + 0] = p1.x
        gridPoints[6 * i + 1] = p1.y
        gridPoints[6 * i + 2] = p1.z
        gridPoints[6 * i + 3] = p2.x
        gridPoints[6 * i + 4] = p2.y
        gridPoints[6 * i + 5] = p2.z

    for i in 0 .. gridLineCount-1:
        var p1 = newVector3(45.0, 0.0, 10.0 * i.float)
        var p2 = newVector3(-45.0, 0.0, 10.0 * i.float)
        p1.z -= gridLineCount / 2.0 * 10.0 - 5
        p2.z -= gridLineCount / 2.0 * 10.0 - 5
        let index = 6 * i + (gridLineCount) * 6
        gridPoints[index + 0] = p1.x
        gridPoints[index + 1] = p1.y
        gridPoints[index + 2] = p1.z
        gridPoints[index + 3] = p2.x
        gridPoints[index + 4] = p2.y
        gridPoints[index + 5] = p2.z

    gridShader.bindShader()
    gridShader.setTransformUniform()

    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, false, 0, gridPoints)

    gl.depthMask(true)
    gl.enable(gl.DEPTH_TEST)
    gl.drawArrays(gl.LINES, 0, 2 * 2 * gridLineCount)

    gl.disable(gl.DEPTH_TEST)
    gl.depthMask(true)

import tables
var drawTable*: TableRef[int, seq[Node]]
method draw*(v: SceneView, r: Rect) =
    procCall v.View.draw(r)
    if v.rootNode.isNil: return

    let c = currentContext()
    v.prepareFramebuffers()

    drawTable = newTable[int, seq[Node]]()
    v.viewProjMatrix = v.getViewProjectionMatrix()
    c.withTransform v.viewProjMatrix:
        v.drawGrid()
        v.rootNode.recursiveDraw(drawTable)
        for k, v in drawTable:
            c.gl.clearDepthStencil()
            for node in v:
                discard node.drawNode()

    if v.numberOfNodesWithBackCompositionInCurrentFrame > 0:
        # When some compositing nodes are optimized away, we have
        # to blit current backup buffer to the screen.
        v.numberOfNodesWithBackCompositionInCurrentFrame = 1
        v.swapCompositingBuffers()

proc rayWithScreenCoords*(v: SceneView, coords: Point): Ray =
    if v.camera.projectionMode == cpOrtho:
        var logicalWidth = v.bounds.width / (v.bounds.height / v.camera.viewportSize.height)
        # let viewCoords = newVector3(coords.x - v.bounds.width / 2.0, coords.y - v.bounds.height / 2.0, 0.0)
        var viewCoords:Vector3
        viewCoords.x = coords.x / v.bounds.width * logicalWidth  - logicalWidth / 2.0
        viewCoords.y = coords.y / v.bounds.height * v.camera.viewportSize.height - v.camera.viewportSize.height / 2.0
        viewCoords.z = 10.0

        result.origin = v.camera.node.worldTransform * viewCoords
        let dirPoint = v.camera.node.worldTransform * newVector3(viewCoords.x, viewCoords.y, -1.0)

        result.direction = dirPoint - result.origin
        result.direction.normalize()
        return

    result.origin = v.camera.node.localToWorld(newVector3())
    let x = (2.0 * coords.x) / v.bounds.width - 1.0
    let y = 1.0 - (2.0 * coords.y) / v.bounds.height
    let rayClip = newVector4(x, y, -1, 1)

    var proj : Transform3D
    v.mCamera.getProjectionMatrix(v.bounds, proj)

    proj.inverse()
    var rayEye = proj * rayClip
    rayEye[2] = -1
    rayEye[3] = 0

    var viewMat = v.mCamera.node.worldTransform

    rayEye = viewMat * rayEye
    result.direction = newVector3(rayEye[0], rayEye[1], rayEye[2])
    result.direction.normalize()

import opengl

proc aquireTempFramebuffer*(v: SceneView): SelfContainedImage =
    let vp = currentContext().gl.getViewport()
    let size = newSize(vp[2].Coord, vp[3].Coord)

    if not v.tempFramebuffers.isNil and v.tempFramebuffers.len > 0:
        result = v.tempFramebuffers[^1]
        v.tempFramebuffers.setLen(v.tempFramebuffers.len - 1)
        if result.size != size:
            echo "REALLOCATING TEMP BUFFER"
            result = imageWithSize(size)
            result.flipVertically()
            #swap(result.texCoords[1], result.texCoords[3])
    else:
        echo "CREATING TEMP BUFFER"
        result = imageWithSize(size)
        result.flipVertically()
        #swap(result.texCoords[1], result.texCoords[3])

proc releaseTempFramebuffer*(v: SceneView, fb: SelfContainedImage) =
    if v.tempFramebuffers.isNil:
        v.tempFramebuffers = newSeq[SelfContainedImage]()
    v.tempFramebuffers.add(fb)

proc swapCompositingBuffers*(v: SceneView) =
    assert(v.numberOfNodesWithBackCompositionInCurrentFrame > 0)
    dec v.numberOfNodesWithBackCompositionInCurrentFrame
    let boundsSize = v.bounds.size
    let c = currentContext()
    let gl = c.gl
    let vp = gl.getViewport()
    when defined(js) or defined(emscripten) or defined(gles2only):
        #proc ortho*(dest: var Matrix4, left, right, bottom, top, near, far: Coord) =
        var mat = ortho(0, Coord(vp[2]), Coord(vp[3]), 0, -1, 1)

        c.withTransform mat:
            if v.numberOfNodesWithBackCompositionInCurrentFrame == 0:
                gl.bindFramebuffer(gl.FRAMEBUFFER, v.mScreenFrameBuffer)
            else:
                gl.bindFramebuffer(v.mBackupFrameBuffer, false)
            let a = c.alpha
            c.alpha = 1.0
            gl.disable(gl.BLEND)
            c.drawImage(v.mActiveFrameBuffer, newRect(0, 0, Coord(vp[2]), Coord(vp[3])))
            gl.enable(gl.BLEND)
            c.alpha = a
    else:
        if v.numberOfNodesWithBackCompositionInCurrentFrame == 0:
            # Swap active buffer to screen
            gl.bindFramebuffer(GL_READ_FRAMEBUFFER, v.mActiveFrameBuffer.framebuffer)
            gl.bindFramebuffer(GL_DRAW_FRAMEBUFFER, v.mScreenFrameBuffer)
        else:
            # Swap active buffer to backup buffer
            gl.bindFramebuffer(v.mBackupFrameBuffer, false)
            gl.bindFramebuffer(GL_READ_FRAMEBUFFER, v.mActiveFrameBuffer.framebuffer)
        glBlitFramebuffer(0, 0, vp[2], vp[3], 0, 0, vp[2], vp[3], GL_COLOR_BUFFER_BIT, GLenum(GL_NEAREST))

    swap(v.mActiveFrameBuffer, v.mBackupFrameBuffer)

proc addAnimation*(v: SceneView, a: Animation) =
    v.animationRunner.pushAnimation(a)

proc removeAnimation*(v: SceneView, a: Animation) = v.animationRunner.removeAnimation(a)

proc addLightSource*(v: SceneView, ls: LightSource) =
    if v.lightSources.isNil():
        v.lightSources = newTable[string, LightSource]()
    if v.lightSources.len() < rod_types.maxLightsCount:
        v.lightSources[ls.node.name] = ls
    else:
        echo "Count of light sources is limited. Current count equals " & $rod_types.maxLightsCount

proc removeLightSource*(v: SceneView, ls: LightSource) =
    if v.lightSources.isNil() or v.lightSources.len() <= 0:
        echo "Current light sources count equals 0."
    else:
        v.lightSources.del(ls.node.name)

import component.ui_component, algorithm

method name*(v: SceneView): string =
    result = "SceneView"

method onTouchEv*(v: SceneView, e: var Event): bool =
    if v.uiComponents.len > 0:
        if e.buttonState == bsDown:
            let r = v.rayWithScreenCoords(e.localPosition)
            type Inter = tuple[i: Vector3, c: UIComponent]
            var intersections = newSeq[Inter]()
            for c in v.uiComponents:
                var inter : Vector3
                if c.intersectsWithUINode(r, inter):
                    intersections.add((inter, c))

            template dist(a, b): expr = (a - b).length
            if intersections.len > 0:
                intersections.sort(proc (x, y: Inter): int =
                    result = int((dist(x.i, r.origin) - dist(y.i, r.origin)) * 5)
                    if result == 0:
                        result = getTreeDistance(x.c.node, y.c.node)
                )

                for i in intersections:
                    result = i.c.handleTouchEv(r, e, i.i)
                    if result:
                        v.touchTarget = i.c.mView
                        break
        else:
            if not v.touchTarget.isNil:
                let target = v.touchTarget
                var localPosition = e.localPosition
                e.localPosition = target.convertPointFromParent(localPosition)
                result = target.processTouchEvent(e)
                e.localPosition = localPosition

    if not result:
        result = procCall v.View.onTouchEv(e)

method handleMouseEvent*(v: SceneView, e: var Event): bool =
    result = procCall v.View.handleMouseEvent(e)
    if v.uiComponents.len > 0:
        let r = v.rayWithScreenCoords(e.localPosition)

        type Inter = tuple[i: Vector3, c: UIComponent]
        var intersections = newSeq[Inter]()

        for c in v.uiComponents:
            var inter : Vector3
            if c.intersectsWithUINode(r, inter):
                intersections.add((inter, c))

        template dist(a, b): expr = (b - a).length

        if intersections.len > 0:
            intersections.sort(proc (x, y: Inter): int =
                result = int((dist(x.i, r.origin) - dist(y.i, r.origin)) * 5)
                if result == 0:
                    result = getTreeDistance(x.c.node, y.c.node)
            )

            for i in intersections:
                result = i.c.handleMouseEvent(r, e, i.i)
                if result: break

method viewOnEnter*(v:SceneView){.base.} = discard
method viewOnExit*(v:SceneView){.base.} = discard

method viewDidMoveToWindow*(v:SceneView)=
    procCall v.View.viewDidMoveToWindow()
    if not v.window.isNil:
        v.viewOnEnter()
        v.window.addAnimationRunner(v.animationRunner)

method viewWillMoveToWindow*(v: SceneView, w: Window) =
    if w.isNil:
        v.viewOnExit()

    if not v.window.isNil:
        v.window.removeAnimationRunner(v.animationRunner)

    procCall v.View.viewWillMoveToWindow(w)
    for c in v.uiComponents:
        c.sceneViewWillMoveToWindow(w)

method init*(v: SceneView, frame: Rect) =
    procCall v.View.init(frame)
    v.animationRunner = newAnimationRunner()

    v.deltaTimeAnimation = newAnimation()
    v.deltaTimeAnimation.numberOfLoops = -1
    v.deltaTimeAnimation.loopDuration = 1.0
    v.deltaTimeAnimation.onAnimate = proc(p: float) =
        deltaTime = v.deltaTimeAnimation.curLoop.float + p - oldTime
        oldTime = v.deltaTimeAnimation.curLoop.float + p

    v.addAnimation(v.deltaTimeAnimation)

    gridShader = newShader(GridVertexShader, GridFragmentShader, @[(0.GLuint, "aPosition")])

import component.all_components
