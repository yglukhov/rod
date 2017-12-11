import rod.editor.editor_inspector_view
import rod.editor.editor_tree_view
import rod.editor.animation_edit_view
import rod.editor.editor_scene_view
import rod.editor.editor_scene_settings
import rod.editor.editor_console

when not (defined(js) or defined(emscripten) or defined(android) or defined(ios)):
    import rod.editor.editor_assets_view
