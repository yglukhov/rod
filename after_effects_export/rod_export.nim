import tables, dom, math
import after_effects
import gradient_property
import times
import json
import algorithm
import strutils
import sequtils
import nimx.matrixes, nimx.pathutils
import rod.quaternion
import rod.utils.text_helpers

const exportSampledAnimations = true
const exportKeyframeAnimations = false

type File = after_effects.File
type PropertyDescription = ref object
    name: string
    fullyQualifiedName: string
    property: AbstractProperty
    valueAtTime: proc(time: float): JsonNode
    keyValue: proc(k: int): JsonNode
    initialValue: proc(): JsonNode
    separatedProperties: seq[AbstractProperty]

type Marker = object
    time*, duration*: float
    comment*: string
    animation*: string
    loops*: int
    animation_end*: string

type ExportSettings = ref object
    layerNames: Table[int, string]
    trckMatteLayers: Table[string, tuple[layer: Layer, layerEnabled: bool]]
    currTrckMatteLayer: Layer
    animatedProperties: seq[PropertyDescription]

var exportSettings: TableRef[string, ExportSettings]

const bannedPropertyNames = ["Time Remap", "Marker", "Checkbox", "Value/Offset/Random Max", "Slider", "Source Text"]
var gCompExportPath = ""
var gExportFolderPath = ""
var resourcePaths: seq[string] = @[]

var exportInOut = true
var transitiveEffects = false
var frameLerp = false

var logTextField: EditText

const exportedVersion = 1

proc logi(args: varargs[string, `$`]) =
    for i in args:
        logTextField.text &= i
    logTextField.text &= "\n"

proc getExportSettings(lay: Layer): ExportSettings =
    result = exportSettings.getOrDefault($lay.containingComp.name)

proc getExportSettings(comp: Composition): ExportSettings =
    result = exportSettings.getOrDefault($comp.name)

proc createExportSettings(comp: Composition): ExportSettings =
    result.new()
    result.layerNames = initTable[int, string]()
    result.trckMatteLayers = initTable[string, tuple[layer: Layer, layerEnabled: bool]]()
    result.animatedProperties = @[]

proc `currTrckMatteLayer=`(lay: Layer | Composition, val: Layer) = 
    var s = lay.getExportSettings()
    s.currTrckMatteLayer = val

proc setLayerName(lay: Layer | Composition, key: int, val: string) =
    var s = lay.getExportSettings()
    s.layerNames[key] = val

template animatedProperties(lay: Layer | Composition): seq[PropertyDescription] =
    var s = lay.getExportSettings()
    s.animatedProperties

proc layerNames(lay: Layer | Composition): Table[int, string] =
    var s = lay.getExportSettings()
    s.layerNames

proc trckMatteLayers(lay: Layer | Composition): Table[string, tuple[layer: Layer, layerEnabled: bool]] =
    var s = lay.getExportSettings()
    s.trckMatteLayers

proc setTrckMatteLayers(lay: Layer | Composition, k: string, v: tuple[layer: Layer, layerEnabled: bool]) =
    var s = lay.getExportSettings()
    s.trckMatteLayers[k] = v

proc currTrckMatteLayer(lay: Layer | Composition): Layer =
    var s = lay.getExportSettings()
    s.currTrckMatteLayer

proc duration*(layer: Layer): float =
    var source = layer.source
    if source.jsObjectType == "FootageItem":
        let footageSource = FootageItem(source)
        if not footageSource.file.isNil:
            result = footageSource.duration
    elif source.jsObjectType == "CompItem":
        let compItem = Composition(source)
        result = compItem.duration

proc getObjectsWithTypeFromCollection*(t: typedesc, collection: openarray[Item], typeName: string): seq[t] =
    for i in collection:
        if i.jsObjectType == typeName:
            result.add(cast[t](i))

proc isNinePartSprite(layer: Layer): bool =
    let ch = layer.children
    ch.len == 1 and ch[0].name == "@NinePartMarker"

proc shouldSerializeLayer(layer: Layer): bool = layer.enabled and ((layer.name.len > 0 and layer.name[0] != '@') or layer.name.len == 0)

proc metadata(layer: Layer): JsonNode =
    if layer.comment.len > 0:
        var c = $layer.comment
        # After effects may insert funny chars instead of quotes.
        c = c.replace("“", "\"")
        c = c.replace("”", "\"")
        try:
            result = parseJson(c)
        except:
            logi "Could not parse layer comment"
            logi c

proc layerIsCompositionRef(layer: Layer): bool =
    not layer.source.isNil and layer.source.jsObjectType == "CompItem"

proc hasCompRefComponent(metadata: JsonNode): bool =
    let comps = metadata{"components"}
    if not comps.isNil:
        for c in comps:
            if c{"_c"}.getStr() == "CompRef": return true

proc childrenCompositions(c: Composition): seq[Composition]=
    result = @[]
    for lay in c.layers:
        if lay.layerIsCompositionRef() and shouldSerializeLayer(lay) and not hasCompRefComponent(lay.metadata): 
            var c = cast[Composition](lay.source)
            result.add(c)
            var chcomps = c.childrenCompositions()
            result.add(chcomps)

proc getSelectedCompositions(recursive: bool): seq[Composition] =
    result = getObjectsWithTypeFromCollection(Composition, app.project.selection, "CompItem")
    if recursive:
        var chcomps = newSeq[Composition]()
        for comp in result:
            chcomps.add(comp.childrenCompositions)
        result.add(chcomps)

proc cutDecimal(v: float, t: float = 1000.0): float =
    result = (v * t).int.float / t

proc cutDecimal[I: static[int], T](v: TVector[I, T], t: float = 1000.0): TVector[I, T] =
    for i in 0 ..< v.len: result[i] = cutDecimal(v[i], t)

proc cutDecimal(q: Quaternion, t: float = 1000.0): Quaternion =
    cutDecimal(q.Vector4, t).Quaternion

proc `&=`(s, a: cstring) {.importcpp: "# += #".}
proc `%`(q: Quaternion): JsonNode =
    `%`(q.Vector4)

proc printPropertiesTree*(p: PropertyOwner, offset: string = " ") =
    logi offset, "propertyOwner name ", p.name
    for i in 0 ..< p.numProperties:
        let prop = p.property(i)
        if prop.isPropertyGroup:
            prop.toPropertyGroup().printPropertiesTree(offset & "  ")
        else:
            logi offset, "  property name ", prop.name

template quaternionWithZRotation(zAngle: float32): Quaternion = newQuaternion(zAngle, newVector3(0, 0, 1))
template quaternionWithEulerRotation(euler: Vector3): Quaternion = newQuaternionFromEulerXYZ(euler.x, euler.y, euler.z)

proc mangledName(layer: Layer): string =
    result = layer.layerNames.getOrDefault(layer.index)
    if result.len == 0:
        result = $layer.name
        if result == $layer.containingComp.name:
            result &= "$" & $layer.index
        else:
            for v in values(layer.layerNames):
                if result == v:
                    result &= "$" & $layer.index
                    break
        layer.setLayerName(layer.index, result)

proc fullyQualifiedPropName(layer: Layer, componentIndex: int, name: string, p: AbstractProperty): string =
    let layerName = layer.mangledName

    if componentIndex == -1:
        result = layerName & "." & name
    else:
        result = layerName & "." & $componentIndex & "." & name

proc isAnimated(p: AbstractProperty): bool =
    p.isTimeVarying and (not p.isSeparationLeader or not p.dimensionsSeparated)

proc newPropDesc[T](layer: Layer, componentIndex: int = -1, name: string, p: Property[T], mapper: proc(val: T, time:tuple[time:float, key:int]): JsonNode = nil): PropertyDescription =
    if p.isNil:
        return

    result.new()
    result.name = name

    result.property = p
    if mapper.isNil:
        result.valueAtTime = proc(t: float): JsonNode =
            % p.valueAtTime(t)
        result.keyValue = proc(k: int): JsonNode =
            % p.keyValue(k)
    else:
        result.valueAtTime = proc(t: float): JsonNode =
            mapper(p.valueAtTime(t), (time: t, key: -1))
        result.keyValue = proc(k: int): JsonNode =
            mapper(p.keyValue(k), (time: -1.0, key: k))

    let vat = result.valueAtTime
    result.initialValue = proc(): JsonNode =
        vat(0)

    result.fullyQualifiedName = fullyQualifiedPropName(layer, componentIndex, name, p)

