import strutils
import unicode
import os

import nimx.unistring
import nimx.types
import nimx.formatted_text
import nimx.font

type TextAttributeType* {.pure.} = enum
    color
    shadowX
    shadowY
    shadowColor
    shadowRadius
    shadowSpread
    font
    fontSize
    trackingAmount
    strokeSize
    strokeColor
    strokeColorFrom
    strokeColorTo
    isStrokeGradient
    isColorGradient
    colorFrom
    colorTo

type Attribute* = tuple[typ: TextAttributeType, value: string]

type TextAttributes* = ref object of RootObj
    start*: int
    to*: int
    attributes*: seq[Attribute]

proc fromHexColor*(clr: string): Color =
    doAssert(clr.len == 8)

    template getComp(start: int): float =
        parseHexInt(clr.substr(start, start + 1)).float / 255.0

    result.r = getComp(0)
    result.g = getComp(2)
    result.b = getComp(4)
    result.a = getComp(6)

proc isStringAttributed*(str: string): bool =
    return str.find("<span style=") > -1

proc removeTextAttributes*(text: string): string =
    var tagOpened: bool
    for i in 0..<text.len:
        let letter = $(text[i])
        if letter != "<" and not tagOpened:
            result &= letter
        elif letter == "<" and (text.continuesWith("span style", i + 1) or text.continuesWith("/span", i + 1)) :
            tagOpened = true
        elif letter == ">":
            tagOpened = false

proc parseAttributedStr(str: var string): seq[TextAttributes] =
    var br = 0
    result = @[]

    proc getTextAttributes(text: var string): TextAttributes =
        var tagOpened: bool
        var currentAttr = TextAttributes.new()
        var strWithAttr = ""
        var middle: int
        var i: int

        for rune in text.runes:
            let letter = $rune
            let offset = text.runeOffset(i)

            if letter == "\"" and text.continuesWith(">", offset + 1):
                middle = i + 1
            if  tagOpened and letter == "\"" and text.continuesWith(">", offset + 1):
                tagOpened = false
            elif letter == "<" and text.continuesWith("/span>", offset + 1):
                currentAttr.to = i - 1
                text.uniDelete(i, i + 6) # /span> len
                text.uniDelete(currentAttr.start, middle)
                break
            elif  tagOpened:
                strWithAttr &= letter
            elif letter == "<" and text.continuesWith("span style=", offset + 1):
                currentAttr.start = i
                tagOpened = true
            i.inc()

        currentAttr.to = currentAttr.to - (middle - currentAttr.start)
        currentAttr.attributes = @[]

        for attrType in TextAttributeType.low..TextAttributeType.high:
            if strWithAttr.find($attrType & ":") > -1:
                var index = strWithAttr.find($attrType & ":") + ($attrType).len
                if index > -1:
                    var attr: Attribute
                    var letter = ""

                    attr.value = ""
                    attr.typ = attrType
                    index.inc()
                    while letter != "\"" and letter != ";" and index <= strWithAttr.len:
                        attr.value &= letter
                        letter = $strWithAttr[index]
                        index.inc()

                    currentAttr.attributes.add(attr)
                    result = currentAttr

    while str.isStringAttributed():
        let attrs = getTextAttributes(str)

        if not attrs.isNil:
            result.add(attrs)

    # for res in result:
    #     echo "res ", res.start, " ", res.to, " ", res.attributes

