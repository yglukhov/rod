import hashes

type AudioSettings* = ref object
    extension*: string # Audio file extension

type GraphicsSettings* = ref object
    downsampleRatio*: float
    compressOutput*: bool
    compressToPVR*: bool
    extrusion*: int
    disablePotAdjustment*: bool
    compressionExceptions*: string

type Settings* = ref object
    graphics*: GraphicsSettings
    audio*: AudioSettings

proc newSettings*(): Settings =
    result.new()
    result.audio.new()
    let a = result.audio
    a.extension = "ogg"

    result.graphics.new()
    let g = result.graphics
    g.downsampleRatio = 1.0
    g.compressOutput = true
    g.compressToPVR = false
    g.extrusion = 1
    g.disablePotAdjustment = false
    g.compressionExceptions = ""

proc hash*(s: AudioSettings | GraphicsSettings): Hash = hash($(s[]))
