import tables, dom, math
import after_effects
import times
import json
import algorithm
import strutils
import nimx.matrixes, nimx.pathutils
import rod.quaternion

type File = after_effects.File

proc getObjectsWithTypeFromCollection*(t: typedesc, collection: openarray[Item], typeName: string): seq[t] =
    for i in collection:
        if i.jsObjectType == typeName:
            result.add(cast[t](i))

proc getSelectedCompositions(): seq[Composition] {.exportc.} =
    getObjectsWithTypeFromCollection(Composition, app.project.selection, "CompItem")

var logTextField: EditText

proc logi(args: varargs[string, `$`]) =
    var text = $logTextField.text
    for i in args:
        text &= i
    text &= "\n"
    logTextField.text = text

proc shouldSerializeLayer(layer: Layer): bool {.exportc.} = return layer.enabled

template quaternionWithZRotation(zAngle: float32): Quaternion = newQuaternion(-zAngle, newVector3(0, 0, 1))

var propertyNameMap = {
    "Rotation" : "rotation",
    "Position" : "translation",
    "X Position": "tX",
    "Y Position": "tY",
    "Scale": "scale",
    "Opacity": "alpha",
    "Input White": "inWhite",
    "Input Black": "inBlack",
    "Gamma": "inGamma",
    "Output White": "outWhite",
    "Output Black": "outBlack"
}.toTable()

let bannedPropertyNames = ["Time Remap", "Marker", "Checkbox", "Value/Offset/Random Max", "Slider", "Source Text"]

var compExportPath = ""

proc getResourceNameFromSourceFile(file: File): string {.exportc.} =
    const footageToken = "(Footage)/"
    let p = $decodeURIComponent(file.path)
    let n = p.find(footageToken)
    var path = ""
    if n != -1:
        path = p.substr(n + footageToken.len) & "/"
    result = relativePathToPath(compExportPath, path & $decodeURIComponent(file.name))

proc getSequenceFileNamesFromSource(f: FootageItem): seq[string] =
    result = newSeq[string]()
    for c in getSequenceFilesFromSource(f):
        result.add(getResourceNameFromSourceFile(c))

proc `%`[T: string | SomeNumber](s: openarray[T]): JsonNode =
    result = newJArray()
    for c in s: result.add(%c)

proc serializeLayerComponents(layer: Layer): JsonNode =
    result = newJObject()
    var source = layer.source
    if not source.isNil:
        if source.jsObjectType == "FootageItem":
            let footageSource = FootageItem(source)
            if not footageSource.file.isNil:
                var sprite = newJObject()
                if footageSource.duration > 0:
                    sprite["fileNames"] = % getSequenceFileNamesFromSource(footageSource)
                else:
                    sprite["fileNames"] = % [getResourceNameFromSourceFile(footageSource.file)]
                result["Sprite"] = sprite
            elif ($source.name).find("Null") != 0 and
                    not footageSource.mainSource.isNil and
                    footageSource.mainSource.jsObjectType == "SolidSource": # Solid source
                var solid = newJObject()
                let solidSource = SolidSource(footageSource.mainSource)
                solid["color"] = %* solidSource.color
                solid["size"] = % [source.width, source.height]
                result["Solid"] = solid

    let effects = layer.propertyGroup("Effects")
    if not effects.isNil:
        let levels = effects.propertyGroup("Levels (Individual Controls)")
        if not levels.isNil:
            var lvl = newJObject()
            lvl["inWhite"] = % levels.property("Input White", float).valueAtTime(0, false)
            lvl["inBlack"] = % levels.property("Input Black", float).valueAtTime(0, false)
            lvl["inGamma"] = % levels.property("Gamma", float).valueAtTime(0, false)
            lvl["outWhite"] = % levels.property("Output White", float).valueAtTime(0, false)
            lvl["outBlack"] = % levels.property("Output Black", float).valueAtTime(0, false)
            result["ChannelLevels"] = lvl

        let numbers = effects.propertyGroup("Numbers")
        if not numbers.isNil:
            var txt = newJObject()
            var color = numbers.property("Fill Color", Vector4).valueAtTime(0)
            txt["color"] = %color
            txt["fontSize"] = % numbers.property("Size", float).valueAtTime(0)
            result["Text"] = txt
            result.delete("Solid")

    var text = layer.propertyGroup("Text")
    if not text.isNil:
        var textDoc = text.property("Source Text", TextDocument).value
        var txt = newJObject()
        txt["text"] = % $textDoc.text
        txt["fontSize"] = % textDoc.fontSize
        txt["color"] = % textDoc.fillColor
        case textDoc.justification
        of tjLeft: txt["justification"] = %"left"
        of tjRight: txt["justification"] = %"right"
        of tjCenter: txt["justification"] = %"center"

        let shadow = layer.propertyGroup("Layer Styles").propertyGroup("Drop Shadow")
        if not shadow.isNil:
            let angle = shadow.property("Angle", float32).valueAtTime(0)
            let distance = shadow.property("Distance", float32).valueAtTime(0)
            let color = shadow.property("Color", Vector4).valueAtTime(0)
            let alpha = shadow.property("Opacity", float32).valueAtTime(0) / 100
            txt["shadowColor"] = %[color.x, color.y, color.z, alpha]
            let radAngle = degToRad(angle + 180)
            txt["shadowOff"] = %[distance * cos(radAngle), - distance * sin(radAngle)]

        result["Text"] = txt