proc newPropDesc[T](layer: Layer, componentIndex: int = -1, name: string, p: Property[T], mapper: proc(val: T): JsonNode = nil): PropertyDescription =
    let map = proc(val: T, time: tuple[time:float, key:int]): JsonNode =
        result = mapper(val)
    result = newPropDesc(layer, componentIndex, name, p, map)

proc newPropDescSeparated[T](layer: Layer, componentIndex: int = -1, name: string, p: seq[Property[T]], mapper: proc(val: seq[T], time:tuple[time:float, key:int]): JsonNode = nil): PropertyDescription =
    if p.isNil:
        return

    result.new()
    result.name = name

    result.property = p[0]
    result.separatedProperties = @[]
    for i in 0 ..< p.len:
        result.separatedProperties.add(p[i])
    let r = result
    if mapper.isNil:
        result.valueAtTime = proc(t: float): JsonNode =
            result = newJArray()
            for sp in r.separatedProperties:
                result.add(%sp.toPropertyOfType(T).valueAtTime(t))
        result.keyValue = proc(k: int): JsonNode =
            result = newJArray()
            for sp in r.separatedProperties:
                result.add(%sp.toPropertyOfType(T).keyValue(k))
    else:
        result.valueAtTime = proc(t: float): JsonNode =
            var args = newSeq[T]()
            for sp in r.separatedProperties:
                args.add(sp.toPropertyOfType(T).valueAtTime(t))
            mapper(args, (time: t, key: -1))
        result.keyValue = proc(k: int): JsonNode =
            var args = newSeq[T]()
            for sp in r.separatedProperties:
                args.add(sp.toPropertyOfType(T).keyValue(k))
            mapper(args, (time: -1.0, key: k))

    let vat = result.valueAtTime
    result.initialValue = proc(): JsonNode =
        vat(0)

    result.fullyQualifiedName = fullyQualifiedPropName(layer, componentIndex, name, p[0])

proc newPropDescSeparated[T](layer: Layer, componentIndex: int = -1, name: string, p: seq[Property[T]], mapper: proc(val: seq[T]): JsonNode = nil): PropertyDescription =
    let map = proc(val: seq[T], time: tuple[time:float, key:int]): JsonNode =
        result = mapper(val)

    result = newPropDescSeparated(layer, componentIndex, name, p, map)

proc addPropDesc[T](layer: Layer, componentIndex: int = -1, name: string, p: Property[T], mapper: proc(val: T, time: tuple[time:float, key:int]): JsonNode = nil): PropertyDescription {.discardable.} =
    result = newPropDesc(layer, componentIndex, name, p, mapper)
    if not result.isNil and p.isAnimated:
        layer.animatedProperties.add(result)

proc addPropDesc[T](layer: Layer, componentIndex: int = -1, name: string, p: Property[T], mapper: proc(val: T): JsonNode = nil): PropertyDescription {.discardable.} =
    let map = proc(val: T, time: tuple[time:float, key:int]): JsonNode =
        result = mapper(val)
    result = addPropDesc(layer, componentIndex, name, p, map)

proc addPropDesc[T](layer: Layer, componentIndex: int = -1, name: string, p: Property[T], defaultValue: T, mapper: proc(val: T, time: tuple[time:float, key:int]): JsonNode = nil): PropertyDescription {.discardable.} =
    result = addPropDesc(layer, componentIndex, name, p, mapper)
    let vat = result.valueAtTime
    result.initialValue = proc(): JsonNode =
        let v = p.valueAtTime(0)
        if v != defaultValue:
            result = vat(0)

proc addPropDesc[T](layer: Layer, componentIndex: int = -1, name: string, p: Property[T], defaultValue: T, mapper: proc(val: T): JsonNode = nil): PropertyDescription {.discardable.} =
    let map = proc(val: T, time: tuple[time:float, key:int]): JsonNode =
        result = mapper(val)

    result = addPropDesc(layer, componentIndex, name, p, defaultValue, map)

proc setInitialValueToResult(pd: PropertyDescription, res: JsonNode) =
    let v = pd.initialValue()
    if not v.isNil:
        res[pd.name] = v

proc getExportPathFromSourceFile(footageSource: FootageItem, file: File): string =
    var path = $footageSource.projectPath
    if path[^1] != '/': path &= "/"
    result = relativePathToPath("/" & gCompExportPath, path & $decodeURIComponent(file.name))

proc isShapeLayer(layer: Layer): bool =
    for q in 0 ..< layer.numProperties:
        var p = layer.property(q)
        case $p.matchName
        of "ADBE Root Vectors Group":
            return true

proc isSolidLayer(layer: Layer): bool =
    let source = FootageItem(layer.source)
    result = not layer.nullLayer and not source.mainSource.isNil and
        source.mainSource.jsObjectType == "SolidSource"

proc isTextMarkerValid(layer: Layer): bool =
    let textMarker = layer.property("Marker", MarkerValue).valueAtTime(0).comment
    let textLayer = layer.propertyGroup("Text").property("Source Text", TextDocument).value.text

    if textMarker == textLayer or removeTextAttributes($textMarker) == textLayer:
        return true


proc getText(layer: Layer): string =
    let markerText = layer.property("Marker", MarkerValue).valueAtTime(0).comment
    let text = layer.propertyGroup("Text")
    let str = text.property("Source Text", TextDocument).value.text

    if not text.isNil:
        if markerText == "":
            return $str
    if layer.isTextMarkerValid():
        result = $markerText
    else:
        raise newException(Exception, "Marker is not valid for text: " & $str)

proc dumpPropertyTree(p: PropertyBase | Layer, indentLevel = 0) =
    ## This may come in handy to research After Effects property structure.
    var ln = ""
    for i in 0 ..< indentLevel: ln &= "    "

    when p is Layer:
        ln &= "+ layer: " & $p.name
    else:
        if p.isPropertyGroup:
            ln &= "+ group: "
        else:
            ln &= "- prop: "
        ln &= $p.name & ": " & $p.matchName
        if not p.isPropertyGroup:
            ln &= ": " & $p.toAbstractProperty().propertyValueType

    logi ln

    template dumpChildren(p: PropertyOwner) =
        for i in 0 ..< p.numProperties:
            dumpPropertyTree(p.property(i), indentLevel + 1)

    when p is Layer:
        dumpChildren(p)
    else:
        if p.isPropertyGroup:
            let p = p.toPropertyGroup()
            dumpChildren(p)

