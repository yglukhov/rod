import nimx/assets/asset_manager
from   nimx/assets/abstract_asset_bundle import nil
import nimx / [ notification_center, abstract_window ]
import rod / asset_bundle

import logging
export asset_bundle

type AssetsLoader* = object
  assets: seq[AssetBundleDescriptor]

onRodAssetBundleDownloadingStart = proc(asset: string) =
  info "[AssetsLoader] Asset downloading started ", asset

onRodAssetBundleDownloadingEnd = proc(asset: string, error: string) =
  info "[AssetsLoader] Asset downloading ended ", asset, " with error ", error.len > 0

onRodAssetBundleDownloadingProgress = proc(asset: string, p: float) =
  info "[AssetsLoader] Asset downloading ", asset, " progress ", p

proc load*(a: var AssetsLoader, assets: openarray[AssetBundleDescriptor], onLoadProgress: proc(p: float) {.gcsafe.} = nil, onLoaded: proc() {.gcsafe.} ) =
  a.assets = @assets
  assert(a.assets.len > 0, "[AssetsLoader] nothing to load")
  assets.loadAssetBundles() do(mountPaths: openarray[string], abs: openarray[AssetBundle], err: string):
    if err.len != 0:
      sharedNotificationCenter().postNotification("SHOW_RESOURCE_LOADING_ALERT")
      return
    let am = sharedAssetManager()
    for i, mnt in mountPaths:
      info "[AssetsLoader] mounting ", mnt
      am.mount(mnt, abs[i])
    var newAbs = newSeqOfCap[abstract_asset_bundle.AssetBundle](abs.len)
    for ab in abs: newAbs.add(ab)
    am.loadAssetsInBundles(newAbs, onLoadProgress) do():
      # info am.dump()
      if not onLoaded.isNil:
        onLoaded()

proc free*(a: var AssetsLoader) =
  let am = sharedAssetManager()
  assert(a.assets.len > 0, "[AssetsLoader] nothing to unload")
  for ab in a.assets:
    info "[AssetsLoader] unmounting ", ab.path
    am.unmount(ab.path)
  a.assets.setLen(0)
  # info am.dump()
  requestGCFullCollect()
