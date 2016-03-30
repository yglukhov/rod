import strutils, algorithm, future
import adobe_tools
import dom
export adobe_tools

type File = adobe_tools.File

type
    Application* = ref ApplicationObj
    ApplicationObj {.importc.} = object of RootObj
        project*: Project
        settings*: Settings

    Settings* = ref SettingsObj
    SettingsObj {.importc.} = object of RootObj

    Project* = ref ProjectObj
    ProjectObj {.importc.} = object of RootObj
        selection*: seq[Item]
        rootFolder*: FolderItem

    ColorLabel* = range[0 .. 16]

    Item* = ref ItemObj
    ItemObj {.importc.} = object of RootObj
        id*: int
        typeName*: cstring # Warning! This value is localized! Barely usable.
        selected*: bool
        name*: cstring
        comment*: cstring
        color*: ColorLabel
        parentFolder*: FolderItem

    AVItem* = ref AVItemObj
    AVItemObj {.importc.} = object of ItemObj
        duration*: float
        frameDuration*: float
        frameRate*: float
        pixelAspect*: float
        width*, height*: int

    FootageItem* = ref FootageItemObj
    FootageItemObj {.importc.} = object of AVItemObj
        file*: File
        mainSource*: FootageSource

    Composition* = ref CompositionObj
    CompositionObj {.importc.} = object of AVItemObj

    Collection*[T] = ref object of RootObj
        fieldToCheckType: T

    FolderItem* = ref FolderItemObj
    FolderItemObj {.importc.} = object of ItemObj

    Layer* = ref LayerObj
    LayerObj {.importc.} = object of ItemObj
        numProperties*: int
        index*: int
        containingComp*: Composition
        parent*: Layer
        enabled*: bool
        width*, height*: int
        source*: AVItem
        isNameSet*: bool
        isTrackMatte*: bool
        hasTrackMatte*: bool
        timeRemapEnabled*: bool

        ## The start time of the layer, expressed in composition time (seconds).
        ## Floating-point value in the range [-10800.0..10800.0] (minus or plus three hours); read/write.
        startTime*: float

    TextLayer* = ref TextLayerObj
    TextLayerObj {.importc.} = object of LayerObj

    PropertyBase* = ref PropertyBaseObj
    PropertyBaseObj {.importc.} = object of RootObj
        name*: cstring

    PropertyType* = enum
        ptProperty
        ptIndexedGroup
        ptNamedGroup

    PropertyValueType* = enum
        pvtVoid, pvtColor, pvtCustomValue, pvtLayerIndex, pvtMaskIndex,
        pvtMarker, pvtShape, pvtTextDocument,
        pvt1d, pvt2d, pvt2dSpatial, pvt3d, pvt3dSpatial

    AbstractProperty* = ref AbstractPropertyObj
    AbstractPropertyObj {.importc.} = object of PropertyBaseObj
        expression*: cstring
        expressionEnabled*: bool
        isTimeVarying*: bool
        dimensionsSeparated*: bool
        isSeparationLeader*: bool

    Property*[T] = ref PropertyObj[T]
    PropertyObj[T] = object of AbstractPropertyObj
        thisFieldIsNeededOnlyToSuppressNimWarning: T

    PropertyGroup* = ref PropertyGroupObj
    PropertyGroupObj {.importc.} = object of PropertyBaseObj
        numProperties*: int

    FootageSource* = ref FootageSourceObj
    FootageSourceObj {.importc.} = object of RootObj

    SolidSource* = ref SolidSourceObj
    SolidSourceObj {.importc.} = object of FootageSourceObj
        color*: array[3, float]

    EditText* = ref EditTextObj
    EditTextObj {.importc.} = object of RootObj
        text*: cstring

    TextJustification* = enum
        tjLeft, tjRight, tjCenter

    TextDocument* = ref TextDocumentObj
    TextDocumentObj {.importc.} = object of RootObj
        text*: cstring
        fontSize*: int
        fillColor*: array[3, float]

    TrackMatteType* = enum
        tmNone, tmAlpha, tmAlphaInverted, tmLuma, tmLumaInverted

template `[]`*[T](c: Collection[T], i: int): T = cast[seq[type(c.fieldToCheckType)]](c)[i + 1]
template len*[T](c: Collection[T]): int = cast[seq[type(c.fieldToCheckType)]](c).len

proc remove*(i: Item) {.importcpp.}

proc layers*(c: Composition): Collection[Layer] = {.emit:"`result` = `c`.layers;".}
proc layer*(c: Composition, name: cstring): Layer {.importcpp.}

iterator items*[T](c: Collection[T]): T =
    for i in 0 ..< c.len: yield c[i]

