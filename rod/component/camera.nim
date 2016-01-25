import nimx.matrixes
import nimx.types
import nimx.context

import rod.component
import rod.rod_types
import rod.property_visitor

export CameraProjection
export Camera

method init*(c: Camera) =
    c.projectionMode = cpPerspective
    c.zNear = 1
    c.zFar = 10000

proc getProjectionMatrix*(c: Camera, viewportBounds: Rect, mat: var Transform3D) =
    case c.projectionMode
    of cpOrtho:
        mat.ortho(-viewportBounds.width / 2, viewportBounds.width / 2, -viewportBounds.height / 2, viewportBounds.height / 2, c.zNear, c.zFar)
    of cpPerspective:
        mat.perspective(30, viewportBounds.width / viewportBounds.height, c.zNear, c.zFar)
    of cpManual:
        doAssert(not c.mManualGetProjectionMatrix.isNil)
        c.mManualGetProjectionMatrix(viewportBounds, mat)

proc `manualGetProjectionMatrix=`*(c: Camera, p: proc(viewportBounds: Rect, mat: var Transform3D)) =
    c.mManualGetProjectionMatrix = p
    c.projectionMode = cpManual

method visitProperties*(c: Camera, p: var PropertyVisitor) =
    p.visitProperty("zNear", c.zNear)
    p.visitProperty("zFar", c.zFar)

registerComponent[Camera]()
