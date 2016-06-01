import nimx.matrixes
import nimx.types
import nimx.event
import nimx.gesture_detector_newtouch
import nimx.view

import rod.rod_types
import rod.node
import rod.quaternion
import rod.component.camera

type EditorCameraController* = ref object
    camera*: Node
    camPivot: Node
    camAnchor: Node
    test: Node
    currentAngle: Vector3

proc newEditorCameraController*(camera: Node) : EditorCameraController =
    new(result)
    result.camera = camera
    result.camPivot = newNode("EditorCameraPivot")#newNodeWithResource("Jsondata/pivot.json", true)#
    result.camAnchor = newNode("EditorCameraAnchor")
    result.camAnchor.translation = camera.translation
    result.currentAngle = newVector3(0)

    camera.parent.addChild(result.camPivot)
    result.camPivot.addChild(result.camAnchor)

proc setToNode(cc: EditorCameraController, n: Node) =
    cc.camPivot.translation = n.translation
    cc.camAnchor.translation = cc.camera.translation

proc onTapDown*(cc: EditorCameraController, e : var Event) =
    echo "onTapDown"
    cc.camAnchor.translation = cc.camera.translation

proc onScrollProgress*(cc: EditorCameraController, dx, dy : float32, e : var Event) =
    cc.currentAngle.x = dy
    cc.currentAngle.y = dx
    let q = newQuaternionFromEulerYXZ(cc.currentAngle.x, cc.currentAngle.y, cc.currentAngle.z)
    cc.camPivot.rotation = q


    var scale: Vector3
    var rot: Quaternion
    var pivotMatrix = cc.camPivot.worldTransform()

    var lookMat = toLookAt(cc.camPivot.worldPos(), cc.camAnchor.worldPos(), newVector3(0,1,0))
    var lookquat = lookMat.fromMatrix4()

    cc.camera.rotation = lookquat
    cc.camera.translation = cc.camAnchor.worldPos()
    cc.camera.sceneView.setNeedsDisplay()


proc onTapUp*(cc: EditorCameraController, dx, dy : float32, e : var Event) =
    echo "onTapUp"