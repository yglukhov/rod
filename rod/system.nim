import nimx / [ class_registry ]
import rod / rod_types

export System

method init*(s: System) {.base.} = discard
method update*(s: System, dt: float) {.base.} = discard
method draw*(s: System) {.base.} = discard

template registerSystem*(T: typedesc) =
  registerClass(T)
