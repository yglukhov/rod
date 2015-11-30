import typetraits, tables
import after_effects
import times
import json
import algorithm
import strutils
import nimx.matrixes
import rod.quaternion

proc getObjectsWithTypeFromCollection*(t: typedesc, collection: openarray[Item]): seq[t] =
    for i in collection:
        if i.typeName == t.name:
            result.add(cast[t](i))

proc getSelectedCompositions(): seq[Composition] {.exportc.} =
    getObjectsWithTypeFromCollection(Composition, app.project.selection)

var logTextField: EditText

proc logi(args: varargs[string, `$`]) =
    var text = $logTextField.text
    for i in args:
        text &= i
    text &= "\n"
    logTextField.text = text

proc getLayerChildren(layer: Layer): seq[Layer] {.exportc.} = layer.children

proc jsonToJS(n: JsonNode): ref RootObj {.exportc.} =
    let s: cstring = $n
    {.emit: "`result` = JSON.parse(`s`);".}

proc jsToJson(n: ref RootObj): JsonNode {.exportc.} =
    var s: cstring
    {.emit: "`s` = JSON.stringify(`n`);".}
    result = parseJson($s)

proc shouldSerializeLayer(layer: Layer): bool {.exportc.} = return layer.enabled

proc quaternionWithZRotation(zAngle: float32): Quaternion {.exportc.} = newQuaternion(zAngle, newVector3(0, 0, 1))

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

let bannedPropertyNames = ["Time Remap", "Marker", "Checkbox"]

proc getResourceNameFromSourceFile(file: after_effects.File): cstring {.exportc.} =
    var footageToken = "(Footage)/"
    let p = $file.path
    var n = p.find(footageToken)
    var path = ""
    if n != -1:
        path = p.substr(n + footageToken.len) & "/"
    result = path & $file.name

{.emit: """

var outputFile = null;

function getSequenceFileNamesFromSource(source) {
    var path = source.file.path;
    var allFilesInDir = new Folder(path).getFiles();
    var srcName = source.name;

    var pattern = /(.*)\[(\d+)-(\d+)\](.*)/

    var matches = srcName.match(pattern)
    if (matches === null) return null;

    var startIndex = parseInt(matches[2]);
    var endIndex = parseInt(matches[3]);

    var result = [];
    for (var i = 0; i < allFilesInDir.length; ++i) {
      var fMatches = allFilesInDir[i].name.match(/([^\d]*)(\d+)(.*)/);
      var index = parseInt(fMatches[2]);
      if (matches[1] == fMatches[1] && matches[matches.length - 1] == fMatches[fMatches.length - 1] && index >= startIndex && index <= endIndex) {
        result.push(getResourceNameFromSourceFile(allFilesInDir[i]));
      }
    }

    return result;
}

function serializeLayerComponents(layer) {
    var result = {};
    var source = layer.source;
    if (source != null) {
        if (source.file != null) {
            var sprite = {};
            if (source.duration > 0) {
                sprite.fileNames = getSequenceFileNamesFromSource(source);
            }
            else {
                sprite.fileNames = [getResourceNameFromSourceFile(source.file)];
                sprite.name = getResourceNameFromSourceFile(source.file);
            }

            var opacity = layer.property("Opacity").valueAtTime(0, false);
            if (opacity != 100) sprite.alpha = opacity / 100.0;
            result["Sprite"] = sprite;
        }
        else if (source.name.indexOf("Null") != 0 && source.mainSource && source.mainSource.color !== undefined) { // Solid source
            var solid = {};
            solid.color = source.mainSource.color;
            solid.size = [source.width, source.height];
            var opacity = layer.property("Opacity").valueAtTime(0, false);
            if (opacity != 100) solid.alpha = opacity / 100.0;
            result["Solid"] = solid;
        }
    }
    var levels = layer.Effects.property("Levels (Individual Controls)");
    if (levels !== null) {
        var lvl = {};
        lvl.inWhite = levels.property("Input White").valueAtTime(0, false);
        lvl.inBlack = levels.property("Input Black").valueAtTime(0, false);
        lvl.inGamma = levels.property("Gamma").valueAtTime(0, false);
        lvl.outWhite = levels.property("Output White").valueAtTime(0, false);
        lvl.outBlack = levels.property("Output Black").valueAtTime(0, false);
        result["ChannelLevels"] = lvl;
    }

    var text = layer.Text;
    if (text !== null && text !== undefined) {
        var textDoc = text.property("Source Text").value;
        var txt = {};
        txt.text = textDoc.text;
        txt.fontSize = textDoc.fontSize;
        txt.color = textDoc.fillColor;
        txt.color.push(layer.property("Opacity").valueAtTime(0, false) / 100);
        switch(textDoc.justification) {
            case ParagraphJustification.LEFT_JUSTIFY: txt.justification = "left"; break;
            case ParagraphJustification.RIGHT_JUSTIFY: txt.justification = "right"; break;
            case ParagraphJustification.CENTER_JUSTIFY: txt.justification = "center"; break;
        }
        result["Text"] = txt;
    }

    return result;
}

""".}

