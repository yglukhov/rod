import std / [ os, streams ]
import nimx / [image]
import nimx/assets/asset_loading
import imgtools / imgtools

when not defined(android) and not defined(ios) and not defined(emscripten):
  import os_files/file_info

proc loadIconForPath*(path: string, size: int, cb: proc(i: Image){.gcsafe.}) {.gcsafe.} =
  let img_data = iconBitmapForFile(path, 128, 128)
  if img_data.len > 0:
    cb(imageWithBitmap(cast[ptr uint8](addr img_data[0]), 128, 128, 4))

proc loadImagePreview*(path: string, size: int, cb: proc(i: Image){.gcsafe.}) {.gcsafe.} =
  loadAsset[Image]("file://" & path) do(i: Image, err: string):
    cb(i)
