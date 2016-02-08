import nimx.types
import nimx.context
import nimx.composition
import nimx.portable_gl

import rod.node

import rod.component

type ClippingRectComponent* = ref object of Component
    clippingRect*: Rect

method draw*(o: ClippingRectComponent) =
    let c = currentContext()
    c.withClippingRect o.clippingRect:
        for c in o.node.children: c.recursiveDraw()

method isPosteffectComponent*(c: ClippingRectComponent): bool = true

registerComponent[ClippingRectComponent]()
