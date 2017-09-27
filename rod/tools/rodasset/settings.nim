import hashes, strutils, os

type AudioSettings* = object
    extension*: string # Audio file extension

type GraphicsSettings* = object
    downsampleRatio*: float
    compressOutput*: bool
    compressToPVR*: bool
    extrusion*: int
    disablePotAdjustment*: bool
    packCompositions*: bool
    quantizeExceptions*: seq[string]
    posterizeExceptions*: seq[string]

type Settings* = ref object
    graphics*: GraphicsSettings
    audio*: AudioSettings
    androidExternal*: bool
    debugOnly*: bool

proc init(g: var GraphicsSettings) {.inline.} =
    g.downsampleRatio = 1.0
    g.compressOutput = true
    g.compressToPVR = false
    g.extrusion = 1
    g.disablePotAdjustment = false
    g.quantizeExceptions = @[]
    g.posterizeExceptions = @[]

proc newSettings*(): Settings =
    result.new()
    result.audio.extension = "ogg"
    result.graphics.init()

proc hash*(s: AudioSettings | GraphicsSettings): Hash = hash($(s))

proc parseExceptions(val, dir: string): seq[string] =
    let values = val.split(",")

    result = @[]
    for v in values:
        if v.contains("*"):
            for file in walkFiles(dir / v):
                result.add(splitFile(file).name)
        else:
            result.add(v)

proc parseConfig*(rabFilePath: string, fast: bool = false): Settings =
    result = newSettings()

    result.graphics.extrusion = 1
    result.graphics.downsampleRatio = 1.0
    result.graphics.packCompositions = true

    for line in lines(rabFilePath):
        let pairs = line.split(" ")
        let key = pairs[0]
        let val = pairs[1]
        case key:
        of "extrusion":
            result.graphics.extrusion = parseInt(val)
        of "disablePotAdjustment":
            result.graphics.disablePotAdjustment = parseBool(val)
        of "downsampleRatio":
            result.graphics.downsampleRatio = parseFloat(val)
        of "exceptions":
            if not fast:
                result.graphics.quantizeExceptions = parseExceptions(val, rabFilePath.parentDir)
        of "noquant":
            if not fast:
                result.graphics.quantizeExceptions = parseExceptions(val, rabFilePath.parentDir)
        of "noposterize":
            if not fast:
                result.graphics.posterizeExceptions = parseExceptions(val, rabFilePath.parentDir)
        of "debugOnly":
            result.debugOnly = parseBool(val)
        of "packCompositions":
            result.graphics.packCompositions = parseBool(val)
        of "androidExternal":
            result.androidExternal = parseBool(val)
