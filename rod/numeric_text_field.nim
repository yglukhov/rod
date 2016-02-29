import strutils
import nimx.text_field
import nimx.view_event_handling

type NumericTextField* = ref object of TextField
    precision*: uint

proc newNumericTextField*(r: Rect, precision: uint = 2): NumericTextField =
    result.new()
    result.init(r)
    result.precision = precision

method onScroll*(v: NumericTextField, e: var Event): bool =
    result = true
    var action = false
    try:
        var val = parseFloat(v.text)
        val += e.offset.y * 0.1
        v.text = formatFloat(val, ffDecimal, v.precision)
        action = true
        v.setNeedsDisplay()
    except:
        discard
    if action:
        v.sendAction()
