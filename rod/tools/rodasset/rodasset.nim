# This is a wrapper to rodasset_main. It compiles rodasset_main with rod
# plugins of the project that calls the wrapper.
import ../tool_wrapper
runWrapper("rodasset", "rod/tools/rodasset/rodasset_main.nim")