proc propertyType*(p: PropertyBase): PropertyType =
    {.emit: """
    switch(`p`.propertyType) {
        case PropertyType.PROPERTY: `result` = 0; break;
        case PropertyType.INDEXED_GROUP: `result` = 1; break;
        case PropertyType.NAMED_GROUP: `result` = 2; break;
    }
    """.}

proc propertyValueType*(p: AbstractProperty): PropertyValueType =
    {.emit: """
    switch(`p`.propertyValueType) {
        case PropertyValueType.NO_VALUE: `result` = 0; break;
        case PropertyValueType.COLOR: `result` = 1; break;
        case PropertyValueType.CUSTOM_VALUE: `result` = 2; break;
        case PropertyValueType.LAYER_INDEX: `result` = 3; break;
        case PropertyValueType.MASK_INDEX: `result` = 4; break;
        case PropertyValueType.MARKER: `result` = 5; break;
        case PropertyValueType.SHAPE: `result` = 6; break;
        case PropertyValueType.TEXT_DOCUMENT: `result` = 7; break;
        case PropertyValueType.OneD: `result` = 8; break;
        case PropertyValueType.TwoD: `result` = 9; break;
        case PropertyValueType.TwoD_SPATIAL: `result` = 10; break;
        case PropertyValueType.ThreeD: `result` = 11; break;
        case PropertyValueType.ThreeD_SPATIAL: `result` = 12; break;
    }
    """.}

template valueTypeFromType(t: typedesc[array[2, float32]]): expr = [pvt2d, pvt2dSpatial]
template valueTypeFromType(t: typedesc[array[3, float32]]): expr = [pvt3d, pvt3dSpatial]
template valueTypeFromType(t: typedesc[array[4, float32]]): expr = [pvtColor]
template valueTypeFromType(t: typedesc[float32]): expr = [pvt1d]
template valueTypeFromType(t: typedesc[float]): expr = [pvt1d]
template valueTypeFromType(t: typedesc[cstring]): expr = [pvt1d]
template valueTypeFromType(t: typedesc[TextDocument]): expr = [pvtTextDocument]

template isPropertyGroup*(p: PropertyBase): bool = p.propertyType != ptProperty

proc toAbstractProperty*(p: PropertyBase): AbstractProperty =
    if p.isPropertyGroup:
        raise newException(Exception, "Property is a group")
    result = cast[AbstractProperty](p)

proc checkPropType(p: AbstractProperty, rt: openarray[PropertyValueType]) =
    let pt = p.propertyValueType
    if pt notin rt:
        raise newException(Exception, "Property " & $p.name & " requested type " & ($ @rt) & " but actual type is " & $pt)

proc toPropertyOfType*(p: PropertyBase, T: typedesc): Property[T] =
    p.toAbstractProperty().checkPropType(valueTypeFromType(T))
    result = cast[Property[T]](p)

proc toPropertyOfType*(p: AbstractProperty, T: typedesc): Property[T] =
    p.checkPropType(valueTypeFromType(T))
    result = cast[Property[T]](p)

proc toPropertyGroup*(p: PropertyBase): PropertyGroup =
    if not p.isPropertyGroup:
        raise newException(Exception, "Property is not a group")
    result = cast[PropertyGroup](p)

proc property*(layer: Layer, name: cstring): PropertyBase {.importcpp.}
proc indexedProperty(layer: Layer, i: int): PropertyBase {.importcpp: "property".}

proc property*(prop: PropertyGroup, name: cstring): PropertyBase {.importcpp.}
proc indexedProperty(prop: PropertyGroup, i: int): PropertyBase {.importcpp: "property".}

type PropertyOwner* = Layer or PropertyGroup

template property*(owner: PropertyOwner, i: int): PropertyBase = owner.indexedProperty(i + 1)

template propertyGroup*(owner: PropertyOwner, name: cstring): PropertyGroup =
    let p = owner.property(name)
    if p.isNil: nil else: p.toPropertyGroup()

template property*(owner: PropertyOwner, name: cstring, T: typedesc): auto =
    let p = owner.property(name)
    if p.isNil: nil else: p.toPropertyOfType(T)

template property*(owner: PropertyOwner, i: int, T: typedesc): auto =
    let p = owner.property(i)
    if p.isNil: nil else: p.toPropertyOfType(T)

proc value*[T](p: Property[T]): T = {.emit: "`result` = `p`.value;".}
proc valueAtTime*[T](p: Property[T], t: float, e: bool = false): T =
    {.emit: "`result` = `p`.valueAtTime(`t`, `e`);".}

proc children*(layer: Layer): seq[Layer] =
    result = newSeq[Layer]()
    for i in layer.containingComp.layers:
        if i.parent == layer: result.add(i)

