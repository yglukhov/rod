import nimx / [ view, app, layout]
import ../../ rod / [ rod_types, message_queue ]
import ./animation / animation_editor_types
import ./[editor_api, editor_composition]
export editor_api, editor_composition, message_queue

type
  EditorMode* {.pure.} = enum
    edit
    animation
    play

  EditorBaseView* = ref object of View
  EditorTabView* = ref object of EditorBaseView
    composition*: CompositionDocument
    commandsQueue*: EditorCommandQueue

  EditorTabPanel* = ref object of EditorBaseView

method onCompositionChanged*(v: EditorTabView, c: CompositionDocument) {.base, gcsafe.} =
  v.composition = c

method onEditorEvent*(v: EditorBaseView, ev: EditorAPIEvent) {.base, gcsafe.} = discard
method setInspectedNode*(v: EditorBaseView, n: Node) {.base, gcsafe.} = discard

method tabs*(v: EditorTabPanel): seq[EditorTabView] {.base, gcsafe.} = @[]

proc addOriginConstraints(w: Window, v: View, desiredOrigin: Point) =
  let w = mainApplication().keyWindow
  var wp = desiredOrigin
  v.addConstraint(modifyStrength(selfPHS.x == wp.x, MEDIUM))
  v.addConstraint(modifyStrength(selfPHS.y == wp.y, MEDIUM))
  v.addConstraint(selfPHS.leading >= w.layout.vars.leading)
  v.addConstraint(selfPHS.trailing <= w.layout.vars.trailing)
  v.addConstraint(selfPHS.top >= w.layout.vars.top)
  v.addConstraint(selfPHS.bottom <= w.layout.vars.bottom)

proc popupAtPoint*(v: View, p: Point) =
  let w = mainApplication().keyWindow
  w.addOriginConstraints(v, p)
  w.addSubview(v)


const
  uiPrimary*      = newColor(0.180, 0.380, 0.800)  # Blue
  uiSecondary*    = newColor(0.120, 0.120, 0.140)  # Dark Gray
  uiAccent*       = newColor(0.950, 0.780, 0.250)  # Gold
  uiBackground*   = newColor(0.090, 0.090, 0.110)  # Almost Black
  uiSurface*      = newColor(0.160, 0.160, 0.180)  # Card Background
  uiText*         = newColor(0.900, 0.900, 0.900)  # White
  uiTextMuted*    = newColor(0.600, 0.620, 0.640)  # Gray
  uiDanger*       = newColor(0.850, 0.250, 0.250)  # Red
  uiSuccess*      = newColor(0.250, 0.750, 0.350)  # Green
  uiHighlight*    = newColor(0.450, 0.900, 0.950)  # Cyan

const
  uiPink*     = newColor(0.98, 0.80, 0.80) # Soft pink
  uiPeach*    = newColor(0.99, 0.87, 0.76) # Peach
  uiYellow*   = newColor(1.00, 0.97, 0.80) # Light yellow
  uiGreen*    = newColor(0.80, 0.93, 0.80) # Mint green
  uiBlue*     = newColor(0.80, 0.88, 0.95) # Baby blue
  uiLavender* = newColor(0.87, 0.80, 0.95) # Soft lavender
  uiGray*     = newColor(0.90, 0.90, 0.90) # Warm light gray