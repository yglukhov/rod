import nimx / [ event ]
import rod / [ rod_types ]

#will be called for all components
method onDrawGizmo*(c: Component) {.base.} = discard

#will be called only for components on selected node
method onKeyDown*(c: Component, e: Event): bool {.base.} = discard
method onKeyUp*(c: Component, e: Event): bool {.base.} = discard
method onTouchDown*(c: Component, e: Event): bool {.base.} = discard
method onTouchMove*(c: Component, e: Event): bool {.base.} = discard
method onTouchUp*(c: Component, e: Event): bool {.base.} = discard
