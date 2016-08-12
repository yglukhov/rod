import tables, dom, math
import after_effects
import times
import json
import algorithm
import strutils
import nimx.matrixes, nimx.pathutils
import rod.quaternion

type File = after_effects.File

var logTextField: EditText

proc logi(args: varargs[string, `$`]) =
    var text = $logTextField.text
    for i in args:
        text &= i
    text &= "\n"
    logTextField.text = text

proc exportSelectedCompositions(exportFolderPath: cstring) {.exportc.} =
    let comp = app.project.activeItem(Composition)
    let layers = comp.selectedLayers
    for layer in layers:
        if not layer.nullLayer:
            logi "Converting layer: ", layer.name
            let newLayer = comp.layers.addNull()
            newLayer.name = layer.name
            newLayer.property("Position", Vector3).setValue(layer.property("Position", Vector3).value)
            layer.remove()

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
