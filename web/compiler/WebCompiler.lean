module

import all Init
import all Init.Data.Array.Basic
import all Init.Data.List.ToArrayImpl
import all Init.Data.String.Basic
import all Init.Data.String.Defs
import all Init.Data.String.Search
import all JMachineC.AST
import all JMachineC.Lexer
import all JMachineC.MDP
import all JMachineC.Parser
import all JMachineC.Codegen

open JMachineC

@[extern "jmc_source_string", never_extract]
opaque sourceString : UInt32 -> String

@[extern "jmc_mesh_string", never_extract]
opaque meshString : UInt32 -> String

@[extern "jmc_store_output", never_extract]
opaque storeOutput : UInt32 -> UInt32 -> @& String -> UInt32

@[extern "jmc_append_output", never_extract]
opaque appendOutput : UInt32 -> @& String -> UInt32

@[extern "jmc_emit_word", never_extract]
opaque emitWord : UInt32 -> UInt32 -> UInt32 -> UInt32 -> UInt32 -> @& String -> UInt32

private def fail (message : String) : UInt32 :=
  storeOutput 0 1 message

private def runtimeRoots (values : List UInt32) : List UInt32 :=
  Array.toListImpl (List.toArrayImpl values)

private def parseNat (text description : String) : Except String Nat :=
  match text.toNat? with
  | some value => pure value
  | none => throw s!"invalid {description}: {text}"

private def parseMesh (text : String) : Except String (Nat × Nat × Nat) := do
  match text.splitOn "x" with
  | [x, y, z] =>
      pure (
        ← parseNat x "mesh X dimension",
        ← parseNat y "mesh Y dimension",
        ← parseNat z "mesh Z dimension")
  | _ => throw s!"invalid mesh topology (expected XxYxZ): {text}"

-- Stream large replicated images through the C++ bridge to avoid constructing
-- and joining a million individual Lean strings for the 512-node variant.
private partial def emitImageWords (world : UInt32) (words : Array ImageWord)
    (broadcast : Bool) (stop i : Nat) : UInt32 :=
  if i < stop then
    let word := words[i]!
    let node := if broadcast then 0xffffffff else word.node.toUInt32
    let world := emitWord world node word.address.toUInt32
      word.value.toUInt32 (word.value / 0x100000000).toUInt32 word.annotation
    emitImageWords world words broadcast stop (i + 1)
  else
    world

private partial def emitImage (world : UInt32) (words : Array ImageWord)
    (broadcast : Bool) (i : Nat) : UInt32 :=
  if i < words.size then
    let stop := min (i + 1024) words.size
    emitImage (emitImageWords world words broadcast stop i) words broadcast stop
  else
    world

private def storeImage (compilation : Compilation) : UInt32 :=
  let world := storeOutput 0 0 ""
  let world := appendOutput world "# NODE  ADDRESS  36-BIT-WORD\n"
  let world := emitImage world compilation.broadcastWords true 0
  emitImage world compilation.nodeSpecificWords false 0

@[export jmc_compile, noinline]
def compileForBrowser (sourceLength nodeCount meshLength : UInt32) : UInt32 :=
  if nodeCount == 0 then
    fail "the browser compiler requires at least one node"
  else
    let topology :=
      if meshLength == 0 then
        pure (0, 0, 0)
      else
        parseMesh (meshString meshLength)
    match topology with
    | .error message => fail message
    | .ok (meshX, meshY, meshZ) =>
      let source := sourceString sourceLength
      match compileCWithOptions source "<browser>" {
          nodeCount := nodeCount.toNat
          meshX := meshX
          meshY := meshY
          meshZ := meshZ
          sourceMap := true } with
      | .error error => fail s!"{error}"
      | .ok compilation => storeImage compilation
