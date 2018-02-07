import json, tables, math

import nimx.types
import nimx.context
import nimx.image
import nimx.view
import nimx.property_visitor
import nimx.render_to_image
import nimx.portable_gl

import rod.viewport
import rod.quaternion
import rod.rod_types
import rod.node
import rod.tools.serializer
import rod.component
import rod.component.camera
import rod.component.clipping_rect_component

const minAlpha = 0.01
const minScale = 0.01
const minSize = 0.01
const absMinPoint = newVector3(high(int).Coord, high(int).Coord, high(int).Coord)
const absMaxPoint = newVector3(low(int).Coord, low(int).Coord, low(int).Coord)

type RTI* = ref object of Component
    mOldWorldVPMat: Matrix4
    mOldVPMat: Matrix4
    mOldVp: Rect
    mGfs: GlFrameState

    mDrawInImage: bool
    mExpandRect: Rect
    mScaleRatio: float32

    bbx*: BBox
    image*: SelfContainedImage
    aspect*: float32
    bBlendOne*: bool
    bFreezeBounds*: bool
    bFreezeChildren*: bool
    bDraw*: bool

template withViewProj(vp: SceneView, mat: Matrix4, body: typed) =
    let old = vp.viewProjMatrix
    vp.viewProjMatrix = mat
    body
    vp.viewProjMatrix = old

template inv(m: Matrix4): Matrix4 =
    var res: Matrix4
    if not m.tryInverse(res):
        res.loadIdentity()
    res

proc minVector(a,b: Vector3): Vector3 =
    return newVector3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))

proc maxVector(a,b:Vector3): Vector3 =
    return newVector3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))

proc nodeBounds2d*(n: Node, minP: var Vector3, maxP: var Vector3) =
    if n.alpha > minAlpha and n.enabled and abs(n.scale.x) > minScale and abs(n.scale.y) > minScale:

        let wrldMat = n.worldTransform()

        var wp0, wp1, wp2, wp3: Vector3

        var i = 0
        while i < n.components.len:
            let comp = n.components[i]
            inc i

            let bb = comp.getBBox()
            let diff = bb.maxPoint - bb.minPoint
            if abs(diff.x) >= minSize and abs(diff.y) >= minSize:

                wp0 = wrldMat * bb.minPoint
                wp1 = wrldMat * newVector3(bb.minPoint.x, bb.maxPoint.y, 0.0)
                wp2 = wrldMat * bb.maxPoint
                wp3 = wrldMat * newVector3(bb.maxPoint.x, bb.minPoint.y, 0.0)

                minP = minVector(minP, wp0)
                minP = minVector(minP, wp1)
                minP = minVector(minP, wp2)
                minP = minVector(minP, wp3)

                maxP = maxVector(maxP, wp0)
                maxP = maxVector(maxP, wp1)
                maxP = maxVector(maxP, wp2)
                maxP = maxVector(maxP, wp3)

            if comp of ClippingRectComponent:
                return

            if comp of RTI:
                return

            if comp.isPosteffectComponent():
                return

        for ch in n.children:
            ch.nodeBounds2d(minP, maxP)

proc setupImageWithBBXSize(rti: RTI) =
    let vp = rti.node.sceneView

    var mxPt: Vector3
    var mnPt: Vector3
    vp.withViewProj rti.mOldWorldVPMat:
        mxPt = vp.worldToScreenPoint(rti.bbx.maxPoint)
        mnPt = vp.worldToScreenPoint(rti.bbx.minPoint)

    var newSz = newSize(abs(mxPt.x - mnPt.x), abs(mxPt.y - mnPt.y)) * rti.mScaleRatio

    if newSz.width > minSize and newSz.height > minSize:
        if rti.image.isNil:
            rti.image = imageWithSize(newSz)
        else:
            if rti.image.size != newSz:
                rti.image.resetToSize(newSz, currentContext().gl)

proc compareBoundsWithViewport(rti: RTI, minP: var Vector3, maxP: var Vector3) =
    let vp = rti.node.sceneView
    let absBounds = vp.convertRectToWindow(vp.bounds)
    var vpWorldOrig: Vector3
    var vpWorldSize: Vector3
    vp.withViewProj rti.mOldWorldVPMat:
        vpWorldOrig = vp.screenToWorldPoint(newVector3(vp.bounds.x.float, vp.bounds.y.float, 0.0))
        vpWorldSize = vp.screenToWorldPoint(newVector3(absBounds.width.float, absBounds.height.float, 0.0))
    minP = maxVector(minP, vpWorldOrig)
    maxP = maxVector(maxP, vpWorldOrig)
    minP = minVector(minP, vpWorldSize)
    maxP = minVector(maxP, vpWorldSize)

