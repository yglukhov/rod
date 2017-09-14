
proc arrayElementType[T](a: typedesc[openarray[T]]): T = discard

proc isPODType*(T: typedesc): bool {.compileTime.} =
    when T is float32 | int16 | int8 | int32:
        return true
    elif T is array:
        var dummy: T
        return isPODType(type(dummy[0]))
    elif T is openarray:
        return isPODType(type(arrayElementType(T)))
    elif T is tuple:
        var v: T
        for k, vv in fieldPairs(v):
            if not isPODType(type(vv)): return false 
        return true
    else:
        return false

var a : tuple[a: int32, b: float32]
when isPODType(type(a)):
    discard
else:
    {.error: "no POD".}


template alignsize*(t: typedesc): int =
    if sizeof(t) > 4:
        4
    else:
        sizeof(t)

# const testa:tuple[a: int32, b: float32]

# static:
#     doAssert(isPODType(int32))
#     doAssert(isPODType(testa))
#     doAssert(not isPODType(tuple[a: int32, b: string]))
