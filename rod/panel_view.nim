import nimx.view
import nimx.app
import nimx.event
import nimx.view_event_handling

type PanelView* = ref object of View

method init*(v: PanelView, r: Rect) =
    procCall v.View.init(r)
    v.backgroundColor = newColor(0.5, 0.5, 0.5, 0.5)

method onMouseDown*(v: PanelView, e: var Event): bool =
    let origPos = v.superview.convertPointToWindow(v.frame.origin)
    let dp = e.position - origPos

    mainApplication().pushEventFilter do(e: var Event, c: var EventFilterControl) -> bool:
        result = true
        if e.kind == etMouse:
            e.localPosition = v.convertPointFromWindow(e.position)
            if e.isButtonUpEvent():
                c = efcBreak
                result = v.onMouseUp(e)
            elif e.isMouseMoveEvent():
                let newPos = v.superview.convertPointFromWindow(e.position - dp)
                v.setFrameOrigin(newPos)
                v.setNeedsDisplay()
