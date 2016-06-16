import nimx.gesture_detector_newtouch
import nimx.view
import nimx.event

type DraggingScrollListener = ref object of OnScrollListener
    view: View
    diff: Point

proc newDraggingScrollListener(v: View): DraggingScrollListener =
    result.new
    result.view = v

method onTapDown(ls: DraggingScrollListener, e: var Event) =
    ls.diff = e.localPosition

method onScrollProgress(ls: DraggingScrollListener, dx, dy : float32, e : var Event) =
    ls.view.setFrameOrigin(e.position - ls.diff)
    ls.view.setNeedsDisplay()

proc enableDraggingByBackground*(v: View) =
     v.addGestureDetector(newScrollGestureDetector(newDraggingScrollListener(v)))
