import math
import nimx.view
import nimx.app
import nimx.event
import nimx.view_event_handling
import nimx.context
import nimx.types
import nimx.composition

type PanelView* = ref object of View
    collapsible*: bool
    collapsed*: bool

    fullHeight*: Coord

method init*(v: PanelView, r: Rect) =
    procCall v.View.init(r)
    v.backgroundColor = newColor(0.5, 0.5, 0.5, 0.5)
    v.collapsed = false
    v.collapsible = false
    v.fullHeight = r.height

var disclosureTriangleComposition = newComposition """
uniform float uAngle;

void compose() {
    vec2 center = vec2(bounds.x + bounds.z / 2.0, bounds.y + bounds.w / 2.0 - 1.0);
    float triangle = sdRegularPolygon(center, 4.0, 3, uAngle);
    drawShape(triangle, vec4(0.5, 0.5, 0.5, 1));
}
"""

proc drawDisclosureTriangle(disclosed: bool, r: Rect) =
    disclosureTriangleComposition.draw r:
        setUniform("uAngle", if disclosed: Coord(PI / 2.0) else: Coord(0))
    discard

var gradientComposition = newComposition """
void compose() {
    vec4 color = gradient(
        smoothstep(bounds.y, 27.0, vPos.y),
        newGrayColor(0.5),
        newGrayColor(0.2)
    );
    drawShape(sdRoundedRect(bounds, 6.0), color);
}
"""

method draw(v: PanelView, r: Rect) =
    # Draws Panel View
    let c = currentContext()

    # Top label
    c.fillColor = newGrayColor(0.15)
    c.strokeColor = newGrayColor(0.15)

    c.drawRoundedRect(newRect(r.x, r.y, r.width, r.height), 6)

    if v.collapsible:
        if not v.collapsed:
            # Main panel
            c.fillColor = newGrayColor(0.35)
            c.strokeColor = newGrayColor(0.35)
            c.drawRect(newRect(r.x, r.y + 27, r.width, r.height - 27))

            # Collapse button open
            drawDisclosureTriangle(true, newRect(r.x, r.y, 27, 27))
        else:
            v.setFrameSize(newSize(v.frame.size.width, if v.collapsed: 27.Coord else: v.fullHeight))
            v.setNeedsDisplay()

            # Collapse button close
            drawDisclosureTriangle(false, newRect(r.x, r.y, 27, 27))

method clipType*(v: PanelView): ClipType = ctDefaultClip

method onMouseDown*(v: PanelView, e: var Event): bool =
    let origPos = v.superview.convertPointToWindow(v.frame.origin)
    let dp = e.position - origPos

    mainApplication().pushEventFilter do(e: var Event, c: var EventFilterControl) -> bool:
        result = true
        if e.kind == etMouse:
            e.localPosition = v.convertPointFromWindow(e.position)
            if e.localPosition.x > 0 and e.localPosition.x < 27 and e.localPosition. y > 0 and e.localPosition.y < 27 and e.isButtonUpEvent():
                if v.collapsible:
                    v.collapsed = not v.collapsed
                    v.setFrameSize(newSize(v.frame.size.width, if v.collapsed: 27.Coord else: v.fullHeight))
                    v.setNeedsDisplay()
                    c = efcBreak
            else:
                if e.isButtonUpEvent():
                    c = efcBreak
                    result = v.onMouseUp(e)
                elif e.isMouseMoveEvent():
                    let newPos = v.superview.convertPointFromWindow(e.position - dp)
                    v.setFrameOrigin(newPos)
                    v.setNeedsDisplay()
