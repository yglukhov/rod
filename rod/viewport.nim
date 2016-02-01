import nimx.context
import nimx.types
import nimx.image
import nimx.render_to_image
import nimx.portable_gl
import nimx.animation
import nimx.window
import nimx.view_event_handling

import tables
import rod_types
import node
import component.camera

import ray
export Viewport
export SceneView


proc `camera=`*(v: SceneView, c: Camera) =
    v.mCamera = c

template rootNode*(v: SceneView): Node2D = v.mRootNode

proc `rootNode=`*(v: SceneView, n: Node2D) =
    if not v.mRootNode.isNil:
        v.mRootNode.nodeWillBeRemovedFromSceneView()
    v.mRootNode = n
    n.nodeWasAddedToSceneView(v)

proc camera*(v: SceneView): Camera =
    if v.mCamera.isNil:
        let nodeWithCamera = v.rootNode.findNode(proc (n: Node2D): bool = not n.componentIfAvailable(Camera).isNil)
        if not nodeWithCamera.isNil:
            v.mCamera = nodeWithCamera.componentIfAvailable(Camera)
    result = v.mCamera

template viewMatrix(v: SceneView): Matrix4 = v.mCamera.node.worldTransform.inversed

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
        gl.bindFramebuffer(v.mActiveFrameBuffer)
        gl.clearWithColor(0, 0, 0, 0)

proc getViewProjectionMatrix*(v: SceneView): Matrix4 =
    let cam = v.camera
    doAssert(not cam.isNil)
    v.viewMatrixCached = v.viewMatrix
    var projTransform : Transform3D
    cam.getProjectionMatrix(v.bounds, projTransform)
    result = projTransform * v.viewMatrixCached

template getViewMatrix*(v: SceneView): Matrix4 {.deprecated.} = v.getViewProjectionMatrix()

proc swapCompositingBuffers*(v: SceneView)

method draw*(v: SceneView, r: Rect) =
    if v.rootNode.isNil: return

    let c = currentContext()
    v.prepareFramebuffers()

    c.withTransform v.getViewProjectionMatrix():
        v.rootNode.recursiveDraw()

    if v.numberOfNodesWithBackCompositionInCurrentFrame > 0:
        # When some compositing nodes are optimized away, we have
        # to blit current backup buffer to the screen.
        v.numberOfNodesWithBackCompositionInCurrentFrame = 1
        v.swapCompositingBuffers()

proc rayWithScreenCoords*(v: SceneView, coords: Point): Ray =
    result.origin = v.camera.node.translation
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
    when defined(js):
        #proc ortho*(dest: var Matrix4, left, right, bottom, top, near, far: Coord) =
        var mat = ortho(0, Coord(vp[2]), Coord(vp[3]), 0, -1, 1)

        c.withTransform mat:
            if v.numberOfNodesWithBackCompositionInCurrentFrame == 0:
                gl.bindFramebuffer(gl.FRAMEBUFFER, v.mScreenFrameBuffer)
            else:
                gl.bindFramebuffer(gl.FRAMEBUFFER, v.mBackupFrameBuffer.framebuffer)
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
            gl.bindFramebuffer(GL_READ_FRAMEBUFFER, v.mActiveFrameBuffer.framebuffer)
            gl.bindFramebuffer(GL_DRAW_FRAMEBUFFER, v.mBackupFrameBuffer.framebuffer)
        glBlitFramebuffer(0, 0, vp[2], vp[3], 0, 0, vp[2], vp[3], GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT, GL_NEAREST)

    swap(v.mActiveFrameBuffer, v.mBackupFrameBuffer)

proc addAnimation*(v: SceneView, a: Animation) = v.window.addAnimation(a)

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

import component.ui_component

method handleMouseEvent*(v: SceneView, e: var Event): bool =
    result = procCall v.View.handleMouseEvent(e)
    if not result and v.uiComponents.len > 0:
        let r = v.rayWithScreenCoords(e.localPosition)
        for c in v.uiComponents:
            result = c.handleMouseEvent(r, e)
            if result: break

method viewWillMoveToWindow*(v: SceneView, w: Window) =
    procCall v.View.viewWillMoveToWindow(w)
    for c in v.uiComponents:
        c.sceneViewWillMoveToWindow(w)

import component.all_components