template checkBounds(rti: RTI) =
    var minP = absMinPoint
    var maxP = absMaxPoint

    for ch in rti.node.children:
        nodeBounds2d(ch, minP, maxP)

    if minP != absMinPoint and maxP != absMaxPoint:
        rti.bbx.minPoint = newVector3(minP.x+rti.mExpandRect.x, minP.y+rti.mExpandRect.y, minP.z)
        rti.bbx.maxPoint = newVector3(maxP.x+rti.mExpandRect.width, maxP.y+rti.mExpandRect.height, maxP.z)
        compareBoundsWithViewport(rti, rti.bbx.minPoint, rti.bbx.maxPoint)
        setupImageWithBBXSize(rti)

template updateAspect(rti: RTI) =
    let vp = rti.node.sceneView
    let absVpBounds = vp.convertRectToWindow(vp.bounds)
    var logicalSize = vp.camera.viewportSize
    if logicalSize == zeroSize:
        logicalSize = absVpBounds.size
    rti.aspect = absVpBounds.height / logicalSize.height

template expandRect*(rti: RTI): Rect = rti.mExpandRect

template `expandRect=`*(rti: RTI, val: Rect) =
    rti.mExpandRect = val
    if not rti.node.isNil:
        checkBounds(rti)
        rti.mDrawInImage = true

template scaleRatio*(rti: RTI): float32 = rti.mScaleRatio

template `scaleRatio=`*(rti: RTI, val: float32) =
    rti.mScaleRatio = val
    if not rti.node.isNil:
        checkBounds(rti)
        rti.mDrawInImage = true

proc vpChanged(rti: RTI): bool =
    result = rti.mOldVp != rti.node.sceneView.bounds
    rti.mOldVp = rti.node.sceneView.bounds

proc getTransitionViewMat(rti: RTI): Matrix4 =
    let vp = rti.node.sceneView
    var vpMtr: Matrix4
    vpMtr.loadIdentity()
    vpMtr.translate(vp.camera.node.worldPos)
    vpMtr.scale(vp.camera.node.scale)
    return vpMtr.inv()

proc getTransitionProjMat(rti: RTI): Matrix4 =
    let vp = rti.node.sceneView

    var worldMinPt: Vector3
    vp.withViewProj rti.mOldWorldVPMat:
        worldMinPt = vp.worldToScreenPoint(rti.bbx.minPoint)

    let worldRtiBounds = newRect(newPoint(worldMinPt.x, worldMinPt.y), rti.image.size / rti.mScaleRatio)

    let left   = -(vp.bounds.width / 2.0 - worldRtiBounds.x) / rti.aspect
    let right  = left + worldRtiBounds.width / rti.aspect
    let top    = -(vp.bounds.height / 2.0 - worldRtiBounds.y) / rti.aspect
    let bottom = top + worldRtiBounds.height / rti.aspect

    var projMat: Matrix4
    projMat.ortho(left, right, bottom, top, vp.camera.zNear, vp.camera.zFar)

    return projMat

proc getImageVPM*(rti: RTI): Matrix4 =
    let vp = rti.node.sceneView
    var mtr: Matrix4
    mtr.loadIdentity()
    mtr.translate(rti.node.worldPos)
    mtr.scale(vp.camera.node.scale)
    return vp.viewProjMatrix * mtr

proc getImageScreenBounds*(rti: RTI): Rect =
    let vp = rti.node.sceneView
    var scrMinPt: Vector3
    var scrWpos: Vector3
    vp.withViewProj rti.mOldWorldVPMat:
        scrMinPt = vp.worldToScreenPoint(rti.bbx.minPoint)
        scrWpos = vp.worldToScreenPoint(rti.node.worldPos)
    let diff = -(scrWpos - scrMinPt) / rti.aspect
    return newRect(newPoint(diff.x, diff.y), rti.image.size / rti.aspect / rti.scaleRatio)

template drawImg*(rti: RTI) =
    if rti.node.sceneView.camera.projectionMode == cpPerspective:
        rti.image.flipVertically()
    currentContext().withTransform rti.getImageVPM():
        currentContext().drawImage(rti.image, rti.getImageScreenBounds())

template drawWithBlend*(rti: RTI) =
    let gl = currentContext().gl
    if rti.bBlendOne:
        gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
        rti.drawImg()
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    else:
        rti.drawImg()

