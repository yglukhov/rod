import strutils
import nimx.text_field
import nimx.view_event_handling

type NumericTextField* = ref object of TextField

proc newNumericTextField*(r: Rect): NumericTextField =
    result.new()
    result.init(r)

method onScroll*(v: NumericTextField, e: var Event): bool =
    var action = false
    try:
        var val = parseFloat(v.text)
        val += e.offset.y * 0.1
        v.text = $val
        action = true
        v.setNeedsDisplay()
    except:
        discard
    if action:
        v.sendAction()
