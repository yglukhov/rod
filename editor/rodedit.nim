# This is a wrapper to rodedit_main. It compiles rodedit_main with rod
# plugins of the project that calls the wrapper.
import ../rod/tools/tool_wrapper
runEditorWrapper("rodedit", "editor/rodedit_main.nim")
