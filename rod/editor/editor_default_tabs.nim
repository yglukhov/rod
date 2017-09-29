import rod.inspector_view
import rod.editor.editor_tree_view
import rod.editor.animation_edit_view

when not (defined(js) or defined(emscripten)):
    import rod.editor.editor_assets_view
