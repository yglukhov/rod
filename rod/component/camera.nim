import math

import nimx.matrixes
import nimx.types
import nimx.context
import nimx.property_visitor
import nimx.view

import rod.component
import rod.rod_types
import rod.viewport
import rod.node

export CameraProjection
export Camera

method init*(c: Camera) =
    c.projectionMode = cpPerspective
    c.zNear = 1
    c.zFar = 10000
    c.fov = 30

proc getProjectionMatrix*(c: Camera, viewportBounds: Rect, mat: var Transform3D) =
    let absBounds = c.node.sceneView.convertRectToWindow(c.node.sceneView.bounds)
    var winSize = absBounds.size
    if not c.node.sceneView.window.isNil:
        winSize = c.node.sceneView.window.bounds.size

    let cy = absBounds.y + absBounds.height / 2
    let cx = absBounds.x + absBounds.width / 2

    case c.projectionMode
    of cpOrtho:
        var logicalSize = c.viewportSize
        if logicalSize == zeroSize:
            logicalSize = absBounds.size
        let k = absBounds.height / logicalSize.height
        let top = -cy / k
        let bottom = (winSize.height - cy) / k
        let left = -cx / k
        let right = (winSize.width - cx) / k

        mat.ortho(left, right, bottom, top, c.zNear, c.zFar)

        let frustumOffset = -10.0
        c.frustum.min = c.node.worldTransform() * newVector3(left + frustumOffset, top + frustumOffset, 0.0)
        c.frustum.max = c.node.worldTransform() * newVector3(right - frustumOffset, bottom - frustumOffset, 0.0)

    of cpPerspective:
        let top = -cy
        let bottom = winSize.height - cy
        let left = -cx
        let right = winSize.width - cx

        let angle = degToRad(c.fov) / 2.0
        let Z = absBounds.height / 2.0 / tan(angle)

        # near plane space
        let nLeft = c.zNear * left / Z
        let nRight = c.zNear * right / Z
        let nTop = c.zNear * top / Z
        let nBottom = c.zNear * bottom / Z

        mat.frustum(nLeft, nRight, -nBottom, -nTop, c.zNear, c.zFar)

    of cpManual:
        doAssert(not c.mManualGetProjectionMatrix.isNil)
        c.mManualGetProjectionMatrix(viewportBounds, mat)

proc intersectFrustum*(c: Camera, bbox: BBox): bool =
    if c.projectionMode != cpOrtho:
        return true

    if c.frustum.min.x < bbox.maxPoint.x and bbox.minPoint.x < c.frustum.max.x and c.frustum.min.y < bbox.maxPoint.y and bbox.minPoint.y < c.frustum.max.y:
        return true

proc `manualGetProjectionMatrix=`*(c: Camera, p: proc(viewportBounds: Rect, mat: var Transform3D)) =
    c.mManualGetProjectionMatrix = p
    c.projectionMode = cpManual

method visitProperties*(c: Camera, p: var PropertyVisitor) =
    p.visitProperty("zNear", c.zNear)
    p.visitProperty("zFar", c.zFar)
    p.visitProperty("fov", c.fov)
    p.visitProperty("vp size", c.viewportSize)
    p.visitProperty("projMode", c.projectionMode)

registerComponent(Camera)