proc `%`[I: static[int]](v: TVector[I, float32]): JsonNode =
    result = newJArray()
    for e in v: result.add(%e)

proc `%`(v: Quaternion): JsonNode =
    result = newJArray()
    for e in v: result.add(%e)

proc serializeLayer(layer: Layer): JsonNode =
    result = newJObject()

    logi ("LAYER: ", layer.name, ", w: ", layer.width, " h: ", layer.height);

    result["name"] = % $layer.name
    result["translation"] = % layer.property("Position", Vector3).valueAtTime(0)
    var scale = layer.property("Scale", Vector3).valueAtTime(0)
    if scale != newVector3(100, 100, 100):
        scale /= 100
        result["scale"] = %scale
    var rotation = layer.property("Rotation", float32).valueAtTime(0, false);
    if (rotation != 0):
        result["rotation"] = % quaternionWithZRotation(rotation)
    var children = getLayerChildren(layer)
    if (children.len > 0):
        var chres = newJArray()
        for child in children:
            if shouldSerializeLayer(child):
                chres.add(serializeLayer(child))

        chres.elems.reverse()
        result["children"] = chres

    if not layer.source.isNil and layer.source.typeName == "Composition":
        result["compositionRef"] = % $layer.source.name

    var components : JsonNode
    {.emit: "`components` = jsToJson(serializeLayerComponents(`layer`));".}
    if components.len > 0: result["components"] = components

type Marker = object
    time*, duration*: float
    comment*: string
    animation*: string
    loops*: int

proc getMarkers(comp: Composition): seq[Marker] =
    result = newSeq[Marker]()
    var tempLayer = comp.layers.addText($comp.duration)

    var tempText = tempLayer.propertyGroup("Text").property("Source Text", cstring)

    tempText.expression = "thisComp.marker.numKeys;"
    var numMarkers = parseInt($tempText.value)

    for i in 1 .. numMarkers:
        tempText.expression = "thisComp.marker.key(" & $i & ").time;"
        var markerTime = parseFloat($tempText.value)
        tempText.expression = "thisComp.marker.key(" & $i & ").comment;"
        var markerComment = $tempText.value
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
            else: logi "Unknown marker key: ", k

proc getAnimationMarkers(comp: Composition): seq[Marker] =
    result = getMarkers(comp)
    for i in 0 ..< result.len - 1:
        parseMarkerComment(result[i].comment, result[i])
        result[i].duration = result[i + 1].time - result[i].time

    if result.len > 0:
        parseMarkerComment(result[^1].comment, result[^1])
        result[^1].duration = comp.duration - result[^1].time

