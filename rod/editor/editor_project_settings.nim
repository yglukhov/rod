import json
import preferences
import nimx.matrixes
import nimx.types
import rod.utils.json_serializer
import rod.utils.json_deserializer
import rod.utils.serialization_codegen
import rod.utils.property_desc

type
    EditorTabSettings* = tuple
        name: string
        frame: Rect

    EditorProject* = tuple
        name: string
        path: string
        tabs: seq[EditorTabSettings]
        composition: string

    EditorSettings* = tuple
        projects: seq[EditorProject]
        lastProject: string

    EditorSettingsObj* = ref object

EditorTabSettings.properties:
    name
    frame

EditorProject.properties:
    name
    path
    tabs
    composition

EditorSettings.properties:
    projects
    lastProject


genJsonSerializationrFor(EditorTabSettings)
genJsonSerializationrFor(EditorProject)
genJsonSerializationrFor(EditorSettings)

proc getEditorSettings*(): EditorSettings=
    if "settings" in sharedPreferences():
        var jn = sharedPreferences()["settings"]
        result = jn.toEditorSettings()
    # echo "Load editor settings: ", result

proc save*(es: EditorSettings)=
    sharedPreferences()["settings"] = es.toJson()
    syncPreferences()

proc saveProject*(proj: EditorProject)=
    var es = getEditorSettings()
    if es.projects.len == 0:
        es.projects.add(proj)
    else:
        var index = 0
        var projIndex = -1
        while index < es.projects.len:
            var p = es.projects[index]
            if p.path == proj.path:
                projIndex = index
                break
            inc index

        if projIndex < 0:
            es.projects.add(proj)
        else:
            es.projects[projIndex] = proj

    es.lastProject = proj.path
    es.save()

proc hasProjectAtPath*(p: string): bool =
    var settings = getEditorSettings()
    for proj in settings.projects:
        if proj.path == p:
            return true

proc getProjectAtPath*(p: string):EditorProject =
    var settings = getEditorSettings()
    for proj in settings.projects:
        if proj.path == p:
            return proj
