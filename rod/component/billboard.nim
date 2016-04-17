import tables

import nimx.context
import nimx.types
import nimx.view
import nimx.matrixes

import rod.node
import rod.property_visitor
import rod.viewport
import rod.quaternion
import rod.component
import rod.component.camera

type Billboard* = ref object of Component
    initialDistanceToCamera: float32
    initialScale: Vector3
    bFixedSize: bool

proc recursiveDrawPost(n: Node) =
    if n.alpha < 0.0000001: return
    let c = currentContext()
    var tr = c.transform
    let oldAlpha = c.alpha
    c.alpha *= n.alpha
    tr.translate(n.translation)
    tr.scale(n.scale)
    c.withTransform tr:
        var hasPosteffectComponent = false
        if not n.components.isNil:
            for v in values(n.components):
                v.draw()
                hasPosteffectComponent = hasPosteffectComponent or v.isPosteffectComponent()
        if not hasPosteffectComponent:
            for c in n.children: c.recursiveDrawPost()
    c.alpha = oldAlpha

method draw*(b: Billboard) =
    let vp = b.node.sceneView

    var modelMatrix: Matrix4
    modelMatrix.lookAt(eye = vp.mCamera.node.worldPos, center = b.node.worldPos, up = newVector3(0,1,0))

    var translation, scale: Vector3
    var rotation: Vector4
    discard modelMatrix.tryGetTranslationFromModel(translation)
    discard modelMatrix.tryGetScaleRotationFromModel(scale, rotation)

    b.node.rotation = rotation

    if b.bFixedSize:
        let currDist = vp.mCamera.node.worldPos - b.node.worldPos
        if b.initialDistanceToCamera == 0:
            b.initialDistanceToCamera = currDist.length()
            b.initialScale = b.node.scale
        let deltaScale = b.initialDistanceToCamera / currDist.length()
        b.node.scale = b.initialScale / deltaScale

    var mvpMatrix: Matrix4
    mvpMatrix.loadIdentity()
    mvpMatrix.translate(b.node.worldPos)
    mvpMatrix.multiply(b.node.rotation.toMatrix4(), mvpMatrix)
    mvpMatrix.scale(b.node.scale)

    mvpMatrix = vp.getViewProjectionMatrix() * mvpMatrix

    let c = currentContext()
    c.withTransform mvpMatrix:
        for c in b.node.children: c.recursiveDrawPost()

method isPosteffectComponent*(b: Billboard): bool = true

method visitProperties*(b: Billboard, p: var PropertyVisitor) =
    p.visitProperty("fixed_size", b.bFixedSize)

registerComponent[Billboard]()