proc serializeEffect(layer: Layer, compIndex: int, p: PropertyGroup): JsonNode =
    case $p.matchName
    of "ADBE Color Balance (HLS)":
        result = newJObject()
        let hue = addPropDesc(layer, compIndex, "hue", p.property("Hue", float)) do(v: float) -> JsonNode:
            % cutDecimal((v / 360))
        hue.setInitialValueToResult(result)
        let saturation = addPropDesc(layer, compIndex, "saturation", p.property("Saturation", float)) do(v: float) -> JsonNode:
            %cutDecimal((v / 100))
        saturation.setInitialValueToResult(result)
        let lightness = addPropDesc(layer, compIndex, "lightness", p.property("Lightness", float)) do(v: float) -> JsonNode:
            %cutDecimal((v / 100))
        lightness.setInitialValueToResult(result)
        result["_c"] = %"ColorBalanceHLS"

    of "ADBE Pro Levels2": # Channel levels (individual controls)
        proc separatedLevelValueAtTime(lvl: PropertyGroup, propName: string, t: float): Vector3 =
            result[0] = lvl.property("Red " & propName, float).valueAtTime(t, false)
            result[1] = lvl.property("Green " & propName, float).valueAtTime(t, false)
            result[2] = lvl.property("Blue " & propName, float).valueAtTime(t, false)

        proc levelsValueAtTime(lvl: PropertyGroup, t: float): JsonNode =
            result = newJObject()
            result["inWhite"] = % lvl.property("Input White", float).valueAtTime(t, false)
            result["inBlack"] = % lvl.property("Input Black", float).valueAtTime(t, false)
            result["inGamma"] = % lvl.property("Gamma", float).valueAtTime(t, false)
            result["outWhite"] = % lvl.property("Output White", float).valueAtTime(t, false)
            result["outBlack"] = % lvl.property("Output Black", float).valueAtTime(t, false)
            result["inWhiteV"] = %separatedLevelValueAtTime(lvl, "Input White", t)
            result["inBlackV"] = %separatedLevelValueAtTime(lvl, "Input Black", t)
            result["inGammaV"] = %separatedLevelValueAtTime(lvl, "Gamma", t)
            result["outWhiteV"] = %separatedLevelValueAtTime(lvl, "Output White", t)
            result["outBlackV"] = %separatedLevelValueAtTime(lvl, "Output Black", t)

        result = levelsValueAtTime(p, 0)
        result["_c"] = %"ChannelLevels"

        var propertyNameMap = {
            "Input White": "inWhite",
            "Input Black": "inBlack",
            "Gamma": "inGamma",
            "Output White": "outWhite",
            "Output Black": "outBlack",

            "Red Input White": "redInWhite",
            "Red Input Black": "redInBlack",
            "Red Gamma": "redInGamma",
            "Red Output White": "redOutWhite",
            "Red Output Black": "redOutBlack",
            "Green Input White": "greenInWhite",
            "Green Input Black": "greenInBlack",
            "Green Gamma": "greenInGamma",
            "Green Output White": "greenOutWhite",
            "Green Output Black": "greenOutBlack",
            "Blue Input White": "blueInWhite",
            "Blue Input Black": "blueInBlack",
            "Blue Gamma": "blueInGamma",
            "Blue Output White": "blueOutWhite",
            "Blue Output Black": "blueOutBlack",

        }.toTable()

        for n in ["Input White", "Input Black", "Gamma", "Output White", "Output Black"]:
            addPropDesc(layer, compIndex, propertyNameMap[n], p.property(n, float))
            addPropDesc(layer, compIndex, propertyNameMap["Red " & n], p.property("Red " & n, float))
            addPropDesc(layer, compIndex, propertyNameMap["Green " & n], p.property("Green " & n, float))
            addPropDesc(layer, compIndex, propertyNameMap["Blue " & n], p.property("Blue " & n, float))

    of "ADBE Ramp": # Ramp
        result = newJObject()
        let startPoint = addPropDesc(layer, compIndex, "startPoint", p.property("Start of Ramp", Vector2))
        startPoint.setInitialValueToResult(result)

        let endPoint = addPropDesc(layer, compIndex, "endPoint", p.property("End of Ramp", Vector2))
        endPoint.setInitialValueToResult(result)

        let startColor = addPropDesc(layer, compIndex, "startColor", p.property("Start Color", Vector4))
        startColor.setInitialValueToResult(result)

        let endColor = addPropDesc(layer, compIndex, "endColor", p.property("End Color", Vector4))
        endColor.setInitialValueToResult(result)

        const linearRamp = 1.0
        const radialRamp = 2.0
        let shape = p.property("Ramp Shape", float).valueAtTime(0)
        if shape == linearRamp: result["shape"] = %0
        else: result["shape"] = %1

        result["_c"] = %"GradientFill"

    of "ADBE Fill": # Fill
        result = newJObject()
        let startColor = addPropDesc(layer, compIndex, "color", p.property("Color", Vector4))
        startColor.setInitialValueToResult(result)
        result["_c"] = %"ColorFill"

    of "ADBE Tint": # Tint
        result = newJObject()
        let blackColor = addPropDesc(layer, compIndex, "black", p.property("Map Black To", Vector4))do(v: Vector4) -> JsonNode:
            %[v[0], v[1], v[2], 1.0]
        blackColor.setInitialValueToResult(result)

        let whiteColor = addPropDesc(layer, compIndex, "white", p.property("Map White To", Vector4))do(v: Vector4) -> JsonNode:
            %[v[0], v[1], v[2], 1.0]

        whiteColor.setInitialValueToResult(result)
        let amount = addPropDesc(layer, compIndex, "amount", p.property("Amount to Tint", float)) do(v: float) -> JsonNode:
            %(v / 100)
        amount.setInitialValueToResult(result)
        result["_c"] = %"Tint"

    else:
        logi "WARNING: Effect not supported. Layer: ", layer.name
        dumpPropertyTree(p)

proc copyAndPrepareFootageItem(footageSource: FootageItem): JsonNode =
    var imageFiles = if footageSource.duration > 0:
            getSequenceFilesFromSource(footageSource)
        else:
            @[footageSource.file]

    # Paths relative to currently exported composition
    let imageFileRelativeExportPaths = newJArray()

    let footagePath = $footageSource.projectPath
    for i, f in imageFiles:
        imageFileRelativeExportPaths.add(%getExportPathFromSourceFile(footageSource, f))

        # Copy the file to the resources
        if app.settings.getSetting("rodExport", "copyResources") == "true":
            let resourcePath = gExportFolderPath & footagePath & "/" & $decodeURIComponent(f.name)
            if not resourcePaths.contains(resourcePath):
                logi "Copying: ", resourcePath
                resourcePaths.add(resourcePath)
                let targetFile = newFile(resourcePath)
                if not targetFile.parent.create():
                    logi "ERROR: Could not create folder for ", resourcePath
                if not f.copy(targetFile):
                    logi "ERROR: Could not copy ", resourcePath

    result = imageFileRelativeExportPaths

proc setTrackMattLayer(layer: Layer) =
    layer.currTrckMatteLayer = layer
    layer.setTrckMatteLayers($layer.mangledName, (layer, layer.enabled))
    layer.currTrckMatteLayer.enabled = true

proc newTrackMatteComponent(layer: Layer, name: string): JsonNode =
    result = newJObject()
    result["layerName"] = %name
    result["maskType"] = %layer.trackMatteType.int
    result["_c"] = %"Mask"

iterator effects(layer: Layer): PropertyGroup =
    let effectsGroup = layer.propertyGroup("Effects")
    if not effectsGroup.isNil:
        for i in 0 ..< effectsGroup.numProperties:
            let p = effectsGroup.property(i)
            if p.isPropertyGroup and p.canSetEnabled and p.enabled:
                yield p.toPropertyGroup()

proc effectWithMatchName(layer: Layer, name: cstring): PropertyGroup =
    for e in layer.effects:
        if e.matchName == name: return e