proc processAttributedText*(fText: FormattedText) =
    if fText.text.isStringAttributed():
        let textAttributesSet = parseAttributedStr(fText.text)
        for ta in textAttributesSet:
            let attrs = ta.attributes

            for a in attrs:
                if a.typ == TextAttributeType.color:
                    let col = fromHexColor(a.value)
                    fText.setTextColorInRange(ta.start, ta.to, col)
                elif a.typ == TextAttributeType.font:
                    let existingFont = fText.fontOfRuneAtPos(ta.start)
                    var s = systemFontSize()

                    if not existingFont.isNil:
                        s = existingFont.size
                        fText.setFontInRange(ta.start, ta.to, newFontWithFace(a.value, s))
                elif a.typ == TextAttributeType.fontSize:
                    let font = fText.fontOfRuneAtPos(ta.start)

                    if not font.isNil:
                        let font = newFontWithFace(font.face, parseFloat(a.value))
                        fText.setFontInRange(ta.start, ta.to, font)
                    else:
                        raise newException(Exception, "You should have font to resize it for string: " & fText.text)
                elif a.typ == TextAttributeType.shadowX:
                    var s = fText.shadowOfRuneAtPos(ta.start)
                    s.offset.width = parseFloat(a.value)
                    fText.setShadowInRange(ta.start, ta.to, s.color, s.offset, s.radius, s.spread)
                elif a.typ == TextAttributeType.shadowY:
                    var s = fText.shadowOfRuneAtPos(ta.start)
                    s.offset.height = parseFloat(a.value)
                    fText.setShadowInRange(ta.start, ta.to, s.color, s.offset, s.radius, s.spread)
                elif a.typ == TextAttributeType.shadowColor:
                    var s = fText.shadowOfRuneAtPos(ta.start)
                    s.color = fromHexColor(a.value)
                    fText.setShadowInRange(ta.start, ta.to, s.color, s.offset, s.radius, s.spread)
                elif a.typ == TextAttributeType.shadowRadius:
                    var s = fText.shadowOfRuneAtPos(ta.start)
                    s.radius = parseFloat(a.value)
                    fText.setShadowInRange(ta.start, ta.to, s.color, s.offset, s.radius, s.spread)
                elif a.typ == TextAttributeType.shadowSpread:
                    var s = fText.shadowOfRuneAtPos(ta.start)
                    s.spread = parseFloat(a.value)
                    fText.setShadowInRange(ta.start, ta.to, s.color, s.offset, s.radius, s.spread)
                elif a.typ == TextAttributeType.trackingAmount:
                    fText.setTrackingInRange(ta.start, ta.to, parseFloat(a.value))
                elif a.typ == TextAttributeType.strokeSize:
                    var s = fText.strokeOfRuneAtPos(0)
                    s.size = parseFloat(a.value)
                    if s.isGradient:
                        fText.setStrokeInRange(ta.start, ta.to, s.color1, s.color2, s.size)
                    else:
                        fText.setStrokeInRange(ta.start, ta.to, s.color1, s.size)
                elif a.typ == TextAttributeType.strokeColor:
                    var s = fText.strokeOfRuneAtPos(ta.start)
                    s.color1 = fromHexColor(a.value)
                    fText.setStrokeInRange(ta.start, ta.to, s.color1, s.size)
                elif a.typ == TextAttributeType.strokeColorFrom:
                    var s = fText.strokeOfRuneAtPos(ta.start)
                    s.color1 = fromHexColor(a.value)
                    fText.setStrokeInRange(ta.start, ta.to, s.color1, s.color2, s.size)
                elif a.typ == TextAttributeType.strokeColorTo:
                    var s = fText.strokeOfRuneAtPos(ta.start)
                    s.color2 = fromHexColor(a.value)
                    fText.setStrokeInRange(ta.start, ta.to, s.color1, s.color2, s.size)
                elif a.typ == TextAttributeType.isStrokeGradient:
                    var s = fText.strokeOfRuneAtPos(ta.start)
                    if parseBool(a.value):
                        fText.setStrokeInRange(ta.start, ta.to, s.color1, s.color2, s.size)
                    else:
                        fText.setStrokeInRange(ta.start, ta.to, s.color1, s.size)
                elif a.typ == TextAttributeType.isColorGradient:
                    var s = fText.colorOfRuneAtPos(ta.start)
                    if parseBool(a.value):
                        fText.setTextColorInRange(ta.start, ta.to, s.color1, s.color2)
                    else:
                        fText.setTextColorInRange(ta.start, ta.to, s.color1)
                elif a.typ == TextAttributeType.colorFrom:
                    var s = fText.colorOfRuneAtPos(ta.start)
                    s.color1 = fromHexColor(a.value)
                    fText.setTextColorInRange(ta.start, ta.to, s.color1, s.color2)
                elif a.typ == TextAttributeType.colorTo:
                    var s = fText.colorOfRuneAtPos(ta.start)
                    s.color2 = fromHexColor(a.value)
                    fText.setTextColorInRange(ta.start, ta.to, s.color1, s.color2)


