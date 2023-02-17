import math, algorithm
import nimx/[ animation, matrixes, types ]
import variant

type
    AbstractAnimationSampler* = ref object of RootObj
        valueType*: TypeId

    AnimationSampler*[T] = ref object of AbstractAnimationSampler
        sampleImpl: proc(s: AnimationSampler[T], p: float): T {.gcsafe.}

    BufferAnimationSampler*[T, B] = ref object of AnimationSampler[T]
        values: B

    ArrayAnimationSampler*[T] = BufferAnimationSampler[T, seq[T]]

    KeyFrame*[T] = object
        p*: float
        v*: T
        tf*: proc(p:float):float {.gcsafe.}

    KeyFrameAnimationSampler*[T] = ref object of AnimationSampler[T]
        keys*: seq[KeyFrame[T]]

proc keyFrame*[T](p: float, v: T, tf: proc(p: float): float {.gcsafe.} = nil): KeyFrame[T] =
    KeyFrame[T](p: p, v: v, tf: tf)

proc newBufferAnimationSampler*[T, B](values: B, lerpBetweenFrames = true, originalLen: int = -1, cutFront: int = 0): BufferAnimationSampler[T, B] =
    result.new()
    result.values = values
    result.valueType = getTypeId(T)
    let r = cast[AnimationSampler[T]](result)

    if lerpBetweenFrames:
        if originalLen == -1:
            r.sampleImpl = proc(sampler: AnimationSampler[T], p: float): T {.gcsafe.} =
                let s = cast[BufferAnimationSampler[T, B]](sampler)
                let ln = s.values.len - 1
                let index = clamp(p * ln.float, 0.float, ln.float)
                let i = index.int
                if i == ln:
                    result = s.values[i]
                else:
                    let m = index mod 1.0
                    result = interpolate(s.values[i], s.values[i + 1], m)

        else:
            r.sampleImpl = proc(sampler: AnimationSampler[T], p: float): T {.gcsafe.} =
                let s = cast[BufferAnimationSampler[T, B]](sampler)
                let ln = originalLen - 1
                let index = clamp(p * ln.float, 0.float, ln.float)
                var i = clamp(index.int - cutFront, 0, s.values.len - 1)

                if i == s.values.len - 1:
                    result = s.values[i]
                elif index.int < cutFront:
                    result = s.values[0]
                else:
                    let m = index mod 1.0
                    result = interpolate(s.values[i], s.values[i + 1], m)
    else:
        if originalLen == -1:
            r.sampleImpl = proc(sampler: AnimationSampler[T], p: float): T {.gcsafe.} =
                let s = cast[BufferAnimationSampler[T, B]](sampler)
                let ln = s.values.len - 1
                let index = clamp(int(p * ln.float), 0, ln)
                result = s.values[index]
        else:
            r.sampleImpl = proc(sampler: AnimationSampler[T], p: float): T {.gcsafe.} =
                let s = cast[BufferAnimationSampler[T, B]](sampler)
                let ln = originalLen - 1
                let index = clamp(int(p * ln.float), 0, ln)
                var i = clamp(index.int - cutFront, 0, s.values.len - 1)
                result = s.values[i]

proc newArrayAnimationSampler*[T](values: seq[T], lerpBetweenFrames = true, originalLen: int = -1, cutFront: int = 0): ArrayAnimationSampler[T] =
    newBufferAnimationSampler[T, seq[T]](values, lerpBetweenFrames, originalLen, cutFront)

proc newKeyFrameAnimationSampler*[T](keys: seq[KeyFrame[T]]): KeyFrameAnimationSampler[T] =
    result.new()
    result.keys = keys
    result.valueType = getTypeId(T)

    let r = cast[AnimationSampler[T]](result)
    r.sampleImpl = proc(sampler: AnimationSampler[T], p: float): T {.gcsafe.} =
        let s = cast[KeyFrameAnimationSampler[T]](sampler)
        if s.keys.len == 0: return
        if p < 0:
            return s.keys[0].v
        elif p > 1:
            return s.keys[^1].v

        var k : KeyFrame[T]
        k.p = p
        let lb = lowerBound(s.keys, k) do(a, b: KeyFrame[T]) -> int:
            cmp(a.p, b.p)

        if lb == s.keys.len: return s.keys[^1].v

        var a, b : int
        if p < s.keys[lb].p:
            a = lb - 1
            b = lb
        elif p > s.keys[lb].p:
            a = lb
            b = lb + 1
        else:
            return s.keys[lb].v

        if a == -1 or b == -1: return s.keys[0].v

        let normalizedP = (p - s.keys[a].p) / (s.keys[b].p - s.keys[a].p)
        if not s.keys[a].tf.isNil:
            result = interpolate(s.keys[a].v, s.keys[b].v, s.keys[a].tf(normalizedP))
        else:
            result = interpolate(s.keys[a].v, s.keys[b].v, normalizedP)

{.push stackTrace: off, noInit.}
proc sample*[TSampler](a: TSampler, p: float): auto {.inline.} = a.sampleImpl(a, float(p))
{.pop.}

when isMainModule:
    proc `==~`(a, b: float): bool =
        abs(a - b) < 0.001

    block: # Test array sampler with lerp
        let s = newArrayAnimationSampler(@[1.0, 3.0, 5.0])
        doAssert(s.sample(-0.5) ==~ 1.0)
        doAssert(s.sample(0) ==~ 1.0)
        doAssert(s.sample(0.25) ==~ 2.0) # Lerp here
        doAssert(s.sample(0.5) ==~ 3.0)
        doAssert(s.sample(0.75) ==~ 4.0) # Lerp here
        doAssert(s.sample(1) ==~ 5.0)
        doAssert(s.sample(1.5) ==~ 5.0)

    block: # Test array sampler without lerp
        let s = newArrayAnimationSampler(@[1.0, 3.0, 5.0], false)
        doAssert(s.sample(-0.5) ==~ 1.0)
        doAssert(s.sample(0) ==~ 1.0)
        doAssert(s.sample(0.25) ==~ 1.0) # No lerp here
        doAssert(s.sample(0.5) ==~ 3.0)
        doAssert(s.sample(0.75) ==~ 3.0) # No lerp here
        doAssert(s.sample(1) ==~ 5.0)
        doAssert(s.sample(1.5) ==~ 5.0)

    block: # Test keyframe sampler (lerp)
        let s = newKeyFrameAnimationSampler(@[keyFrame(0.0, 1.0), keyFrame(0.5, 2.0), keyFrame(1.0, 4.0)])
        doAssert(s.sample(-0.5) ==~ 1.0)
        doAssert(s.sample(0) ==~ 1.0)
        doAssert(s.sample(0.25) ==~ 1.5) # Lerp here
        doAssert(s.sample(0.5) ==~ 2.0)
        doAssert(s.sample(0.75) ==~ 3.0) # Lerp here
        doAssert(s.sample(1) ==~ 4.0)
        doAssert(s.sample(1.5) ==~ 4.0)