proc serializeLayerStyles(layer: Layer, result: JsonNode) =
    let layerStyles = layer.propertyGroup("Layer Styles")
    let gradientOverlay = layerStyles.propertyGroup("Gradient Overlay")

    if not gradientOverlay.isNil and gradientOverlay.canSetEnabled and gradientOverlay.enabled:
        var go = newJObject()
        let shape = gradientOverlay.property("Style", int).value.int

        if shape > 2: #now we support linear and radial style only
            raise newException(Exception, "Gradient overlay style for " & $layer.name & " is not supported! ")

        var text = layer.propertyGroup("Text")
        let vectorLayer = layer.property("Contents")
        let alpha = gradientOverlay.property("Opacity", float32).valueAtTime(0) / 100
        let angle = gradientOverlay.property("Angle", float).value
        let angleR = angle.degToRad()
        var width = layer.width.float
        var height = layer.height.float
        let beta = arctan(height / width).radToDeg()
        var startPoint: Vector2
        var endPoint: Vector2

        var offset = newVector2()
        # offset for text
        if not text.isNil:
            var textDoc = text.property("Source Text", TextDocument).value
            if textDoc.boxText:
                let pos = textDoc.boxTextPos
                let sz = textDoc.boxTextSize

                offset.x = pos[0]
                offset.y = pos[1]
                width = sz[0]
                height = sz[1]

        # offset for vector shapes
        if not vectorLayer.isNil:
            let shapes = vectorLayer.toPropertyGroup()
            for q in 0 ..< shapes.numProperties:
                let shape = shapes.property(q)
                let shapeProps = shape.toPropertyGroup()

                if not shape.isNil and shape.isPropertyGroup:
                    let shapeGroup = shapeProps.property("Contents").toPropertyGroup()

                    for i in 0 ..< shapeGroup.numProperties:
                        let p = shapeGroup.property(i)
                        let shapePathGroup = p.toPropertyGroup()
                        let name = $p.name

                        if "Rectangle Path " & $(q+1) in name or "Ellipse Path " & $(q+1) in name:
                            let size = shapePathGroup.property("Size", Vector2).valueAtTime(0)
                            offset -= size / 2.0
                            break

        if angle >= 0 and angle < beta:
            startPoint = newVector2(0, height / 2 * tan(angleR) + height / 2)
        elif angle >= beta and angle < 180 - beta:
            startPoint = newVector2(width / 2 - height / (2.0 * tan(angleR)), height)
        elif angle >= 180 - beta and angle < 180 + beta:
            startPoint = newVector2(width, width / 2 - height / 2 * tan(angleR))
        else:
            startPoint = newVector2(width / 2 + height / (2 * tan(angleR)), 0)

        endPoint = newVector2(width - startPoint.x, height - startPoint.y)

        if shape == 2: #Radial
            startPoint = newVector2(width / 2, height / 2)

        if gradientOverlay.property("Reverse", float).value == 1:
            swap(startPoint, endPoint)

        startPoint += offset
        endPoint += offset

        let colors = gradientOverlay.getGradientColors(layer.containingComp)
        let c0 = colors[0]
        let c1 = colors[1]

        go["shape"] = %(shape - 1)
        go["startColor"] = %newVector4(c0[0], c0[1], c0[2], alpha)
        go["endColor"] = %newVector4(c1[0], c1[1], c1[2], alpha)
        go["startPoint"] = %startPoint
        go["endPoint"] = %endPoint
        go["localCoords"] = %true
        go["_c"] = %"GradientFill"
        result.add(go)


proc serializeEffectComponents(layer: Layer, result: JsonNode) =
    let blendMode = layer.blendMode
    if blendMode != BlendingMode.NORMAL:
        result.add(%*{"_c": "VisualModifier", "blendMode": % $blendMode})

    for p in layer.effects:
        let c = serializeEffect(layer, result.len, p)
        if not c.isNil: result.add(c)

    if not layer.currTrckMatteLayer.isNil and layer.hasTrackMatte:
        if not transitiveEffects:
            logi "\n\nEnable Transitive Effects for export masks!!!\n\n"
            raise

        let traсkMatte = newTrackMatteComponent(layer, $layer.currTrckMatteLayer.mangledName)
        layer.currTrckMatteLayer = nil
        if not traсkMatte.isNil:
            result.add(traсkMatte)

    if exportInOut:
        let ael = newJObject()
        ael["inPoint"] = %cutDecimal(layer.inPoint)
        ael["outPoint"] = %cutDecimal(layer.outPoint)
        ael["scale"] = %cutDecimal(layer.stretch / 100.0)
        ael["startTime"] = %cutDecimal(layer.startTime)
        ael["duration"] = %layer.duration()
        ael["timeremap"] = %0.0
        ael["timeRemapEnabled"] = %layer.timeRemapEnabled
        ael["_c"] = %"AELayer"

        let timeRemap = layer.property("Time Remap", float32)
        if layer.layerIsCompositionRef() and layer.timeRemapEnabled and not timeRemap.isNil:
            let timeRemapDesc = addPropDesc(layer, result.len, "timeremap", timeRemap) do(v: float32) -> JsonNode:
                %(v / layer.duration())
            timeRemapDesc.setInitialValueToResult(ael)

        result.add(ael)

proc ninePartSpriteGeometry(layer: Layer): array[4, float] =
    let mLayer = layer.children[0]
    let pp = mLayer.property("Position", Vector3).value
    let sp = mLayer.property("Scale", Vector3).value
    let ap = mLayer.property("Anchor Point", Vector3).value

    let x = pp.x.float - ap.x.float
    let y = pp.y.float - ap.y.float
    let w = mLayer.width.float * sp.x / 100
    let h = mLayer.height.float * sp.y / 100

    let marginLeft = x
    let marginRight = layer.width.float - (x + w)
    let marginTop = y
    let marginBottom = layer.height.float - (y + h)

    result = [marginLeft, marginRight, marginTop, marginBottom]

proc extractShapeTransformProp(layer: Layer): tuple[position: Property[Vector2], anchor: Property[Vector2], scale: Property[Vector2]] =
    let vectorLayer = layer.property("Contents")

    if not vectorLayer.isNil:
        let shapes = vectorLayer.toPropertyGroup()
        for q in 0 ..< shapes.numProperties:
            let shape = shapes.property(q)
            let name = $shape.name

            if not shape.isNil and shape.isPropertyGroup:
                let shapeProps = shape.toPropertyGroup()
                if not shapeProps.isNil:
                    let transP = shapeProps.property("Transform")
                    if not transP.isNil:
                        let trans = transP.toPropertyGroup()
                        if not trans.isNil:
                            result = (
                                position: trans.property("Position", Vector2),

                                anchor: trans.property("Anchor Point", Vector2),

                                scale: trans.property("Scale", Vector2)
                            )
                            return


proc serializeShape(layer: Layer, result: JsonNode) =
    let vectorLayer = layer.property("Contents")
    if not vectorLayer.isNil:
        let shapes = vectorLayer.toPropertyGroup()
        for q in 0 ..< shapes.numProperties:
            let shape = shapes.property(q)
            let shapeProps = shape.toPropertyGroup()

            # let transform = shapeProps.propertyGroup("Transform")
            # if not transform.isNil:
            #     let position = transform.property("Position", Vector2).valueAtTime(0)
            #     if position[0] > 0 or position[1] > 0:
            #         raise newException(Exception, "wrong way to set position")

            if not shape.isNil and shape.isPropertyGroup:
                let shapeGroup = shapeProps.property("Contents").toPropertyGroup()

                var shape = newJObject()
                shape["_c"] = % "VectorShape"

                for i in 0 ..< shapeGroup.numProperties:
                    let p = shapeGroup.property(i)
                    let shapePathGroup = p.toPropertyGroup()
                    let name = $p.name
                    let compIndex = result.len

                    if "Rectangle Path " & $(q+1) in name:
                        let size = shapePathGroup.property("Size", Vector2)
                        let radius = shapePathGroup.property("Roundness", float32)
                        shape["shapeType"] = % 0

                        let sizeDesc = addPropDesc(layer, compIndex, "size", size) do(v: Vector2) -> JsonNode:
                            %[v[0], v[1]]
                        sizeDesc.setInitialValueToResult(shape)

                        let radiusDesc = addPropDesc(layer, compIndex, "radius", radius) do(v: float32, frame: tuple[time: float, key: int]) -> JsonNode:
                            var minSize: float
                            var size0: Vector2
                            if frame.time > -1.0:
                                size0 = size.valueAtTime(frame.time)
                            else:
                                size0 = size.keyValue(frame.key)
                            minSize = min(size0[0], size0[1])
                            result = %min(minSize / 2.0, v)

                        radiusDesc.setInitialValueToResult(shape)

                    elif "Ellipse Path " & $(q+1) in name:
                        let size = shapePathGroup.property("Size", Vector2)
                        let sizeDesc = addPropDesc(layer, compIndex, "size", size) do(v: Vector2) -> JsonNode:
                            %[v[0], v[1]]
                        sizeDesc.setInitialValueToResult(shape)

                        shape["shapeType"] = % 1


                    elif "Polystar Path " & $(q+1) in name:
                        shape["shapeType"] = % 2
                        #TODO need support?

                    elif "Stroke " & $(q+1) in name:
                        let stroke = shapeGroup.propertyGroup("Stroke")
                        if not stroke.isNil and stroke.canSetEnabled and stroke.enabled:

                            var color = shapePathGroup.property("Color", Vector4)
                            var opacity = shapePathGroup.property("Opacity", float32)

                            let colorDesc = addPropDesc(layer, compIndex, "strokeColor", color) do(v: Vector4, frame: tuple[time: float, key: int]) -> JsonNode:
                                var alpha: float
                                if frame.time > -1.0:
                                    alpha = opacity.valueAtTime(frame.time) / 100.0
                                else:
                                    alpha = opacity.keyValue(frame.key) / 100.0

                                result = %[v[0], v[1], v[2], alpha]

                            colorDesc.setInitialValueToResult(shape)

                            var strokeWidth = shapePathGroup.property("Stroke Width", float32)
                            let strokeDesc = addPropDesc(layer, compIndex, "strokeWidth", strokeWidth) do(v: float32) -> JsonNode:
                                    %v
                            strokeDesc.setInitialValueToResult(shape)
                        else:
                            shape["strokeColor"] = %[0.0, 0.0, 0.0, 0.0]

                    elif "Fill " & $(q+1) in name:
                        let fill = shapeGroup.propertyGroup("Fill")
                        if not fill.isNil and fill.canSetEnabled and fill.enabled:
                            var color = shapePathGroup.property("Color", Vector4)
                            var opacity = shapePathGroup.property("Opacity", float32)

                            let colorDesc = addPropDesc(layer, compIndex, "color", color) do(v: Vector4, frame: tuple[time: float, key: int]) -> JsonNode:
                                var alpha: float
                                if frame.time > -1.0:
                                    alpha = opacity.valueAtTime(frame.time) / 100.0
                                else:
                                    alpha = opacity.keyValue(frame.key) / 100.0

                                result = %[v[0], v[1], v[2], alpha]

                            colorDesc.setInitialValueToResult(shape)
                        else:
                            shape["color"] = %[0.0, 0.0, 0.0, 0.0]

                result.add(shape)

