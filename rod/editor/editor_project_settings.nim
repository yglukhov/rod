import nimx/[matrixes, types]
import rod / rod_types
import json, os, logging, options

type
  EditorTabSettings* = object
    name*: string
    frame*: Rect

  EditorSettings* = object
    AutosaveInterval: Option[float]
    EditorCameras: Option[seq[EditorCameraSettings]]

  EditorCameraSettings* = object
    name*: string
    viewportSize*: Size
    projectionMode*: CameraProjection

  EditorProject* = object
    name*: string
    path*: string
    tabs*: seq[EditorTabSettings]
    composition*: string
    settings*: EditorSettings

const SettingsFileName = "settings.json"

let UserSettingsPath = getHomeDir() & "/.rodedit/" & SettingsFileName
let ProjSettingsPath = getAppDir() & "/.rodedit/" & SettingsFileName

template settingsFiles(): seq[string] =
  @[UserSettingsPath, ProjSettingsPath]

proc merge(a, b: JsonNode): JsonNode =
  if a.isNil and b.isNil: return
  if a.isNil:
    result = parseJson($b)
  else:
    if b.kind == a.kind and b.kind == JObject:
      result = parseJson($a)
      for k, v in b:
        if k notin a:
          result[k] = v
        else:
          result[k] = merge(a[k], b[k])
    else:
      result = parseJson($b)

proc getEditorSettingsJson(): JsonNode =
  var jsettings: JsonNode
  try:
    for sf in settingsFiles:
      info "getEditorSettingsJson: ", sf
      if fileExists(sf):
        jsettings = merge(jsettings, parseFile(sf))
  except Exception as e:
    warn "Can't parse editor settings! ", e.msg, "\n", e.getStackTrace()
  result = jsettings

proc loadEditorSettings*(proj: var EditorProject) =
  let jsettings = getEditorSettingsJson()
  if not jsettings.isNil:
      proj.settings = jsettings.to(EditorSettings)
  echo "loadEditorSettings ", if jsettings.isNil: "nil" else: $jsettings

proc autosaveInterval*(p: EditorProject): float =
  result = 120.0
  if p.settings.AutosaveInterval.isSome:
    result = p.settings.AutosaveInterval.get()

proc editorCameras*(p: EditorProject): seq[EditorCameraSettings] =
  result = @[
    EditorCameraSettings(name: "[EditorCamera2D]", viewportSize: newSize(1920, 1080), projectionMode: cpOrtho),
    EditorCameraSettings(name: "[EditorCamera3D]", viewportSize: newSize(1920, 1080), projectionMode: cpPerspective)
  ]
  if not p.settings.EditorCameras.isSome: return
  var r = p.settings.EditorCameras.get()
  if r.len == 0: return
  result = r
