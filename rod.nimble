# Package
version       = "0.1.0"
author        = "Anonymous"
description   = "Graphics engine"
license       = "MIT"

bin           = @["rod/tools/rodasset/rodasset", "editor/rodedit"]
installExt    = @["nim"]

# Dependencies
requires "nimx"
requires "https://github.com/SSPKrolik/nimasset#head"
requires "variant"
requires "os_files"
requires "https://github.com/yglukhov/imgtools"
requires "cligen"
requires "untar#head"
requires "tempfile"
requires "https://github.com/yglukhov/threadpools"
requires "https://github.com/yglukhov/preferences"
requires "sha1"
