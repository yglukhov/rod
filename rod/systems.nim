import nimx / [ class_registry ]
import rod / rod_types
import tables

export System

method init*(s: System) {.base.} = discard
method update*(s: System, dt: float) {.base.} = discard
method draw*(s: System) {.base.} = discard

proc createSystem*(name: string): System =
  if isClassRegistered(name) == false:
    raise newException(Exception, "System " & name & " is not registered")

  result = newObjectOfClass(name).System
  result.init()

proc createSystem*(T: typedesc): System =
  result = createSystem($T)

template registerSystem*(T: typedesc) =
  registerClass(T)
