import sha1, os, osproc, algorithm, strutils, times, hashes
import rod/utils/serialization_hash_calculator
import nimx/class_registry
import rod/component

import settings

# When asset packing algorithm changes, we should increase `hashVersion`
# to invalidate old caches.
const hashVersion = 13

const audioFileExtensions = [".wav", ".ogg", ".mp3"]

const max_copy_attempts = 5

proc isAudio(path: string): bool {.inline.} =
    for e in audioFileExtensions:
        if path.endsWith(e): return true

proc isGraphics(path: string): bool {.inline.} = path.endsWith(".png")

proc gitDirHash(path: string): string =
    let (outp, errC) = execCmdEx("git ls-tree -d HEAD " & path)
    if errC == 0:
        let comps = outp.split()
        if comps.len > 3:
            return comps[2]

proc isHiddenFile(path: string): bool =
    let slash = path.rfind({'/', '\\'})
    if slash != -1:
        result = path[slash + 1] == '.'

proc gitStatus(statusLine: string, status: char): bool {.inline.} =
    statusLine[0] == status or statusLine[1] == status

proc getFileNameFromMovedGitStatusLine(statusLine: string): string {.inline.} =
    const separator = " -> "
    let idx = statusLine.rfind(separator)
    result = statusLine[idx + separator.len .. ^1]

proc componentsHash(): Hash =
    var componentNames = newSeq[string]()
    for c in registeredSubclassesOfType(Component):
        componentNames.add(c)

    componentNames.sort() do(a, b: string) -> int:
        cmp(a, b)

    var calc = newSerializationHashCalculator()
    for n in componentNames:
        let c = newObjectOfClass(n).Component
        c.serializationHash(calc)

    result = calc.hash

proc dirHashImplGit(path, baseHash: string, s: Settings): string {.inline.} =
    result = newStringOfCap(2048)
    result &= baseHash
    result &= ';'

    let (outp, errC) = execCmdEx("git status -s " & path)
    if errC != 0:
        raise newException(Exception, "git status returned " & $errC)

    for ln in outp.splitLines:
        if ln.len == 0: continue
        var f = ln[3 .. ^1]
        if f.isHiddenFile(): continue

        result &= f
        result &= ';'

        if not ln.gitStatus('D'):
            if ln.gitStatus('R'):
                f = getFileNameFromMovedGitStatusLine(ln)

            if dirExists(f):
                for path in walkDirRec(f):
                    result &= $getLastModificationTime(path)
                    result &= ';'
                    result &= path
                    result &= ';'
            else:
                result &= $getLastModificationTime(f)
                result &= ';'

    var hasSound = false
    var hasGraphics = false
    for f in walkDirRec(path):
        if not f.isHiddenFile():
            if not hasSound and f.isAudio():
                hasSound = true
                if hasGraphics: break
            elif not hasGraphics and f.isGraphics():
                hasGraphics = true
                if hasSound: break

    if hasSound:
        result &= $hash(s.audio)
        result &= ';'

    if hasGraphics:
        result &= $hash(s.graphics)
        result &= ';'

    result &= ";" & $hashVersion & ";" & $componentsHash()

    result = sha1.compute(result).toHex()

proc dirHashImplNoGit(path: string, s: Settings): string =
    var hasSound = false
    var hasGraphics = false

    var allFiles = newSeq[string]()
    for f in walkDirRec(path):
        if not f.isHiddenFile():
            if not hasSound and f.isAudio():
                hasSound = true
            elif not hasGraphics and f.isGraphics():
                hasGraphics = true
            allFiles.add(f)

    allFiles.sort(system.cmp[string])

    var hashStr = ""
    for f in allFiles:
        if path.len > 0:
            hashStr &= f.substr(path.len + 1) & ":"
        else:
            hashStr &= f & ":"
        hashStr &= $hash(readFile(f)) & ";"
    if hasSound:
        hashStr &= $hash(s.audio) & ";"
    if hasGraphics:
        hashStr &= $hash(s.graphics) & ";"

    hashStr &= $hashVersion & $componentsHash()

    result = sha1.compute(hashStr).toHex()

proc dirHash*(path: string, s: Settings): string {.inline.} =
#    let startTime = epochTime()

    let gdh = gitDirHash(path)
    if unlikely gdh.len == 0:
        result = dirHashImplNoGit(path, s)
    else:
        result = dirHashImplGit(path, gdh, s)

#    let endTime = epochTime()
    # if gdh.isNil:
    #     echo "Calculated hash without git help"
    # echo "Calculated hash for: ", endTime - startTime

proc copyResourcesFromCache*(cache, cacheHash, dst: string) =
    let hashFile = dst / ".hash"
    if fileExists(hashFile) and readFile(hashFile) == cacheHash: return
    removeDir(dst)
    let tmp = dst & ".tmp"
    removeDir(tmp)
    createDir(tmp)
    copyDir(cache, tmp)
    writeFile(tmp / ".hash", cacheHash)

    var attemptCounter = 0
    var fileMoved = false
    while(not fileMoved):
        try:
            moveFile(tmp, dst)
            fileMoved = true
        except:
            # On Windows file could be inaccessible some time for some reasons,
            # So we try few times and raise exeption after that.
            if attemptCounter < max_copy_attempts:
                attemptCounter += 1
                sleep(1000)
            else:
                raise newException(Exception, "Couldn't rename $# to $#. Message:\n $#".format(tmp, dst, getCurrentExceptionMsg()))

proc getCache*(cacheOverride: string = ""): string =
    if cacheOverride.len > 0: return expandTilde(cacheOverride)
    result = getEnv("ROD_ASSET_CACHE")
    if result.len > 0: return
    result = getTempDir() / "rod_asset_cache"