proc serializeDrawableComponents(layer: Layer, result: JsonNode) =
    let numbers = layer.effectWithMatchName("ADBE Numbers2")
    if not numbers.isNil:
        let num = newJObject()
        let color = numbers.property("Fill Color", Vector4).valueAtTime(0)
        num["color"] = %color
        num["fontSize"] = % numbers.property("Size", float).valueAtTime(0)
        num["_c"] = %"Text"
        result.add(num)

    var source = layer.source
    if not source.isNil:
        if source.jsObjectType == "FootageItem":
            let footageSource = FootageItem(source)
            if not footageSource.file.isNil:
                var sprite = newJObject()
                sprite["fileNames"] = copyAndPrepareFootageItem(footageSource)
                sprite["_c"] = %"Sprite"
                if layer.isNinePartSprite():
                    let g = layer.ninePartSpriteGeometry()
                    sprite["segments"] = %g
                result.add(sprite)

            elif layer.isSolidLayer and numbers.isNil:
                var solid = newJObject()
                let solidSource = SolidSource(footageSource.mainSource)
                solid["color"] = %* solidSource.color
                solid["size"] = % [source.width, source.height]
                solid["_c"] = % "Solid"
                result.add(solid)

    var text = layer.propertyGroup("Text")
    if not text.isNil:
        var textDoc = text.property("Source Text", TextDocument).value
        var txt = newJObject()
        txt["text"] = % (layer.getText()).replace('\r', '\l')
        txt["font"] = % $textDoc.font
        txt["fontSize"] = % textDoc.fontSize
        txt["color"] = % textDoc.fillColor
        if textDoc.boxText:
            let pos = textDoc.boxTextPos
            let sz = textDoc.boxTextSize

            # Bounded text in rod respect line spacing, so that first line is
            # drawn at top + lineSpacing. AfterEffect draws the first line
            # immediately at the bounds top. Here we adjust bounds top by leading
            # to correspond to rod logic.
            let topOffsetFix = textDoc.leading - textDoc.fontSize.float

            txt["bounds"] = % [pos[0], pos[1] - topOffsetFix, sz[0], sz[1] + topOffsetFix]
            # logi "bounds: ", txt["bounds"]

        case textDoc.justification
        of tjLeft:
            txt["justification"] = %"haLeft"
        of tjRight:
            txt["justification"] = %"haRight"
        of tjCenter:
            txt["justification"] = %"haCenter"

        let layerStyles = layer.propertyGroup("Layer Styles")
        let shadow = layerStyles.propertyGroup("Drop Shadow")
        if not shadow.isNil and shadow.canSetEnabled and shadow.enabled:
            let angle = shadow.property("Angle", float32).valueAtTime(0)
            let distance = shadow.property("Distance", float32).valueAtTime(0)
            let color = shadow.property("Color", Vector4).valueAtTime(0)
            let alpha = shadow.property("Opacity", float32).valueAtTime(0) / 100
            txt["shadowColor"] = %[color.x, color.y, color.z, alpha]
            let radAngle = degToRad(angle + 180)
            let radius = shadow.property("Size", float32).valueAtTime(0)
            let spread = 1.0 - shadow.property("Spread", float32).valueAtTime(0) / 100
            txt["shadowOff"] = %*[distance * cos(radAngle), - distance * sin(radAngle)]
            txt["shadowRadius"] = %radius
            txt["shadowSpread"] = %spread

        let stroke = layerStyles.propertyGroup("Stroke")
        if not stroke.isNil and stroke.canSetEnabled and stroke.enabled:
            let size = stroke.property("Size", float32).valueAtTime(0)
            let color = stroke.property("Color", Vector4).valueAtTime(0)
            let alpha = stroke.property("Opacity", float32).valueAtTime(0) / 100
            txt["strokeColor"] = %[color.x, color.y, color.z, alpha]
            txt["strokeSize"] = %size

        txt["_c"] = %"Text"
        result.add(txt)

    if layer.isShapeLayer():
        layer.serializeShape(result)

proc exportPath(c: Item): string =
    result = c.projectPath
    if result == "/":
        result = "compositions"
    else:
        result = result[1 .. ^1]

