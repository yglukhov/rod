import securehash, os, algorithm, strutils

proc dirHash*(path: string, profile: string = ""): string =
    var allFiles = newSeq[string]()
    for f in walkDirRec(path):
        let sf = f.splitFile()
        if not sf.name.startsWith('.'):
            if sf.ext == ".wav":
                allFiles.add(f & "." & profile)
            else:
                allFiles.add(f)
    allFiles.sort(system.cmp[string])
    var hashStr = allFiles.join(":")
    for f in allFiles:
        hashStr &= $secureHash(f)
    result = ($secureHash(hashStr)).toLowerAscii()

proc copyResourcesFromCache*(cache, cacheHash, dst: string) =
    if dirExists(dst) and dirHash(dst) == cacheHash: return
    removeDir(dst)
    createDir(dst)
    copyDir(cache, dst)

proc getCache*(cacheOverride: string = nil): string =
    if cacheOverride.len > 0: return expandTilde(cacheOverride)
    result = getEnv("ROD_ASSET_CACHE")
    if result.len > 0: return
    result = getTempDir() / "rod_asset_cache"

