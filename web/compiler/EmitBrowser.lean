import Lean
import Lean.Compiler.Backend.EmitWasm

-- The compiler's lexer and code generator use tail-recursive traversals.
-- Browser-sized stacks require the backend's tail-call emission mode.
unsafe def main (args : List String) : IO UInt32 := do
  let [source, output] := args
    | throw <| IO.userError "usage: EmitBrowser.lean SOURCE.lean OUTPUT.wasm"
  Lean.initSearchPath (← Lean.findSysroot)
  Lean.enableInitializersExecution
  let some env ← Lean.Elab.runFrontend (← IO.FS.readFile source)
    (Lean.Compiler.compiler.postponeCompile.set {} false) source `WebCompiler
    | return 1
  let bytes ← IO.ofExcept <| Lean.Compiler.Backend.EmitWasm.emitWasmWithConfig
    { wholeProgram := true, emitTailCalls := true } env `WebCompiler
  IO.FS.writeBinFile output bytes
  return 0