method componentNodeWasAddedToSceneView*(rti: RTI) =
    rti.mOldVp = rti.node.sceneView.bounds
    rti.scaleRatio = 1.0
    rti.bDraw = true

method getBBox*(rti: RTI): BBox =
    var mtrInv = rti.node.worldTransform
    mtrInv = mtrInv.inv()
    result.minPoint = mtrInv * rti.bbx.minPoint
    result.minPoint.z = 0
    result.maxPoint = mtrInv * rti.bbx.maxPoint
    result.maxPoint.z = 0

method componentNodeWillBeRemovedFromSceneView*(rti: RTI) =
    if not rti.image.isNil:
        let gl = currentContext().gl
        gl.deleteFramebuffer(rti.image.framebuffer)
        gl.deleteRenderbuffer(rti.image.renderbuffer)
        gl.deleteTexture(rti.image.texture)
        rti.image.framebuffer = invalidFrameBuffer
        rti.image.renderbuffer = invalidRenderBuffer
        rti.image.texture = invalidTexture
        rti.image = nil

method beforeDraw*(rti: RTI, index: int): bool =
    result = true

    rti.mOldWorldVPMat = rti.node.sceneView.getViewProjectionMatrix()

    if not rti.bFreezeBounds or rti.vpChanged():
        rti.checkBounds()

    if not rti.image.isNil:

        rti.updateAspect()

        if not rti.bFreezeChildren or rti.mDrawInImage:

            let gl = currentContext().gl

            gl.disable(gl.SCISSOR_TEST)

            rti.mOldVPMat = rti.node.sceneView.viewProjMatrix
            rti.node.sceneView.viewProjMatrix = rti.getTransitionProjMat() * rti.getTransitionViewMat()

            rti.image.beginDraw(rti.mGfs)

            result = false

method afterDraw*(rti: RTI, index: int) =
    if not rti.image.isNil:
        let gl = currentContext().gl

        if not rti.bFreezeChildren or rti.mDrawInImage:

            rti.mDrawInImage = false

            rti.image.endDraw(rti.mGfs)
            if not rti.image.flipped:
                rti.image.flipVertically()

            rti.node.sceneView.viewProjMatrix = rti.mOldVPMat

        if rti.bDraw:
            if rti.node.sceneView.editing:
                gl.enable(gl.DEPTH_TEST)
                rti.drawWithBlend()
                gl.disable(gl.BLEND)
                if rti.node.sceneView.camera.projectionMode == cpPerspective:
                    rti.image.flipVertically()
                currentContext().withTransform rti.getImageVPM():
                    var r = rti.getImageScreenBounds()
                    let lineWidth = 1.0 / rti.aspect
                    r.origin = r.origin - newPoint(lineWidth, lineWidth)
                    r.size = r.size + newSize(lineWidth*2.0, lineWidth*2.0)
                    currentContext().drawImage(rti.image, r)
                gl.enable(gl.BLEND)
                gl.disable(gl.DEPTH_TEST)
            else:
                rti.drawWithBlend()

method serialize*(rti: RTI, serealizer: Serializer): JsonNode =
    result = newJObject()
    result.add("bBlendOne", serealizer.getValue(rti.bBlendOne))
    result.add("expandRect", serealizer.getValue(rti.expandRect))
    result.add("scaleRatio", serealizer.getValue(rti.scaleRatio))
    result.add("needDraw", serealizer.getValue(rti.bDraw))

method deserialize*(rti: RTI, j: JsonNode, serealizer: Serializer) =
    serealizer.deserializeValue(j, "bBlendOne", rti.bBlendOne)
    serealizer.deserializeValue(j, "expandRect", rti.expandRect)
    serealizer.deserializeValue(j, "scaleRatio", rti.scaleRatio)
    serealizer.deserializeValue(j, "needDraw", rti.bDraw)

method visitProperties*(rti: RTI, p: var PropertyVisitor) =

    template img(rti: RTI): Image = rti.image.Image
    template `img=`(rti: RTI, i: Image) = discard

    p.visitProperty("image", rti.img)
    p.visitProperty("scale rat", rti.scaleRatio)
    p.visitProperty("expand bb", rti.expandRect)
    p.visitProperty("freeze bb", rti.bFreezeBounds)
    p.visitProperty("freeze ch", rti.bFreezeChildren)
    p.visitProperty("blend one", rti.bBlendOne)
    p.visitProperty("draw result", rti.bDraw)


registerComponent(RTI, "Effects")
