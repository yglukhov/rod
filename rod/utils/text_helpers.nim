import nimx/types
import strutils

proc fromHexColor*(clr: string): Color =
    doAssert(clr.len == 8)

    template getComp(start: int): float =
        parseHexInt(clr.substr(start, start + 1)).float / 255.0

    result.r = getComp(0)
    result.g = getComp(2)
    result.b = getComp(4)
    result.a = getComp(6)

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