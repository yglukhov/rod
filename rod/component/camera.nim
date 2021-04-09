import nimx / [matrixes, types, context, property_visitor, view]
import rod / [component, rod_types, node]
import rod / utils / [ property_desc, serialization_codegen ]
import math

export CameraProjection
export Camera

Camera.properties:
    projectionMode
    zNear
    zFar
    fov
    viewportSize

method init*(c: Camera) =
    c.projectionMode = cpPerspective
    c.zNear = 1
    c.zFar = 10000
    c.fov = 30

proc calculateOrthoData(c: Camera): tuple[top, bottom, left, right: float] =
    let absBounds = c.node.sceneView.convertRectToWindow(c.node.sceneView.bounds)
    var winSize = absBounds.size
    if not c.node.sceneView.window.isNil:
        winSize = c.node.sceneView.window.bounds.size

    let cy = absBounds.y + absBounds.height / 2
    let cx = absBounds.x + absBounds.width / 2

    var logicalSize = c.viewportSize
    if logicalSize == zeroSize:
        logicalSize = absBounds.size
        c.viewportSize = logicalSize
    let k = absBounds.height / logicalSize.height
    result.top = -cy / k
    result.bottom = (winSize.height - cy) / k
    result.left = -cx / k
    result.right = (winSize.width - cx) / k

proc getFrustum*(c: Camera): Frustum =
    let d = c.calculateOrthoData()
    let frustumOffset = -10.0
    let wt = c.node.worldTransform()
    result.minPoint = wt * newVector3(d.left + frustumOffset, d.top + frustumOffset, 0.0)
    result.maxPoint = wt * newVector3(d.right - frustumOffset, d.bottom - frustumOffset, 0.0)

proc getProjectionMatrix*(c: Camera, viewportBounds: Rect, mat: var Transform3D) =
    doAssert(not c.node.sceneView.isNil)
    let absBounds = c.node.sceneView.convertRectToWindow(c.node.sceneView.bounds)
    var winSize = absBounds.size
    if not c.node.sceneView.window.isNil:
        winSize = c.node.sceneView.window.bounds.size

    let cy = absBounds.y + absBounds.height / 2
    let cx = absBounds.x + absBounds.width / 2

    case c.projectionMode
    of cpOrtho:
        let d = c.calculateOrthoData()
        mat.ortho(d.left, d.right, d.bottom, d.top, c.zNear, c.zFar)

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

method visitProperties*(c: Camera, p: var PropertyVisitor) =
    p.visitProperty("zNear", c.zNear)
    p.visitProperty("zFar", c.zFar)
    p.visitProperty("fov", c.fov)
    p.visitProperty("vp size", c.viewportSize)
    p.visitProperty("projMode", c.projectionMode)

genSerializationCodeForComponent(Camera)
registerComponent(Camera)
