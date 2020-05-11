import nimx / [ view, types, matrixes, context ]
import rod / [ rod_types, node, viewport ]
import rod / tools / debug_draw
import rod / editor / editor_types
import math

type EditorSceneGrid* = ref object of View
  gridSize: Size
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
  
  c.withTransform mvp:
    let p0 = v.currentScene.screenToWorldPoint(newVector3())
    let p1 = v.currentScene.screenToWorldPoint(newVector3(r.width, r.height))    
    var gr = newRect(p0.x, p0.y, p1.x - p0.x, p1.y - p0.y)

    gr.origin.x = gr.x - (gr.x mod v.gridSize.width)
    gr.origin.y = gr.y - (gr.y mod v.gridSize.height)
    c.strokeColor = newColor(0.0, 0.0, 0.0, 0.1)
    DDdrawGrid(gr, v.gridSize)

    
    gr.origin.x = gr.x - (gr.x mod (v.gridSize.width * 5))
    gr.origin.y = gr.y - (gr.y mod (v.gridSize.height * 5))
    c.strokeColor = newColor(0.0, 0.0, 0.0, 0.3)
    DDdrawGrid(gr, newSize(v.gridSize.width * 5, v.gridSize.height * 5))

    DDdrawRect(newRect(0, 0, 1920, 1080))
