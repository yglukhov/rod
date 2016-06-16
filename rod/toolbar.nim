import nimx.view, nimx.context
import view_dragging_listener

type Toolbar* = ref object of View

method init*(v: Toolbar, r: Rect) =
    procCall v.View.init(r)
    v.enableDraggingByBackground()

const leftMargin = 10.Coord
const xPadding = 3.Coord
const verticalMargin = 3.Coord

method resizeSubviews*(v: Toolbar, oldSize: Size) =
    var x = leftMargin
    let height = v.bounds.height - verticalMargin * 2
    for s in v.subviews:
        var fr = s.frame
        fr.origin.x = x
        fr.origin.y = verticalMargin
        fr.size.height = height
        x += fr.width + xPadding
        s.setFrame(fr)

method draw*(view: Toolbar, rect: Rect) =
    let c = currentContext()
    c.strokeWidth = 2
    c.strokeColor = newGrayColor(0.6, 0.7)
    c.fillColor = newGrayColor(0.3, 0.7)
    c.drawRoundedRect(view.bounds, 5)

proc updateWidth(v: Toolbar) =
    var totalWidth = leftMargin
    for s in v.subviews:
        totalWidth += s.frame.width + xPadding
    v.setFrameSize(newSize(totalWidth, v.frame.height))

proc addSubview*(v: Toolbar, s: View) =
    procCall v.View.addSubview(s)
    v.updateWidth()