proc serializeLayer(layer: Layer): JsonNode =
    result = newJObject()

    logi("LAYER: ", layer.name, ", w: ", layer.width, " h: ", layer.height);
    result["name"] = % layer.mangledName

    let transform = layer.propertyGroup("Transform")

    var extraTrans = layer.isShapeLayer()
    if not extraTrans:
        let position = addPropDesc(layer, -1, "translation", transform.property("Position", Vector3), newVector3()) do(v: Vector3) -> JsonNode:
            %cutDecimal(newVector3(v.x, v.y, v.z * -1.0))
        position.setInitialValueToResult(result)

        addPropDesc(layer, -1, "tX", transform.property("X Position", float))
        addPropDesc(layer, -1, "tY", transform.property("Y Position", float))

        let scale = addPropDesc(layer, -1, "scale", transform.property("Scale", Vector3), newVector3(100, 100, 100)) do(v: Vector3) -> JsonNode:
            %cutDecimal(v / 100)
        scale.setInitialValueToResult(result)

        let anchor = addPropDesc(layer, -1, "anchor", transform.property("Anchor Point", Vector3), newVector3()) do(v: Vector3) -> JsonNode:
            %cutDecimal(v)
        anchor.setInitialValueToResult(result)

    else:
        let props = layer.extractShapeTransformProp()
        if not props.position.isNil:

            let position = addPropDesc(layer, -1, "translation", transform.property("Position", Vector3), newVector3()) do(v: Vector3, frame: tuple[time: float, key: int]) -> JsonNode:
                var ep: Vector2
                if frame.time > -1:
                    ep = props.position.valueAtTime(frame.time)
                else:
                    ep = props.position.keyValue(frame.key)

                let cp = newVector3(v.x, v.y, v.z * -1.0) + newVector3(ep.x, ep.y)

                %cutDecimal(cp)

            position.setInitialValueToResult(result)

            addPropDesc(layer, -1, "tX", transform.property("X Position", float))
            addPropDesc(layer, -1, "tY", transform.property("Y Position", float))

            let scale = addPropDesc(layer, -1, "scale", transform.property("Scale", Vector3), newVector3(100, 100, 100)) do(v: Vector3, frame: tuple[time: float, key: int]) -> JsonNode:
                var es: Vector2
                if frame.time > -1:
                    es = props.scale.valueAtTime(frame.time)
                else:
                    es = props.scale.keyValue(frame.key)

                es = es / 100

                let cs = (v / 100) * newVector3(es.x, es.y, 1.0)
                %cutDecimal(cs)

            scale.setInitialValueToResult(result)

            let anchor = addPropDesc(layer, -1, "anchor", transform.property("Anchor Point", Vector3), newVector3()) do(v: Vector3, frame: tuple[time: float, key: int]) -> JsonNode:
                var ep: Vector2
                if frame.time > -1:
                    ep = props.anchor.valueAtTime(frame.time)
                else:
                    ep = props.anchor.keyValue(frame.key)

                let val = v + newVector3(ep.x, ep.y)
                %cutDecimal(val)

            anchor.setInitialValueToResult(result)

        else:
            raise


    if layer.threeDLayer:
        let xprop = transform.property("X Rotation", float)
        let yprop = transform.property("Y Rotation", float)
        let zprop = transform.property("Z Rotation", float)

        let rotationEuler = newPropDescSeparated(layer, -1, "rotation", @[xprop, yprop, zprop]) do(v: seq[float]) -> JsonNode:
            % cutDecimal(newQuaternionFromEulerYXZ(v[0], v[1], v[2]))
        if not rotationEuler.isNil() and (xprop.isAnimated() or yprop.isAnimated() or zprop.isAnimated()):
            layer.animatedProperties.add(rotationEuler)
        rotationEuler.setInitialValueToResult(result)
    else:
        let rotation = addPropDesc(layer, -1, "rotation", transform.property("Rotation", float), 0) do(v: float) -> JsonNode:
            % cutDecimal(quaternionWithZRotation(v))
        rotation.setInitialValueToResult(result)



    let alpha = addPropDesc(layer, -1, "alpha", layer.property("Opacity", float), 100) do(v: float) -> JsonNode:
        %cutDecimal(v / 100.0)
    alpha.setInitialValueToResult(result)

    let md = layer.metadata()
    let hasCompRef = md.hasCompRefComponent()

    if not hasCompRef and not layer.isNinePartSprite():
        var children = layer.children
        if children.len > 0:
            var chres = newJArray()
            for child in children:
                if child.isTrackMatte:
                    setTrackMattLayer(child)
                if shouldSerializeLayer(child):
                    chres.add(serializeLayer(child))
            if chres.len > 0:
                chres.elems.reverse()
                result["children"] = chres

    if layer.layerIsCompositionRef():
        result["compositionRef"] = %relativePathToPath(gCompExportPath, layer.source.exportPath & "/" & $layer.source.name)

    if not transitiveEffects: result["affectsChildren"] = %false

    if layer.isTrackMatte:
        let lrr = layer.trckMatteLayers.getOrDefault($layer.name)
        if not lrr.layer.isNil:
            result["enabled"] = %lrr.layerEnabled

    var components = newJArray()
    layer.serializeEffectComponents(components)

    var styles = newJArray()
    layer.serializeLayerStyles(components)

    let additionalComponents = md{"components"}
    if not additionalComponents.isNil:
        for c in additionalComponents:
            if c{"_c"}.getStr() == "CompRef":
                c["size"] = %[layer.width, layer.height]
            components.add(c)

    if not hasCompRef:
        layer.serializeDrawableComponents(components)

    if components.len > 0: result["components"] = components


proc getMarkers(comp: Composition): seq[Marker] =
    result = @[]

    const undoGroupId = "__rod_export_script_undo_group__"
    app.beginUndoGroup(undoGroupId)
    let tempLayer = comp.layers.addText()

    let tempText = tempLayer.propertyGroup("Text").property("Source Text", TextDocument)
    tempText.expression = "thisComp.marker.numKeys"
    let numMarkers = parseInt($tempText.value.text)

    for i in 1 .. numMarkers:
        tempText.expression = "thisComp.marker.key(" & $i & ").time"
        let markerTime = parseFloat($tempText.value.text)
        tempText.expression = "thisComp.marker.key(" & $i & ").comment"
        let markerComment = $tempText.value.text
        result.add(Marker(
          time: markerTime,
          comment: markerComment
        ))
    app.endUndoGroup()
    app.undo(undoGroupId)

proc parseMarkerComment(comment: string, res: var Marker) =
    for ln in comment.splitLines:
        var kv = ln.split(":")
        if kv.len == 2:
            let k = kv[0].strip()
            let v = kv[1].strip()
            case k
            of "animation": res.animation = v
            of "loops": res.loops = parseInt(v)
            of "animation_end": res.animation_end = v
            else: logi "Unknown marker key: ", k

proc getAnimationEndMarkersFromMarkers(markers: openarray[Marker]): seq[Marker] =
    result = @[]
    for m in markers:
        if m.animation_end.len > 0:
            result.add(m)

proc getAnimationMarkers(comp: Composition): seq[Marker] =
    var markers = getMarkers(comp)
    for i in 0 ..< markers.len:
        parseMarkerComment(markers[i].comment, markers[i])

    var end_markers = getAnimationEndMarkersFromMarkers(markers)

    result = @[]
    for m in markers:
        if m.animation.len == 0:
            logi "WARNING: Marker ignored: ", m.comment
        else:
            result.add(m)

    if result.len > 0:
        for i in 0 ..< result.len - 1:
            result[i].duration = result[i + 1].time - result[i].time

        result[^1].duration = comp.duration - result[^1].time

    for em in end_markers:
        for i in 0 ..< result.len:
            if em.animation_end == result[i].animation:
                doAssert(em.time > result[i].time)
                result[i].duration = em.time - result[i].time

proc `%`(e: KeyframeEase): JsonNode =
    const c = 0.66
    let y = e.speed * (e.influence / 100) * c
    result = %*[
        e.influence / 100,
        y
    ]

proc getPropertyAnimation(pd: PropertyDescription, marker: Marker, fps: float): JsonNode =
    var animationStartTime = marker.time
    var animationEndTime = marker.time + marker.duration;
    #if (pd.property.numKeys > 0) {
    #  animationStartTime = Math.max(animationStartTime, pd.property.keyTime(1));
    #  animationEndTime = Math.min(animationEndTime, pd.property.keyTime(pd.property.numKeys));
    #}

    #if (animationStartTime >= animationEndTime - 0.0001) {
    # return null;
    #}

    result = newJObject()

    when exportKeyframeAnimations:
        let nk = pd.property.numKeys
        logi "prop: ", pd.fullyQualifiedName
        logi "nk: ", nk
        var keys = newJArray()

        let lastKeyTime = pd.property.keyTime(pd.property.numKeys)

        for i in 1 .. nk:
    #        const c = 0.66
            # let oe = prop.keyOutTemporalEase(i)[0]
            # let outY = oe.speed * (oe.influence / 100) * c
            # let ie = prop.keyInTemporalEase(i)[0]
            # let inY = - ie.speed * (ie.influence / 100) * c
            let inEase = pd.property.keyInTemporalEase(i)
            let outEase = pd.property.keyOutTemporalEase(i)
            if inEase.len != 1 or outEase.len != 1:
                logi "ERROR: Too many eases. Exported file might not be valid."
            let key = %*{
                "ie": inEase[0],
                "oe": outEase[0],
                "p": pd.property.keyTime(i) / lastKeyTime,
                "v": pd.keyValue(i)
            }
            keys.add(key)

            # logi i, " in: ", inY
            # logi i, " out: ", outY
        result["keys"] = keys

    when exportSampledAnimations:
        var timeStep = 1.0 / fps;
        var sampledPropertyValues = newJArray()

        var dEndTime = animationEndTime - 0.0001; # Due to floating point errors, we
        # may hit end time, so prevent that.

        var s = animationStartTime
        while s < dEndTime:
            sampledPropertyValues.add(pd.valueAtTime(s))
            s += timeStep
        #  logi(JSON.stringify(sampledPropertyValues));
        #  sampledPropertyValues.push(converter(prop.valueAtTime(animationEndTime, false)));

        result["values"] = sampledPropertyValues

    result["duration"] = %(animationEndTime - animationStartTime)
    if marker.loops != 0: result["numberOfLoops"] = %marker.loops

