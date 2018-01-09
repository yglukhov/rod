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
        file*: File

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

    MarkerValue* = ref MarkerValueObj
    MarkerValueObj {.importc.} = object of RootObj
        comment*: cstring

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
        nullLayer*: bool
        threeDLayer*: bool
        expression*: cstring
        ## The start time of the layer, expressed in composition time (seconds).
        ## Floating-point value in the range [-10800.0..10800.0] (minus or plus three hours); read/write.
        startTime*: float
        stretch*: float
        outPoint*: float
        inPoint*: float

    TextLayer* = ref TextLayerObj
    TextLayerObj {.importc.} = object of LayerObj

    AVLayer* = ref AVLayerObj
    AVLayerObj {.importc.} = object of LayerObj

    PropertyBase* = ref PropertyBaseObj
    PropertyBaseObj {.importc.} = object of RootObj
        name*: cstring
        matchName*: cstring
        enabled*: bool
        active*: bool
        isEffect*: bool
        selected*: bool
        parentProperty*: PropertyGroup
        canSetEnabled*: bool

    PropertyType* = enum
        ptProperty
        ptIndexedGroup
        ptNamedGroup

    PropertyValueType* = enum
        pvtVoid, pvtColor, pvtCustomValue, pvtLayerIndex, pvtMaskIndex,
        pvtMarker, pvtShape, pvtTextDocument,
        pvt1d, pvt2d, pvt2dSpatial, pvt3d, pvt3dSpatial

    KeyframeInterpolationType* = enum
        kitLinear
        kitBezier
        hitHold

    AbstractProperty* = ref AbstractPropertyObj
    AbstractPropertyObj {.importc.} = object of PropertyBaseObj
        expression*: cstring
        expressionEnabled*: bool
        isTimeVarying*: bool
        dimensionsSeparated*: bool
        isSeparationLeader*: bool
        numKeys*: int

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
        font*: cstring
        fontSize*: int
        fillColor*: array[3, float]
        leading*: float
        tracking*: float
        strokeWidth*: float
        strokeColor*: array[3, float]
        applyStroke*: bool
        applyFill*: bool
        allCaps*: bool
        pointText*: bool
        boxText*: bool
        boxTextSize*: array[2, float] # According to the docs, these are ints, but in reality they are floats
        boxTextPos*: array[2, float]

    TrackMatteType* = enum
        tmNone, tmAlpha, tmAlphaInverted, tmLuma, tmLumaInverted

    BlendingMode* {.pure.} = enum
        NORMAL, ADD

    KeyframeEase* = ref KeyframeEaseObj
    KeyframeEaseObj {.importc.} = object of RootObj
        ## The speed value of the keyframe. The units depend on the type of keyframe,
        ## and are displayed in the Keyframe Velocity dialog box.
        speed*: float
        ## The influence value of the keyframe, as shown in the Keyframe Velocity dialog box.
        ## Value in the range [0.1..100.0]
        influence*: float

    Rect* = ref RectObj
    RectObj {.importc.} = object of RootObj
        top*, left*, width*, height*: float

{.push checks:off.}
proc `[]`*[T](c: Collection[T], i: int): T = cast[seq[type(c.fieldToCheckType)]](c)[i + 1]
{.pop.}
template len*[T](c: Collection[T]): int = cast[seq[type(c.fieldToCheckType)]](c).len

proc remove*(i: Item) {.importcpp.}

proc layers*(c: Composition): Collection[Layer] = {.emit:"`result` = `c`.layers;".}
proc selectedLayers*(c: Composition): seq[Layer] = {.emit:"`result` = `c`.selectedLayers; if (`result`.length === undefined) { `result` = [`result`]; }".}
proc layer*(c: Composition, name: cstring): Layer {.importcpp.}

proc sourceRectAtTime*(layer: Layer, time: float, extents: bool): Rect {.importcpp.}

