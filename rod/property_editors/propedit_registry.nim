import nimx.view
import nimx.property_editors.propedit_registry as npr

export npr

import rod.node
import variant

proc propertyEditorForProperty*(n: Node, title: string, v: Variant, onChangeCallback, changeInspectorCallback: proc()): View =
    propertyEditorForProperty(newVariant(n), title, v, onChangeCallback, changeInspectorCallback)