proc getAnimatableProperties(fromObj: PropertyOwner, res: var seq[AbstractProperty], name: string = "") =
    for i in 0 ..< fromObj.numProperties:
        let p = fromObj.property(i)
        let fullyQualifiedPropName = name & "." & $p.name
        if p.isPropertyGroup:
            if p.name != "Layer Styles" and ((p.isEffect and p.canSetEnabled and p.enabled) or not p.isEffect):
                getAnimatableProperties(p.toPropertyGroup(), res, fullyQualifiedPropName)
        else:
            let pr = p.toAbstractProperty()
            if pr.isTimeVarying and $pr.name notin bannedPropertyNames:
                if not pr.isSeparationLeader or not pr.dimensionsSeparated:
                    logi "Animatable prop: ", fullyQualifiedPropName
                    res.add(pr)

proc layerFootage(layer: Layer): FootageItem =
    var source = layer.source
    if not source.isNil:
        if source.jsObjectType == "FootageItem":
            result = FootageItem(source)

proc isSequenceLayer(layer: Layer): bool =
    let f = layer.layerFootage
    if not f.isNil and not f.file.isNil and f.duration > 0:
        result = true

proc sequenceFrameAtTime(layer: Layer, f: FootageItem, t: float, length: int): int =
    var relTime = t - layer.startTime

    if layer.timeRemapEnabled:
        let timeRemap = layer.property("Time Remap", float)
        relTime = timeRemap.valueAtTime(t)

    # Clamp relTime to layer duration
    if relTime < 0: relTime = 0
    if relTime >= f.duration: relTime = f.duration - 0.01

    result = round(relTime / f.frameDuration mod length.float).int
    if result >= length:
        result.dec()

proc getSequenceLayerAnimationForMarker(layer: Layer, marker: Marker, result: JsonNode, fps: float) =
    var animationStartTime = marker.time
    var animationEndTime = marker.time + marker.duration;

    var timeStep = 1.0 / fps;
    var sampledPropertyValues = newJArray()

    var dEndTime = animationEndTime - 0.0001; # Due to floating point errors, we
    # may hit end time, so prevent that.

    let footage = layer.layerFootage

    var s = animationStartTime
    let length =  getSequenceFilesFromSource(footage).len
    while s < dEndTime:
        sampledPropertyValues.add(%sequenceFrameAtTime(layer, footage, s, length))
        s += timeStep

    let anim = newJObject()
    anim["duration"] = %(animationEndTime - animationStartTime)
    anim["animScale"] = %(layer.stretch / 100.0)
    anim["frameLerp"] = %false
    anim["values"] = sampledPropertyValues

    if marker.loops != 0: anim["numberOfLoops"] = %marker.loops

    var fullyQualifiedPropName = layer.mangledName & ".curFrame"
    result[fullyQualifiedPropName] = anim

proc getLayerActiveAtTimeAnimationForMarker(layer: Layer, marker: Marker, result: JsonNode, fps: float) =
    var animationStartTime = marker.time
    var animationEndTime = marker.time + marker.duration;

    var timeStep = 1.0 / fps;
    var sampledPropertyValues = newJArray()

    var dEndTime = animationEndTime - 0.0001;
    var s = animationStartTime
    while s < dEndTime:
        sampledPropertyValues.add(%layer.activeAtTime(s))
        s += timeStep

    let anim = newJObject()
    anim["duration"] = %(animationEndTime - animationStartTime)
    anim["animScale"] = %(layer.stretch / 100.0)
    anim["values"] = sampledPropertyValues
    anim["frameLerp"] = %false

    var fullyQualifiedPropName = layer.mangledName & ".enabled"
    result[fullyQualifiedPropName] = anim

proc serializeCompositionBuffers(composition: Composition): JsonNode=
    result = newJArray()
    var animationsBuffer = newJObject()
    var allCompositionMarker : Marker
    allCompositionMarker.time = 0.0
    allCompositionMarker.duration = composition.duration
    allCompositionMarker.animation = "aeAllCompositionAnimation"

    for pd in composition.animatedProperties:
        animationsBuffer[pd.fullyQualifiedName] = getPropertyAnimation(pd, allCompositionMarker, composition.frameRate)

    var aeContainingLayers = newJArray()

    for layer in composition.layers:
        if shouldSerializeLayer(layer):
            aeContainingLayers.add(%layer.mangledName)
            if layer.isSequenceLayer():
                getSequenceLayerAnimationForMarker(
                    layer,
                    allCompositionMarker,
                    animationsBuffer,
                    composition.frameRate
                )
            if not layer.isTrackMatte:
                getLayerActiveAtTimeAnimationForMarker(
                    layer,
                    allCompositionMarker,
                    animationsBuffer,
                    composition.frameRate
                )

    for k, v in animationsBuffer:
        var values = v["values"]
        var cutVals = newJArray()
        var valsBack = newJArray()
        let valuesLen = values.len

        var cutFront, cutBack: int
        var isFrontCutting = true
        var isBackCutting = true

        for i in 0 ..< valuesLen:
            let curFront = values[i]
            let curBack = values[valuesLen - 1 - i]
            if $curFront == $values[0] and isFrontCutting:
                inc cutFront
            else:
                isFrontCutting = false

            if $curBack == $values[valuesLen - 1] and isBackCutting:
                inc cutBack
            else:
                isBackCutting = false

        for i in (cutFront - 1) .. (valuesLen - cutBack):
            cutVals.add(values[i])

        if cutFront == valuesLen:
            cutVals.add(values[0])

        v["len"] = %valuesLen
        v["cutf"] = %(cutFront - 1)
        v["values"] = cutVals
        v["frameLerp"] = %frameLerp

    var animations = newJObject()
    var animationMarkers = getAnimationMarkers(composition)
    animationMarkers.add(allCompositionMarker)

    for m in animationMarkers:
        var markerTime = newJObject()
        markerTime["start"] = %m.time
        markerTime["duration"] = %m.duration
        animations[m.animation] = markerTime

    var compC = newJObject()
    if animationsBuffer.len > 0:
        compC["buffers"] = animationsBuffer
    compC["markers"] = animations
    if aeContainingLayers.len > 0:
        compC["layers"] = aeContainingLayers
    compC["_c"] = %"AEComposition"

    result.add(compC)

proc serializeCompositionAnimations(composition: Composition): JsonNode =
    result = newJObject()

    var animationMarkers = getAnimationMarkers(composition)
    for m in animationMarkers:
        var animations = newJObject()
        logi("Exporting animation: ", m.animation, ": ", epochTime())

        for pd in composition.animatedProperties:
            animations[pd.fullyQualifiedName] = getPropertyAnimation(pd, m, composition.frameRate)

        for layer in composition.layers:
            if shouldSerializeLayer(layer) and layer.isSequenceLayer():
                getSequenceLayerAnimationForMarker(
                    layer,
                    m,
                    animations,
                    composition.frameRate
                )

        if animations.len > 0:
            result[m.animation] = animations

proc serializeComposition(composition: Composition): JsonNode =
    resourcePaths = @[]

    let rootLayer = composition.layer("root")
    if not rootLayer.isNil:
        result = serializeLayer(rootLayer)
        result["name"] = % $composition.name
    else:
        result = % {
          "name": % $composition.name
        }
        var children = newJArray();
        for layer in composition.layers:
            if layer.parent.isNil:
                if layer.isTrackMatte:
                    setTrackMattLayer(layer)
                if shouldSerializeLayer(layer):
                    children.add(serializeLayer(layer))
        children.elems.reverse()
        if children.len > 0:
            result["children"] = children

    if exportInOut:
        let animComp = serializeCompositionBuffers(composition)
        result["components"] = animComp
    else:
        let animations = serializeCompositionAnimations(composition)
        if animations.len > 0:
            result["animations"] = animations

    let f = app.project.file
    if not f.isNil:
        result["aep_name"] = % $f.name


