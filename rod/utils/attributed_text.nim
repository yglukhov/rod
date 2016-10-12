import strutils
import unicode

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
    lineSpacing

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
    result = @[]

    proc getTextAttributes(text: var string): TextAttributes =
        var tagOpened: bool
        var currentAttr = TextAttributes.new()
        var strWithAttr = ""
        var middle: int
        var i: int

        var middleOffset: int
        var startOffset: int
        var rune: Rune
        var offset = 0

        while offset < text.len:
            fastRuneAt(text, offset, rune)
            let ordRune = rune.int32

            if ordRune == ord('\"') and text.continuesWith(">", offset):
                middle = i + 1
                middleOffset = offset
            if  tagOpened and ordRune == ord('\"') and text.continuesWith(">", offset):
                tagOpened = false
            elif ordRune == ord('<') and text.continuesWith("/span>", offset):
                currentAttr.to = i - 1
                text.delete(offset - 1, offset + 5) # /span> len
                text.delete(startOffset - 1, middleOffset)
                break
            elif  tagOpened:
                var pos = strWithAttr.len
                fastToUTF8Copy(rune, strWithAttr, pos)
            elif ordRune == ord('<') and text.continuesWith("span style=", offset):
                currentAttr.start = i
                startOffset = offset
                tagOpened = true
            i.inc()

        currentAttr.to = currentAttr.to - (middle - currentAttr.start)
        currentAttr.attributes = @[]

        for attrType in TextAttributeType.low..TextAttributeType.high:
            let findAttr = strWithAttr.find($attrType & ":")
            if findAttr > -1:
                var index = findAttr + ($attrType).len
                if index > -1:
                    var attr: Attribute
                    var letter: char

                    attr.value = ""
                    attr.typ = attrType
                    index.inc()
                    while letter != '\"' and letter != ';' and index <= strWithAttr.len:
                        if letter != '\0':
                            attr.value &= letter
                        letter = strWithAttr[index]
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
                elif a.typ == TextAttributeType.lineSpacing:
                    fText.lineSpacing = parseFloat(a.value)

when isMainModule:
    block: # Test latin symbols string
        var toParse = "It's a small\n<span style=\"strokeColor:FF0000FF;strokeSize:3.5;isColorGradient:true;colorFrom:00FF00FF;colorTo:0000FFFF\">string</span> example - <span style=\"color:FFFF00FF\">duh</span>!"
        let original = "It's a small\nstring example - duh!"
        let textAttributesSet = parseAttributedStr(toParse)
        let first = textAttributesSet[0]
        let second = textAttributesSet[1]

        doAssert(toParse == original)
        doAssert(first.start == 13)
        doAssert(first.to == 19)
        doAssert(second.start == 30)
        doAssert(second.to == 33)
        doAssert((first.attributes[0]).typ == TextAttributeType.strokeSize)
        doAssert((first.attributes[1]).typ == TextAttributeType.strokeColor)
        doAssert((first.attributes[2]).value == "true")
        doAssert((first.attributes[3]).value == "00FF00FF")
        doAssert((second.attributes[0]).typ == TextAttributeType.color and (second.attributes[0]).value == "FFFF00FF")

    block: # Test cyrillic symbols string
        var toParse = "<span style=\"shadowX:-3.67;shadowY:2.0;shadowColor:000000FF\">Хороший</span> <span style=\"fontSize:100\">БОРЩ</span> - с капусточкой, но не <span style=\"color:FF0000FF\">красный</span>..."
        let original = "Хороший БОРЩ - с капусточкой, но не красный..."
        let textAttributesSet = parseAttributedStr(toParse)
        let first = textAttributesSet[0]
        let second = textAttributesSet[1]
        let third = textAttributesSet[2]
        let clr = newColor(1.0, 0, 0)

        doAssert(toParse == original)
        doAssert(first.start == 0)
        doAssert(first.to == 7)
        doAssert(second.start == 8)
        doAssert(second.to == 12)
        doAssert(third.start == 36)
        doAssert(third.to == 43)
        doAssert((parseFloat(first.attributes[0].value)) == -3.67)
        doAssert((parseFloat(first.attributes[1].value)) == 2.0)
        doAssert((first.attributes[2]).typ == TextAttributeType.shadowColor)
        doAssert((second.attributes[0]).typ == TextAttributeType.fontSize)
        doAssert((fromHexColor(third.attributes[0].value)) == clr)


