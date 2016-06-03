import nimx.matrixes
import nimx.types
import nimx.event
import nimx.gesture_detector_newtouch
import nimx.view

import rod.viewport
import rod.rod_types
import rod.node
import rod.quaternion
import rod.component.camera

type EditorCameraController* = ref object
    camera*: Node
    camPivot: Node
    camAnchor: Node
    test: Node
    currentShift: Vector3
    currNode: Node
    currKey: VirtualKey
    currMouseKey: VirtualKey

proc newEditorCameraController*(camera: Node) : EditorCameraController =
    new(result)
    result.camera = camera
    result.camPivot = newNode("EditorCameraPivot")
    result.camAnchor = newNode("EditorCameraAnchor")
    result.camAnchor.translation = camera.translation
    result.currentShift = newVector3(0)

    camera.parent.addChild(result.camPivot)
    result.camPivot.addChild(result.camAnchor)

proc updateCamera(cc: EditorCameraController) =
    var worldMat = cc.camAnchor.worldTransform()
    var pos: Vector3
    var scale: Vector3
    var rot: Quaternion
    discard worldMat.tryGetTranslationFromModel(pos)
    discard worldMat.tryGetScaleRotationFromModel(scale, rot)

    cc.camera.translation = pos
    cc.camera.rotation = newQuaternion(rot.x, rot.y, rot.z, -rot.w)

proc setToNode*(cc: EditorCameraController, n: Node) =
    cc.currNode = n
    echo "setToNode  "
    if not cc.currNode.isNil:
        cc.camPivot.translation = cc.currNode.worldPos
    else:
        cc.camPivot.translation = newVector3(0.0)

    cc.updateCamera()

var prev_x = 0.0
var prev_y = 0.0
proc onTapDown*(cc: EditorCameraController, e : var Event) =
    cc.currMouseKey = e.keyCode
    prev_x = 0.0
    prev_y = 0.0


proc onTapUp*(cc: EditorCameraController, dx, dy : float32, e : var Event) =
    cc.currMouseKey = 0.VirtualKey

proc onKeyDown*(cc: EditorCameraController, e: var Event) =
    cc.currKey = e.keyCode
    if e.keyCode == VirtualKey.F:
        if not cc.currNode.isNil:
            cc.camPivot.translation = cc.currNode.translation
        else:
            cc.camPivot.translation = newVector3(0.0)

proc onKeyUp*(cc: EditorCameraController, e: var Event) =
    if e.keyCode == VirtualKey.R:
        cc.camPivot.rotation = newQuaternion(0.0, 0.0, 0.0, 1.0)
        cc.camPivot.translation = newVector3(0.0)
        cc.updateCamera()

    cc.currKey = 0.VirtualKey

proc onScrollProgress*(cc: EditorCameraController, dx, dy : float, e : var Event) =
    if cc.currKey == VirtualKey.LeftAlt or cc.currKey == VirtualKey.RightAlt:
        cc.currentShift.x -= prev_y - dy
        cc.currentShift.y -= prev_x - dx

        let q = newQuaternionFromEulerXYZ(cc.currentShift.x, cc.currentShift.y, cc.currentShift.z)
        cc.camPivot.rotation = q

    if cc.currMouseKey == VirtualKey.MouseButtonMiddle:
        var shift_pos = newVector3(prev_x - dx, -prev_y + dy, 0.0) * 0.1
        var rotMat = cc.camPivot.rotation.toMatrix4()
        shift_pos = rotMat.transformPoint(shift_pos)
        # shift_pos = viewMatrix.transformPoint(shift_pos)

        cc.camPivot.translation += shift_pos

    prev_x = dx
    prev_y = dy

    cc.updateCamera()

proc onMouseScrroll*(cc: EditorCameraController, e : var Event) =
    var dir = -cc.camAnchor.translation
    dir.normalize()
    cc.camAnchor.translation += dir * e.offset.y

    cc.updateCamera()

# proc onScrollProgress*(cc: EditorCameraController, dx, dy : float32, e : var Event) =
#     cc.currentAngle.x = dy
#     cc.currentAngle.y = dx
#     let q = newQuaternionFromEulerYXZ(cc.currentAngle.x, cc.currentAngle.y, cc.currentAngle.z)
#     cc.camPivot.rotation = q

#     var scale: Vector3
#     var rot: Quaternion
#     var pivotMatrix = cc.camPivot.worldTransform()

#     var lookMat = toLookAt(cc.camPivot.worldPos(), cc.camAnchor.worldPos(), newVector3(0,1,0))
#     var lookquat = lookMat.fromMatrix4()

#     cc.camera.rotation = lookquat
#     cc.camera.translation = cc.camAnchor.worldPos()
#     cc.camera.sceneView.setNeedsDisplay()


