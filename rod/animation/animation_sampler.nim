import math, algorithm
import nimx.animation
import variant

type
    AbstractAnimationSampler* = ref object of RootObj
        valueType*: TypeId

    AnimationSampler*[T] = ref object of AbstractAnimationSampler
        sampleImpl: proc(s: AnimationSampler[T], p: float): T

    BufferAnimationSampler*[T, B] = ref object of AnimationSampler[T]
        values: B

    ArrayAnimationSampler*[T] = BufferAnimationSampler[T, seq[T]]

    LinearKeyFrame*[T] = tuple[p: float, v: T]
    BezierKeyFrame*[T] = tuple[p: float, inX, inY, outX, outY: float, v: T]

    LinearKeyFrameAnimationSampler*[T] = ref object of AnimationSampler[T]
        keys*: seq[LinearKeyFrame[T]]

    BezierKeyFrameAnimationSampler*[T] = ref object of AnimationSampler[T]
        keys*: seq[BezierKeyFrame[T]]

proc newBufferAnimationSampler*[T, B](values: B, lerpBetweenFrames = true, originalLen: int = -1, cutFront: int = 0): BufferAnimationSampler[T, B] =
    result.new()
    result.values = values
    result.valueType = getTypeId(T)
    let r = cast[AnimationSampler[T]](result)

    if lerpBetweenFrames:
        if originalLen == -1:
            r.sampleImpl = proc(sampler: AnimationSampler[T], p: float): T =
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
            r.sampleImpl = proc(sampler: AnimationSampler[T], p: float): T =
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
            r.sampleImpl = proc(sampler: AnimationSampler[T], p: float): T =
                let s = cast[BufferAnimationSampler[T, B]](sampler)
                let ln = s.values.len - 1
                let index = clamp(int(p * ln.float), 0, ln)
                result = s.values[index]
        else:
            r.sampleImpl = proc(sampler: AnimationSampler[T], p: float): T =
                let s = cast[BufferAnimationSampler[T, B]](sampler)
                let ln = originalLen - 1
                let index = clamp(int(p * ln.float), 0, ln)
                var i = clamp(index.int - cutFront, 0, s.values.len - 1)
                result = s.values[i]

proc newArrayAnimationSampler*[T](values: seq[T], lerpBetweenFrames = true, originalLen: int = -1, cutFront: int = 0): ArrayAnimationSampler[T] =
    newBufferAnimationSampler[T, seq[T]](values, lerpBetweenFrames, originalLen, cutFront)

proc newLinearKeyFrameAnimationSampler*[T](keys: seq[LinearKeyFrame[T]]): LinearKeyFrameAnimationSampler[T] =
    result.new()
    result.keys = keys
    result.valueType = getTypeId(T)

    let r = cast[AnimationSampler[T]](result)
    r.sampleImpl = proc(sampler: AnimationSampler[T], p: float): T =
        let s = cast[LinearKeyFrameAnimationSampler[T]](sampler)
        if p < 0:
            return s.keys[0].v
        elif p > 1:
            return s.keys[^1].v

        var k : LinearKeyFrame[T]
        k.p = p
        let lb = lowerBound(s.keys, k) do(a, b: LinearKeyFrame[T]) -> int:
            cmp(a.p, b.p)

        var a, b : int
        if p < s.keys[lb].p:
            a = lb - 1
            b = lb
        elif p > s.keys[lb].p:
            a = lb
            b = lb + 1
        else:
            return s.keys[lb].v

        let normalizedP = (p - s.keys[a].p) / (s.keys[b].p - s.keys[a].p)
        result = interpolate(s.keys[a].v, s.keys[b].v, normalizedP)

proc newBezierKeyFrameAnimationSampler*[T](keys: seq[BezierKeyFrame[T]]): BezierKeyFrameAnimationSampler[T] =
    result.new()
    result.keys = keys
    result.valueType = getTypeId(T)

    let r = cast[AnimationSampler[T]](result)
    r.sampleImpl = proc(sampler: AnimationSampler[T], p: float): T =
        let s = cast[BezierKeyFrameAnimationSampler[T]](sampler)
        if p < 0:
            return s.keys[0].v
        elif p > 1:
            return s.keys[^1].v

        var k : BezierKeyFrame[T]
        k.p = p
        let lb = lowerBound(s.keys, k) do(a, b: BezierKeyFrame[T]) -> int:
            cmp(a.p, b.p)

        if lb >= s.keys.len: return s.keys[^1].v

        var a, b : int
        if p < s.keys[lb].p:
            if lb == 0: return s.keys[0].v
            a = lb - 1
            b = lb
        elif p > s.keys[lb].p:
            a = lb
            b = lb + 1
        else:
            return s.keys[lb].v

        let temporalLength = s.keys[b].p - s.keys[a].p
        let normalizedP = (p - s.keys[a].p) / temporalLength

        #let spacialLength = abs(s.keys[b].v - s.keys[a].v)
        # let spacialLength = 300.Coord


        # echo "a: ", s.keys[a].v
        # echo "b: ", s.keys[b].v
        # echo "len: ", spacialLength
        # echo "1: ", s.keys[a].outTangent.x / temporalLength, ", ", s.keys[a].outTangent.y / spacialLength
        # echo "2: ", -s.keys[b].inTangent.x / temporalLength, ", ", s.keys[b].inTangent.y / spacialLength
        # echo "p: ", normalizedP
        # let resp = bezierXForProgress(s.keys[a].outX / temporalLength,
        #                     s.keys[a].outY / spacialLength,
        #                     -s.keys[b].inX / temporalLength,
        #                     s.keys[b].inY / spacialLength,
        #                     normalizedP)
        # result = s.keys[a].v + resp * spacialLength
        # echo "result: ", result
        result = interpolate(s.keys[a].v, s.keys[b].v, normalizedP)




        # let s = cast[BezierKeyFrameAnimationSampler[T]](sampler)
        # if p < 0:
        #     return s.keys[0].v
        # elif p > 1:
        #     return s.keys[^1].v

        # var k : BezierKeyFrame[T]
        # k.p = p
        # let lb = lowerBound(s.keys, k) do(a, b: BezierKeyFrame[T]) -> int:
        #     cmp(a.p, b.p)

        # var a, b : int
        # if p < s.keys[lb].p:
        #     a = lb - 1
        #     b = lb
        # elif p > s.keys[lb].p:
        #     a = lb
        #     b = lb + 1
        # else:
        #     return s.keys[lb].v

        # let normalizedP = (p - s.keys[a].p) / (s.keys[b].p - s.keys[a].p)
        # result = interpolate(s.keys[a].v, s.keys[b].v, normalizedP)

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
        let s = newLinearKeyFrameAnimationSampler(@[(0.0, 1.0), (0.5, 2.0), (1.0, 4.0)])
        doAssert(s.sample(-0.5) ==~ 1.0)
        doAssert(s.sample(0) ==~ 1.0)
        doAssert(s.sample(0.25) ==~ 1.5) # Lerp here
        doAssert(s.sample(0.5) ==~ 2.0)
        doAssert(s.sample(0.75) ==~ 3.0) # Lerp here
        doAssert(s.sample(1) ==~ 4.0)
        doAssert(s.sample(1.5) ==~ 4.0)
