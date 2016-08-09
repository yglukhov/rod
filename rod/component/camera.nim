import nimx.matrixes
import nimx.types
import nimx.context
import nimx.property_visitor

import rod.component
import rod.rod_types

export CameraProjection
export Camera

method init*(c: Camera) =
    c.projectionMode = cpPerspective
    c.zNear = 1
    c.zFar = 10000
    c.fov = 45

proc getProjectionMatrix*(c: Camera, viewportBounds: Rect, mat: var Transform3D) =
    case c.projectionMode
    of cpOrtho:
        if c.viewportSize.height > 0:
            let logicalWidth = viewportBounds.width / (viewportBounds.height / c.viewportSize.height)
            mat.ortho(-logicalWidth / 2, logicalWidth / 2, c.viewportSize.height / 2, -c.viewportSize.height / 2, c.zNear, c.zFar)
        else:
            mat.ortho(-viewportBounds.width / 2, viewportBounds.width / 2, -viewportBounds.height / 2, viewportBounds.height / 2, c.zNear, c.zFar)
    of cpPerspective:
        mat.perspective(c.fov, viewportBounds.width / viewportBounds.height, c.zNear, c.zFar)
    of cpManual:
        doAssert(not c.mManualGetProjectionMatrix.isNil)
        c.mManualGetProjectionMatrix(viewportBounds, mat)

proc `manualGetProjectionMatrix=`*(c: Camera, p: proc(viewportBounds: Rect, mat: var Transform3D)) =
    c.mManualGetProjectionMatrix = p
    c.projectionMode = cpManual

method visitProperties*(c: Camera, p: var PropertyVisitor) =
    p.visitProperty("zNear", c.zNear)
    p.visitProperty("zFar", c.zFar)
    p.visitProperty("projMode", c.projectionMode)

registerComponent[Camera]()
