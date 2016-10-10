import securehash, os, osproc, algorithm, strutils, times, hashes

# When asset packing algorithm changes, we should increase `hashVersion`
# to invalidate old caches.
const hashVersion = 1

const useExperimentalOptimization = false

proc dirHash*(path: string, profile: string = ""): string =
    var hasSound = false

    when useExperimentalOptimization:
        # Use git
        var lsFilesArgs = ["ls-files", "-o", "--exclude-standard", path]
        let untracked = execProcess("git", lsFilesArgs, options = {poUsePath})
        var gitStageArgs = @["add"]
        for i in untracked.splitLines():
            gitStageArgs.add(i)
        if gitStageArgs.len > 1:
            discard execProcess("git", gitStageArgs, options = {poUsePath})
        lsFilesArgs[1] = "-smd"
        var all = execProcess("git", lsFilesArgs, options = {poUsePath})
        if gitStageArgs.len > 1:
            gitStageArgs[0] = "reset"
            discard execProcess("git", gitStageArgs, options = {poUsePath})
        for ln in splitLines(all):
            if ln.endsWith(".wav"):
                hasSound = true
                break
        if hasSound:
            all &= profile
        result = ($secureHash(all)).toLowerAscii()
    else:
        var allFiles = newSeq[string]()
        for f in walkDirRec(path):
            let sf = f.splitFile()
            if not sf.name.startsWith('.'):
                if sf.ext == ".wav":
                    hasSound = true
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
            hashStr &= profile
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
