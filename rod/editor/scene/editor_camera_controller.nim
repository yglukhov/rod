import nimx/[matrixes, types, event, view]
import rod/[viewport, rod_types, node, quaternion ]

type EditorCameraController* = ref object
    camera*: Node
    editedView: SceneView
    camPivot: Node
    camAnchor: Node

    startPos: Vector3
    startPivotPos: Vector3
    startPivotRot: Quaternion
    startAngle: Vector3
    currentAngle: Vector3
    currNode: Node
    currKey: VirtualKey
    currMouseKey: VirtualKey
    prev_x, prev_y: float


proc calculatePivotPos(camNode: Node): Vector3 =
    var dir = newVector3(0, 0, -1)
    dir = camNode.worldTransform().transformDirection(dir)
    dir.normalize()
    dir = dir * 100.0

    result = camNode.worldPos + dir

proc setCamera*(cc: EditorCameraController, camNode: Node) =
    cc.camPivot.worldPos = calculatePivotPos(camNode)

    var scale: Vector3
    var rot: Vector4
    discard camNode.worldTransform.tryGetScaleRotationFromModel(scale, rot)
    cc.camPivot.rotation = newQuaternion(rot.x, rot.y, rot.z, rot.w)

    cc.camAnchor.worldPos = camNode.worldPos
    cc.startPos = cc.camAnchor.worldPos
    cc.startPivotPos = cc.camPivot.worldPos
    cc.startPivotRot = cc.camPivot.rotation

    var q = cc.camPivot.rotation
    q.w = -q.w
    cc.currentAngle = q.eulerAngles()
    cc.startAngle = cc.currentAngle

proc newEditorCameraController*(view: SceneView) : EditorCameraController =
    new(result)
    result.editedView = view
    result.camPivot = newNode("EditorCameraPivot")
    result.camAnchor = newNode("EditorCameraAnchor")
    result.currentAngle = newVector3(0)

    result.editedView.rootNode.addChild(result.camPivot)
    result.camPivot.addChild(result.camAnchor)

    result.setCamera(result.editedView.camera.node)

proc updateCamera(cc: EditorCameraController) =
    var worldMat = cc.camAnchor.worldTransform()
    var pos: Vector3
    var scale: Vector3
    var rot: Vector4
    discard worldMat.tryGetTranslationFromModel(pos)
    discard worldMat.tryGetScaleRotationFromModel(scale, rot)

    cc.editedView.camera.node.worldPos = pos
    cc.editedView.camera.node.rotation = newQuaternion(rot.x, rot.y, rot.z, rot.w)

proc setToNode*(cc: EditorCameraController, n: Node) =
    cc.currNode = n
    if not cc.currNode.isNil and (cc.currNode != cc.editedView.camera.node):
        cc.camPivot.worldPos = cc.currNode.worldPos

    cc.updateCamera()

proc onTapDown*(cc: EditorCameraController, e : var Event) =
    cc.camAnchor.worldPos = cc.editedView.camera.node.worldPos
    cc.currMouseKey = e.keyCode
    cc.prev_x = 0.0
    cc.prev_y = 0.0

proc onTapUp*(cc: EditorCameraController, dx, dy : float32, e : var Event) =
    cc.currMouseKey = 0.VirtualKey

proc onKeyDown*(cc: EditorCameraController, e: var Event) =
    cc.currKey = e.keyCode

proc onKeyUp*(cc: EditorCameraController, e: var Event) =
    if e.keyCode == VirtualKey.R:
        cc.camPivot.rotation = cc.startPivotRot
        cc.camPivot.worldPos = cc.startPivotPos
        cc.camAnchor.worldPos = cc.startPos
        cc.currentAngle = cc.startAngle

        cc.updateCamera()

    cc.currKey = 0.VirtualKey

proc onScrollProgress*(cc: EditorCameraController, dx, dy : float, e : var Event) =
    if cc.editedView.camera.projectionMode == cpOrtho: 
        if cc.currMouseKey == VirtualKey.MouseButtonSecondary:

            var shift_pos = newVector3(cc.prev_x - dx, cc.prev_y - dy, 0.0) * cc.editedView.camera.node.scale
            cc.prev_x = dx
            cc.prev_y = dy
            cc.camPivot.worldPos = cc.camPivot.worldPos + shift_pos
            cc.updateCamera()
            
        return

    if cc.currKey == VirtualKey.LeftAlt or cc.currKey == VirtualKey.RightAlt:
        cc.currentAngle.x += cc.prev_y - dy
        cc.currentAngle.y += cc.prev_x - dx

        let q = newQuaternionFromEulerXYZ(cc.currentAngle.x, cc.currentAngle.y, cc.currentAngle.z)
        cc.camPivot.rotation = q

    if cc.currMouseKey == VirtualKey.MouseButtonMiddle:
        var speed = 0.1
        if cc.currKey == VirtualKey.LeftShift:
            speed = 1.0

        var shift_pos = newVector3(cc.prev_x - dx, -cc.prev_y + dy, 0.0) * speed
        var rotMat = cc.camPivot.rotation.toMatrix4()
        rotMat.multiply(shift_pos, shift_pos)

        cc.camPivot.worldPos = cc.camPivot.worldPos + shift_pos

    cc.prev_x = dx
    cc.prev_y = dy

    cc.updateCamera()


proc onMouseScrroll*(cc: EditorCameraController, e : var Event) =
    var dir: Vector3 = cc.camPivot.worldPos - cc.camAnchor.worldPos
    let ndir: Vector3 = normalized(dir)
    let offset: Vector3 = ndir * e.offset.y - ndir * e.offset.x * 10.0

    if cc.editedView.camera.projectionMode == cpOrtho:
        cc.editedView.camera.node.scale = cc.editedView.camera.node.scale + e.offset.y * 0.005
        return
    
    # 0 coord lock protection
    if length(offset) > length(dir) - 0.1 and dot(offset, dir) > 0.5:
        return

    cc.camAnchor.worldPos = cc.camAnchor.worldPos + offset

    cc.updateCamera()