proc replacer(n: JsonNode): ref RootObj =
    case n.kind
    of JNull: result = nil
    of JBool:
        let b = n.bval
        {.emit: "`result` = `b`;".}
    of JArray:
        var r = newSeq[ref RootObj]()
        for e in n.elems:
            r.add(replacer(e))
        {.emit: "`result` = `r`;".}
    of JString:
        var e : cstring = n.str
        {.emit: "`result` = `e`;".}
    of JInt:
        let e = n.num
        {.emit: "`result` = `e`;".}
    of JFloat:
        let e = n.fnum
        {.emit: "`result` = `e`;".}
    of JObject:
        {.emit: "`result` = {};"}
        for k, v in n:
            let ck : cstring = k
            let val = replacer(v)
            {.emit: "`result`[`ck`] = `val`;".}

proc fastJsonStringify(n: JsonNode): cstring =
    let r = replacer(n)
    {.emit: "`result` = JSON.stringify(`r`, null, 2);".}

proc exportSelectedCompositions(exportFolderPath: cstring, recursive = false) =
    logTextField.text = ""

    let compositions = getSelectedCompositions(recursive)
    
    gExportFolderPath = $exportFolderPath
    exportSettings = newTable[string, ExportSettings]()

    for i in 0 .. compositions.high:
        let c = compositions[i]
        let compName = $c.name
        if compName in exportSettings: 
            logi("Skiping composition ", compName, ". Already exported.")
            continue

        gCompExportPath = c.exportPath()

        let fullExportPath = gExportFolderPath & "/" & gCompExportPath

        try:
            if not newFolder(fullExportPath).create():
                logi "ERROR: Could not create folder ", fullExportPath
        except:
            discard
        
        let filePath = fullExportPath & "/" & compName & ".jcomp"
        logi("Exporting: ", compName, " to ", filePath)
        let file = newFile(filePath)
        file.encoding = "UTF-8"
        file.openForWriting()
        file.lineFeed = lfUnix
        try:
            exportSettings[compName] = createExportSettings(c)

            let serializedComp = serializeComposition(c)
            serializedComp["version"] = %exportedVersion
            file.write(fastJsonStringify(serializedComp))

            for k, v in c.trckMatteLayers:
                v.layer.enabled = v.layerEnabled
            exportSettings[compName] = nil

        except:
            logi "Exception caught: ", getCurrentExceptionMsg()
            let s = getCurrentException().getStackTrace()
            if not s.isNil: logi s
        file.close()

        logi "Done: ", compName

    logi("Done. ", epochTime())
    if recursive:
        logi("Recursive compostions exported ", compositions.len)


proc buildUI(contextObj: ref RootObj) =
  if false: exportSelectedCompositions(nil) # Workaround for nim issue #5951

  {.emit: """
  var mainWindow = null;
  if (`contextObj` instanceof Panel) {
    mainWindow = `contextObj`;
  } else {
    mainWindow = new Window("palette", "Animations", undefined, {
      resizeable: true
    });
    mainWindow.size = [640, 300];
  }
  //mainWindow.alignment = ['fill', 'fill'];

  var topGroup = mainWindow.add("group{orientation:'row'}");
  topGroup.alignment = ["fill", "top"];

  var browseGroup = topGroup.add("group{orientation:'column'}");
  browseGroup.alignment = ["fill", "top"];

  var setPathButton = browseGroup.add("button", undefined, "Browse");
  setPathButton.alignment = ["left", "top"];

  var filePath = browseGroup.add("statictext");
  filePath.alignment = ["fill", "bottom"];

  var exportOptionsGroup = topGroup.add("group{orientation:'column'}");
  exportOptionsGroup.alignment = ["fill", "top"];

  var copyResourcesCheckBox = exportOptionsGroup.add("checkbox", undefined, "Copy resources");
  copyResourcesCheckBox.alignment = ["fill", "top"];
  copyResourcesCheckBox.value = true;
  app.settings.saveSetting("rodExport", "copyResources", "true");

  copyResourcesCheckBox.onClick = function(e) {
    app.settings.saveSetting("rodExport", "copyResources", copyResourcesCheckBox.value + "");
  };

  var transitiveEffectsCheckBox = exportOptionsGroup.add("checkbox", undefined, "Transitive effects");
  transitiveEffectsCheckBox.alignment = ["fill", "bottom"];
  `transitiveEffects`[0] = app.settings.haveSetting("rodExport", "transitiveEffects") &&
    app.settings.getSetting("rodExport", "transitiveEffects") == "true";
  transitiveEffectsCheckBox.value = `transitiveEffects`[0];

  transitiveEffectsCheckBox.onClick = function(e) {
    `transitiveEffects`[0] = transitiveEffectsCheckBox.value;
    app.settings.saveSetting("rodExport", "transitiveEffects", transitiveEffectsCheckBox.value + "");
  };

  var exportInOutGroup = topGroup.add("group{orientation:'column'}");
  exportInOutGroup.alignment = ["fill", "top"];

  var inOutCheckBox = exportInOutGroup.add("checkbox", undefined, "Export InOut");
  inOutCheckBox.alignment = ["fill", "top"];

  `exportInOut`[0] = app.settings.haveSetting("rodExport", "exportInOut") &&
     app.settings.getSetting("rodExport", "exportInOut") == "true";
  inOutCheckBox.value = `exportInOut`[0];

  inOutCheckBox.onClick = function(e) {
    `exportInOut`[0] = inOutCheckBox.value;
    app.settings.saveSetting("rodExport", "exportInOut", inOutCheckBox.value + "");
  }

  var frameLerpCheckBox = exportInOutGroup.add("checkbox", undefined, "Frame lerp");
  frameLerpCheckBox.alignment = ["fill", "bottom"];
  `frameLerp`[0] = app.settings.haveSetting("rodExport", "frameLerp") &&
     app.settings.getSetting("rodExport", "frameLerp") == "true";
  frameLerpCheckBox.value = `frameLerp`[0];
  frameLerpCheckBox.onClick = function(e){
    `frameLerp`[0] = frameLerpCheckBox.value;
    app.settings.saveSetting("rodExport", "frameLerp", frameLerpCheckBox.value + "");
  }

  var buttonGroup = topGroup.add("group{orientation:'column'}");
  buttonGroup.aligment = ["right", "center"]

  var exportButton = buttonGroup.add("button", undefined,
    "Export");
  exportButton.alignment = ["right", "top"];
  exportButton.enabled = false;

  var exportRecButton = buttonGroup.add("button", undefined,
    "Export recursive");
  exportRecButton.alignment = ["right", "bottom"];
  exportRecButton.enabled = false;

  if (app.settings.haveSetting("rodExport", "outputPath")) {
    exportButton.enabled = true;
    exportRecButton.enabled = true;
    filePath.text = app.settings.getSetting("rodExport", "outputPath");
  } else {
    filePath.text = "Output: (not specified)";
  }

  var resultText = mainWindow.add(
    "edittext{alignment:['fill','fill'], properties: { multiline:true } }");
  `logTextField`[0] = resultText;

  setPathButton.onClick = function(e) {
    var outputFile = Folder.selectDialog("Choose an output folder");
    if (outputFile) {
      exportButton.enabled = true;
      exportRecButton.enabled = true;
      filePath.text = outputFile.absoluteURI;
      app.settings.saveSetting("rodExport", "outputPath", outputFile.absoluteURI);
    } else {
      exportButton.enabled = false;
      exportRecButton.enabled = false;
    }
  };

  exportButton.onClick = function(e) {
    `exportSelectedCompositions`(filePath.text);
  };
  
  exportRecButton.onClick = function(e) {
    `exportSelectedCompositions`(filePath.text, true);
  };

  mainWindow.addEventListener("resize", function(e) {
    this.layout.resize();
  });

  mainWindow.addEventListener("close", function(e) {
    app.cancelTask(taskId);
    stopServer();
  });

  mainWindow.onResizing = mainWindow.onResize = function() {
    this.layout.resize();
  };

  if (mainWindow instanceof Window) {
    //    mainWindow.onShow = function() {
    //        readMetaData();
    //    }
    mainWindow.show();
  } else {
    mainWindow.layout.layout(true);
    //    readMetaData();
  }
  """.}
var this {.importc.}: ref RootObj
buildUI(this)