proc activeItem*(p: Project, T: typedesc): T = {.emit: "`result` = `p`.activeItem;".}

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
        default: throw "Unknown property type";
    }
    """.}

template valueTypeFromType(t: typedesc[array[2, float32]]): untyped = [pvt2d, pvt2dSpatial]
template valueTypeFromType(t: typedesc[array[3, float32]]): untyped = [pvt3d, pvt3dSpatial]
template valueTypeFromType(t: typedesc[array[4, float32]]): untyped = [pvtColor]
template valueTypeFromType(t: typedesc[float32]): untyped = [pvt1d]
template valueTypeFromType(t: typedesc[float]): untyped = [pvt1d]
template valueTypeFromType(t: typedesc[cstring]): untyped = [pvt1d]
template valueTypeFromType(t: typedesc[int]): untyped = [pvt1d]
template valueTypeFromType(t: typedesc[TextDocument]): untyped = [pvtTextDocument]
template valueTypeFromType(t: typedesc[MarkerValue]): untyped = [pvtMarker]

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
proc addProperty*(prop: PropertyGroup, name: cstring) {.importcpp.}
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

proc nearestKeyIndex*(p: AbstractProperty, t: float): int {.importcpp.}
proc keyTime*(p: AbstractProperty, i: int): float {.importcpp.}

proc keyValue*[T](p: Property[T], i: int): T {.importcpp.}
proc keyRoving*(p: AbstractProperty, i: int): bool {.importcpp.}
proc keySelected*(p: AbstractProperty, i: int): bool {.importcpp.}
proc keyTemporalAutoBezier*(p: AbstractProperty, i: int): bool {.importcpp.}
proc keyTemporalContinuous*(p: AbstractProperty, i: int): bool {.importcpp.}
proc keySpatialAutoBezier*(p: AbstractProperty, i: int): bool {.importcpp.}
proc keySpatialContinuous*(p: AbstractProperty, i: int): bool {.importcpp.}


proc nativeKeyframeInterpolationTypeToNim(t: RootRef): KeyframeInterpolationType =
    {.emit: """
    switch(`t`) {
        case KeyInInterpolationType.LINEAR: `result` = 0; break;
        case KeyInInterpolationType.BEZIER: `result` = 1; break;
        case KeyInInterpolationType.HOLD: `result` = 2; break;
    }
    """.}

proc nativeKeyInInterpolationType(p: AbstractProperty, i: int): RootRef {.importcpp: "keyInInterpolationType".}
proc nativeKeyOutInterpolationType(p: AbstractProperty, i: int): RootRef {.importcpp: "keyOutInterpolationType".}

proc keyInInterpolationType*(p: AbstractProperty, i: int): KeyframeInterpolationType =
    nativeKeyframeInterpolationTypeToNim(p.nativeKeyInInterpolationType(i))
proc keyOutInterpolationType*(p: AbstractProperty, i: int): KeyframeInterpolationType =
    nativeKeyframeInterpolationTypeToNim(p.nativeKeyOutInterpolationType(i))

proc keyInTemporalEase*(p: AbstractProperty, i: int): seq[KeyframeEase] {.importcpp.}
proc keyOutTemporalEase*(p: AbstractProperty, i: int): seq[KeyframeEase] {.importcpp.}

#proc isInterpolationTypeValid*(p: AbstractProperty, kit: KeyframeInterpolationType): bool =

proc value*[T](p: Property[T]): T = {.emit: "`result` = `p`.value;".}
proc valueAtTime*[T](p: Property[T], t: float, e: bool = false): T =
    {.emit: "`result` = `p`.valueAtTime(`t`, `e`);".}

proc setValue*[T](p: Property[T], v: T) = {.emit: "`p`.setValue(`v`);".}
proc setValueAtTime*[T](p: Property[T], t: float, v: T) = {.emit: "`p`.setValueAtTime(`t`, `v`);".}

proc children*(layer: Layer): seq[Layer] =
    result = newSeq[Layer]()
    for i in layer.containingComp.layers:
        if i.parent == layer: result.add(i)

proc addText*(col: Collection[Layer], text: cstring): TextLayer {.importcpp.}
proc addText*(col: Collection[Layer]): TextLayer {.importcpp.}
proc addNull*(col: Collection[Layer], duration: float): Layer {.importcpp.}
proc addNull*(col: Collection[Layer]): Layer {.importcpp.}
proc addSolid*(col: Collection[Layer], color: array[3, float], name: cstring, width, height: int, aspect: float): AVLayer {.importcpp.}
proc precompose*(col: Collection[Layer], indices: openarray[int], name: cstring, moveAllAttributes: bool): Composition {.importcpp.}

proc newTextDocument*(text: cstring = ""): TextDocument {.importc: "new TextDocument".}
proc newKeyframeEase*(speed, influence: float): KeyframeEase {.importc: "new KeyframeEase".}
proc `$`*(k: KeyframeEase): string = "{speed: " & $k.speed & ", influence: " & $k.influence & "}"

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
proc escapeRegExp*(str: cstring): cstring =
    var res: cstring = ""
    {.emit: """
        `res` = `str`.replace(new RegExp("[\\\\^$*+?.()|[\\]{}]", "g"), "\\$&");
    """.}
    result = res

proc getSequenceFilesFromSource*(source: FootageItem): seq[File] =
    var cacheValid = false
    {.emit: """
    if (`source`.__sequenceFiles !== undefined) {
        `result` = `source`.__sequenceFiles;
        `cacheValid` = true;
    }
    """.}
    if cacheValid: return

    var allFilesInDir = newFolder(source.file.path).getFiles()
    var pattern = newRegex("""(.*)\[(\d+)-(\d+)\](.*)""")
    var matches = source.name.match(pattern)
    if matches.isNil:
        return nil

    var startIndex = parseInt($matches[2])
    var endIndex = parseInt($matches[3])

    var pattern2 = newRegex($escapeRegExp(matches[1]) & """(\d+)""" & $escapeRegExp(matches[^1]))

    type E = tuple[index: int, f: File]
    var filesWithIndexes = newSeq[E]()

    for i in allFilesInDir:
        let str = decodeURIComponent(i.name)
        var fMatches = str.match(pattern2)
        if not fMatches.isNil:
            var index = parseInt($fMatches[1])
            if index >= startIndex and index <= endIndex:
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

    {.emit: """
    `source`.__sequenceFiles = `result`;
    """.}


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

proc blendMode*(layer: Layer): BlendingMode =
    var bm = 0
    {.emit: """
        `bm` = `layer`.blendingMode;
    """.}
    case bm
    of 5220, 5020:
        result = BlendingMode.ADD
    else:
        result = BlendingMode.NORMAL

proc activeAtTime*(layer: Layer, t: float): bool=
    var res = false
    {.emit: """
        `res` = `layer`.activeAtTime(`t`);
    """
    .}
    result = res

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

proc beginUndoGroup*(a: Application, name: cstring) {.importcpp.}
proc endUndoGroup*(a: Application) {.importcpp.}

proc executeCommand*(a: Application, c: int) {.importcpp.}
proc findMenuCommandId*(a: Application, name: cstring): int {.importcpp.}
proc undo*(a: Application, name: string) =
    ## This function uses undocumented API. Use at your own risk.
    a.executeCommand(16)
