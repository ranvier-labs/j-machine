import JMachineC

open JMachineC

private structure Options where
  inputs : Array String := #[]
  output : Option String := none
  listing : Option String := none
  nodes : Nat := 1
  meshX : Nat := 0
  meshY : Nat := 0
  meshZ : Nat := 0
  broadcastImage : Bool := false
  distributedCode : Bool := false

private def usage : String :=
  "usage: jmc INPUT.c [INPUT2.c ...] -o OUTPUT.image [--listing OUTPUT.lst] [--nodes N] [--mesh XxYxZ] [--broadcast-image|--distributed-code]\n"

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

private def parseArgs : List String → Except String Options
  | [] => throw usage
  | args =>
      let rec loop (remaining : List String) (options : Options) : Except String Options := do
        match remaining with
        | [] =>
            if options.inputs.isEmpty then throw usage
            if options.output.isNone then throw usage
            if options.broadcastImage && options.distributedCode then
              throw "--broadcast-image and --distributed-code are mutually exclusive"
            pure options
        | "-o" :: path :: tail => loop tail { options with output := some path }
        | "--listing" :: path :: tail => loop tail { options with listing := some path }
        | "--nodes" :: count :: tail =>
            loop tail { options with nodes := ← parseNat count "node count" }
        | "--mesh" :: topology :: tail =>
            let (x, y, z) ← parseMesh topology
            loop tail { options with meshX := x, meshY := y, meshZ := z }
        | "--broadcast-image" :: tail =>
            loop tail { options with broadcastImage := true }
        | "--distributed-code" :: tail =>
            loop tail { options with distributedCode := true }
        | "-h" :: _ => throw usage
        | "--help" :: _ => throw usage
        | argument :: tail =>
            if argument.startsWith "-" then throw s!"unknown option: {argument}\n{usage}"
            loop tail { options with inputs := options.inputs.push argument }
      loop args {}

def main (args : List String) : IO UInt32 := do
  let options ← match parseArgs args with
    | .ok parsed => pure parsed
    | .error message => IO.eprintln message; return 2
  let output := options.output.get!
  let mut sources := #[]
  for input in options.inputs do
    let source ← try IO.FS.readFile input catch error =>
      IO.eprintln s!"jmc: cannot read {input}: {error}"
      return 2
    sources := sources.push (source, input)
  let codePlacement :=
    if options.distributedCode then CodePlacement.distributedHome
    else CodePlacement.replicated
  match compileCSourcesWithOptions sources {
      nodeCount := options.nodes
      meshX := options.meshX
      meshY := options.meshY
      meshZ := options.meshZ
      codePlacement } with
  | .error error => IO.eprintln s!"jmc: {error}"; pure 1
  | .ok compilation =>
      try
        IO.FS.writeFile output <|
          if options.distributedCode then distributedCodeImageText compilation
          else if options.broadcastImage then broadcastImageText compilation
          else imageText compilation
        match options.listing with
        | some path => IO.FS.writeFile path compilation.listing
        | none => pure ()
        IO.println s!"compiled {options.inputs.size} translation unit(s): {compilation.words.size} image words, result at 0x{MDP.toHex 5 compilation.resultAddress}"
        pure 0
      catch error =>
        IO.eprintln s!"jmc: cannot write output: {error}"
        pure 2
