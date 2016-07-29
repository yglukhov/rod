import nimx.view

type DopesheetView* = ref object of View

method init*(v: DopesheetView, r: Rect) =
    procCall v.View.init(r)
    v.backgroundColor = newColor(1, 0, 0, 0.5)
