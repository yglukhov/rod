import nimx / [ view, types, matrixes, context, portable_gl ]
import rod / [ rod_types, node, viewport ]
import rod / tools / debug_draw
import rod / editor / editor_types
import math

type EditorSceneGrid* = ref object of View
  gridSize*: Size
  currentScene: SceneView

method init*(v: EditorSceneGrid, r: Rect) =
  procCall v.View.init(r)
  v.gridSize = newSize(100, 100)

proc `scene=`*(v: EditorSceneGrid, s: SceneView) =
  v.currentScene = s

method draw*(v: EditorSceneGrid, r: Rect) =
  procCall v.View.draw(r)

  if v.currentScene.isNil: return

  let mvp = v.currentScene.getViewProjectionMatrix()
  let c = currentContext()
  

  template drawGrid(r: Rect,s: Size, color: Color) =
    var gr = r
    gr.origin.x = gr.x - (s.width + (gr.x mod s.width))
    gr.origin.y = gr.y - (s.height + (gr.y mod s.height))
    gr.size.width += s.width
    gr.size.height += s.height
    c.strokeColor = color
    
    DDdrawGrid(gr, s)


  c.withTransform mvp:
    let p0 = v.currentScene.screenToWorldPoint(newVector3())
    let p1 = v.currentScene.screenToWorldPoint(newVector3(r.width, r.height))    
    var gr = newRect(p0.x, p0.y, p1.x - p0.x, p1.y - p0.y)
    
    # looks like incorrect opengl state with ClipView, so this circle Won't be rendered
    DDdrawCircle(newVector3(), 1)

    drawGrid(gr, v.gridSize, newColor(0.0, 0.0, 0.0, 0.1))
    drawGrid(gr, newSize(v.gridSize.width * 5, v.gridSize.height * 5), newColor(0.0, 0.0, 0.0, 0.3))

    DDdrawRect(newRect(0, 0, v.currentScene.camera.viewportSize.width, v.currentScene.camera.viewportSize.height))
