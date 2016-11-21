import securehash, os, osproc, algorithm, strutils, times, hashes

import settings

# When asset packing algorithm changes, we should increase `hashVersion`
# to invalidate old caches.
const hashVersion = 2

const audioFileExtensions = [".wav", ".ogg", "mp3"]

proc isAudio(path: string): bool {.inline.} =
    for e in audioFileExtensions:
        if path.endsWith(e): return true

proc isGraphics(path: string): bool {.inline.} = path.endsWith(".png")

proc dirHash*(path: string, s: Settings): string =
    var hasSound = false
    var hasGraphics = false

    var allFiles = newSeq[string]()
    for f in walkDirRec(path):
        let sf = f.splitFile()
        if not sf.name.startsWith('.'):
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

    hashStr &= $hashVersion

    result = ($secureHash(hashStr)).toLowerAscii()

proc copyResourcesFromCache*(cache, cacheHash, dst: string) =
    let hashFile = dst / ".hash"
    if fileExists(hashFile) and readFile(hashFile) == cacheHash: return
    removeDir(dst)
    createDir(dst)
    copyDir(cache, dst)
    writeFile(hashFile, cacheHash)

proc getCache*(cacheOverride: string = nil): string =
    if cacheOverride.len > 0: return expandTilde(cacheOverride)
    result = getEnv("ROD_ASSET_CACHE")
    if result.len > 0: return
    result = getTempDir() / "rod_asset_cache"