proc layerIsCompositionRef(layer: Layer): bool =
    not layer.source.isNil and layer.source.jsObjectType == "CompItem"

proc requiresAuxParent(layer: Layer): bool =
    let ap = layer.property("Anchor Point", Vector3)
    if ap.value != newVector3(0, 0, 0):
        result = true

var layerNames = initTable[int, string]()

proc mangledName(layer: Layer): string =
    result = layerNames.getOrDefault(layer.index)
    if result.len == 0:
        result = $layer.name
        for v in values(layerNames):
            if result == v:
                result &= "$" & $layer.index
                break
        layerNames[layer.index] = result

proc auxLayerName(layer: Layer): string = layer.mangledName & "$AUX"

proc exportPath(c: Item): string =
    result = c.projectPath
    if result == "/":
        result = "compositions"
    else:
        result = result[1 .. ^1]

proc serializeLayer(layer: Layer): JsonNode =
    result = newJObject()

    logi ("LAYER: ", layer.name, ", w: ", layer.width, " h: ", layer.height);

    result["name"] = % layer.mangledName
    result["translation"] = % layer.property("Position", Vector3).valueAtTime(0)
    var scale = layer.property("Scale", Vector3).valueAtTime(0)
    if scale != newVector3(100, 100, 100):
        scale /= 100
        result["scale"] = %scale
    var rotation = layer.property("Rotation", float32).valueAtTime(0, false);
    if (rotation != 0):
        result["rotation"] = % quaternionWithZRotation(rotation)

    let opacity = layer.property("Opacity", float).valueAtTime(0)
    if opacity != 100:
        result["alpha"] = % (opacity / 100.0)

    var children = layer.children
    if children.len > 0:
        var chres = newJArray()
        for child in children:
            if shouldSerializeLayer(child):
                chres.add(serializeLayer(child))

        if chres.len > 0:
            chres.elems.reverse()
        result["children"] = chres

    if layer.layerIsCompositionRef():
        result["compositionRef"] = %relativePathToPath(compExportPath, layer.source.exportPath & "/" & $layer.source.name & ".json")

    var components = serializeLayerComponents(layer)
    if components.len > 0: result["components"] = components

    if layer.requiresAuxParent:
        logi "Creating aux parent for: ", layer.mangledName
        var auxNode = newJObject()
        auxNode["name"] = % layer.auxLayerName
        let pos = layer.property("Position", Vector3).valueAtTime(0)
        auxNode["translation"] = % pos
        if not result["scale"].isNil:
            auxNode["scale"] = result["scale"]
            result.delete("scale")

        if not result["rotation"].isNil:
            auxNode["rotation"] = result["rotation"]
            result.delete("rotation")

        result["translation"] = % (- layer.property("Anchor Point", Vector3).valueAtTime(0))
        auxNode["children"] = % [result]
        result = auxNode

type Marker = object
    time*, duration*: float
    comment*: string
    animation*: string
    loops*: int
    animation_end*: string

proc getMarkers(comp: Composition): seq[Marker] =
    result = newSeq[Marker]()
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
    tempLayer.remove()

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

proc getAnimationEndMarkers(comp: Composition): seq[Marker] =
    var markers = getMarkers(comp)

    result = newSeq[Marker]()
    for i in 0 ..< markers.len:
        parseMarkerComment(markers[i].comment, markers[i])
        if markers[i].animation_end.len > 0:
            result.add(markers[i])


proc getAnimationMarkers(comp: Composition): seq[Marker] =
    var markers = getMarkers(comp)
    var end_markers = getAnimationEndMarkers(comp)

    result = newSeq[Marker]()
    for i in 0 ..< markers.len:
        parseMarkerComment(markers[i].comment, markers[i])
        if markers[i].animation.len == 0:
            logi "WARNING: Marker ignored: ", markers[i].comment
        else:
            result.add(markers[i])

    if result.len > 0:
        for i in 0 ..< result.len - 1:
            result[i].duration = result[i + 1].time - result[i].time

        result[^1].duration = comp.duration - result[^1].time


    for em in end_markers:
        for i in 0 ..< result.len:
            if em.animation_end == result[i].animation:
                doAssert(em.time > result[i].time)
                result[i].duration = em.time - result[i].time