proc addText*(col: Collection[Layer], text: cstring): TextLayer {.importcpp.}
proc addText*(col: Collection[Layer]): TextLayer {.importcpp.}
proc addNull*(col: Collection[Layer], duration: float): Layer {.importcpp.}
proc addNull*(col: Collection[Layer]): Layer {.importcpp.}

proc newTextDocument*(text: cstring = ""): TextDocument {.importc: "new TextDocument".}

proc getProtoName*(y: ref object): cstring {.importc: "Object.prototype.toString.call".}

proc jsObjectType*(y: ref object): string =
    var protoName = $getProtoName(y)
    const start = "[object "
    assert(protoName.startsWith(start))
    result = protoName.substr(start.len, protoName.len - 2)

type
    JSRegExp = ref JSRegExpObj
    JSRegExpObj {.importc.} = object

proc newRegex*(pattern, flags: cstring): JSRegExp {.importc: "new RegExp".}
proc newRegex*(pattern: cstring): JSRegExp {.importc: "new RegExp".}
proc match*(str: cstring, reg: JSRegExp): seq[cstring] {.importcpp.}

proc getSequenceFilesFromSource*(source: FootageItem): seq[File] =
    var allFilesInDir = newFolder(source.file.path).getFiles()
    var pattern = newRegex("""(.*)\[(\d+)-(\d+)\](.*)""")
    var matches = source.name.match(pattern)
    if matches.isNil:
        return nil

    var startIndex = parseInt($matches[2])
    var endIndex = parseInt($matches[3])

    var pattern2 = newRegex("""([^\d]*)(\d+)(.*)""")

    type E = tuple[index: int, f: File]
    var filesWithIndexes = newSeq[E]()

    for i in allFilesInDir:
        let str = decodeURIComponent(i.name)
        var fMatches = str.match(pattern2)
        if not fMatches.isNil and fMatches.len >= 2:
            var index = parseInt($fMatches[2])
            if (matches[1] == fMatches[1] and
                    matches[^1] == fMatches[^1] and
                    index >= startIndex and index <= endIndex):
                filesWithIndexes.add((index, i))
                result.add(i)

    {.emit: """
    `filesWithIndexes` = `filesWithIndexes`.sort(function(a, b) {
        return a.Field0 - b.Field0;
        });
    """.}

    #filesWithIndexes.sort(proc (a, b: E): int = a.index - b.index)
    result = newSeq[File](filesWithIndexes.len)

    for i, f in filesWithIndexes:
        result[i] = f.f

proc justification*(td: TextDocument): TextJustification =
    {.emit: """
    switch(`td`.justification) {
        case ParagraphJustification.LEFT_JUSTIFY: `result` = 0; break;
        case ParagraphJustification.RIGHT_JUSTIFY: `result` = 1; break;
        case ParagraphJustification.CENTER_JUSTIFY: `result` = 2; break;
    }
    """.}

proc trackMatteType*(layer: Layer): TrackMatteType =
    {.emit: """
    switch(`layer`.trackMatteType) {
        case TrackMatteType.NO_TRACK_MATTE: `result` = 0; break;
        case TrackMatteType.ALPHA: `result` = 1; break;
        case TrackMatteType.ALPHA_INVERTED: `result` = 2; break;
        case TrackMatteType.LUMA: `result` = 3; break;
        case TrackMatteType.LUMA_INVERTED: `result` = 4; break;
    }
    """.}

proc getSetting*(s: Settings, sectionName, keyName: cstring): cstring {.importcpp.}
proc saveSetting*(s: Settings, sectionName, keyName, value: cstring) {.importcpp.}
proc haveSetting*(s: Settings, sectionName, keyName: cstring): bool {.importcpp.}

var app* {.importc, nodecl.}: Application
var systemUserName* {.importc: "system.userName", nodecl.}: cstring # The current user name.
var systemMachineName* {.importc: "system.machineName", nodecl.}: cstring # The name of the host computer.
var systemOsName* {.importc: "system.osName", nodecl.}: cstring # The name of the operating system.
var systemOsVersion* {.importc: "system.osVersion", nodecl.}: cstring # The version of the operating system.

# Executes a system command, as if you had typed it on the operating system’s command line.
# Returns whatever the system outputs in response to the command, if anything.
# In Windows, you can invoke commands using the `/c` switch for the `cmd.exe` command,
# passing the command to run in escaped quotes (\"...\"). For example, the
# following retrieves the current time and displays it to the user:
# ```
#   var timeStr = callSystem("cmd.exe /c \"time /t\"")
#   alert("Current time is " & timeStr)
# ```
proc callSystem*(cmd: cstring): cstring {.importc: "system.callSystem".}

proc projectPath*(i: Item): string =
    if app.project.rootFolder == i.parentFolder:
        result = "/"
    else:
        result = projectPath(i.parentFolder)
        if not result.endsWith("/"):
            result &= "/"
        result &= $i.parentFolder.name