proc jsonPropertyAccessor(p: AbstractProperty): proc(t: float): JsonNode =
    case $p.name
    of "Rotation":
        result = proc(t: float): JsonNode =
            % quaternionWithZRotation(p.toPropertyOfType(float).valueAtTime(t))
    of "Scale":
        result = proc(t: float): JsonNode =
            % (p.toPropertyOfType(Vector3).valueAtTime(t) / 100)
    of "Opacity":
        result = proc(t: float): JsonNode =
            % (p.toPropertyOfType(float).valueAtTime(t) / 100)
    else:
        case p.propertyValueType
        of pvt2d, pvt2dSpatial:
            result = proc(t: float): JsonNode =
                % (p.toPropertyOfType(Vector2).valueAtTime(t))

        of pvt3d, pvt3dSpatial:
            result = proc(t: float): JsonNode =
                % (p.toPropertyOfType(Vector3).valueAtTime(t))

        of pvt1d:
            result = proc(t: float): JsonNode =
                % (p.toPropertyOfType(float).valueAtTime(t))

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

    result = %{
      #"startTime": marker.startTime - animationStartTime,
      "duration": %(animationEndTime - animationStartTime),
      "values": sampledPropertyValues
    };
    if marker.loops != 0: result["numberOfLoops"] = %marker.loops

proc mapPropertyName(name: string): string =
    result = propertyNameMap.getOrDefault(name)
    if result.len == 0:
        result = name

proc getAnimatableProperties(fromObj: PropertyOwner, res: var seq[AbstractProperty]) =
    for i in 0 ..< fromObj.numProperties:
        let p = fromObj.property(i)
        if p.isPropertyGroup:
            getAnimatableProperties(p.toPropertyGroup(), res)
        else:
            let pr = p.toAbstractProperty()
            if pr.isTimeVarying and $fromObj.name notin bannedPropertyNames:
                if not pr.isSeparationLeader or not pr.dimensionsSeparated:
                    res.add(pr)

proc getLayerAnimationForMarker(layer: Layer, marker: Marker, result: JsonNode) =
    var props = newSeq[AbstractProperty]()
    getAnimatableProperties(layer, props);
    for pr in props:
        var anim = getPropertyAnimation(pr, marker)
        var fullyQualifiedPropName = $layer.name & "." & mapPropertyName($pr.name)
        logi("PROP: ", fullyQualifiedPropName)
        result[fullyQualifiedPropName] = anim

proc serializeCompositionAnimations(composition: Composition): JsonNode =
    var animationMarkers = getAnimationMarkers(composition)
    result = newJObject()
    for m in animationMarkers:
        var animations = newJObject()
        logi("Exporting animation: ", m.animation);
        for layer in composition.layers:
            if shouldSerializeLayer(layer):
                getLayerAnimationForMarker(layer, m,
                  animations)
        if animations.len > 0:
            result[m.animation] = animations;

proc serializeComposition(composition: Composition): JsonNode =
    let rootLayer = composition.layer("root")
    if not rootLayer.isNil:
        result = serializeLayer(rootLayer)
        result["name"] = % $composition.name
        result.delete("translation")
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
        result["animations"] = animations;

proc exportSelectedCompositions(exportFolderPath: cstring) {.exportc.} =
    let compositions = getSelectedCompositions()
    let folderPath = $exportFolderPath
    for c in compositions:
        let filePath = folderPath & "/" & $c.name & ".json"
        logi("Exporting: ", c.name, " to ", filePath)
        let file = newFile(filePath)
        file.openForWriting()
        try:
            var serializedComp = serializeComposition(c)
            file.write(serializedComp.pretty)
        except:
            logi("Exception caught: ", getCurrentExceptionMsg())
        file.close()

    logi("Done. ", epochTime())

{.emit: """

function buildUI(contextObj) {
  var debug = true;

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
  filePath.text = "Output: (not specified)";

  var exportButton = topGroup.add("button", undefined,
    "Export selected compositions");
  exportButton.alignment = ["right", "center"];
  exportButton.enabled = false;

  var resultText = mainWindow.add(
    "edittext{alignment:['fill','fill'], properties: { multiline:true } }");
  `logTextField`[0] = resultText;

  setPathButton.onClick = function(e) {
    outputFile = Folder.selectDialog("Choose an output folder");
    if (outputFile) {
      exportButton.enabled = true;
      filePath.text = outputFile.absoluteURI;
    } else {
      exportButton.enabled = false;
    }
  };

  exportButton.onClick = function(e) {
    `logTextField`[0].text = "";
    exportSelectedCompositions(filePath.text);
  };

  if (debug) {
    filePath.text = "/Users/yglukhov/Projects/falcon/res/compositions";
    exportButton.enabled = true;
    exportButton.onClick();
  }

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