proc jsonPropertyAccessor(p: AbstractProperty): proc(t: float): JsonNode =
    case $p.name
    of "Rotation":
        let cp = p.toPropertyOfType(float)
        result = proc(t: float): JsonNode =
            % quaternionWithZRotation(cp.valueAtTime(t))
    of "Scale":
        let cp = p.toPropertyOfType(Vector3)
        result = proc(t: float): JsonNode =
            % (cp.valueAtTime(t) / 100)
    of "Opacity":
        let cp = p.toPropertyOfType(float)
        result = proc(t: float): JsonNode =
            % (cp.valueAtTime(t) / 100)
    else:
        case p.propertyValueType
        of pvt2d, pvt2dSpatial:
            let cp = p.toPropertyOfType(Vector2)
            result = proc(t: float): JsonNode =
                % (cp.valueAtTime(t))

        of pvt3d, pvt3dSpatial:
            let cp = p.toPropertyOfType(Vector3)
            result = proc(t: float): JsonNode =
                % (cp.valueAtTime(t))

        of pvt1d:
            let cp = p.toPropertyOfType(float)
            result = proc(t: float): JsonNode =
                % (cp.valueAtTime(t))

        else:
            raise newException(Exception, "Unknown property type to convert: " & $p.propertyValueType)

proc getPropertyAnimation(prop: AbstractProperty, marker: Marker): JsonNode =
    var animationStartTime = marker.time
    var animationEndTime = marker.time + marker.duration;
    #if (prop.numKeys > 0) {
    #  animationStartTime = Math.max(animationStartTime, prop.keyTime(1));
    #  animationEndTime = Math.min(animationEndTime, prop.keyTime(prop.numKeys));
    #}

    #if (animationStartTime >= animationEndTime - 0.0001) {
    # return null;
    #}

    var fps = 30.0;
    var timeStep = 1.0 / fps;
    var sampledPropertyValues = newJArray()
    var accessor = jsonPropertyAccessor(prop)

    var dEndTime = animationEndTime - 0.0001; # Due to floating point errors, we
    # may hit end time, so prevent that.

    var s = animationStartTime
    while s < dEndTime:
        sampledPropertyValues.add(accessor(s))
        s += timeStep
    #  logi(JSON.stringify(sampledPropertyValues));
    #  sampledPropertyValues.push(converter(prop.valueAtTime(animationEndTime, false)));

    result = newJObject()
    result["duration"] = %(animationEndTime - animationStartTime)
    result["values"] = sampledPropertyValues
    if marker.loops != 0: result["numberOfLoops"] = %marker.loops

proc mapPropertyName(name: string): string =
    result = propertyNameMap.getOrDefault(name)
    if result.len == 0:
        result = name

proc getAnimatableProperties(fromObj: PropertyOwner, res: var seq[AbstractProperty], name: string = "") =
    for i in 0 ..< fromObj.numProperties:
        let p = fromObj.property(i)
        let fullyQualifiedPropName = name & "." & $p.name
        if p.isPropertyGroup:
            if p.name != "Layer Styles":
                getAnimatableProperties(p.toPropertyGroup(), res, fullyQualifiedPropName)
        else:
            let pr = p.toAbstractProperty()
            if pr.isTimeVarying and $pr.name notin bannedPropertyNames:
                if not pr.isSeparationLeader or not pr.dimensionsSeparated:
                    logi "Animatable prop: ", fullyQualifiedPropName
                    res.add(pr)

proc belongsToAux(p: AbstractProperty): bool =
    for i in ["Scale".cstring, "Rotation", "Position", "X Position", "Y Position"]:
        if p.name == i: return true

proc getLayerAnimationForMarker(layer: Layer, marker: Marker, props: openarray[AbstractProperty], result: JsonNode) =
    for pr in props:
        var anim = getPropertyAnimation(pr, marker)
        let layerName = if pr.belongsToAux and layer.requiresAuxParent:
                layer.auxLayerName
            else:
                layer.mangledName
        var fullyQualifiedPropName = layerName & "." & mapPropertyName($pr.name)
        result[fullyQualifiedPropName] = anim

proc layerFootage(layer: Layer): FootageItem =
    var source = layer.source
    if not source.isNil:
        if source.jsObjectType == "FootageItem":
            result = FootageItem(source)

proc isSequenceLayer(layer: Layer): bool =
    let f = layer.layerFootage
    if not f.isNil and not f.file.isNil and f.duration > 0:
        result = true

proc sequenceFrameAtTime(layer: Layer, f: FootageItem, t: float): int =
    var relTime = t - layer.startTime

    if layer.timeRemapEnabled:
        let timeRemap = layer.property("Time Remap", float)
        relTime = timeRemap.valueAtTime(t)

    # Clamp relTime to layer duration
    if relTime < 0: relTime = 0
    if relTime >= f.duration: relTime = f.duration - 0.01

    result = int(relTime / f.frameDuration)

