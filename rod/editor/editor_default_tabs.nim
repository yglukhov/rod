import rod/editor/[editor_inspector_view, editor_tree_view,
    animation/editor_animation_view, scene/editor_scene_view, scene/editor_scene_settings,
    editor_console
]

when not (defined(js) or defined(emscripten) or defined(android) or defined(ios)):
    import rod/editor/editor_assets_view