proc getSequenceLayerAnimationForMarker(layer: Layer, marker: Marker, result: JsonNode) =
    var animationStartTime = marker.time
    var animationEndTime = marker.time + marker.duration;

    var fps = 30.0;
    var timeStep = 1.0 / fps;
    var sampledPropertyValues = newJArray()

    var dEndTime = animationEndTime - 0.0001; # Due to floating point errors, we
    # may hit end time, so prevent that.

    let footage = layer.layerFootage

    var s = animationStartTime
    while s < dEndTime:
        sampledPropertyValues.add(%sequenceFrameAtTime(layer, footage, s))
        s += timeStep

    let anim = newJObject()
    anim["duration"] = %(animationEndTime - animationStartTime)
    anim["values"] = sampledPropertyValues
    if marker.loops != 0: anim["numberOfLoops"] = %marker.loops

    var fullyQualifiedPropName = layer.mangledName & ".curFrame"
    result[fullyQualifiedPropName] = anim

proc serializeCompositionAnimations(composition: Composition): JsonNode =
    var animationMarkers = getAnimationMarkers(composition)
    result = newJObject()

    var layerAnimatebleProps = newSeq[seq[AbstractProperty]]()

    for m in animationMarkers:
        var animations = newJObject()
        logi("Exporting animation: ", m.animation, ": ", epochTime())
        var i = 0
        for layer in composition.layers:
            if shouldSerializeLayer(layer):
                if layerAnimatebleProps.len <= i:
                    var props = newSeq[AbstractProperty]()
                    getAnimatableProperties(layer, props)
                    layerAnimatebleProps.add(props)
                getLayerAnimationForMarker(layer, m, layerAnimatebleProps[i], animations)

                if layer.isSequenceLayer():
                    getSequenceLayerAnimationForMarker(layer, m, animations)

                inc i
        if animations.len > 0:
            result[m.animation] = animations

proc serializeComposition(composition: Composition): JsonNode =
    layerNames = initTable[int, string]()

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
                if shouldSerializeLayer(layer):
                    children.add(serializeLayer(layer))
        children.elems.reverse()
        if children.len > 0:
            result["children"] = children

    let animations = serializeCompositionAnimations(composition)

    if animations.len > 0:
        result["animations"] = animations

proc replacer(n: JsonNode): ref RootObj {.exportc.} =
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
    {.emit: "`result` = JSON.stringify(`replacer`(`n`), null, 2);".}

proc exportSelectedCompositions(exportFolderPath: cstring) {.exportc.} =
    let compositions = getSelectedCompositions()
    let folderPath = $exportFolderPath
    for c in compositions:
        compExportPath = c.exportPath
        let fullExportPath = folderPath & "/" & c.exportPath
        if not newFolder(fullExportPath).create():
            logi "ERROR: Could not create folder ", fullExportPath
        let filePath = fullExportPath & "/" & $c.name & ".json"
        logi("Exporting: ", c.name, " to ", filePath)
        let file = newFile(filePath)
        file.openForWriting()
        file.lineFeed = lfUnix
        try:
            var serializedComp = serializeComposition(c)
            file.write(fastJsonStringify(serializedComp))
        except:
            logi("Exception caught: ", getCurrentExceptionMsg())
        file.close()

    logi("Done. ", epochTime())

{.emit: """

function buildUI(contextObj) {
  var mainWindow = null;
  if (contextObj instanceof Panel) {
    mainWindow = contextObj;
  } else {
    mainWindow = new Window("palette", "Animations", undefined, {
      resizeable: true
    });
    mainWindow.size = [640, 300];
  }
  //mainWindow.alignment = ['fill', 'fill'];

  var topGroup = mainWindow.add("group{orientation:'row'}");
  topGroup.alignment = ["fill", "top"];

  var setPathButton = topGroup.add("button", undefined, "Browse");
  setPathButton.alignment = ["left", "center"];

  var filePath = topGroup.add("statictext");
  filePath.alignment = ["fill", "fill"];

  var exportButton = topGroup.add("button", undefined,
    "Export selected compositions");
  exportButton.alignment = ["right", "center"];
  exportButton.enabled = false;

  if (app.settings.haveSetting("rodExport", "outputPath")) {
    exportButton.enabled = true;
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
      filePath.text = outputFile.absoluteURI;
      app.settings.saveSetting("rodExport", "outputPath", outputFile.absoluteURI);
    } else {
      exportButton.enabled = false;
    }
  };

  exportButton.onClick = function(e) {
    `logTextField`[0].text = "";
    exportSelectedCompositions(filePath.text);
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
}

buildUI(this);

""".}
