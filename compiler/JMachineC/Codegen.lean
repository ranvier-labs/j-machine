module

public import JMachineC.MDP
public import JMachineC.Parser

public section

namespace JMachineC
open MDP

inductive CodePlacement where
  | replicated
  | distributedHome
deriving Repr, BEq, Inhabited

structure CompilerOptions where
  nodeCount : Nat := 1
  meshX : Nat := 0
  meshY : Nat := 0
  meshZ : Nat := 0
  codePlacement : CodePlacement := .replicated
deriving Repr, Inhabited

structure ImageWord where
  node : Nat := 0
  address : Nat
  value : Word
  annotation : String := ""
deriving Repr, Inhabited

structure Compilation where
  words : Array ImageWord
  broadcastWords : Array ImageWord := #[]
  nodeSpecificWords : Array ImageWord := #[]
  applicationStart : Nat := 0
  applicationEnd : Nat := 0
  symbols : List (String × Nat)
  listing : String
  resultAddress : Nat := 0x300
deriving Repr, Inhabited

private def codeBase : Nat := 0x1000
private def resultBase : Nat := 0x300
private def globalBase : Nat := 0x800
private def stackBase : Nat := 0x4000
private def heapPointerAddress : Nat := 0x700
private def nodeIdentityAddress : Nat := 0x701
private def processFreeHeadAddress : Nat := 0x702
private def bulkFreeHeadAddress : Nat := 0x703
private def codeCacheReadyAddress : Nat := 0x704
private def codeRequestCountAddress : Nat := 0x705
private def codeInstallCountAddress : Nat := 0x706
private def codeAckCountAddress : Nat := 0x707
private def futureFaultCountAddress : Nat := 0x708
private def sendFaultCountAddress : Nat := 0x709
private def aggregateSetBaseAddress : Nat := 0x70a
private def aggregateSetCountAddress : Nat := 0x70b
private def aggregateSetIndexAddress : Nat := 0x70c
private def mdcArgumentErrorAddress : Nat := 0x70d
private def sendRetryBackgroundBase : Nat := 0x720
private def sendRetryPriority0Base : Nat := 0x740
private def sendRetryPriority1Base : Nat := 0x760
private def heapBase : Nat := 0x10000
private def queue0Base : Nat := 0x20000
private def queue1Base : Nat := 0x21000
private def queueMask : Nat := 0x3ff
private def runtimeFrameSize : Nat := 64
private def processStackWords : Nat := 512
private def bulkBlockWords : Nat := 1024
private def codeCacheBase : Nat := 0x30000
-- QHL exposes ten occupancy bits.  The largest aligned message it can
-- distinguish from empty is therefore 1020 words, not 1024.  Four words are
-- the MSG header plus cache offset, payload length, and final-chunk flag.
private def codeChunkWords : Nat := 1016
private def spawnHandlerLabel : String := "__mdc_spawn"
private def responseHandlerLabel : String := "__mdc_set"
private def aggregateResponseHandlerLabel : String := "__mdc_set_aggregate"
private def futureFaultHandlerLabel : String := "__mdc_future_fault"
private def sendFaultHandlerLabel : String := "__mdc_send_fault"
private def wakeHandlerLabel : String := "__mdc_wakeup"
private def codeRequestHandlerLabel : String := "__mdc_code_request"
private def codeInstallHandlerLabel : String := "__mdc_code_install"
private def codeAckHandlerLabel : String := "__mdc_code_ack"
private def mdcArgumentErrorHandlerLabel : String := "__mdc_argument_error"

private def alignUp (value alignment : Nat) : Nat :=
  if alignment <= 1 then value else ((value + alignment - 1) / alignment) * alignment

private partial def typeAlignmentFrom (aggregates : Array Aggregate) (type : CType) : Nat :=
  match type.stripTopQualifiers with
  | .array element _ => typeAlignmentFrom aggregates element
  | .structType name _ =>
      (aggregates.find? fun item => item.kind == .structKind && item.name == name).map
        (fun item => item.alignment) |>.getD 1
  | .unionType name _ =>
      (aggregates.find? fun item => item.kind == .unionKind && item.name == name).map
        (fun item => item.alignment) |>.getD 1
  | _ => 1

private structure ParameterLayout where
  slots : Array Nat := #[]
  words : Nat := 0

private def parameterLayout (aggregates : Array Aggregate) (returnType : CType)
    (parameters : Array CType) : ParameterLayout := Id.run do
  let base := 1 + if returnType.toRValue.isAggregate then 1 else 0
  let mut cursor := base
  let mut slots := #[]
  for type in parameters do
    cursor := alignUp cursor (typeAlignmentFrom aggregates type)
    slots := slots.push cursor
    cursor := cursor + type.wordSize
  return { slots := slots, words := cursor - base }

private def processMessageSlot : Nat := 7
private def processResumeIpSlot : Nat := 32
private def processR0Slot : Nat := 33
private def processR1Slot : Nat := 34
private def processR2Slot : Nat := 35
private def processR3Slot : Nat := 36
private def processA0Slot : Nat := 37
private def processA2Slot : Nat := 38
private def processA3Slot : Nat := 39
private def processFutureAddressSlot : Nat := 40
private def processNextWaiterSlot : Nat := 41
private def processBulkCountSlot : Nat := 42
private def processBulkListSlot : Nat := 43

private def isBulkPointerType : CType → Bool
  | type =>
      match type.toRValue.pointerPointee? with
      | some pointee => pointee.toRValue.isInt
      | none => false

private def isBulkPairAt (parameters : Array Parameter) (index : Nat) : Bool :=
  index + 1 < parameters.size && parameters[index]!.type.toRValue.isInt &&
    isBulkPointerType parameters[index + 1]!.type

private def remoteLogicalArgumentCount (parameters : Array Parameter) : Nat := Id.run do
  let mut count := 0
  let mut index := 0
  while index < parameters.size do
    count := count + 1
    index := index + if isBulkPairAt parameters index then 2 else 1
  return count

private inductive AtomicBuiltin where
  | init
  | killDependency
  | threadFence
  | signalFence
  | isLockFree
  | store (explicit : Bool)
  | load (explicit : Bool)
  | exchange (explicit : Bool)
  | compareExchange (weak explicit : Bool)
  | fetch (op : BinaryOp) (explicit : Bool)
  | flagTestAndSet (explicit : Bool)
  | flagClear (explicit : Bool)
deriving Repr, BEq

private def atomicBuiltin? : String → Option AtomicBuiltin
  | "atomic_init" => some .init
  | "kill_dependency" => some .killDependency
  | "atomic_thread_fence" => some .threadFence
  | "atomic_signal_fence" => some .signalFence
  | "atomic_is_lock_free" => some .isLockFree
  | "atomic_store" => some (.store false)
  | "atomic_store_explicit" => some (.store true)
  | "atomic_load" => some (.load false)
  | "atomic_load_explicit" => some (.load true)
  | "atomic_exchange" => some (.exchange false)
  | "atomic_exchange_explicit" => some (.exchange true)
  | "atomic_compare_exchange_strong" => some (.compareExchange false false)
  | "atomic_compare_exchange_strong_explicit" => some (.compareExchange false true)
  | "atomic_compare_exchange_weak" => some (.compareExchange true false)
  | "atomic_compare_exchange_weak_explicit" => some (.compareExchange true true)
  | "atomic_fetch_add" => some (.fetch .add false)
  | "atomic_fetch_add_explicit" => some (.fetch .add true)
  | "atomic_fetch_sub" => some (.fetch .sub false)
  | "atomic_fetch_sub_explicit" => some (.fetch .sub true)
  | "atomic_fetch_or" => some (.fetch .bitOr false)
  | "atomic_fetch_or_explicit" => some (.fetch .bitOr true)
  | "atomic_fetch_xor" => some (.fetch .bitXor false)
  | "atomic_fetch_xor_explicit" => some (.fetch .bitXor true)
  | "atomic_fetch_and" => some (.fetch .bitAnd false)
  | "atomic_fetch_and_explicit" => some (.fetch .bitAnd true)
  | "atomic_flag_test_and_set" => some (.flagTestAndSet false)
  | "atomic_flag_test_and_set_explicit" => some (.flagTestAndSet true)
  | "atomic_flag_clear" => some (.flagClear false)
  | "atomic_flag_clear_explicit" => some (.flagClear true)
  | _ => none

mutual
private partial def atomicAggregateWordsInType : CType → Nat
  | .qualified base qualifiers =>
      max (if qualifiers.isAtomic && base.isAggregate then base.wordSize else 0)
        (atomicAggregateWordsInType base)
  | .pointer pointee | .array pointee _ => atomicAggregateWordsInType pointee
  | .function returnType parameters =>
      parameters.foldl (fun maximum parameter =>
        max maximum (atomicAggregateWordsInType parameter))
        (atomicAggregateWordsInType returnType)
  | _ => 0

private partial def atomicAggregateWordsInExpr : Expr → Nat
  | .intLit _ type _ | .sizeofType type _ | .alignofType type _ =>
      atomicAggregateWordsInType type
  | .variable .. => 0
  | .call _ args destination _ =>
      args.foldl (fun maximum arg =>
        max maximum (atomicAggregateWordsInExpr arg))
        (destination.map atomicAggregateWordsInExpr |>.getD 0)
  | .indirectCall callee args destination _ =>
      args.foldl (fun maximum arg =>
        max maximum (atomicAggregateWordsInExpr arg)) <|
        max (atomicAggregateWordsInExpr callee)
          (destination.map atomicAggregateWordsInExpr |>.getD 0)
  | .assign target value _ | .compoundAssign _ target value _ |
      .comma target value _ | .binary _ target value _ | .subscript target value _ =>
      max (atomicAggregateWordsInExpr target) (atomicAggregateWordsInExpr value)
  | .conditional condition thenValue elseValue _ =>
      max (atomicAggregateWordsInExpr condition) <|
        max (atomicAggregateWordsInExpr thenValue)
          (atomicAggregateWordsInExpr elseValue)
  | .unary _ value _ | .member value _ _ _ | .postfix _ value _ |
      .prefix _ value _ | .sizeofExpr value _ => atomicAggregateWordsInExpr value
  | .cast type value _ =>
      max (atomicAggregateWordsInType type) (atomicAggregateWordsInExpr value)
  | .genericSelection _ associations _ =>
      associations.foldl (fun maximum association =>
        max maximum <| max
          (association.1.map atomicAggregateWordsInType |>.getD 0)
          (atomicAggregateWordsInExpr association.2)) 0
  | .compoundLiteral type initializer _ _ =>
      max (atomicAggregateWordsInType type)
        (atomicAggregateWordsInInitializer initializer)

private partial def atomicAggregateWordsInInitializer : Initializer Expr → Nat
  | .value value _ => atomicAggregateWordsInExpr value
  | .stringLiteral .. => 0
  | .list elements _ => elements.foldl (fun maximum element =>
      max maximum (atomicAggregateWordsInInitializer element.2)) 0
end

private partial def atomicAggregateWordsInStmt : Stmt → Nat
  | .block statements _ | .declarationGroup statements _ =>
      statements.foldl (fun maximum statement =>
        max maximum (atomicAggregateWordsInStmt statement)) 0
  | .declaration type _ initializer _ _ | .registerDeclaration type _ initializer _ =>
      max (atomicAggregateWordsInType type)
        (initializer.map atomicAggregateWordsInInitializer |>.getD 0)
  | .staticDeclaration type _ _ _ _ _ | .externDeclaration type _ _ _ |
      .functionDeclaration type _ _ => atomicAggregateWordsInType type
  | .expression value _ | .returnStmt value _ =>
      value.map atomicAggregateWordsInExpr |>.getD 0
  | .ite condition thenBranch elseBranch _ =>
      max (atomicAggregateWordsInExpr condition) <|
        max (atomicAggregateWordsInStmt thenBranch)
          (elseBranch.map atomicAggregateWordsInStmt |>.getD 0)
  | .whileLoop condition body _ =>
      max (atomicAggregateWordsInExpr condition) (atomicAggregateWordsInStmt body)
  | .doWhileLoop body condition _ =>
      max (atomicAggregateWordsInStmt body) (atomicAggregateWordsInExpr condition)
  | .forLoop init condition step body _ =>
      max (init.map atomicAggregateWordsInStmt |>.getD 0) <|
        max (condition.map atomicAggregateWordsInExpr |>.getD 0) <|
          max (step.map atomicAggregateWordsInExpr |>.getD 0)
            (atomicAggregateWordsInStmt body)
  | .switchStmt value body _ =>
      max (atomicAggregateWordsInExpr value) (atomicAggregateWordsInStmt body)
  | .caseLabel _ body _ | .defaultLabel body _ | .labeled _ body _ =>
      atomicAggregateWordsInStmt body
  | .breakStmt .. | .continueStmt .. | .gotoStmt .. => 0

private def programAtomicAggregateWords (program : Program) : Nat :=
  let globals := program.globals.foldl (fun maximum global =>
    max maximum (atomicAggregateWordsInType global.type)) 0
  let declarations := program.declarations.foldl (fun maximum declaration =>
    let parameterMaximum := declaration.parameters.foldl (fun current parameter =>
      max current (atomicAggregateWordsInType parameter.type)) 0
    max maximum <| max (atomicAggregateWordsInType declaration.returnType)
      parameterMaximum) globals
  program.functions.foldl (fun maximum function =>
    let parameterMaximum := function.parameters.foldl (fun current parameter =>
      max current (atomicAggregateWordsInType parameter.type)) 0
    max maximum <| max (atomicAggregateWordsInType function.returnType) <|
      max parameterMaximum (atomicAggregateWordsInStmt function.body)) declarations

mutual
private partial def exprLocalWords : Expr → Nat
  | .intLit .. | .variable .. | .sizeofExpr .. | .sizeofType .. | .alignofType .. => 0
  | .call _ args destination _ =>
      args.foldl (fun total arg => total + exprLocalWords arg)
        (destination.map exprLocalWords |>.getD 0)
  | .indirectCall callee args destination _ =>
      args.foldl (fun total arg => total + exprLocalWords arg)
        (exprLocalWords callee + (destination.map exprLocalWords |>.getD 0))
  | .assign target value _ | .compoundAssign _ target value _ |
      .comma target value _ | .binary _ target value _ | .subscript target value _ =>
      exprLocalWords target + exprLocalWords value
  | .conditional condition thenValue elseValue _ =>
      exprLocalWords condition + exprLocalWords thenValue + exprLocalWords elseValue
  | .unary _ value _ | .cast _ value _ | .member value _ _ _ |
      .postfix _ value _ | .prefix _ value _ => exprLocalWords value
  | .genericSelection _ associations _ =>
      associations.foldl (fun total association =>
        total + exprLocalWords association.2) 0
  | .compoundLiteral type initializer alignment _ =>
      (alignment - 1) + type.wordSize + initializerLocalWords initializer

private partial def initializerLocalWords : Initializer Expr → Nat
  | .value value _ => exprLocalWords value
  | .stringLiteral .. => 0
  | .list elements _ => elements.foldl
      (fun total element => total + initializerLocalWords element.2) 0
end

private structure InitializerSubobject where
  type : CType
  offset : Nat
  bitWidth : Option Nat := none
  bitOffset : Nat := 0
deriving Inhabited

private def InitializerSubobject.selectionStart (target : InitializerSubobject) : Nat :=
  target.offset * 32 + target.bitOffset

private def InitializerSubobject.selectionWidth (target : InitializerSubobject) : Nat :=
  target.bitWidth.getD (target.type.wordSize * 32)

private def InitializerSubobject.selectionEnd (target : InitializerSubobject) : Nat :=
  target.selectionStart + target.selectionWidth

private structure ResolvedInitializerAction (α : Type) where
  target : InitializerSubobject
  value : α
  pos : Pos
deriving Inhabited

private structure InitializerResolution (α : Type) where
  zeroRegions : Array InitializerSubobject := #[]
  actions : Array (ResolvedInitializerAction α) := #[]
deriving Inhabited

private partial def countLocals : Stmt → Nat
  | .block statements _ => statements.foldl (fun total stmt => total + countLocals stmt) 0
  | .declarationGroup declarations _ =>
      declarations.foldl (fun total stmt => total + countLocals stmt) 0
  | .declaration type _ initializer alignment _ =>
      (alignment.value - 1) + type.wordSize +
        (initializer.map initializerLocalWords |>.getD 0)
  | .registerDeclaration type _ initializer _ =>
      type.wordSize + (initializer.map initializerLocalWords |>.getD 0)
  | .staticDeclaration .. => 0
  | .externDeclaration .. | .functionDeclaration .. => 0
  | .expression value _ | .returnStmt value _ => value.map exprLocalWords |>.getD 0
  | .ite condition thenBranch elseBranch _ =>
      exprLocalWords condition + countLocals thenBranch +
        (elseBranch.map countLocals |>.getD 0)
  | .whileLoop condition body _ => exprLocalWords condition + countLocals body
  | .doWhileLoop body condition _ => countLocals body + exprLocalWords condition
  | .forLoop init condition step body _ =>
      (init.map countLocals |>.getD 0) +
        (condition.map exprLocalWords |>.getD 0) +
        (step.map exprLocalWords |>.getD 0) + countLocals body
  | .switchStmt value body _ => exprLocalWords value + countLocals body
  | .caseLabel _ body _ | .defaultLabel body _ => countLocals body
  | .labeled _ body _ => countLocals body
  | .breakStmt .. | .continueStmt .. | .gotoStmt .. => 0

private partial def statementMaximumAlignment : Stmt → Nat
  | .block statements _ | .declarationGroup statements _ =>
      statements.foldl (fun maximum stmt => max maximum (statementMaximumAlignment stmt)) 1
  | .declaration _ _ _ alignment _ | .staticDeclaration _ _ _ _ alignment _ |
      .externDeclaration _ _ alignment _ => alignment.value
  | .ite _ thenBranch elseBranch _ =>
      max (statementMaximumAlignment thenBranch)
        (elseBranch.map statementMaximumAlignment |>.getD 1)
  | .whileLoop _ body _ | .doWhileLoop body _ _ | .switchStmt _ body _ |
      .caseLabel _ body _ | .defaultLabel body _ | .labeled _ body _ =>
      statementMaximumAlignment body
  | .forLoop init _ _ body _ =>
      max (init.map statementMaximumAlignment |>.getD 1)
        (statementMaximumAlignment body)
  | _ => 1

private partial def collectSourceLabels : Stmt → Array (String × Pos)
  | .block statements _ | .declarationGroup statements _ =>
      statements.foldl (fun labels stmt => labels ++ collectSourceLabels stmt) #[]
  | .ite _ thenBranch elseBranch _ =>
      collectSourceLabels thenBranch ++
        (elseBranch.map collectSourceLabels |>.getD #[])
  | .whileLoop _ body _ | .doWhileLoop body _ _ => collectSourceLabels body
  | .forLoop init _ _ body _ =>
      (init.map collectSourceLabels |>.getD #[]) ++ collectSourceLabels body
  | .switchStmt _ body _ | .caseLabel _ body _ | .defaultLabel body _ =>
      collectSourceLabels body
  | .labeled name body pos => #[(name, pos)] ++ collectSourceLabels body
  | _ => #[]

private partial def collectSourceGotos : Stmt → Array (String × Pos)
  | .block statements _ | .declarationGroup statements _ =>
      statements.foldl (fun gotos stmt => gotos ++ collectSourceGotos stmt) #[]
  | .ite _ thenBranch elseBranch _ =>
      collectSourceGotos thenBranch ++
        (elseBranch.map collectSourceGotos |>.getD #[])
  | .whileLoop _ body _ | .doWhileLoop body _ _ => collectSourceGotos body
  | .forLoop init _ _ body _ =>
      (init.map collectSourceGotos |>.getD #[]) ++ collectSourceGotos body
  | .switchStmt _ body _ | .caseLabel _ body _ | .defaultLabel body _ =>
      collectSourceGotos body
  | .labeled _ body _ => collectSourceGotos body
  | .gotoStmt name pos => #[(name, pos)]
  | _ => #[]

private partial def collectSwitchLabels : Stmt → Array (Option Int × Pos)
  | .block statements _ | .declarationGroup statements _ =>
      statements.foldl (fun labels stmt => labels ++ collectSwitchLabels stmt) #[]
  | .ite _ thenBranch elseBranch _ =>
      collectSwitchLabels thenBranch ++
        (elseBranch.map collectSwitchLabels |>.getD #[])
  | .whileLoop _ body _ | .doWhileLoop body _ _ => collectSwitchLabels body
  | .forLoop init _ _ body _ =>
      (init.map collectSwitchLabels |>.getD #[]) ++ collectSwitchLabels body
  | .switchStmt .. => #[]
  | .caseLabel value body pos =>
      #[(some value, pos)] ++ collectSwitchLabels body
  | .defaultLabel body pos => #[(none, pos)] ++ collectSwitchLabels body
  | .labeled _ body _ => collectSwitchLabels body
  | _ => #[]

private def parameterStorageWords (parameters : Array Parameter) : Nat :=
  parameters.foldl (fun total parameter => total + parameter.type.wordSize) 0

private def parameterTypeStorageWords (parameters : Array CType) : Nat :=
  parameters.foldl (fun total type => total + type.wordSize) 0

private def aggregateResultWords (returnType : CType) : Nat :=
  if returnType.toRValue.isAggregate then returnType.wordSize else 0

private def localCallTemporaryWords (returnType : CType)
    (parameters : Array CType) : Nat :=
  parameterTypeStorageWords parameters + aggregateResultWords returnType

mutual
private partial def exprSpills (directCallWords : String → Nat)
    (indirectCallWords : Nat) : Expr → Nat
  | .intLit .. | .variable .. => 0
  | .call name args destination _ =>
      let nested := args.foldl
        (fun maximum arg => max maximum (exprSpills directCallWords indirectCallWords arg))
        (destination.map (exprSpills directCallWords indirectCallWords) |>.getD 0)
      if (atomicBuiltin? name).isSome && destination.isNone then 64 + nested
      else if name == "computer" && destination.isNone then 3 + nested
      else if destination.isSome then directCallWords name + 16 + nested
      else directCallWords name + nested
  | .indirectCall callee args destination _ =>
      let nested := args.foldl
        (fun maximum arg => max maximum (exprSpills directCallWords indirectCallWords arg))
        (max (exprSpills directCallWords indirectCallWords callee)
          (destination.map (exprSpills directCallWords indirectCallWords) |>.getD 0))
      (if destination.isSome then indirectCallWords + 16 else indirectCallWords + 1) + nested
  | .assign target value _ =>
      5 + max (exprSpills directCallWords indirectCallWords value)
        (exprSpills directCallWords indirectCallWords target)
  | .compoundAssign _ target value _ =>
      20 + max (exprSpills directCallWords indirectCallWords value)
        (exprSpills directCallWords indirectCallWords target)
  | .conditional condition thenValue elseValue _ =>
      max (exprSpills directCallWords indirectCallWords condition) <|
        max (exprSpills directCallWords indirectCallWords thenValue)
          (exprSpills directCallWords indirectCallWords elseValue)
  | .comma lhs rhs _ =>
      max (exprSpills directCallWords indirectCallWords lhs)
        (exprSpills directCallWords indirectCallWords rhs)
  | .unary _ value _ | .cast _ value _ => exprSpills directCallWords indirectCallWords value
  | .genericSelection _ associations _ =>
      associations.foldl (fun maximum association =>
        max maximum (exprSpills directCallWords indirectCallWords association.2)) 0
  | .subscript base index _ =>
      max (exprSpills directCallWords indirectCallWords base)
        (2 + exprSpills directCallWords indirectCallWords index)
  | .member base _ _ _ => exprSpills directCallWords indirectCallWords base
  | .compoundLiteral _ initializer _ _ =>
      initializerSpills directCallWords indirectCallWords initializer
  | .sizeofExpr .. | .sizeofType .. | .alignofType .. => 0
  | .postfix _ target _ | .prefix _ target _ =>
      12 + exprSpills directCallWords indirectCallWords target
  | .binary op lhs rhs _ =>
      if op == .logicalAnd || op == .logicalOr then
        max (exprSpills directCallWords indirectCallWords lhs)
          (exprSpills directCallWords indirectCallWords rhs)
      else
        -- Integer unsigned arithmetic temporarily changes the architectural U
        -- flag and therefore preserves both operands and the result.  Reserve
        -- the same eight-word window for every non-short-circuit binary form
        -- so nested expressions cannot alias that state.
        max (exprSpills directCallWords indirectCallWords lhs)
          (8 + exprSpills directCallWords indirectCallWords rhs)

private partial def initializerSpills (directCallWords : String → Nat)
    (indirectCallWords : Nat) : Initializer Expr → Nat
  | .value value _ => 5 + exprSpills directCallWords indirectCallWords value
  | .stringLiteral .. => 0
  | .list elements _ => elements.foldl (fun maximum element =>
      max maximum (initializerSpills directCallWords indirectCallWords element.2)) 0
end

private partial def stmtSpills (directCallWords : String → Nat)
    (indirectCallWords : Nat) : Stmt → Nat
  | .block statements _ => statements.foldl
      (fun maximum stmt => max maximum (stmtSpills directCallWords indirectCallWords stmt)) 0
  | .declarationGroup declarations _ => declarations.foldl
      (fun maximum stmt => max maximum (stmtSpills directCallWords indirectCallWords stmt)) 0
  | .declaration _ _ initializer _ _ | .registerDeclaration _ _ initializer _ =>
      initializer.map (initializerSpills directCallWords indirectCallWords) |>.getD 0
  | .staticDeclaration .. => 0
  | .externDeclaration .. | .functionDeclaration .. => 0
  | .expression value _ =>
      value.map (exprSpills directCallWords indirectCallWords) |>.getD 0
  | .returnStmt value _ =>
      4 + (value.map (exprSpills directCallWords indirectCallWords) |>.getD 0)
  | .ite condition thenBranch elseBranch _ =>
      max (exprSpills directCallWords indirectCallWords condition) <|
        max (stmtSpills directCallWords indirectCallWords thenBranch)
          (elseBranch.map (stmtSpills directCallWords indirectCallWords) |>.getD 0)
  | .whileLoop condition body _ =>
      max (exprSpills directCallWords indirectCallWords condition)
        (stmtSpills directCallWords indirectCallWords body)
  | .doWhileLoop body condition _ =>
      max (stmtSpills directCallWords indirectCallWords body)
        (exprSpills directCallWords indirectCallWords condition)
  | .forLoop init condition step body _ =>
      let expressionMaximum := [condition, step].foldl
        (fun maximum value => max maximum
          (value.map (exprSpills directCallWords indirectCallWords) |>.getD 0)) 0
      max (init.map (stmtSpills directCallWords indirectCallWords) |>.getD 0) <|
        max expressionMaximum (stmtSpills directCallWords indirectCallWords body)
  | .switchStmt value body _ =>
      max (1 + exprSpills directCallWords indirectCallWords value)
        (stmtSpills directCallWords indirectCallWords body)
  | .caseLabel _ body _ | .defaultLabel body _ =>
      stmtSpills directCallWords indirectCallWords body
  | .labeled _ body _ => stmtSpills directCallWords indirectCallWords body
  | .breakStmt .. | .continueStmt .. | .gotoStmt .. => 0

private structure FunctionInfo where
  function : Function
  linkName : String
  inlineDefinition : Bool := false
  effectiveNoreturn : Bool := false
  id : Nat
  parameterSlots : Array Nat
  parameterStorageWords : Nat
  localCount : Nat
  spillCount : Nat
  frameSize : Nat
deriving Repr, Inhabited

private def FunctionInfo.hasAggregateResult (info : FunctionInfo) : Bool :=
  info.function.returnType.toRValue.isAggregate

private def FunctionInfo.parameterBase (info : FunctionInfo) : Nat :=
  1 + if info.hasAggregateResult then 1 else 0

private def FunctionInfo.parameterWords (info : FunctionInfo) : Nat :=
  info.parameterStorageWords

private def parameterSlotFromTypes (aggregates : Array Aggregate) (returnType : CType)
    (parameters : Array CType) (index : Nat) : Nat :=
  let layout := parameterLayout aggregates returnType parameters
  layout.slots[index]?.getD (1 + if returnType.toRValue.isAggregate then 1 else 0)

private def FunctionInfo.parameterSlot (info : FunctionInfo) (index : Nat) : Nat :=
  info.parameterSlots[index]?.getD info.parameterBase

private def FunctionInfo.localBase (info : FunctionInfo) : Nat :=
  info.parameterBase + info.parameterWords

private def FunctionInfo.scratchBase (info : FunctionInfo) : Nat :=
  info.localBase + info.localCount

private structure GlobalInfo where
  global : Global
  slot : Nat
deriving Repr, Inhabited

private inductive PendingWord where
  | literal (value : Word)
  | branchDisplacement (target : String)
  | inlineBranch (opcode : Opcode) (conditionRegister : Nat) (target : String)
  | messageHeader (target : String) (length : Nat) (unchecked : Bool := false)
deriving Repr, Inhabited

private structure CodeWord where
  pending : PendingWord
  annotation : String
deriving Repr, Inhabited

private inductive Storage where
  | local (slot : Nat) (type : CType) (isRegister : Bool := false)
  | global (slot : Nat) (type : CType)
  | externObject (name : String) (type : CType) (pos : Pos)
  | function (name : String) (type : CType)
deriving Repr, Inhabited

private structure GeneratorState where
  file : String
  options : CompilerOptions
  items : Array CodeWord := #[]
  labels : List (String × Nat) := []
  nextLabel : Nat := 0
  functions : Array FunctionInfo
  globals : Array GlobalInfo
  sourceGlobals : Array Global
  aggregates : Array Aggregate
  currentFunction : Option FunctionInfo := none
  scopes : List (List (String × Storage)) := [[]]
  nextLocal : Nat := 1
  breakTarget : Option String := none
  continueTarget : Option String := none
  switchCaseLabels : List (Pos × String) := []
  futureTarget : Option Expr := none
deriving Inhabited

private abbrev GenM := StateT GeneratorState (Except CompileError)

private def codegenError (pos : Pos) (message : String) : GenM α := do
  let state ← get
  throw { file := state.file, pos := pos, message := message }

private def lookupByName? (entries : List (String × α)) (name : String) : Option α :=
  entries.findSome? fun entry => if entry.1 == name then some entry.2 else none

private def functionInfo? (name : String) : GenM (Option FunctionInfo) := do
  let state ← get
  let unit := state.currentFunction.map (fun info => info.function.translationUnit)
  match unit with
  | some translationUnit =>
      match state.functions.toList.find? fun info =>
          info.function.name == name && info.function.linkage == .internal &&
            info.function.translationUnit == translationUnit with
      | some info =>
          if state.currentFunction.any FunctionInfo.inlineDefinition then
            codegenError state.currentFunction.get!.function.pos
              s!"external inline definition may not reference internal-linkage function '{name}'"
          pure (some info)
      | none => pure <| state.functions.toList.find? fun info =>
          info.function.name == name && info.function.linkage == .external &&
            !info.inlineDefinition
  | none => pure <| state.functions.toList.find? fun info =>
      info.function.name == name && info.function.linkage == .external &&
        !info.inlineDefinition

private def globalInfo? (name : String) : GenM (Option GlobalInfo) := do
  let state ← get
  let unit := state.currentFunction.map (fun info => info.function.translationUnit)
  match unit with
  | some translationUnit =>
      match state.globals.toList.find? fun info =>
          info.global.name == name && info.global.linkage == .internal &&
            info.global.translationUnit == translationUnit with
      | some info => pure (some info)
      | none => pure <| state.globals.toList.find? fun info =>
          info.global.name == name && info.global.linkage == .external
  | none => pure <| state.globals.toList.find? fun info =>
      info.global.name == name && info.global.linkage == .external

private def sourceGlobal? (name : String) : GenM (Option Global) := do
  let state ← get
  let unit := state.currentFunction.map (fun info => info.function.translationUnit)
  match unit with
  | some translationUnit =>
      match state.sourceGlobals.toList.find? fun global =>
          global.name == name && global.linkage == .internal &&
            global.translationUnit == translationUnit with
      | some global => pure (some global)
      | none => pure <| state.sourceGlobals.toList.find? fun global =>
          global.name == name && global.linkage == .external
  | none => pure <| state.sourceGlobals.toList.find? fun global =>
      global.name == name && global.linkage == .external

private def aggregateInfo? (kind : AggregateKind) (name : String) : GenM (Option Aggregate) := do
  pure <| (← get).aggregates.toList.find? fun info =>
    info.kind == kind && info.name == name

private partial def normalizeType (type : CType) : GenM CType := do
  match type with
  | .pointer pointee => pure (.pointer (← normalizeType pointee))
  | .array element length => pure (.array (← normalizeType element) length)
  | .function returnType parameters =>
      pure (.function (← normalizeType returnType)
        (← parameters.mapM normalizeType))
  | .qualified base qualifiers =>
      pure ((← normalizeType base).withQualifiers qualifiers)
  | .structType name _ =>
      pure (.structType name ((← aggregateInfo? .structKind name).map (fun info => info.size) |>.getD 0))
  | .unionType name _ =>
      pure (.unionType name ((← aggregateInfo? .unionKind name).map (fun info => info.size) |>.getD 0))
  | other => pure other

private def typeAlignment (type : CType) : GenM Nat := do
  pure (typeAlignmentFrom (← get).aggregates type)

private def memberInfo (aggregateType : CType) (name : String) (pos : Pos) : GenM Member := do
  let aggregate ← match aggregateType.stripTopQualifiers with
    | .structType tag _ => aggregateInfo? .structKind tag
    | .unionType tag _ => aggregateInfo? .unionKind tag
    | _ => pure none
  let aggregate ← match aggregate with
    | some info => pure info
    | none => codegenError pos "member access requires a complete struct or union type"
  match aggregate.members.toList.find? fun member => member.name == name with
  | some member => pure { member with type := ← normalizeType member.type }
  | none => codegenError pos s!"{match aggregate.kind with | .structKind => "struct" | .unionKind => "union"} '{aggregate.name}' has no member '{name}'"

private partial def requireRemoteAggregateWords (type : CType) (pos : Pos) : GenM Unit := do
  match type.stripTopQualifiers with
  | .int | .boolType | .plainChar | .integer .. | .enumType _ => pure ()
  | .array element _ => requireRemoteAggregateWords element pos
  | .structType name _ =>
      let aggregate ← match ← aggregateInfo? .structKind name with
        | some info => pure info
        | none => codegenError pos "remote aggregate has an incomplete member layout"
      for member in aggregate.members do
        requireRemoteAggregateWords member.type member.pos
  | .unionType name _ =>
      let aggregate ← match ← aggregateInfo? .unionKind name with
        | some info => pure info
        | none => codegenError pos "remote aggregate has an incomplete member layout"
      for member in aggregate.members do
        requireRemoteAggregateWords member.type member.pos
  | .pointer _ =>
      codegenError pos
        "remote aggregate contains a pointer; use an explicit length/pointer bulk parameter"
  | .void | .function .. =>
      codegenError pos "remote aggregate contains a non-object member"
  | .qualified base _ => requireRemoteAggregateWords base pos

private partial def initializerObjectTypeAt? (type : CType) (offset : Nat) : GenM (Option CType) := do
  match type.stripTopQualifiers with
  | .array element length =>
      let width := element.wordSize
      if width == 0 || offset >= width * length then pure none
      else initializerObjectTypeAt? element (offset % width)
  | .structType name _ =>
      match ← aggregateInfo? .structKind name with
      | none => pure none
      | some aggregate =>
          match aggregate.members.toList.find? fun member =>
              offset >= member.offset && offset < member.offset + member.type.wordSize with
          | none => pure none
          | some member =>
              let qualifiers := type.topQualifiers
              let propagated : TypeQualifiers := {
                isConst := qualifiers.isConst, isVolatile := qualifiers.isVolatile }
              initializerObjectTypeAt? (member.type.withQualifiers propagated)
                (offset - member.offset)
  | .unionType name _ =>
      match ← aggregateInfo? .unionKind name with
      | some aggregate =>
          match aggregate.members[0]? with
          | some member => initializerObjectTypeAt? member.type offset
          | none => pure none
      | none => pure none
  | _ => pure (if offset == 0 then some type else none)

private def currentFunction : GenM FunctionInfo := do
  match (← get).currentFunction with
  | some info => pure info
  | none => codegenError default "internal error: no current function"

private def sourceCodeLabel (name : String) : GenM String := do
  let info ← currentFunction
  pure s!".user-label.{info.id}.{name}"

private def switchCaseCodeLabel? (pos : Pos) : GenM (Option String) := do
  pure <| (← get).switchCaseLabels.findSome? fun entry =>
    if entry.1 == pos then some entry.2 else none

private def emitPending (pending : PendingWord) (annotation : String) : GenM Unit :=
  modify fun state => { state with items := state.items.push { pending, annotation } }

private def emitConstantWord (value : Word) (annotation : String) : GenM Unit :=
  emitPending (.literal value) annotation

private def emitInteger (value : Int) (annotation : String := "constant") : GenM Unit :=
  emitConstantWord (integer value) annotation

private def emitMessageHeader (target : String) (length : Nat)
    (unchecked : Bool := false) : GenM Unit :=
  emitPending (.messageHeader target length unchecked)
    s!"message header for {target}, length {length}"

private def emitInstruction (opcode : Opcode) (op2 op1 op0 : Nat)
    (annotation : String) : GenM Unit :=
  emitPending (.literal (instructionPair (instruction opcode op2 op1 op0))) annotation

private def emitMove (destination source : Nat) : GenM Unit :=
  emitInstruction .read destination 0 (operandR source)
    s!"move r{source}, r{destination}"

private def freshLabel (stem : String) : GenM String := do
  let state ← get
  modify fun current => { current with nextLabel := current.nextLabel + 1 }
  pure s!".{stem}.{state.nextLabel}"

private def defineLabel (name : String) (pos : Pos := default) : GenM Unit := do
  let state ← get
  if (lookupByName? state.labels name).isSome then
    codegenError pos s!"duplicate code label '{name}'"
  modify fun current => { current with labels := (name, current.items.size) :: current.labels }

private def emitBranch (opcode : Opcode) (conditionRegister : Nat)
    (target : String) : GenM Unit := do
  emitPending (.branchDisplacement target) s!"displacement to {target}"
  emitInstruction opcode 0 conditionRegister (operandR 0) s!"branch {target}"

private def emitInlineBranch (opcode : Opcode) (conditionRegister : Nat)
    (target : String) : GenM Unit :=
  emitPending (.inlineBranch opcode conditionRegister target)
    s!"inline branch {target}"

private def emitConditionalBranch (opcode : Opcode) (target : String) : GenM Unit := do
  emitMove 1 0
  emitBranch opcode 1 target

private def emitLoadLocal (slot destination : Nat) : GenM Unit := do
  emitInteger (Int.ofNat slot) s!"frame slot {slot}"
  emitInstruction .add 0 3 (operandR 0) "frame offset"
  emitInstruction .read destination 0 (operandMemoryRegister 0 1)
    s!"load frame[{slot}], r{destination}"

private def emitStoreLocal (slot source : Nat) : GenM Unit := do
  if source != 1 then emitMove 1 source
  emitInteger (Int.ofNat slot) s!"frame slot {slot}"
  emitInstruction .add 0 3 (operandR 0) "frame offset"
  emitInstruction .write 0 1 (operandMemoryRegister 0 1)
    s!"store r1, frame[{slot}]"
  if source == 0 then emitMove 0 1

private def emitLoadGlobal (slot destination : Nat) : GenM Unit := do
  if slot < 64 then
    emitInstruction .read destination (slot / 16) (operandMemoryImmediate slot 3)
      s!"load global[{slot}], r{destination}"
  else
    emitInteger (Int.ofNat slot) s!"global slot {slot}"
    emitInstruction .read destination 0 (operandMemoryRegister 0 3)
      s!"load global[{slot}], r{destination}"

private def emitStoreGlobal (slot source : Nat) : GenM Unit := do
  if slot < 64 then
    emitInstruction .write (slot / 16) source (operandMemoryImmediate slot 3)
      s!"store r{source}, global[{slot}]"
  else
    if source != 1 then emitMove 1 source
    emitInteger (Int.ofNat slot) s!"global slot {slot}"
    emitInstruction .write 0 1 (operandMemoryRegister 0 3)
      s!"store r1, global[{slot}]"
    if source == 0 then emitMove 0 1

private def emitSetAddressRegisterConstant (register base : Nat)
    (length : Nat := 0) : GenM Unit := do
  emitConstantWord (address false false base length)
    s!"address 0x{toHex 5 base}, length {length}"
  emitInstruction .writeR 0 0 (registerOperand false false (4 + register))
    s!"set A{register}"

private def emitAddressWordFromInteger (length : Nat := 1) : GenM Unit := do
  emitInstruction .logicalShift 0 0 (operandImmediate 10) "address base << 10"
  emitMove 1 0
  emitInteger (Int.ofNat length) s!"address length := {length}"
  emitInstruction .or 0 1 (operandR 0) "combine address base and length"
  emitMove 1 0
  emitInteger (Int.ofNat Tag.addr.encoding) "ADDR tag"
  emitInstruction .writeTag 0 1 (operandR 0) "construct dynamic ADDR"

private def emitAddressWordFromBaseAndLength : GenM Unit := do
  -- Entry is R0=integer base and R1=integer length. The ADDR format is
  -- base[19:0] in bits 29:10 and a ten-bit bounds field in bits 9:0.
  emitInstruction .logicalShift 0 0 (operandImmediate 10) "address base << 10"
  emitInstruction .or 0 0 (operandR 1) "combine dynamic address length"
  emitInstruction .writeTag 0 0 (operandImmediate (Int.ofNat Tag.addr.encoding))
    "construct dynamic ADDR"

private def emitDynamicMessageHeader (target : String) (lengthSlot : Nat) : GenM Unit := do
  -- Relocation resolves the handler portion. Retagging it as INT permits the
  -- run-time message length to be inserted without unchecked arithmetic.
  emitLoadLocal lengthSlot 1
  emitMessageHeader target 0
  emitInstruction .writeTag 0 0 (operandImmediate (Int.ofNat Tag.int.encoding))
    "retag relocatable message base as INT"
  emitInstruction .or 0 0 (operandR 1) "insert dynamic MDC message length"
  emitInstruction .writeTag 0 0 (operandImmediate (Int.ofNat Tag.msg.encoding))
    "construct dynamic MSG header"

private def emitSetAddressRegisterFromInteger (register : Nat)
    (length : Nat := 1) : GenM Unit := do
  emitAddressWordFromInteger length
  emitInstruction .writeR 0 0 (registerOperand false false (4 + register))
    s!"set dynamic A{register}"

private def emitAddressRegisterBaseAsInteger (register : Nat) : GenM Unit := do
  emitConstantWord (boolean true) "enter pointer-field extraction"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := true"
  emitInstruction .readR 0 0 (registerOperand false false (4 + register))
    s!"read A{register}"
  emitInstruction .writeTag 0 0 (operandImmediate (Int.ofNat Tag.int.encoding))
    "retag address data as INT"
  emitMove 1 0
  emitInteger (-10) "address base right-shift count"
  emitInstruction .logicalShift 0 1 (operandR 0) "extract address base"
  -- Relocation and invalidity live above the twenty-bit base field. They must
  -- not leak into C pointer-to-integer conversion or null comparison.
  emitMove 1 0
  emitInteger (Int.ofNat addressMask) "address base field mask"
  emitInstruction .and 0 1 (operandR 0) "mask address base field"
  emitMove 1 0
  emitConstantWord (boolean false) "leave pointer-field extraction"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := false"
  emitMove 0 1

private def emitPhysicalAddressFromA2R2 : GenM Unit := do
  -- Entry is A2=bounds-tagged lvalue base and R2=word offset.
  emitAddressRegisterBaseAsInteger 2
  emitInstruction .add 0 0 (operandR 2) "add lvalue word offset"

private def emitForceMemoryRegister (offsetRegister addressRegister destination : Nat)
    (annotation : String) : GenM Unit := do
  let inspectLabel ← freshLabel "future.inspect"
  let resolvedLabel ← freshLabel "future.resolved"
  defineLabel inspectLabel
  emitInstruction .readTag 0 0
    (operandMemoryRegister offsetRegister addressRegister) s!"inspect {annotation} tag"
  emitInstruction .sub 0 0 (operandImmediate (Int.ofNat Tag.future.encoding))
    s!"{annotation} still FUT"
  emitConditionalBranch .branchNotZero resolvedLabel
  emitInstruction .readR 0 0 (registerOperand false false 0x19)
    "future consumer is background context"
  emitConditionalBranch .branchTrue inspectLabel
  -- READ is deliberately legal on FUT (but not CFUT) in the MDP v11 ISA: it
  -- moves the tagged future without consuming it.  Move the FUT into the
  -- requested register, then use exact EQ as the forcing primitive.  EQ faults
  -- on FUT/CFUT while remaining harmless if the producer wins the race between
  -- the tag inspection and READ.  The fault FIP identifies the following
  -- branch, so a woken process returns through tag inspection and reloads the
  -- now-resolved value.
  emitInstruction .read destination 0
    (operandMemoryRegister offsetRegister addressRegister)
    s!"move unresolved {annotation} FUT"
  if destination != 0 then emitMove 0 destination
  emitInstruction .equal 0 0 (operandR 0)
    s!"force unresolved {annotation} with exact EQ"
  emitBranch .branch 0 inspectLabel
  defineLabel resolvedLabel
  emitInstruction .read destination 0
    (operandMemoryRegister offsetRegister addressRegister) s!"force {annotation}"

private def emitForceLocal (slot destination : Nat) : GenM Unit := do
  emitInteger (Int.ofNat slot) s!"future-aware frame slot {slot}"
  emitInstruction .add 2 3 (operandR 0) "future-aware frame offset"
  emitForceMemoryRegister 2 1 destination s!"frame[{slot}]"

private def emitForceGlobal (slot destination : Nat) : GenM Unit := do
  emitInteger (Int.ofNat slot) s!"future-aware global slot {slot}"
  emitMove 2 0
  emitForceMemoryRegister 2 3 destination s!"global[{slot}]"

private def emitLoadMessage (offset destination : Nat) : GenM Unit := do
  if offset < 64 then
    emitInstruction .read destination (offset / 16) (operandMemoryImmediate offset 3)
      s!"load message[{offset}], r{destination}"
  else
    emitInteger (Int.ofNat offset) s!"message offset {offset}"
    emitInstruction .read destination 0 (operandMemoryRegister 0 3)
      s!"load message[{offset}], r{destination}"

private def emitLoadMessageDynamic (offsetSlot destination : Nat) : GenM Unit := do
  emitLoadLocal offsetSlot 0
  emitInstruction .read destination 0 (operandMemoryRegister 0 3)
    s!"load message[frame[{offsetSlot}]], r{destination}"

private def emitLoadProcessSlot (slot destination : Nat) : GenM Unit := do
  emitInstruction .read destination (slot / 16) (operandMemoryImmediate slot 1)
    s!"load process header[{slot}], r{destination}"

private def emitStoreProcessSlot (slot source : Nat) : GenM Unit := do
  emitInstruction .write (slot / 16) source (operandMemoryImmediate slot 1)
    s!"store r{source}, process header[{slot}]"

private def emitRetagUnchecked (tag : Tag) (annotation : String) : GenM Unit := do
  emitMove 1 0
  emitConstantWord (boolean true) s!"enter unchecked {annotation}"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := true"
  emitInstruction .writeTag 0 1 (operandImmediate (Int.ofNat tag.encoding)) annotation
  emitMove 1 0
  emitConstantWord (boolean false) s!"leave unchecked {annotation}"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := false"
  emitMove 0 1

private def emitPointerBaseAsInteger : GenM Unit := do
  -- Entry is a bounds-tagged pointer in R0. Address-register writes enforce
  -- the ADDR tag before the architectural base field is decoded.
  emitInstruction .writeR 0 0 (registerOperand false false 0x06)
    "pointer base extraction := A2"
  emitAddressRegisterBaseAsInteger 2

private def emitPointerOffset (elementWords : Nat) (subtract : Bool := false) : GenM Unit := do
  -- Entry is R0=ADDR pointer and R1=INT element displacement. C pointer
  -- movement changes bits 29:10 (the MDP physical base) while retaining the
  -- relocation, invalid, and bounds fields of the original capability.
  emitMove 2 0
  if elementWords != 1 then
    emitInteger (Int.ofNat elementWords) "pointer element width"
    emitInstruction .mul 1 1 (operandR 0) "scale pointer displacement"
  emitInstruction .arithmeticShift 1 1 (operandImmediate 10)
    "position pointer displacement in ADDR base field"
  emitMove 0 2
  emitMove 2 1
  emitMove 1 0
  emitConstantWord (boolean true) "enter unchecked pointer arithmetic"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := true"
  emitInstruction (if subtract then .sub else .add) 0 1 (operandR 2)
    (if subtract then "subtract pointer base displacement"
     else "add pointer base displacement")
  emitMove 1 0
  emitConstantWord (boolean false) "leave unchecked pointer arithmetic"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := false"
  emitMove 0 1

private def emitIntegerToPointer : GenM Unit := do
  let null ← freshLabel "cast.pointer.null"
  let done ← freshLabel "cast.pointer.done"
  -- Conditional branches consume R0 for their displacement but retain the
  -- tested integer in R1. Preserve the resulting pointer across the one
  -- unconditional branch in the non-null path for the same reason.
  emitConditionalBranch .branchZero null
  emitMove 0 1
  emitAddressWordFromInteger 0
  emitMove 1 0
  emitBranch .branch 0 done
  defineLabel null
  emitConstantWord (address false true 0 0) "null C pointer (invalid ADDR)"
  emitMove 1 0
  defineLabel done
  emitMove 0 1

private def lookupStorage? (name : String) : GenM (Option Storage) := do
  let state ← get
  for scope in state.scopes do
    match lookupByName? scope name with
    | some storage => return some storage
    | none => pure ()
  match ← globalInfo? name with
  | some info =>
      if info.global.linkage == .internal &&
          state.currentFunction.any FunctionInfo.inlineDefinition then
        codegenError state.currentFunction.get!.function.pos
          s!"external inline definition may not reference internal-linkage object '{name}'"
      pure (some (.global info.slot info.global.type))
  | none =>
      match ← sourceGlobal? name with
      | some global =>
          if global.linkage == .internal &&
              state.currentFunction.any FunctionInfo.inlineDefinition then
            codegenError state.currentFunction.get!.function.pos
              s!"external inline definition may not reference internal-linkage object '{name}'"
          pure (some (.externObject name global.type global.pos))
      | none => pure none

private def lookupStorage (name : String) (pos : Pos) : GenM Storage := do
  match ← lookupStorage? name with
  | some storage => pure storage
  | none => codegenError pos s!"use of undeclared identifier '{name}'"

private def Storage.type : Storage → CType
  | .local _ type _ | .global _ type | .externObject _ type _ | .function _ type => type

private def emitAddressOfStorage (storage : Storage) : GenM Unit := do
  match storage with
  | .local slot type _ =>
      emitAddressRegisterBaseAsInteger 1
      emitInstruction .add 0 0 (operandR 3) "current frame base"
      emitMove 1 0
      emitInteger (Int.ofNat slot) s!"physical frame slot {slot}"
      emitInstruction .add 0 1 (operandR 0) "frame object address"
      emitAddressWordFromInteger type.wordSize
  | .global slot type =>
      emitConstantWord (address false false (globalBase + slot) type.wordSize)
        s!"address of global[{slot}]"
  | .externObject name _ pos =>
      codegenError pos s!"undefined external global '{name}'"
  | .function name _ =>
      match ← functionInfo? name with
      | some info =>
          emitInteger (Int.ofNat (info.id + 1))
            s!"encoded CALL vector index for {info.function.name}"
      | none => codegenError default s!"use of undefined function '{name}'"

private def emitLoadVariable (name : String) (pos : Pos) : GenM Unit := do
  match ← lookupStorage name pos with
  | storage@(.local slot type _) =>
      if type.isArray then emitAddressOfStorage storage
      else if type.toRValue.isInteger then emitForceLocal slot 0
      else emitLoadLocal slot 0
  | storage@(.global slot type) =>
      if type.isArray then emitAddressOfStorage storage
      else if type.toRValue.isInteger then emitForceGlobal slot 0
      else emitLoadGlobal slot 0
  | storage@(.function ..) => emitAddressOfStorage storage
  | .externObject name _ _ => codegenError pos s!"undefined external global '{name}'"

private def emitStoreVariable (name : String) (pos : Pos) : GenM Unit := do
  match ← lookupStorage name pos with
  | .local slot type _ =>
      if type.isArray then codegenError pos "array objects are not assignable"
      if type.isConstQualified then codegenError pos "assignment to a const-qualified object"
      else emitStoreLocal slot 0
  | .global slot type =>
      if type.isArray then codegenError pos "array objects are not assignable"
      if type.isConstQualified then codegenError pos "assignment to a const-qualified object"
      else emitStoreGlobal slot 0
  | .function name _ => codegenError pos s!"function '{name}' is not assignable"
  | .externObject name _ _ => codegenError pos s!"undefined external global '{name}'"

private def pushScope : GenM Unit :=
  modify fun state => { state with scopes := [] :: state.scopes }

private def popScope : GenM Unit :=
  modify fun state => { state with scopes := state.scopes.drop 1 }

private def declareLocal (type : CType) (name : String) (pos : Pos)
    (isRegister : Bool := false) (alignment : Nat := 1) : GenM Nat := do
  let state ← get
  let scope := state.scopes.head?.getD []
  if (lookupByName? scope name).isSome then
    codegenError pos s!"redeclaration of local variable '{name}'"
  let slot := alignUp state.nextLocal (max alignment (← typeAlignment type))
  let scopes := ((name, .local slot type isRegister) :: scope) :: state.scopes.drop 1
  modify fun current => {
    current with nextLocal := slot + type.wordSize, scopes := scopes }
  pure slot

private def allocateAnonymousLocal (type : CType) : GenM Nat := do
  let slot := alignUp (← get).nextLocal (← typeAlignment type)
  modify fun current => { current with nextLocal := slot + type.wordSize }
  pure slot

private def declareStaticLocal (type : CType) (name backingName : String)
    (pos : Pos) : GenM Unit := do
  let state ← get
  let scope := state.scopes.head?.getD []
  if (lookupByName? scope name).isSome then
    codegenError pos s!"redeclaration of local variable '{name}'"
  let info ← match ← globalInfo? backingName with
    | some found => pure found
    | none => codegenError pos s!"internal error: missing static storage for '{name}'"
  if info.global.type != type then
    codegenError pos s!"internal error: static storage type mismatch for '{name}'"
  let scopes := ((name, Storage.global info.slot type) :: scope) :: state.scopes.drop 1
  modify fun current => { current with scopes := scopes }

private def declareExternObject (type : CType) (name : String) (pos : Pos) : GenM Unit := do
  let state ← get
  let scope := state.scopes.head?.getD []
  let storage ← match ← globalInfo? name with
    | some found => pure (Storage.global found.slot found.global.type)
    | none =>
        match ← sourceGlobal? name with
        | some declaration => pure (Storage.externObject name declaration.type pos)
        | none => codegenError pos s!"internal error: missing extern declaration for '{name}'"
  if storage.type != type then
    codegenError pos s!"extern declaration of '{name}' has a conflicting type"
  match lookupByName? scope name with
  | some prior =>
      if prior.type != type then
        codegenError pos s!"conflicting block-scope declaration of '{name}'"
  | none =>
      let scopes := ((name, storage) :: scope) :: state.scopes.drop 1
      modify fun current => { current with scopes := scopes }

private def declareBlockFunction (type : CType) (name : String) (pos : Pos) : GenM Unit := do
  let state ← get
  let scope := state.scopes.head?.getD []
  match lookupByName? scope name with
  | some prior =>
      if prior.type != type then
        codegenError pos s!"conflicting block-scope declaration of '{name}'"
  | none =>
      let scopes := ((name, Storage.function name type) :: scope) :: state.scopes.drop 1
      modify fun current => { current with scopes := scopes }

private def emitRetagInt : GenM Unit :=
  emitInstruction .writeTag 0 0 (operandImmediate 1) "C boolean to INT tag"

private def compatiblePointedTypes (lhs rhs : CType) : Bool :=
  lhs.stripTopQualifiers == rhs.stripTopQualifiers

private def qualifiersInclude (target source : TypeQualifiers) : Bool :=
  (!source.isConst || target.isConst) &&
  (!source.isVolatile || target.isVolatile) &&
  (!source.isRestrict || target.isRestrict) &&
  (!source.isAtomic || target.isAtomic)

private def pointerValueCompatible (targetPointee sourcePointee : CType) : Bool :=
  let targetBase := targetPointee.stripTopQualifiers
  let sourceBase := sourcePointee.stripTopQualifiers
  let functionInvolved := targetBase.isFunction || sourceBase.isFunction
  let baseCompatible :=
    if functionInvolved then targetBase == sourceBase
    else targetBase == sourceBase || targetBase.isVoid || sourceBase.isVoid
  baseCompatible && qualifiersInclude targetPointee.topQualifiers sourcePointee.topQualifiers

private def isNullPointerConstant : Expr → Bool
  | .intLit value _ _ => value == 0
  | .cast type value _ => type.toRValue.isInteger && isNullPointerConstant value
  | _ => false

private def conditionalPointerType? (lhs rhs : CType) : Option CType := do
  let lhsPointee ← lhs.toRValue.pointerPointee?
  let rhsPointee ← rhs.toRValue.pointerPointee?
  let lhsBase := lhsPointee.stripTopQualifiers
  let rhsBase := rhsPointee.stripTopQualifiers
  let functionInvolved := lhsBase.isFunction || rhsBase.isFunction
  if functionInvolved then
    if lhsBase != rhsBase then none
  else if lhsBase != rhsBase && !lhsBase.isVoid && !rhsBase.isVoid then none
  let qualifiers := lhsPointee.topQualifiers.merge rhsPointee.topQualifiers
  let resultBase :=
    if functionInvolved || (!lhsBase.isVoid && rhsBase.isVoid) then rhsBase
    else lhsBase
  pure (.pointer (resultBase.withQualifiers qualifiers))

private def functionType (info : FunctionInfo) : CType :=
  .function info.function.returnType (info.function.parameters.map fun parameter => parameter.type)

private def selectGenericAssociation (controlType : CType)
    (associations : Array (Option CType × Expr)) (pos : Pos) : GenM Expr := do
  let controlType := (← normalizeType controlType).toRValue.stripTopQualifiers
  let mut declaredTypes : Array CType := #[]
  let mut selected? : Option Expr := none
  let mut default? : Option Expr := none
  for association in associations do
    match association.1 with
    | none =>
        if default?.isSome then
          codegenError pos "a generic association list may contain only one default"
        default? := some association.2
    | some declaredType =>
        let declaredType := (← normalizeType declaredType).stripTopQualifiers
        unless declaredType.isObjectType do
          codegenError pos "a generic association type must be a complete object type"
        if declaredTypes.any fun prior => prior == declaredType then
          codegenError pos
            "a generic association list may not contain compatible duplicate types"
        declaredTypes := declaredTypes.push declaredType
        if declaredType == controlType then
          if selected?.isSome then
            codegenError pos "the controlling expression matches multiple generic associations"
          selected? := some association.2
  match selected?.orElse (fun _ => default?) with
  | some selected => return selected
  | none => codegenError pos "the controlling expression type is not compatible with any generic association"

private def emitFunctionDesignator (info : FunctionInfo) : GenM Unit :=
  -- A C null function pointer must not alias CALL-vector entry zero. Stored
  -- function pointers therefore use index+1 and are decoded only at an
  -- indirect invocation boundary.
  emitInteger (Int.ofNat (info.id + 1))
    s!"encoded CALL vector index for {info.function.name}"

mutual
  private partial def inferExprType (expression : Expr) : GenM CType := do
    match expression with
    | .intLit _ type _ => pure type
    | .compoundLiteral type _ _ _ => pure (← normalizeType type).toRValue
    | .sizeofExpr .. | .sizeofType .. | .alignofType .. =>
        pure (CType.cInteger .longRank false)
    | .variable name pos =>
        match ← lookupStorage? name with
        | some storage => pure (← normalizeType storage.type).toRValue
        | none =>
            match ← functionInfo? name with
            | some info => pure (.pointer (← normalizeType (functionType info)))
            | none => codegenError pos s!"use of undeclared identifier '{name}'"
    | .call name args destination pos =>
        match atomicBuiltin? name with
        | some builtin =>
            if destination.isSome then
              codegenError pos s!"atomic generic function '{name}' cannot be remotely invoked"
            let expectCount (count : Nat) : GenM Unit := do
              unless args.size == count do
                codegenError pos s!"'{name}' expects {count} arguments, got {args.size}"
            let atomicObjectType (index : Nat) : GenM CType := do
              let pointerType ← inferExprType args[index]!
              let pointee ← match pointerType.pointerPointee? with
                | some type => normalizeType type
                | none =>
                    codegenError args[index]!.pos
                      s!"argument {index + 1} of '{name}' must point to an atomic object"
              unless pointee.isAtomicQualified && pointee.isObjectType do
                codegenError args[index]!.pos
                  s!"argument {index + 1} of '{name}' must point to an atomic object"
              pure pointee
            let requireMutableAtomicObject (type : CType) (index : Nat) : GenM Unit := do
              if type.isConstQualified then
                codegenError args[index]!.pos
                  s!"argument {index + 1} of '{name}' points to a const-qualified atomic object"
            let checkValueCompatible (targetType : CType) (source : Expr) : GenM Unit := do
              let target := targetType.toRValue
              let sourceType := (← inferExprType source).toRValue
              let compatible :=
                if target.isBool && (sourceType.isInteger || sourceType.isPointer) then true
                else if target.isInteger && sourceType.isInteger then true
                else
                  match target.pointerPointee?, sourceType.pointerPointee? with
                  | some targetPointee, some sourcePointee =>
                      pointerValueCompatible targetPointee sourcePointee
                  | some _, none => sourceType.isInteger && isNullPointerConstant source
                  | none, none =>
                      target.stripTopQualifiers == sourceType.stripTopQualifiers
                  | none, some _ => false
              unless compatible do
                codegenError source.pos s!"incompatible value type in '{name}'"
            let checkOrder (index : Nat) : GenM Unit := do
              unless (← inferExprType args[index]!).isInteger do
                codegenError args[index]!.pos "memory order must have integer or memory_order type"
            match builtin with
            | .killDependency =>
                expectCount 1
                inferExprType args[0]!
            | .threadFence | .signalFence =>
                expectCount 1
                checkOrder 0
                pure .void
            | .isLockFree =>
                expectCount 1
                discard <| atomicObjectType 0
                pure .boolType
            | .init =>
                expectCount 2
                let objectType ← atomicObjectType 0
                requireMutableAtomicObject objectType 0
                checkValueCompatible objectType args[1]!
                pure .void
            | .store explicit =>
                expectCount (if explicit then 3 else 2)
                let objectType ← atomicObjectType 0
                requireMutableAtomicObject objectType 0
                checkValueCompatible objectType args[1]!
                if explicit then checkOrder 2
                pure .void
            | .load explicit =>
                expectCount (if explicit then 2 else 1)
                let objectType ← atomicObjectType 0
                if explicit then checkOrder 1
                pure objectType.toRValue
            | .exchange explicit =>
                expectCount (if explicit then 3 else 2)
                let objectType ← atomicObjectType 0
                requireMutableAtomicObject objectType 0
                checkValueCompatible objectType args[1]!
                if explicit then checkOrder 2
                pure objectType.toRValue
            | .compareExchange _ explicit =>
                expectCount (if explicit then 5 else 3)
                let objectType ← atomicObjectType 0
                requireMutableAtomicObject objectType 0
                let expectedType ← match (← inferExprType args[1]!).pointerPointee? with
                  | some type => normalizeType type
                  | none =>
                      codegenError args[1]!.pos
                        s!"argument 2 of '{name}' must point to the non-atomic value type"
                unless expectedType.stripTopQualifiers == objectType.toRValue do
                  codegenError args[1]!.pos
                    s!"argument 2 of '{name}' has an incompatible pointed-to type"
                if expectedType.isConstQualified then
                  codegenError args[1]!.pos
                    s!"argument 2 of '{name}' points to a const-qualified expected value"
                checkValueCompatible objectType args[2]!
                if explicit then
                  checkOrder 3
                  checkOrder 4
                pure .boolType
            | .fetch op explicit =>
                expectCount (if explicit then 3 else 2)
                let objectType ← atomicObjectType 0
                requireMutableAtomicObject objectType 0
                let valueType := objectType.toRValue
                if valueType.isPointer then
                  unless op == .add || op == .sub do
                    codegenError pos "only atomic_fetch_add/sub apply to atomic pointer types"
                else
                  unless valueType.isInteger && !valueType.isBool do
                    codegenError pos "atomic fetch operations require a non-_Bool integer or pointer type"
                unless (← inferExprType args[1]!).isInteger do
                  codegenError args[1]!.pos "atomic fetch operand must have integer type"
                if explicit then checkOrder 2
                pure valueType
            | .flagTestAndSet explicit | .flagClear explicit =>
                expectCount (if explicit then 2 else 1)
                let objectType ← atomicObjectType 0
                requireMutableAtomicObject objectType 0
                unless objectType.toRValue.isBool do
                  codegenError args[0]!.pos "atomic flag operation requires atomic_flag *"
                if explicit then checkOrder 1
                pure (if let .flagClear _ := builtin then .void else .boolType)
        | none =>
            match ← lookupStorage? name with
            | some (.function _ type) =>
                match (← normalizeType type).toRValue.functionPointerSignature? with
                | some (returnType, _) => pure returnType.toRValue
                | none => codegenError pos s!"internal error: '{name}' has a non-function declaration"
            | some storage =>
                match (← normalizeType storage.type).toRValue.functionPointerSignature? with
                | some (returnType, _) => pure returnType.toRValue
                | none => codegenError pos s!"called object '{name}' is not a function pointer"
            | none =>
                if name == "computer" || name == "computers" then pure .int
                else match ← functionInfo? name with
                  | some info => pure info.function.returnType.toRValue
                  | none => codegenError pos s!"call to undefined function '{name}'"
    | .indirectCall callee _ _ pos =>
        match (← inferExprType callee).toRValue.functionPointerSignature? with
        | some (returnType, _) => pure returnType.toRValue
        | none => codegenError pos "called expression is not a function pointer"
    | .assign target _ _ | .compoundAssign _ target _ _ |
        .postfix _ target _ | .prefix _ target _ =>
        pure (← inferLValueObjectType target).toRValue
    | .genericSelection control associations pos =>
        let controlType ← inferExprType control
        for association in associations do
          discard <| inferExprType association.2
        let selected ← selectGenericAssociation controlType associations pos
        inferExprType selected
    | .conditional condition thenValue elseValue pos =>
        let conditionType ← inferExprType condition
        unless conditionType.isInteger || conditionType.isPointer do
          codegenError condition.pos "conditional operator requires a scalar condition"
        let thenType ← inferExprType thenValue
        let elseType ← inferExprType elseValue
        if thenType.isInteger && elseType.isInteger then
          let thenArithmeticType ← promotedExprIntegerType thenValue thenType
          let elseArithmeticType ← promotedExprIntegerType elseValue elseType
          match CType.usualIntegerConversion thenArithmeticType elseArithmeticType with
          | some type => pure type
          | none => codegenError pos "internal error computing conditional integer type"
        else if thenType.isPointer && elseType.isPointer then
          match conditionalPointerType? thenType elseType with
          | some type => pure type
          | none => codegenError pos "conditional pointer operands have incompatible types"
        else if thenType.isPointer && elseType.isInteger &&
            isNullPointerConstant elseValue then
          pure thenType
        else if elseType.isPointer && thenType.isInteger &&
            isNullPointerConstant thenValue then
          pure elseType
        else if thenType.isVoid && elseType.isVoid then pure .void
        else if thenType.stripTopQualifiers == elseType.stripTopQualifiers &&
            thenType.isAggregate then
          pure thenType
        else
          codegenError pos "conditional operands have incompatible types"
    | .comma lhs rhs _ =>
        discard <| inferExprType lhs
        pure (← inferExprType rhs).toRValue
    | .cast type _ _ => pure type.toRValue
    | .unary .addressOf value _ =>
        if (← bitFieldMember? value).isSome then
          codegenError value.pos "cannot take the address of a bit-field"
        match value with
        | .variable name pos =>
            match ← lookupStorage? name with
            | some (.local _ _ true) =>
                codegenError pos s!"cannot take the address of register object '{name}'"
            | some storage => pure (.pointer (← normalizeType storage.type))
            | none =>
                match ← functionInfo? name with
                | some info => pure (.pointer (← normalizeType (functionType info)))
                | none => codegenError pos s!"use of undeclared identifier '{name}'"
        | _ => pure (.pointer (← inferLValueObjectType value))
    | .unary .dereference value pos =>
        match (← inferExprType value).pointerPointee? with
        | some pointee => pure pointee.toRValue
        | none => codegenError pos "dereference operand is not a pointer"
    | .unary op value pos =>
      let valueType ← inferExprType value
      if op == .logicalNot then
        if valueType.isInteger || valueType.isPointer then pure .int
        else codegenError pos "logical-not operator requires a scalar operand"
      else if valueType.isInteger then promotedExprIntegerType value valueType
      else codegenError pos "integer unary operator requires an integer operand"
    | .binary op lhs rhs pos =>
      let lhsType ← inferExprType lhs
      let rhsType ← inferExprType rhs
      if op == .logicalAnd || op == .logicalOr then
        if (lhsType.isInteger || lhsType.isPointer) &&
            (rhsType.isInteger || rhsType.isPointer) then pure .int
        else codegenError pos "logical operator requires scalar operands"
      else if lhsType.isInteger && rhsType.isInteger then
        let lhsArithmeticType ← promotedExprIntegerType lhs lhsType
        let rhsArithmeticType ← promotedExprIntegerType rhs rhsType
        if op == .lt || op == .le || op == .gt || op == .ge ||
            op == .eq || op == .ne || op == .logicalAnd || op == .logicalOr then
          pure .int
        else if op == .shl || op == .shr then
          pure lhsArithmeticType.integerPromotion
        else
          match CType.usualIntegerConversion lhsArithmeticType rhsArithmeticType with
          | some type => pure type
          | none => codegenError pos "internal error computing usual integer conversions"
      else match op, lhsType, rhsType with
        | .add, .pointer pointee, integerType | .add, integerType, .pointer pointee =>
            unless integerType.isInteger do
              codegenError pos "pointer arithmetic requires an integer displacement"
            if pointee.isObjectType then pure (.pointer pointee)
            else codegenError pos "pointer arithmetic requires a complete object type"
        | .sub, .pointer lhsPointee, .pointer rhsPointee =>
            if compatiblePointedTypes lhsPointee rhsPointee && lhsPointee.isObjectType then
              pure .int
            else codegenError pos "pointer subtraction requires compatible complete object types"
        | .sub, .pointer pointee, integerType =>
            unless integerType.isInteger do
              codegenError pos "pointer arithmetic requires an integer displacement"
            if pointee.isObjectType then pure (.pointer pointee)
            else codegenError pos "pointer arithmetic requires a complete object type"
        | .eq, .pointer lhsPointee, .pointer rhsPointee
        | .ne, .pointer lhsPointee, .pointer rhsPointee =>
            if pointerValueCompatible lhsPointee rhsPointee ||
                pointerValueCompatible rhsPointee lhsPointee then pure .int
            else codegenError pos "pointer equality requires compatible pointer types"
        | .eq, .pointer _, integerType | .ne, .pointer _, integerType =>
            unless integerType.isInteger do
              codegenError pos "pointer comparison requires another pointer or an integer null constant"
            if isNullPointerConstant rhs then pure .int
            else codegenError pos "pointer comparison with integer requires a null pointer constant"
        | .eq, integerType, .pointer _ | .ne, integerType, .pointer _ =>
            unless integerType.isInteger do
              codegenError pos "pointer comparison requires another pointer or an integer null constant"
            if isNullPointerConstant lhs then pure .int
            else codegenError pos "pointer comparison with integer requires a null pointer constant"
        | .lt, .pointer lhsPointee, .pointer rhsPointee
        | .le, .pointer lhsPointee, .pointer rhsPointee
        | .gt, .pointer lhsPointee, .pointer rhsPointee
        | .ge, .pointer lhsPointee, .pointer rhsPointee =>
            if compatiblePointedTypes lhsPointee rhsPointee && lhsPointee.isObjectType then
              pure .int
            else codegenError pos "relational pointer comparison requires compatible object types"
        | _, _, _ => codegenError pos "invalid operand types for binary operator"
    | .subscript base _ pos =>
        match (← inferExprType base).pointerPointee? with
        | some element => pure element.toRValue
        | none => codegenError pos "subscripted value is not a pointer or array"
    | .member base name indirect pos =>
        pure (← memberObjectType base name indirect pos).toRValue

  private partial def inferLValueObjectType (expression : Expr) : GenM CType := do
    match expression with
    | .variable name pos => normalizeType (← lookupStorage name pos).type
    | .compoundLiteral type _ _ _ => normalizeType type
    | .unary .dereference pointer pos =>
        match (← inferExprType pointer).pointerPointee? with
        | some pointee => normalizeType pointee
        | none => codegenError pos "dereference operand is not a pointer"
    | .subscript base _ pos =>
        match (← inferExprType base).pointerPointee? with
        | some element => normalizeType element
        | none => codegenError pos "subscripted value is not a pointer or array"
    | .member base name indirect pos =>
        memberObjectType base name indirect pos true
    | .genericSelection control associations pos =>
        let controlType ← inferExprType control
        for association in associations do
          discard <| inferExprType association.2
        let selected ← selectGenericAssociation controlType associations pos
        inferLValueObjectType selected
    | _ => codegenError expression.pos "expression is not an lvalue"

  private partial def memberObjectType (base : Expr) (name : String) (indirect : Bool)
      (pos : Pos) (requireLValueBase : Bool := false) : GenM CType := do
    let aggregateType ←
      if indirect then
        match (← inferExprType base).pointerPointee? with
        | some pointee => normalizeType pointee
        | none => codegenError pos "'->' requires a pointer to struct or union"
      else
        if requireLValueBase then normalizeType (← inferLValueObjectType base)
        else normalizeType (← inferExprType base)
    let member ← memberInfo aggregateType name pos
    let aggregateQualifiers := aggregateType.topQualifiers
    let propagated : TypeQualifiers := {
      isConst := aggregateQualifiers.isConst
      isVolatile := aggregateQualifiers.isVolatile }
    normalizeType (member.type.withQualifiers propagated)

  private partial def bitFieldMember? (expression : Expr) : GenM (Option Member) := do
    match expression with
    | .member base name indirect pos =>
        let aggregateType ←
          if indirect then
            match (← inferExprType base).pointerPointee? with
            | some pointee => normalizeType pointee
            | none => codegenError pos "'->' requires a pointer to struct or union"
          else normalizeType (← inferExprType base)
        let member ← memberInfo aggregateType name pos
        pure (if member.bitWidth.isSome then some member else none)
    | .genericSelection control associations pos =>
        let selected ←
          selectGenericAssociation (← inferExprType control) associations pos
        bitFieldMember? selected
    | _ => pure none

  private partial def promotedExprIntegerType (expression : Expr)
      (type : CType) : GenM CType := do
    match ← bitFieldMember? expression with
    | some member =>
        match member.bitWidth with
        | some width =>
            if type.isBool || width < 32 then pure .int
            else pure type.integerPromotion
        | none => pure type.integerPromotion
    | none => pure type.integerPromotion
end

private def isCharacterObjectType (type : CType) : Bool :=
  match type.stripTopQualifiers with
  | .plainChar | .integer .charRank _ => true
  | _ => false

private def isCharacterArrayType (type : CType) : Bool :=
  match type.stripTopQualifiers with
  | .array element _ => isCharacterObjectType element
  | _ => false

private def literalElementTypeCompatible (encoding : LiteralEncoding)
    (element : CType) : Bool :=
  if encoding == .ordinary || encoding == .utf8 then
    isCharacterObjectType element
  else
    element.stripTopQualifiers == encoding.elementType

private def positionalInitializerSubobjects
    (target : InitializerSubobject) : GenM (Array InitializerSubobject) := do
  let type ← normalizeType target.type
  match type.stripTopQualifiers with
  | .array element length =>
      let element ← normalizeType element
      pure <| (Array.range length).map fun index =>
        { type := element, offset := target.offset + index * element.wordSize }
  | .structType name _ =>
      let aggregate ← match ← aggregateInfo? .structKind name with
        | some found => pure found
        | none => codegenError default s!"initializer requires complete struct '{name}'"
      let qualifiers := type.topQualifiers
      let propagated : TypeQualifiers := {
        isConst := qualifiers.isConst, isVolatile := qualifiers.isVolatile }
      let namedMembers := aggregate.members.filter fun member =>
        member.name != "" && member.bitWidth != some 0
      namedMembers.mapM fun member => do
        pure {
          type := ← normalizeType (member.type.withQualifiers propagated)
          offset := target.offset + member.offset
          bitWidth := member.bitWidth
          bitOffset := member.bitOffset }
  | .unionType name _ =>
      let aggregate ← match ← aggregateInfo? .unionKind name with
        | some found => pure found
        | none => codegenError default s!"initializer requires complete union '{name}'"
      match aggregate.members.find? fun member =>
          member.name != "" && member.bitWidth != some 0 with
      | some member =>
          let qualifiers := type.topQualifiers
          let propagated : TypeQualifiers := {
            isConst := qualifiers.isConst, isVolatile := qualifiers.isVolatile }
          pure #[{
            type := ← normalizeType (member.type.withQualifiers propagated)
            offset := target.offset + member.offset
            bitWidth := member.bitWidth
            bitOffset := member.bitOffset }]
      | none => pure #[]
  | _ => pure #[{ type := type, offset := target.offset }]

private partial def initializerLeafSubobjects
    (target : InitializerSubobject) : GenM (Array InitializerSubobject) := do
  if target.bitWidth.isSome then
    pure (if target.bitWidth == some 0 then #[] else #[target])
  else
    match target.type.stripTopQualifiers with
    | .array .. | .structType .. | .unionType .. =>
        let direct ← positionalInitializerSubobjects target
        let mut leaves := #[]
        for subobject in direct do
          leaves := leaves ++ (← initializerLeafSubobjects subobject)
        pure leaves
    | _ => pure #[target]

private def resolveInitializerDesignatorPath (root : InitializerSubobject)
    (designators : Array InitializerDesignator) :
    GenM (InitializerSubobject × Array InitializerSubobject) := do
  let mut current := root
  let mut regions := #[]
  for designator in designators do
    match designator with
    | .member name pos =>
        let member ← memberInfo current.type name pos
        current := {
          type := member.type
          offset := current.offset + member.offset
          bitWidth := member.bitWidth
          bitOffset := member.bitOffset }
        regions := regions.push current
    | .index value pos =>
        let (element, length) ← match current.type.arrayElement? with
          | some info => pure info
          | none => codegenError pos "array designator requires an array subobject"
        if value < 0 || value.toNat >= length then
          codegenError pos s!"array designator index {value} is outside bound {length}"
        let element ← normalizeType element
        current := {
          type := element
          offset := current.offset + value.toNat * element.wordSize }
        regions := regions.push current
  pure (current, regions)

private def selectPositionalInitializerSubobject
    (sourceType? : α → GenM (Option CType)) (target : InitializerSubobject)
    (activeRegions : Array InitializerSubobject) (cursor : Nat)
    (initializer : Initializer α) : GenM InitializerSubobject := do
  if cursor >= target.selectionWidth then
    codegenError initializer.pos "too many initializers for object"
  if cursor == 0 && isCharacterArrayType target.type then
    match initializer with
    | .stringLiteral .. => return target
    | _ => pure ()
  let absoluteSelection := target.selectionStart + cursor
  let mut direct? := none
  let mut leaf? : Option InitializerSubobject := none
  for leaf in (← initializerLeafSubobjects target) do
    if leaf.selectionStart >= absoluteSelection &&
        leaf?.all (fun prior => leaf.selectionStart < prior.selectionStart) then
      leaf? := some leaf
  for region in activeRegions do
    if absoluteSelection >= region.selectionStart &&
        absoluteSelection < region.selectionEnd then
      let directObjects ← positionalInitializerSubobjects region
      for direct in directObjects do
        if direct.selectionStart >= absoluteSelection &&
            direct?.all (fun prior =>
              direct.selectionStart < prior.selectionStart) then
          direct? := some direct
      for leaf in (← initializerLeafSubobjects region) do
        if leaf.selectionStart >= absoluteSelection &&
            leaf?.all (fun prior => leaf.selectionStart < prior.selectionStart) then
          leaf? := some leaf
  if direct?.any (fun direct => direct.selectionStart > absoluteSelection) &&
      leaf?.isSome then
    direct? := none
  match initializer, direct? with
  | .list .., some direct | .stringLiteral .., some direct => pure direct
  | .value value _, some direct =>
      if direct.type.toRValue.isAggregate then
        match ← sourceType? value with
        | some sourceType =>
            if sourceType.stripTopQualifiers == direct.type.stripTopQualifiers then
              pure direct
            else
              match leaf? with
              | some leaf => pure leaf
              | none => codegenError initializer.pos "initializer does not select a scalar subobject"
        | none =>
            match leaf? with
            | some leaf => pure leaf
            | none => codegenError initializer.pos "initializer does not select a scalar subobject"
      else if direct.type.isArray then
        match leaf? with
        | some leaf => pure leaf
        | none => codegenError initializer.pos "initializer does not select a scalar subobject"
      else pure direct
  | _, none =>
      match leaf? with
      | some leaf => pure leaf
      | none => codegenError initializer.pos "too many initializers for aggregate or union"

private partial def resolveInitializer [Inhabited α]
    (sourceType? : α → GenM (Option CType))
    (integerValue : Int → Pos → α) (stringValue : String → Pos → α)
    (target : InitializerSubobject) (initializer : Initializer α) :
    GenM (InitializerResolution α) := do
  let normalizedType ← normalizeType target.type
  let target := { target with type := normalizedType }
  match initializer with
  | .value value pos =>
      if target.type.isArray then
        codegenError pos "array object requires a brace or string initializer"
      if target.type.toRValue.isAggregate then
        match ← sourceType? value with
        | some sourceType =>
            unless sourceType.stripTopQualifiers == target.type.stripTopQualifiers do
              codegenError pos "aggregate initializer has an incompatible type"
        | none => codegenError pos "aggregate initializer requires a compatible expression"
      pure { actions := #[{ target := target, value := value, pos := pos }] }
  | .stringLiteral values encoding storageName pos =>
      match target.type.stripTopQualifiers with
      | .array element length =>
          let element ← normalizeType element
          unless literalElementTypeCompatible encoding element do
            codegenError pos s!"{encoding.prefix} string literal requires an array with compatible element type"
          if values.size > length then
            codegenError pos "string literal is too long for the initialized character array"
          let payload := if values.size < length then values.push 0 else values
          let mut actions := #[]
          for index in [0:payload.size] do
            actions := actions.push {
              target := { type := element, offset := target.offset + index }
              value := integerValue payload[index]! pos
              pos := pos }
          pure { zeroRegions := #[target], actions := actions }
      | _ =>
          pure { actions := #[{
            target := target, value := stringValue storageName pos, pos := pos }] }
  | .list elements _ =>
      let mut resolution : InitializerResolution α := { zeroRegions := #[target] }
      let mut cursor := 0
      for (designators, nested) in elements do
        let selected ←
          if designators.isEmpty then
            selectPositionalInitializerSubobject sourceType? target
              resolution.zeroRegions cursor nested
          else
            let designated ← resolveInitializerDesignatorPath target designators
            resolution := { resolution with
              zeroRegions := resolution.zeroRegions ++ designated.2 }
            pure designated.1
        let nestedResolution ← resolveInitializer sourceType? integerValue stringValue selected nested
        resolution := {
          zeroRegions := resolution.zeroRegions ++ nestedResolution.zeroRegions
          actions := resolution.actions ++ nestedResolution.actions }
        cursor := selected.selectionStart - target.selectionStart +
          selected.selectionWidth
      pure resolution

private def ensureModifiableLValue (target : Expr) (pos : Pos) : GenM CType := do
  let type ← inferLValueObjectType target
  if type.isArray then codegenError pos "array objects are not assignable"
  if type.isConstQualified then
    codegenError pos "assignment to a const-qualified object"
  if !type.isObjectType then codegenError pos "assignment target is not an object type"
  pure type

private def valueCompatible (targetType sourceType : CType) (source : Expr) : Bool :=
  let target := targetType.toRValue
  let sourceType := sourceType.toRValue
  if target.isBool && (sourceType.isInteger || sourceType.isPointer) then true
  else if target.isInteger && sourceType.isInteger then true
  else
    match target.pointerPointee?, sourceType.pointerPointee? with
    | some targetPointee, some sourcePointee =>
        pointerValueCompatible targetPointee sourcePointee
    | some _, none => sourceType.isInteger && isNullPointerConstant source
    | none, none => target.stripTopQualifiers == sourceType.stripTopQualifiers
    | none, some _ => false

private def requireValueCompatible (targetType : CType) (source : Expr) (pos : Pos)
    (context : String) : GenM Unit := do
  let sourceType ← inferExprType source
  unless valueCompatible targetType sourceType source do
    codegenError pos s!"incompatible types in {context}"

private def emitNormalizeBoolValue (sourceType : CType) : GenM Unit := do
  let sourceType := sourceType.toRValue
  if sourceType.isPointer && !sourceType.isFunctionPointer then
    emitPointerBaseAsInteger
  emitMove 1 0
  emitInteger 0 "_Bool conversion zero"
  emitInstruction .notEqualData 0 1 (operandR 0) "normalize scalar to _Bool"
  emitRetagInt

private def emitTargetConversion (targetType sourceType : CType) : GenM Unit := do
  let targetType := targetType.toRValue
  let sourceType := sourceType.toRValue
  if targetType.isBool then
    emitNormalizeBoolValue sourceType
  else if targetType.isPointer && sourceType.isInteger && !targetType.isFunctionPointer then
    -- requireValueCompatible has already established that this is a C null
    -- pointer constant.  Object pointers use the MDP ADDR tag, so retaining
    -- the integer representation would fault as soon as the value is used as
    -- an address or scalar condition.
    emitIntegerToPointer

private def emitLValueRegistersAsAddress (type : CType) : GenM Unit := do
  -- Entry is A2=object base capability and R2=word offset, as produced by
  -- emitLValueLocation. Rebuild a capability whose bounds describe exactly
  -- the selected aggregate value.
  emitInstruction .readR 0 0 (registerOperand false false 0x06)
    "aggregate lvalue base"
  emitPointerBaseAsInteger
  emitInstruction .add 0 0 (operandR 2) "aggregate lvalue word offset"
  emitAddressWordFromInteger type.wordSize

private def emitCopyAggregateAddressToLocal (type : CType) (destinationSlot : Nat) : GenM Unit := do
  -- Entry is an ADDR for the complete source aggregate in R0. A2 retains the
  -- source capability while frame stores use A1, so every word can be copied
  -- without an unbounded host-side temporary.
  emitInstruction .writeR 0 0 (registerOperand false false 0x06)
    "aggregate argument source := A2"
  for offset in [0:type.wordSize] do
    emitInteger (Int.ofNat offset) "aggregate argument word offset"
    emitInstruction .read 1 0 (operandMemoryRegister 0 2)
      "load aggregate argument word"
    emitStoreLocal (destinationSlot + offset) 1

private def emitEnterUnchecked : GenM Unit := do
  emitConstantWord (boolean true) "enter unchecked C unsigned operation"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := true"

private def emitLeaveUnchecked : GenM Unit := do
  emitConstantWord (boolean false) "leave unchecked C unsigned operation"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := false"

private def emitEnterAtomic (savedInterruptSlot : Nat) : GenM Unit := do
  emitInstruction .readR 0 0 (registerOperand false false 0x1a)
    "save message-dispatch mask for seq_cst atomic operation"
  emitStoreLocal savedInterruptSlot 0
  emitConstantWord (boolean true) "enter seq_cst atomic critical section"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1a) "I := true"

private def emitLeaveAtomic (savedInterruptSlot : Nat) : GenM Unit := do
  emitLoadLocal savedInterruptSlot 0
  emitInstruction .writeR 0 0 (registerOperand false false 0x1a)
    "restore message-dispatch mask after seq_cst atomic operation"

private def emitAtomicAggregateLoad (objectType : CType) (depth : Nat) : GenM Unit := do
  let valueType := objectType.toRValue
  unless objectType.isAtomicQualified && valueType.isAggregate do
    codegenError default "internal error: aggregate atomic load requires an atomic aggregate lvalue"
  let info ← currentFunction
  let snapshotSlot := info.scratchBase + depth
  -- Convert the selected lvalue into an exact capability before masking
  -- dispatch. A2 then remains the source base while A1 addresses the frame
  -- snapshot and saved I-mask word.
  emitLValueRegistersAsAddress valueType
  emitInstruction .writeR 0 0 (registerOperand false false 0x06)
    "atomic aggregate source := A2"
  emitEnterAtomic (snapshotSlot + valueType.wordSize)
  for offset in [0:valueType.wordSize] do
    emitInteger (Int.ofNat offset) "atomic aggregate source word offset"
    emitInstruction .read 1 0 (operandMemoryRegister 0 2)
      "load atomic aggregate snapshot word"
    emitStoreLocal (snapshotSlot + offset) 1
  emitLeaveAtomic (snapshotSlot + valueType.wordSize)
  emitAddressOfStorage (.local snapshotSlot valueType false)

private def emitLogicalShiftR0 (amount : Int) (annotation : String) : GenM Unit := do
  if amount != 0 then
    emitMove 1 0
    emitInteger amount s!"{annotation} count"
    emitInstruction .logicalShift 1 1 (operandR 0) annotation
    emitMove 0 1

private def emitMaskLowBits (width : Nat) (annotation : String) : GenM Unit := do
  if width < 32 then
    let mask := (1 <<< width) - 1
    emitMove 1 0
    emitInteger (Int.ofNat mask) s!"{annotation} mask"
    emitInstruction .and 0 0 (operandR 1) annotation

private def emitExtractBitFieldValue (width bitOffset : Nat) (signed : Bool)
    (annotation : String) : GenM Unit := do
  if bitOffset != 0 then
    emitLogicalShiftR0 (-Int.ofNat bitOffset) s!"{annotation} align"
  emitMaskLowBits width s!"{annotation} truncate"
  if signed && width < 32 then
    let signBit := 1 <<< (width - 1)
    emitMove 1 0
    emitInteger (Int.ofNat signBit) s!"{annotation} sign bit"
    emitInstruction .xor 0 0 (operandR 1) s!"{annotation} bias sign bit"
    emitMove 1 0
    emitInteger (Int.ofNat signBit) s!"{annotation} sign bias"
    emitInstruction .sub 1 1 (operandR 0) s!"{annotation} sign extend"
    emitMove 0 1

private def emitExtractBitField (member : Member) : GenM Unit := do
  match member.bitWidth with
  | some width =>
      if width == 0 then
        codegenError member.pos "an unnamed zero-width bit-field has no value"
      emitExtractBitFieldValue width member.bitOffset
        (member.type.toRValue.isSignedInteger && !member.type.toRValue.isBool)
        s!"extract bit-field {member.name}"
  | none => codegenError member.pos "internal error: member is not a bit-field"

private def emitStoreBitField (member : Member) (scratch : Nat)
    (annotation : String) : GenM Unit := do
  let width ← match member.bitWidth with
    | some width => pure width
    | none => codegenError member.pos "internal error: member is not a bit-field"
  if width == 0 then
    codegenError member.pos "an unnamed zero-width bit-field is not assignable"
  let lowMask := if width == 32 then 0xffffffff else (1 <<< width) - 1
  let fieldMask := lowMask <<< member.bitOffset
  let clearMask := 0xffffffff - fieldMask
  emitStoreLocal scratch 1
  emitForceMemoryRegister 2 2 0 s!"{annotation} containing word"
  emitStoreLocal (scratch + 1) 0
  emitLoadLocal scratch 0
  if member.type.toRValue.isBool then
    emitNormalizeBoolValue member.type.toRValue
  emitMaskLowBits width s!"{annotation} stored value"
  emitStoreLocal (scratch + 2) 0
  if member.bitOffset != 0 then
    emitInstruction .readR 0 0 (registerOperand false false 0x1c)
      s!"{annotation} save unchecked mask"
    emitStoreLocal (scratch + 3) 0
    emitConstantWord (boolean true) s!"{annotation} enter unchecked placement"
    emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := true"
    emitLoadLocal (scratch + 2) 0
    emitLogicalShiftR0 (Int.ofNat member.bitOffset) s!"{annotation} place value"
    emitStoreLocal (scratch + 4) 0
    emitLoadLocal (scratch + 3) 0
    emitInstruction .writeR 0 0 (registerOperand false false 0x1c)
      s!"{annotation} restore unchecked mask"
  else
    emitLoadLocal (scratch + 2) 0
    emitStoreLocal (scratch + 4) 0
  emitLoadLocal (scratch + 1) 1
  emitInteger (Int.ofNat clearMask) s!"{annotation} clear mask"
  emitInstruction .and 0 0 (operandR 1) s!"{annotation} clear prior field"
  emitMove 1 0
  emitLoadLocal (scratch + 4) 0
  emitInstruction .or 0 0 (operandR 1) s!"{annotation} merge field"
  emitMove 1 0
  emitInstruction .write 0 1 (operandMemoryRegister 2 2) annotation
  emitLoadLocal (scratch + 2) 0
  emitExtractBitFieldValue width 0
    (member.type.toRValue.isSignedInteger && !member.type.toRValue.isBool)
    s!"{annotation} result"

private def emitUncheckedIntegerBinary (opcode : Opcode) (scratch : Nat)
    (annotation : String) : GenM Unit := do
  -- Entry is R0=lhs and R1=rhs, with lhs already saved at `scratch` by the
  -- expression evaluator. Unchecked MDP arithmetic implements C's modulo-2^32
  -- unsigned operations while preserving the INT tag from lhs.
  emitStoreLocal (scratch + 1) 1
  emitEnterUnchecked
  emitLoadLocal (scratch + 1) 1
  emitLoadLocal scratch 0
  emitInstruction opcode 0 0 (operandR 1) annotation
  emitStoreLocal (scratch + 2) 0
  emitLeaveUnchecked
  emitLoadLocal (scratch + 2) 0

private def emitUncheckedIntegerUnary (opcode : Opcode) (scratch : Nat)
    (annotation : String) : GenM Unit := do
  emitStoreLocal scratch 0
  emitEnterUnchecked
  emitLoadLocal scratch 0
  emitInstruction opcode 0 0 (operandR 0) annotation
  emitStoreLocal (scratch + 1) 0
  emitLeaveUnchecked
  emitLoadLocal (scratch + 1) 0

private def emitUnsignedComparison (opcode : Opcode) (scratch : Nat)
    (annotation : String) : GenM Unit := do
  -- Flipping bit 31 maps unsigned order to signed order.  This allows the
  -- published signed comparison instructions to implement all four unsigned
  -- relations without changing the architectural model.
  emitStoreLocal (scratch + 1) 1
  emitLoadLocal scratch 0
  emitMove 2 0
  emitInteger (-2147483648) "unsigned comparison sign-bit bias"
  emitInstruction .xor 0 2 (operandR 0) "bias unsigned lhs"
  emitStoreLocal (scratch + 2) 0
  emitLoadLocal (scratch + 1) 0
  emitMove 2 0
  emitInteger (-2147483648) "unsigned comparison sign-bit bias"
  emitInstruction .xor 0 2 (operandR 0) "bias unsigned rhs"
  emitMove 1 0
  emitLoadLocal (scratch + 2) 0
  emitInstruction opcode 0 0 (operandR 1) annotation
  emitRetagInt

private def emitSignedDivision (op : BinaryOp) (scratch : Nat) : GenM Unit := do
  -- Entry is R0=dividend, R1=divisor. Eight compiler spill words hold the
  -- magnitudes, quotient, remainder, bit index, signs, and one temporary.
  emitStoreLocal (scratch + 1) 1
  emitLoadLocal scratch 0
  emitInstruction .less 0 0 (operandImmediate 0) "dividend is negative"
  emitRetagInt
  emitStoreLocal (scratch + 6) 0
  emitLoadLocal (scratch + 1) 0
  emitInstruction .less 0 0 (operandImmediate 0) "divisor is negative"
  emitRetagInt
  emitStoreLocal (scratch + 7) 0
  emitLoadLocal (scratch + 7) 1
  emitLoadLocal (scratch + 6) 0
  emitInstruction .xor 0 0 (operandR 1) "quotient sign"
  emitStoreLocal (scratch + 5) 0

  -- Magnitude arithmetic is intentionally unchecked: abs(INT_MIN) is the
  -- unsigned magnitude 0x80000000. The generated C operation remains checked
  -- before and after this bounded runtime sequence.
  emitConstantWord (boolean true) "enter unchecked divider runtime"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := true"

  let dividendPositive ← freshLabel "div.dividend.positive"
  emitLoadLocal (scratch + 6) 0
  emitConditionalBranch .branchZero dividendPositive
  emitLoadLocal scratch 0
  emitInstruction .negate 0 0 (operandR 0) "absolute dividend"
  emitStoreLocal scratch 0
  defineLabel dividendPositive

  let divisorPositive ← freshLabel "div.divisor.positive"
  emitLoadLocal (scratch + 7) 0
  emitConditionalBranch .branchZero divisorPositive
  emitLoadLocal (scratch + 1) 0
  emitInstruction .negate 0 0 (operandR 0) "absolute divisor"
  emitStoreLocal (scratch + 1) 0
  defineLabel divisorPositive

  emitInteger 0 "initial quotient"
  emitStoreLocal (scratch + 2) 0
  emitInteger 0 "initial remainder"
  emitStoreLocal (scratch + 3) 0
  emitInteger 31 "initial divide bit"
  emitStoreLocal (scratch + 4) 0

  let loopLabel ← freshLabel "div.loop"
  let loopEnd ← freshLabel "div.end"
  defineLabel loopLabel
  emitLoadLocal (scratch + 1) 0
  emitConditionalBranch .branchZero loopEnd
  emitLoadLocal (scratch + 4) 0
  emitInstruction .less 0 0 (operandImmediate 0) "divide bit exhausted"
  emitConditionalBranch .branchNotZero loopEnd

  -- remainder = (remainder << 1) | ((dividend >> bit) & 1)
  emitLoadLocal (scratch + 4) 0
  emitInstruction .negate 1 0 (operandR 0) "negative logical shift count"
  emitLoadLocal scratch 0
  emitInstruction .logicalShift 0 0 (operandR 1) "extract dividend bit"
  emitInstruction .and 0 0 (operandImmediate 1) "isolate dividend bit"
  emitStoreLocal (scratch + 7) 0
  emitLoadLocal (scratch + 3) 0
  emitInstruction .logicalShift 0 0 (operandImmediate 1) "shift remainder"
  emitStoreLocal (scratch + 3) 0
  emitLoadLocal (scratch + 7) 1
  emitLoadLocal (scratch + 3) 0
  emitInstruction .or 0 0 (operandR 1) "append dividend bit"
  emitStoreLocal (scratch + 3) 0

  -- Unsigned remainder >= divisor. Signed comparison is sufficient when the
  -- sign bits agree; otherwise a set sign bit denotes the larger unsigned word.
  let remainderNonnegative ← freshLabel "div.rem.nonnegative"
  let signedCompare ← freshLabel "div.unsigned.same.sign"
  let subtractLabel ← freshLabel "div.subtract"
  let noSubtract ← freshLabel "div.no.subtract"
  emitLoadLocal (scratch + 3) 0
  emitInstruction .less 0 0 (operandImmediate 0) "remainder sign bit"
  emitConditionalBranch .branchZero remainderNonnegative
  emitLoadLocal (scratch + 1) 0
  emitInstruction .less 0 0 (operandImmediate 0) "divisor sign bit"
  emitConditionalBranch .branchNotZero signedCompare
  emitBranch .branch 0 subtractLabel
  defineLabel remainderNonnegative
  emitLoadLocal (scratch + 1) 0
  emitInstruction .less 0 0 (operandImmediate 0) "divisor sign bit"
  emitConditionalBranch .branchNotZero noSubtract
  defineLabel signedCompare
  emitLoadLocal (scratch + 1) 1
  emitLoadLocal (scratch + 3) 0
  emitInstruction .greaterEqual 0 0 (operandR 1) "unsigned remainder >= divisor"
  emitConditionalBranch .branchZero noSubtract

  defineLabel subtractLabel
  emitLoadLocal (scratch + 1) 1
  emitLoadLocal (scratch + 3) 0
  emitInstruction .sub 0 0 (operandR 1) "subtract divisor"
  emitStoreLocal (scratch + 3) 0
  emitLoadLocal (scratch + 4) 1
  emitInteger 1 "quotient bit"
  emitInstruction .logicalShift 0 0 (operandR 1) "position quotient bit"
  emitStoreLocal (scratch + 7) 0
  emitLoadLocal (scratch + 7) 1
  emitLoadLocal (scratch + 2) 0
  emitInstruction .or 0 0 (operandR 1) "set quotient bit"
  emitStoreLocal (scratch + 2) 0

  defineLabel noSubtract
  emitLoadLocal (scratch + 4) 0
  emitInstruction .sub 0 0 (operandImmediate 1) "next divide bit"
  emitStoreLocal (scratch + 4) 0
  emitBranch .branch 0 loopLabel
  defineLabel loopEnd

  let signSlot := if op == .div then scratch + 5 else scratch + 6
  let valueSlot := if op == .div then scratch + 2 else scratch + 3
  let positiveResult ← freshLabel "div.result.positive"
  let resultReady ← freshLabel "div.result.ready"
  emitLoadLocal signSlot 0
  emitConditionalBranch .branchZero positiveResult
  emitLoadLocal valueSlot 0
  emitInstruction .negate 0 0 (operandR 0) "apply signed divide result"
  emitStoreLocal (scratch + 7) 0
  emitBranch .branch 0 resultReady
  defineLabel positiveResult
  emitLoadLocal valueSlot 0
  emitStoreLocal (scratch + 7) 0
  defineLabel resultReady
  emitConstantWord (boolean false) "leave unchecked divider runtime"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := false"
  emitLoadLocal (scratch + 7) 0

private def emitUnsignedDivision (op : BinaryOp) (scratch : Nat) : GenM Unit := do
  -- Entry is R0=dividend and R1=divisor, with dividend already saved at
  -- `scratch`. Restoring division is performed on their raw 32-bit payloads;
  -- quotient and remainder therefore have exact C unsigned semantics,
  -- including values with bit 31 set.
  emitStoreLocal (scratch + 1) 1
  emitEnterUnchecked
  emitInteger 0 "initial unsigned quotient"
  emitStoreLocal (scratch + 2) 0
  emitInteger 0 "initial unsigned remainder"
  emitStoreLocal (scratch + 3) 0
  emitInteger 31 "initial unsigned divide bit"
  emitStoreLocal (scratch + 4) 0

  let loopLabel ← freshLabel "udiv.loop"
  let loopEnd ← freshLabel "udiv.end"
  defineLabel loopLabel
  emitLoadLocal (scratch + 1) 0
  emitConditionalBranch .branchZero loopEnd
  emitLoadLocal (scratch + 4) 0
  emitInstruction .less 0 0 (operandImmediate 0) "unsigned divide bit exhausted"
  emitConditionalBranch .branchNotZero loopEnd

  emitLoadLocal (scratch + 4) 0
  emitInstruction .negate 1 0 (operandR 0) "negative logical shift count"
  emitLoadLocal scratch 0
  emitInstruction .logicalShift 0 0 (operandR 1) "extract unsigned dividend bit"
  emitInstruction .and 0 0 (operandImmediate 1) "isolate unsigned dividend bit"
  emitStoreLocal (scratch + 7) 0
  emitLoadLocal (scratch + 3) 0
  emitInstruction .logicalShift 0 0 (operandImmediate 1) "shift unsigned remainder"
  emitStoreLocal (scratch + 3) 0
  emitLoadLocal (scratch + 7) 1
  emitLoadLocal (scratch + 3) 0
  emitInstruction .or 0 0 (operandR 1) "append unsigned dividend bit"
  emitStoreLocal (scratch + 3) 0

  let remainderNonnegative ← freshLabel "udiv.rem.nonnegative"
  let sameSign ← freshLabel "udiv.same.sign"
  let subtractLabel ← freshLabel "udiv.subtract"
  let noSubtract ← freshLabel "udiv.no.subtract"
  emitLoadLocal (scratch + 3) 0
  emitInstruction .less 0 0 (operandImmediate 0) "unsigned remainder sign bit"
  emitConditionalBranch .branchZero remainderNonnegative
  emitLoadLocal (scratch + 1) 0
  emitInstruction .less 0 0 (operandImmediate 0) "unsigned divisor sign bit"
  emitConditionalBranch .branchNotZero sameSign
  emitBranch .branch 0 subtractLabel
  defineLabel remainderNonnegative
  emitLoadLocal (scratch + 1) 0
  emitInstruction .less 0 0 (operandImmediate 0) "unsigned divisor sign bit"
  emitConditionalBranch .branchNotZero noSubtract
  defineLabel sameSign
  emitLoadLocal (scratch + 1) 1
  emitLoadLocal (scratch + 3) 0
  emitInstruction .greaterEqual 0 0 (operandR 1) "unsigned remainder >= divisor"
  emitConditionalBranch .branchZero noSubtract

  defineLabel subtractLabel
  emitLoadLocal (scratch + 1) 1
  emitLoadLocal (scratch + 3) 0
  emitInstruction .sub 0 0 (operandR 1) "subtract unsigned divisor"
  emitStoreLocal (scratch + 3) 0
  emitLoadLocal (scratch + 4) 1
  emitInteger 1 "unsigned quotient bit"
  emitInstruction .logicalShift 0 0 (operandR 1) "position unsigned quotient bit"
  emitStoreLocal (scratch + 7) 0
  emitLoadLocal (scratch + 7) 1
  emitLoadLocal (scratch + 2) 0
  emitInstruction .or 0 0 (operandR 1) "set unsigned quotient bit"
  emitStoreLocal (scratch + 2) 0

  defineLabel noSubtract
  emitLoadLocal (scratch + 4) 0
  emitInstruction .sub 0 0 (operandImmediate 1) "next unsigned divide bit"
  emitStoreLocal (scratch + 4) 0
  emitBranch .branch 0 loopLabel
  defineLabel loopEnd
  emitLeaveUnchecked
  emitLoadLocal (if op == .div then scratch + 2 else scratch + 3) 0

private def positivePowerOfTwoConstant? (expression : Expr) : GenM (Option Nat) := do
  let candidate : Option Nat ← match expression with
    | .intLit value _ _ =>
        pure <| if value > 0 then some value.toNat else none
    | .call "computers" args none _ =>
        if args.isEmpty then pure (some (← get).options.nodeCount) else pure none
    | _ => pure none
  match candidate with
  | some value =>
      if value != 0 && (value &&& (value - 1)) == 0 then pure (some value)
      else pure none
  | none => pure none

private def emitSignedPowerOfTwoRemainder (divisor scratch : Nat) : GenM Unit := do
  -- C signed remainder has the dividend's sign. For a positive power-of-two
  -- divisor, compute the magnitude with a mask and restore that sign. The
  -- negative path is briefly unchecked so -INT_MIN can be represented as the
  -- unsigned magnitude 0x80000000, exactly as in the general divider.
  let mask := divisor - 1
  let nonnegativeLabel ← freshLabel "mod.power2.nonnegative"
  let doneLabel ← freshLabel "mod.power2.done"
  emitStoreLocal scratch 0
  emitLoadLocal scratch 0
  emitInstruction .less 0 0 (operandImmediate 0) "power-of-two remainder dividend is negative"
  emitRetagInt
  emitConditionalBranch .branchZero nonnegativeLabel

  emitConstantWord (boolean true) "enter unchecked power-of-two remainder"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := true"
  emitLoadLocal scratch 0
  emitInstruction .negate 0 0 (operandR 0) "power-of-two remainder magnitude"
  emitMove 1 0
  emitInteger (Int.ofNat mask) "power-of-two remainder mask"
  emitInstruction .and 0 1 (operandR 0) "mask negative remainder magnitude"
  emitInstruction .negate 0 0 (operandR 0) "restore negative remainder sign"
  emitStoreLocal (scratch + 1) 0
  emitConstantWord (boolean false) "leave unchecked power-of-two remainder"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := false"
  emitLoadLocal (scratch + 1) 0
  -- Every branch displacement is materialized through R0. Preserve the
  -- negative result across the jump before converging with the nonnegative
  -- path; otherwise the displacement itself becomes the expression value.
  emitMove 2 0
  emitBranch .branch 0 doneLabel

  defineLabel nonnegativeLabel
  emitLoadLocal scratch 0
  emitMove 1 0
  emitInteger (Int.ofNat mask) "power-of-two remainder mask"
  emitInstruction .and 0 1 (operandR 0) "mask nonnegative remainder"
  emitMove 2 0
  defineLabel doneLabel
  emitMove 0 2

private partial def exactPowerOfTwoShift? (value : Nat) : Option Nat :=
  if value == 0 then none
  else
    let rec loop (remaining shift : Nat) : Option Nat :=
      if remaining == 1 then some shift
      else if remaining % 2 != 0 then none
      else loop (remaining / 2) (shift + 1)
    loop value 0

private def emitLogicalRightShift (amount : Nat) (annotation : String) : GenM Unit := do
  emitMove 1 0
  emitInteger (-Int.ofNat amount) s!"negative logical shift count -{amount}"
  emitInstruction .logicalShift 0 1 (operandR 0) annotation

private def emitDivideByPositiveConstant (op : BinaryOp) (divisor scratch : Nat) : GenM Unit := do
  if divisor == 1 then
    if op == .mod then emitInteger 0 "remainder modulo one"
  else
    match exactPowerOfTwoShift? divisor with
    | some shift =>
        if op == .div then
          emitLogicalRightShift shift s!"divide nonnegative rank by {divisor}"
        else
          emitSignedPowerOfTwoRemainder divisor scratch
    | none =>
        emitStoreLocal scratch 0
        emitInteger (Int.ofNat divisor) s!"positive topology divisor {divisor}"
        emitMove 1 0
        emitLoadLocal scratch 0
        emitSignedDivision op scratch

private def emitLogicalRankToNnr (scratch : Nat) : GenM Unit := do
  -- Entry and result are tagged INT values. The compiler's source language
  -- exposes dense logical ranks; the MDP router consumes packed X[4:0],
  -- Y[4:0], Z[5:0] coordinates in NNR and destination routing words.
  let options := (← get).options
  emitStoreLocal (scratch + 8) 0
  emitDivideByPositiveConstant .mod options.meshX scratch
  emitStoreLocal (scratch + 9) 0
  emitLoadLocal (scratch + 8) 0
  emitDivideByPositiveConstant .div options.meshX scratch
  emitStoreLocal (scratch + 8) 0
  emitDivideByPositiveConstant .mod options.meshY scratch
  emitStoreLocal (scratch + 10) 0
  emitLoadLocal (scratch + 8) 0
  emitDivideByPositiveConstant .div options.meshY scratch
  emitInstruction .logicalShift 0 0 (operandImmediate 10) "pack topology Z coordinate"
  emitStoreLocal (scratch + 8) 0
  emitLoadLocal (scratch + 10) 0
  emitInstruction .logicalShift 0 0 (operandImmediate 5) "pack topology Y coordinate"
  emitStoreLocal (scratch + 10) 0
  emitLoadLocal (scratch + 9) 1
  emitLoadLocal (scratch + 10) 0
  emitInstruction .or 0 0 (operandR 1) "combine topology X and Y coordinates"
  emitStoreLocal (scratch + 10) 0
  emitLoadLocal (scratch + 8) 1
  emitLoadLocal (scratch + 10) 0
  emitInstruction .or 0 0 (operandR 1) "construct packed MDP destination NNR"

private def emitNnrToLogicalRank (scratch : Nat) : GenM Unit := do
  -- Inverse of emitLogicalRankToNnr for computer():
  -- rank = x + meshX * (y + meshY * z).
  let options := (← get).options
  emitStoreLocal scratch 0
  emitInstruction .and 0 0 (operandImmediate 31) "extract topology X coordinate"
  emitStoreLocal (scratch + 1) 0

  emitLoadLocal scratch 0
  emitLogicalRightShift 5 "extract topology Y coordinate"
  emitInstruction .and 0 0 (operandImmediate 31) "mask topology Y coordinate"
  emitStoreLocal (scratch + 2) 0
  emitInteger (Int.ofNat options.meshX) "topology X extent"
  emitMove 1 0
  emitLoadLocal (scratch + 2) 0
  emitInstruction .mul 0 0 (operandR 1) "scale topology Y coordinate"
  emitStoreLocal (scratch + 2) 0
  emitLoadLocal (scratch + 1) 1
  emitLoadLocal (scratch + 2) 0
  emitInstruction .add 0 0 (operandR 1) "accumulate topology X and Y"
  emitStoreLocal (scratch + 1) 0

  emitLoadLocal scratch 0
  emitLogicalRightShift 10 "extract topology Z coordinate"
  emitStoreLocal (scratch + 2) 0
  emitInteger 63 "topology Z-coordinate mask"
  emitMove 1 0
  emitLoadLocal (scratch + 2) 0
  emitInstruction .and 0 0 (operandR 1) "mask topology Z coordinate"
  emitStoreLocal (scratch + 2) 0
  emitInteger (Int.ofNat (options.meshX * options.meshY)) "topology XY plane size"
  emitMove 1 0
  emitLoadLocal (scratch + 2) 0
  emitInstruction .mul 0 0 (operandR 1) "scale topology Z coordinate"
  emitStoreLocal (scratch + 2) 0
  emitLoadLocal (scratch + 1) 1
  emitLoadLocal (scratch + 2) 0
  emitInstruction .add 0 0 (operandR 1) "construct dense logical node rank"

mutual
 private partial def emitExpr (expression : Expr) (depth : Nat := 0) : GenM Unit := do
  match expression with
  | .intLit value _ _ => emitInteger value
  | .variable name pos =>
      match ← lookupStorage? name with
      | some storage@(.function ..) => emitAddressOfStorage storage
      | some storage =>
          if storage.type.toRValue.isAggregate then
            if storage.type.isAtomicQualified then
              emitAddressOfStorage storage
              emitInstruction .writeR 0 0 (registerOperand false false 0x06)
                "atomic aggregate lvalue base := A2"
              emitInteger 0 "atomic aggregate lvalue offset"
              emitMove 2 0
              emitAtomicAggregateLoad storage.type depth
            else emitAddressOfStorage storage
          else emitLoadVariable name pos
      | none =>
          match ← functionInfo? name with
          | some info => emitFunctionDesignator info
          | none => codegenError pos s!"use of undeclared identifier '{name}'"
  | .compoundLiteral sourceType initializers _alignment pos =>
      let type ← normalizeType sourceType
      let slot ← allocateAnonymousLocal type
      emitInitializeLocalObject type "compound literal" initializers pos slot none depth
      if type.toRValue.isAggregate && type.isAtomicQualified then
        emitAddressOfStorage (.local slot type false)
        emitInstruction .writeR 0 0 (registerOperand false false 0x06)
          "atomic aggregate compound-literal base := A2"
        emitInteger 0 "atomic aggregate compound-literal offset"
        emitMove 2 0
        emitAtomicAggregateLoad type depth
      else if type.isArray || type.toRValue.isAggregate then
        emitAddressOfStorage (.local slot type false)
      else if type.toRValue.isInteger then
        emitForceLocal slot 0
      else
        emitLoadLocal slot 0
  | .genericSelection control associations pos =>
      discard <| inferExprType expression
      let beforeControl ← get
      emitExpr control depth
      set beforeControl
      for association in associations do
        let beforeAssociation ← get
        emitExpr association.2 depth
        set beforeAssociation
      let selected ← selectGenericAssociation (← inferExprType control) associations pos
      emitExpr selected depth
  | .assign target value pos =>
      let targetObjectType ← ensureModifiableLValue target pos
      let bitField? ← bitFieldMember? target
      requireValueCompatible targetObjectType value pos "assignment"
      let targetType := targetObjectType.toRValue
      match targetType with
      | .structType .. | .unionType .. =>
          let sourceType ← inferExprType value
          if sourceType != targetType then
            codegenError pos "aggregate assignment requires identical struct or union types"
          let info ← currentFunction
          let scratch := info.scratchBase + depth
          emitLValueLocation target (depth + 4)
          emitLValueRegistersAsAddress targetType
          emitStoreLocal scratch 0
          emitExpr value (depth + 4)
          if targetObjectType.isAtomicQualified then
            -- Materialize the converted right operand before entering the
            -- target's critical section. Besides making the complete store
            -- indivisible, this stable snapshot is the value of the
            -- assignment expression after dispatch is restored.
            emitCopyAggregateAddressToLocal targetType (scratch + 4)
            emitEnterAtomic (scratch + 2)
            emitLoadLocal scratch 0
            emitInstruction .writeR 0 0 (registerOperand false false 0x06)
              "atomic aggregate target := A2"
            for offset in [0:targetType.wordSize] do
              emitLoadLocal (scratch + 4 + offset) 1
              emitInteger (Int.ofNat offset) "atomic aggregate target word offset"
              emitInstruction .write 0 1 (operandMemoryRegister 0 2)
                "store atomic aggregate word"
            emitLeaveAtomic (scratch + 2)
            emitAddressOfStorage (.local (scratch + 4) targetType false)
          else
            emitStoreLocal (scratch + 1) 0
            for offset in [0:targetType.wordSize] do
              emitLoadLocal (scratch + 1) 0
              emitInstruction .writeR 0 0 (registerOperand false false 0x06)
                "aggregate source := A2"
              emitInteger (Int.ofNat offset) "aggregate source word offset"
              emitInstruction .read 1 0 (operandMemoryRegister 0 2)
                "copy aggregate source word"
              emitLoadLocal scratch 0
              emitInstruction .writeR 0 0 (registerOperand false false 0x06)
                "aggregate target := A2"
              emitInteger (Int.ofNat offset) "aggregate target word offset"
              emitInstruction .write 0 1 (operandMemoryRegister 0 2)
                "copy aggregate target word"
            emitLoadLocal scratch 0
      | _ =>
          match target with
          | .variable name _ =>
              emitExpr value depth
              emitTargetConversion targetObjectType (← inferExprType value)
              emitStoreVariable name pos
          | _ =>
              let info ← currentFunction
              let scratch := info.scratchBase + depth
              emitExpr value depth
              emitTargetConversion targetObjectType (← inferExprType value)
              emitStoreLocal scratch 0
              emitLValueLocation target (depth + 5)
              emitLoadLocal scratch 1
              match bitField? with
              | some member =>
                  emitStoreBitField member scratch "store through C bit-field lvalue"
              | none =>
                  emitInstruction .write 0 1 (operandMemoryRegister 2 2)
                    "store through C lvalue"
                  emitMove 0 1
  | .compoundAssign op target value pos =>
      emitCompoundAssignment op target value pos depth
  | .conditional condition thenValue elseValue _ =>
      let resultType ← inferExprType expression
      let conditionType ← inferExprType condition
      let elseLabel ← freshLabel "conditional.else"
      let endLabel ← freshLabel "conditional.end"
      emitExpr condition depth
      if conditionType.isPointer then emitNormalizeBoolValue conditionType
      emitConditionalBranch .branchZero elseLabel
      emitExpr thenValue depth
      let thenType ← inferExprType thenValue
      if resultType.isPointer && thenType.isInteger then
        unless resultType.isFunctionPointer do emitIntegerToPointer
      else
        emitTargetConversion resultType thenType
      emitMove 1 0
      emitBranch .branch 0 endLabel
      defineLabel elseLabel
      emitExpr elseValue depth
      let elseType ← inferExprType elseValue
      if resultType.isPointer && elseType.isInteger then
        unless resultType.isFunctionPointer do emitIntegerToPointer
      else
        emitTargetConversion resultType elseType
      emitMove 1 0
      defineLabel endLabel
      emitMove 0 1
  | .comma lhs rhs _ =>
      emitExpr lhs depth
      emitExpr rhs depth
  | .unary op value pos =>
      match op with
      | .addressOf =>
          if (← bitFieldMember? value).isSome then
            codegenError value.pos "cannot take the address of a bit-field"
          match value with
          | .variable name variablePos =>
              match ← lookupStorage? name with
              | some (.local _ _ true) =>
                  codegenError variablePos s!"cannot take the address of register object '{name}'"
              | some storage => emitAddressOfStorage storage
              | none =>
                  match ← functionInfo? name with
                  | some info => emitFunctionDesignator info
                  | none => codegenError variablePos s!"use of undeclared identifier '{name}'"
          | .unary .dereference pointer _ => emitExpr pointer depth
          | _ =>
              emitLValueLocation value depth
              emitInstruction .readR 0 0 (registerOperand false false 0x06)
                "address-of lvalue base"
              emitMove 1 2
              emitPointerOffset 1
      | .dereference =>
          match (← inferExprType value).pointerPointee? with
          | some pointee =>
              if pointee.isFunction || pointee.isArray then
                emitExpr value depth
              else
                emitLValueLocation (.unary .dereference value pos) depth
                let resultType ← inferExprType (.unary .dereference value pos)
                if resultType.isAggregate then
                  let objectType ← inferLValueObjectType (.unary .dereference value pos)
                  if objectType.isAtomicQualified then
                    emitAtomicAggregateLoad objectType depth
                  else emitLValueRegistersAsAddress resultType
                else if resultType.isInteger then
                  emitForceMemoryRegister 2 2 0 "dereferenced object"
                else
                  emitInstruction .read 0 0 (operandMemoryRegister 2 2) "dereference pointer"
          | none => codegenError pos "dereference operand is not a pointer"
      | .neg =>
          emitExpr value depth
          let valueType := (← inferExprType value).integerPromotion
          if valueType.isSignedInteger then
            emitInstruction .negate 0 0 (operandR 0) "signed negate"
          else
            let info ← currentFunction
            let scratch := info.scratchBase + depth
            emitUncheckedIntegerUnary .negate scratch "unsigned negate modulo 2^32"
      | .bitNot =>
          emitExpr value depth
          emitInstruction .not 0 0 (operandR 0) "bitwise not"
      | .logicalNot =>
          emitExpr value depth
          let valueType ← inferExprType value
          if valueType.isPointer then emitNormalizeBoolValue valueType
          emitMove 1 0
          emitInteger 0
          emitInstruction .equalData 0 1 (operandR 0) "logical not"
          emitRetagInt
  | .cast targetType value pos =>
      let sourceType := (← inferExprType value).toRValue
      match targetType.toRValue, sourceType with
      | .void, _ =>
          emitExpr value depth
          emitInteger 0 "discarded void cast value"
      | target, source =>
          if target.isBool && (source.isInteger || source.isPointer) then
            emitExpr value depth
            emitNormalizeBoolValue source
          else if target.isInteger && source.isInteger then
            -- All integer scalar representations are one 32-bit MDP word;
            -- rank and signedness affect operations, not the stored bits.
            emitExpr value depth
          else if target.isInteger && source.isPointer then
            emitExpr value depth
            unless source.isFunctionPointer do emitPointerBaseAsInteger
          else if target.isPointer && source.isInteger then
            emitExpr value depth
            unless target.isFunctionPointer do emitIntegerToPointer
          else match target, source with
          | target@(.pointer _), source@(.pointer _) =>
              if target.isFunctionPointer == source.isFunctionPointer then emitExpr value depth
              else codegenError pos "conversion between function and object pointers is not supported"
          | .array .., _ => codegenError pos "cast target cannot be an array type"
          | _, _ => codegenError pos "invalid C cast"
  | .subscript base index pos =>
      emitLValueLocation (.subscript base index pos) depth
      let resultType ← inferExprType (.subscript base index pos)
      if resultType.isAggregate then
        let objectType ← inferLValueObjectType (.subscript base index pos)
        if objectType.isAtomicQualified then
          emitAtomicAggregateLoad objectType depth
        else emitLValueRegistersAsAddress resultType
      else if resultType.isInteger then
        emitForceMemoryRegister 2 2 0 "array element"
      else
        emitInstruction .read 0 0 (operandMemoryRegister 2 2) "load array element"
  | .member base name indirect pos =>
      let type ← memberObjectType base name indirect pos
      let bitField? ← bitFieldMember? (.member base name indirect pos)
      emitLValueLocation (.member base name indirect pos) depth
      if type.isArray then
        emitInstruction .readR 0 0 (registerOperand false false 0x06)
          "array member base"
        emitMove 1 2
        emitPointerOffset 1
      else
        match type.toRValue with
        | .int | .boolType | .plainChar | .integer .. =>
            emitForceMemoryRegister 2 2 0 s!"member {name}"
            match bitField? with
            | some member => emitExtractBitField member
            | none => pure ()
        | .pointer _ =>
            emitInstruction .read 0 0 (operandMemoryRegister 2 2) s!"load member {name}"
        | .structType .. | .unionType .. =>
            if type.isAtomicQualified then emitAtomicAggregateLoad type depth
            else emitLValueRegistersAsAddress type
        | .void => codegenError pos "member has void type"
        | .function .. => codegenError pos "member has function type"
        | .array .. | .enumType .. | .qualified .. =>
            codegenError pos "internal error: non-canonical qualified member type"
  | .sizeofType sourceType pos =>
      let type ← normalizeType sourceType
      if type.isVoid || type.isFunction || type.wordSize == 0 then
        codegenError pos "sizeof requires a complete object type"
      emitInteger (Int.ofNat type.wordSize) "sizeof(type)"
  | .sizeofExpr value pos =>
      if (← bitFieldMember? value).isSome then
        codegenError pos "sizeof may not be applied to a bit-field"
      let beforeOperand ← get
      emitExpr value depth
      set beforeOperand
      let type ← match value with
        | .variable name variablePos => pure (← lookupStorage name variablePos).type
        | .compoundLiteral sourceType _ _ _ => normalizeType sourceType
        | .unary .dereference _ _ | .subscript .. | .member .. =>
            inferLValueObjectType value
        | _ => inferExprType value
      if type.isVoid || type.isFunction || type.wordSize == 0 then
        codegenError pos "sizeof requires a complete object type"
      emitInteger (Int.ofNat type.wordSize) "sizeof(expression)"
  | .alignofType sourceType pos =>
      let type ← normalizeType sourceType
      unless type.isObjectType do
        codegenError pos "_Alignof requires a complete object type"
      emitInteger (Int.ofNat (← typeAlignment type)) "_Alignof(type)"
  | .binary .logicalAnd lhs rhs _ =>
      let falseLabel ← freshLabel "land.false"
      let endLabel ← freshLabel "land.end"
      emitExpr lhs depth
      let lhsType ← inferExprType lhs
      if lhsType.isPointer then emitNormalizeBoolValue lhsType
      emitConditionalBranch .branchZero falseLabel
      emitExpr rhs depth
      let rhsType ← inferExprType rhs
      if rhsType.isPointer then emitNormalizeBoolValue rhsType
      emitConditionalBranch .branchZero falseLabel
      emitInteger 1 "logical true"
      emitBranch .branch 0 endLabel
      defineLabel falseLabel
      emitInteger 0 "logical false"
      defineLabel endLabel
  | .binary .logicalOr lhs rhs _ =>
      -- Comparison operands are BOOL-tagged words. BNZ on a BOOL takes the
      -- branch for false as well as true on the RTL, so `||` is built from
      -- BZ alone, the way `&&` is: fall into the true value when an operand
      -- is nonzero, and branch past it when it is zero.
      let tryRhsLabel ← freshLabel "lor.rhs"
      let falseLabel ← freshLabel "lor.false"
      let endLabel ← freshLabel "lor.end"
      emitExpr lhs depth
      let lhsType ← inferExprType lhs
      if lhsType.isPointer then emitNormalizeBoolValue lhsType
      emitConditionalBranch .branchZero tryRhsLabel
      emitInteger 1 "logical true"
      emitBranch .branch 0 endLabel
      defineLabel tryRhsLabel
      emitExpr rhs depth
      let rhsType ← inferExprType rhs
      if rhsType.isPointer then emitNormalizeBoolValue rhsType
      emitConditionalBranch .branchZero falseLabel
      emitInteger 1 "logical true"
      emitBranch .branch 0 endLabel
      defineLabel falseLabel
      emitInteger 0 "logical false"
      defineLabel endLabel
  | .binary op lhs rhs pos =>
      let lhsType ← inferExprType lhs
      let rhsType ← inferExprType rhs
      discard <| inferExprType (.binary op lhs rhs pos)
      let info ← currentFunction
      let scratch := info.scratchBase + depth
      if lhsType.isInteger && rhsType.isInteger then
        let lhsArithmeticType ← promotedExprIntegerType lhs lhsType
        let rhsArithmeticType ← promotedExprIntegerType rhs rhsType
        let operationType ←
          if op == .shl || op == .shr then pure lhsArithmeticType.integerPromotion
          else match CType.usualIntegerConversion lhsArithmeticType rhsArithmeticType with
            | some type => pure type
            | none => codegenError pos "internal error computing usual integer conversions"
        let signedOperation := operationType.isSignedInteger
        let powerOfTwoDivisor ←
          if op == .mod then positivePowerOfTwoConstant? rhs else pure none
        match op, powerOfTwoDivisor with
        | .mod, some divisor =>
            emitExpr lhs depth
            if signedOperation then
              emitSignedPowerOfTwoRemainder divisor scratch
            else
              emitInstruction .and 0 0 (operandImmediate (Int.ofNat (divisor - 1)))
                "unsigned power-of-two remainder"
        | _, _ =>
            emitExpr lhs depth
            emitStoreLocal scratch 0
            emitExpr rhs (depth + 8)
            emitMove 1 0
            emitLoadLocal scratch 0
            if op == .div || op == .mod then
              if signedOperation then emitSignedDivision op scratch
              else emitUnsignedDivision op scratch
            else match op with
            | .add =>
                if signedOperation then emitInstruction .add 0 0 (operandR 1) "signed add"
                else emitUncheckedIntegerBinary .add scratch "unsigned add modulo 2^32"
            | .sub =>
                if signedOperation then emitInstruction .sub 0 0 (operandR 1) "signed subtract"
                else emitUncheckedIntegerBinary .sub scratch "unsigned subtract modulo 2^32"
            | .mul =>
                if signedOperation then emitInstruction .mul 0 0 (operandR 1) "signed multiply"
                else emitUncheckedIntegerBinary .mul scratch "unsigned multiply modulo 2^32"
            | .shl =>
                if signedOperation then
                  emitInstruction .logicalShift 0 0 (operandR 1) "signed shift left"
                else
                  emitUncheckedIntegerBinary .logicalShift scratch
                    "unsigned shift left modulo 2^32"
            | .shr =>
                emitInstruction .negate 1 0 (operandR 1) "negate shift count"
                emitInstruction (if signedOperation then .arithmeticShift else .logicalShift)
                  0 0 (operandR 1)
                  (if signedOperation then "signed shift right" else "unsigned shift right")
            | .bitAnd => emitInstruction .and 0 0 (operandR 1) "bitwise and"
            | .bitXor => emitInstruction .xor 0 0 (operandR 1) "bitwise xor"
            | .bitOr => emitInstruction .or 0 0 (operandR 1) "bitwise or"
            | compare@(.lt) | compare@(.le) | compare@(.gt) | compare@(.ge) =>
                let opcode := match compare with
                  | .lt => Opcode.less
                  | .le => Opcode.lessEqual
                  | .gt => Opcode.greater
                  | _ => Opcode.greaterEqual
                if signedOperation then
                  emitInstruction opcode 0 0 (operandR 1) "signed integer comparison"
                  emitRetagInt
                else
                  emitUnsignedComparison opcode scratch "unsigned integer comparison"
            | .eq => emitInstruction .equalData 0 0 (operandR 1) "integer equal"; emitRetagInt
            | .ne => emitInstruction .notEqualData 0 0 (operandR 1) "integer not equal"; emitRetagInt
            | .div | .mod | .logicalAnd | .logicalOr => pure ()
      else match op, lhsType, rhsType with
      | .sub, .pointer pointee, .pointer _ =>
          emitExpr lhs depth
          emitStoreLocal scratch 0
          emitExpr rhs (depth + 8)
          emitPointerBaseAsInteger
          emitMove 2 0
          emitLoadLocal scratch 0
          emitPointerBaseAsInteger
          emitInstruction .sub 0 0 (operandR 2) "pointer base difference"
          if pointee.wordSize != 1 then
            emitStoreLocal scratch 0
            emitInteger (Int.ofNat pointee.wordSize) "pointer difference element width"
            emitMove 1 0
            emitSignedDivision .div scratch
      | _, lhsPointer@(.pointer _), rhsPointer@(.pointer _) =>
          emitExpr lhs depth
          emitStoreLocal scratch 0
          emitExpr rhs (depth + 8)
          if lhsPointer.isFunctionPointer && rhsPointer.isFunctionPointer then
            emitMove 2 0
            emitLoadLocal scratch 0
          else
            emitPointerBaseAsInteger
            emitMove 2 0
            emitLoadLocal scratch 0
            emitPointerBaseAsInteger
          match op with
          | .lt => emitInstruction .less 0 0 (operandR 2) "pointer less than"
          | .le => emitInstruction .lessEqual 0 0 (operandR 2) "pointer less or equal"
          | .gt => emitInstruction .greater 0 0 (operandR 2) "pointer greater than"
          | .ge => emitInstruction .greaterEqual 0 0 (operandR 2) "pointer greater or equal"
          | .eq => emitInstruction .equalData 0 0 (operandR 2) "pointer equal"
          | .ne => emitInstruction .notEqualData 0 0 (operandR 2) "pointer not equal"
          | _ => pure ()
          emitRetagInt
      | .add, .pointer pointee, integerType | .sub, .pointer pointee, integerType =>
          unless integerType.isInteger do codegenError pos "pointer displacement is not an integer"
          emitExpr lhs depth
          emitStoreLocal scratch 0
          emitExpr rhs (depth + 8)
          emitMove 1 0
          emitLoadLocal scratch 0
          emitPointerOffset pointee.wordSize (op == .sub)
      | .add, integerType, .pointer pointee =>
          unless integerType.isInteger do codegenError pos "pointer displacement is not an integer"
          emitExpr lhs depth
          emitStoreLocal scratch 0
          emitExpr rhs (depth + 8)
          emitMove 2 0
          emitLoadLocal scratch 1
          emitMove 0 2
          emitPointerOffset pointee.wordSize
      | compare, lhsPointer@(.pointer _), integerType =>
          unless integerType.isInteger do codegenError pos "pointer null operand is not an integer"
          emitExpr lhs depth
          unless lhsPointer.isFunctionPointer do emitPointerBaseAsInteger
          emitStoreLocal scratch 0
          emitExpr rhs (depth + 8)
          emitMove 2 0
          emitLoadLocal scratch 0
          emitInstruction (if compare == .eq then .equalData else .notEqualData)
            0 0 (operandR 2) "pointer/null comparison"
          emitRetagInt
      | compare, integerType, rhsPointer@(.pointer _) =>
          unless integerType.isInteger do codegenError pos "pointer null operand is not an integer"
          emitExpr lhs depth
          emitStoreLocal scratch 0
          emitExpr rhs (depth + 8)
          unless rhsPointer.isFunctionPointer do emitPointerBaseAsInteger
          emitMove 2 0
          emitLoadLocal scratch 0
          emitInstruction (if compare == .eq then .equalData else .notEqualData)
            0 0 (operandR 2) "null/pointer comparison"
          emitRetagInt
      | _, _, _ => codegenError pos "invalid operand types for binary operator"
  | .postfix op target pos => emitUpdate op target pos depth true
  | .prefix op target pos => emitUpdate op target pos depth false
  | .indirectCall callee args destination pos =>
      match (← inferExprType callee).toRValue.functionPointerSignature? with
      | some (returnType, parameters) =>
          emitIndirectCall callee args destination returnType parameters pos depth
      | none => codegenError pos "called expression is not a function pointer"
  | .call name args destination pos =>
      match atomicBuiltin? name with
      | some builtin =>
          emitAtomicBuiltin name builtin args destination pos depth
          return
      | none => pure ()
      match ← lookupStorage? name with
      | some (.function ..) => pure ()
      | some storage =>
          match (← normalizeType storage.type).toRValue.functionPointerSignature? with
          | some (returnType, parameters) =>
              emitIndirectCall (.variable name pos) args destination returnType parameters pos depth
              return
          | none => codegenError pos s!"called object '{name}' is not a function pointer"
      | none => pure ()
      match destination with
      | none =>
          if name == "computer" then
            if !args.isEmpty then codegenError pos "computer() takes no arguments"
            let info ← currentFunction
            let scratch := info.scratchBase + depth
            emitInstruction .readR 0 0 (registerOperand false false 0x14)
              "read packed current-computer NNR"
            emitNnrToLogicalRank scratch
          else if name == "computers" then
            if !args.isEmpty then codegenError pos "computers() takes no arguments"
            emitInteger (Int.ofNat (← get).options.nodeCount) "number of computers"
          else
            let info ← match ← functionInfo? name with
              | some found => pure found
              | none => codegenError pos s!"call to undefined function '{name}'"
            if args.size != info.function.parameters.size then
              codegenError pos s!"function '{name}' expects {info.function.parameters.size} arguments, got {args.size}"
            let caller ← currentFunction
            let scratchBase := caller.scratchBase
            let parameterTypes := info.function.parameters.map fun parameter => parameter.type
            let parameterWords := parameterTypeStorageWords parameterTypes
            let returnWords := aggregateResultWords info.function.returnType
            let temporaryWords := parameterWords + returnWords
            let argumentBase := scratchBase + depth
            let returnBufferSlot := argumentBase + parameterWords
            for index in [0:args.size] do
              let parameterType := info.function.parameters[index]!.type
              requireValueCompatible parameterType args[index]!
                args[index]!.pos s!"argument {index + 1} of '{name}'"
              let argumentSlot := argumentBase +
                (parameterTypes.toList.take index |>.foldl
                  (fun total type => total + type.wordSize) 0)
              emitExpr args[index]! (depth + temporaryWords)
              if parameterType.toRValue.isAggregate then
                emitCopyAggregateAddressToLocal parameterType argumentSlot
              else
                emitTargetConversion parameterType (← inferExprType args[index]!)
                emitStoreLocal argumentSlot 0
            if info.hasAggregateResult then
              emitAddressOfStorage (.local returnBufferSlot
                (.array .int info.function.returnType.wordSize) false)
              emitStoreLocal (caller.frameSize + 1) 0
            for index in [0:args.size] do
              let parameterType := info.function.parameters[index]!.type
              let sourceSlot := argumentBase +
                (parameterTypes.toList.take index |>.foldl
                  (fun total type => total + type.wordSize) 0)
              let targetSlot := caller.frameSize + info.parameterSlot index
              for offset in [0:parameterType.wordSize] do
                emitLoadLocal (sourceSlot + offset) 0
                emitStoreLocal (targetSlot + offset) 0
            emitInteger (Int.ofNat caller.frameSize) "advance stack frame"
            emitInstruction .add 3 3 (operandR 0) "sp += frame size"
            emitInstruction .call 0 0 (operandImmediate (Int.ofNat info.id)) s!"call {name}"
            emitInteger (-Int.ofNat caller.frameSize) "restore stack frame"
            emitInstruction .add 3 3 (operandR 0) "sp -= frame size"
            if info.hasAggregateResult then
              emitAddressOfStorage (.local returnBufferSlot
                (.array .int info.function.returnType.wordSize) false)
            else
              emitMove 0 1
      | some destinationExpr =>
          if name == "computer" || name == "computers" then
            codegenError pos s!"builtin '{name}' cannot be remotely invoked"
          let info ← match ← functionInfo? name with
            | some found => pure found
            | none => codegenError pos s!"remote call to undefined function '{name}'"
          emitRemoteCall none info.id name args destinationExpr
            info.function.returnType info.function.parameters pos depth

 private partial def emitAtomicBuiltin (name : String) (builtin : AtomicBuiltin)
    (args : Array Expr) (destination : Option Expr) (pos : Pos) (depth : Nat) : GenM Unit := do
  discard <| inferExprType (.call name args destination pos)
  let info ← currentFunction
  let scratch := info.scratchBase + depth
  let nestedDepth := depth + 64
  let objectType : GenM CType := do
    let pointerType ← inferExprType args[0]!
    match pointerType.pointerPointee? with
    | some pointee => normalizeType pointee
    | none => codegenError pos s!"'{name}' requires a pointer to an atomic object"
  let emitObjectPointer : GenM CType := do
    let type ← objectType
    emitExpr args[0]! nestedDepth
    emitStoreLocal scratch 0
    pure type
  let restoreObjectAddress : GenM Unit := do
    emitLoadLocal scratch 0
    emitInstruction .writeR 0 0 (registerOperand false false 0x06)
      s!"{name} object := A2"
    emitInteger 0 s!"{name} object offset"
    emitMove 2 0
  let emitOrder (index : Nat) : GenM Unit := do
    emitExpr args[index]! nestedDepth
    emitStoreLocal (scratch + 8 + index) 0
  let constantOrder? (index : Nat) : Option Int :=
    match args[index]? with
    | some (.intLit value _ _) => some value
    | _ => none
  let validateOrder (index : Nat) (allowed : List Int) : GenM Unit := do
    match constantOrder? index with
    | some value => unless allowed.contains value do
        codegenError args[index]!.pos s!"invalid memory_order value for '{name}'"
    | none => pure ()
  let evaluateDesired (objectType : CType) (index : Nat) (slot : Nat) : GenM Unit := do
    emitExpr args[index]! nestedDepth
    if objectType.toRValue.isAggregate then
      emitCopyAggregateAddressToLocal objectType.toRValue slot
    else
      emitTargetConversion objectType (← inferExprType args[index]!)
      emitStoreLocal slot 0
  let emitScalarStore (slot : Nat) (annotation : String) : GenM Unit := do
    restoreObjectAddress
    emitLoadLocal slot 1
    emitInstruction .write 0 1 (operandMemoryRegister 2 2) annotation
  let emitAggregateStore (type : CType) (sourceSlot : Nat)
      (masked : Bool) (annotation : String) : GenM Unit := do
    if masked then emitEnterAtomic (scratch + 12)
    restoreObjectAddress
    for offset in [0:type.wordSize] do
      emitLoadLocal (sourceSlot + offset) 1
      emitInteger (Int.ofNat offset) s!"{annotation} offset"
      emitInstruction .write 0 1 (operandMemoryRegister 0 2) annotation
    if masked then emitLeaveAtomic (scratch + 12)
  let emitBool (value : Bool) (annotation : String) : GenM Unit := do
    emitInteger (if value then 1 else 0) annotation
    emitNormalizeBoolValue .int
  match builtin with
  | .killDependency =>
      emitExpr args[0]! nestedDepth
  | .threadFence | .signalFence =>
      validateOrder 0 [0, 1, 2, 3, 4, 5]
      emitOrder 0
      emitInstruction .nop 0 0 (operandR 0)
        (if builtin == .threadFence then "atomic thread fence" else "atomic signal fence")
      emitInteger 0 "void atomic fence result"
  | .isLockFree =>
      let type ← emitObjectPointer
      emitBool (type.wordSize == 1) "atomic lock-free query"
  | .init =>
      let type ← emitObjectPointer
      evaluateDesired type 1 (scratch + 16)
      if type.toRValue.isAggregate then
        emitAggregateStore type.toRValue (scratch + 16) false "initialize atomic aggregate word"
      else emitScalarStore (scratch + 16) "initialize atomic scalar"
      emitInteger 0 "void atomic_init result"
  | .store explicit =>
      let type ← emitObjectPointer
      evaluateDesired type 1 (scratch + 16)
      if explicit then
        validateOrder 2 [0, 3, 5]
        emitOrder 2
      if type.toRValue.isAggregate then
        emitAggregateStore type.toRValue (scratch + 16) true "atomic_store aggregate word"
      else emitScalarStore (scratch + 16) "atomic_store scalar"
      emitInteger 0 "void atomic_store result"
  | .load explicit =>
      let type ← emitObjectPointer
      if explicit then
        validateOrder 1 [0, 1, 2, 5]
        emitOrder 1
      restoreObjectAddress
      if type.toRValue.isAggregate then
        emitAtomicAggregateLoad type (depth + 16)
      else
        emitInstruction .read 0 0 (operandMemoryRegister 2 2) "atomic_load scalar"
  | .exchange explicit =>
      let type ← emitObjectPointer
      let valueType := type.toRValue
      evaluateDesired type 1 (scratch + 16)
      if explicit then
        validateOrder 2 [0, 1, 2, 3, 4, 5]
        emitOrder 2
      if valueType.isAggregate then
        let oldSlot := scratch + 16 + valueType.wordSize
        emitEnterAtomic (scratch + 16 + 2 * valueType.wordSize)
        restoreObjectAddress
        for offset in [0:valueType.wordSize] do
          emitInteger (Int.ofNat offset) "atomic_exchange source word offset"
          emitInstruction .read 1 0 (operandMemoryRegister 0 2)
            "atomic_exchange load prior aggregate word"
          emitStoreLocal (oldSlot + offset) 1
          emitLoadLocal (scratch + 16 + offset) 1
          emitInteger (Int.ofNat offset) "atomic_exchange target word offset"
          emitInstruction .write 0 1 (operandMemoryRegister 0 2)
            "atomic_exchange store aggregate word"
        emitLeaveAtomic (scratch + 16 + 2 * valueType.wordSize)
        emitAddressOfStorage (.local oldSlot valueType false)
      else
        emitEnterAtomic (scratch + 4)
        restoreObjectAddress
        emitInstruction .read 0 0 (operandMemoryRegister 2 2)
          "atomic_exchange load prior scalar"
        emitStoreLocal (scratch + 2) 0
        emitLoadLocal (scratch + 16) 1
        emitInstruction .write 0 1 (operandMemoryRegister 2 2)
          "atomic_exchange store scalar"
        emitLeaveAtomic (scratch + 4)
        emitLoadLocal (scratch + 2) 0
  | .compareExchange _weak explicit =>
      let type ← emitObjectPointer
      let valueType := type.toRValue
      emitExpr args[1]! nestedDepth
      emitStoreLocal (scratch + 1) 0
      evaluateDesired type 2 (scratch + 16)
      if explicit then
        validateOrder 3 [0, 1, 2, 3, 4, 5]
        validateOrder 4 [0, 1, 2, 5]
        match constantOrder? 3, constantOrder? 4 with
        | some success, some failure =>
            let allowedFailure : List Int := match success with
              | 0 => [0]
              | 1 => [0, 1]
              | 2 => [0, 1, 2]
              | 3 => [0]
              | 4 => [0, 1, 2]
              | _ => [0, 1, 2, 5]
            unless allowedFailure.contains failure do
              codegenError args[4]!.pos
                "compare-exchange failure memory order is stronger than success order"
        | _, _ => pure ()
        emitOrder 3
        emitOrder 4
      let failureLabel ← freshLabel "atomic.compare.failure"
      let finishLabel ← freshLabel "atomic.compare.finish"
      if valueType.isAggregate then
        let oldSlot := scratch + 16 + valueType.wordSize
        let savedInterruptSlot := scratch + 16 + 2 * valueType.wordSize
        emitEnterAtomic savedInterruptSlot
        restoreObjectAddress
        for offset in [0:valueType.wordSize] do
          emitInteger (Int.ofNat offset) "compare-exchange object word offset"
          emitInstruction .read 1 0 (operandMemoryRegister 0 2)
            "compare-exchange load object word"
          emitStoreLocal (oldSlot + offset) 1
        emitLoadLocal (scratch + 1) 0
        emitInstruction .writeR 0 0 (registerOperand false false 0x06)
          "compare-exchange expected := A2"
        for offset in [0:valueType.wordSize] do
          emitInteger (Int.ofNat offset) "compare-exchange expected word offset"
          emitInstruction .read 1 0 (operandMemoryRegister 0 2)
            "compare-exchange load expected word"
          emitLoadLocal (oldSlot + offset) 0
          emitInstruction .notEqual 0 0 (operandR 1)
            "compare-exchange aggregate word mismatch"
          emitRetagInt
          emitConditionalBranch .branchNotZero failureLabel
        restoreObjectAddress
        for offset in [0:valueType.wordSize] do
          emitLoadLocal (scratch + 16 + offset) 1
          emitInteger (Int.ofNat offset) "compare-exchange desired word offset"
          emitInstruction .write 0 1 (operandMemoryRegister 0 2)
            "compare-exchange store desired aggregate word"
        emitBool true "compare-exchange success"
        emitStoreLocal (scratch + 3) 0
        emitBranch .branch 0 finishLabel
        defineLabel failureLabel
        emitLoadLocal (scratch + 1) 0
        emitInstruction .writeR 0 0 (registerOperand false false 0x06)
          "compare-exchange failure expected := A2"
        for offset in [0:valueType.wordSize] do
          emitLoadLocal (oldSlot + offset) 1
          emitInteger (Int.ofNat offset) "compare-exchange expected update offset"
          emitInstruction .write 0 1 (operandMemoryRegister 0 2)
            "compare-exchange update expected aggregate word"
        emitBool false "compare-exchange failure"
        emitStoreLocal (scratch + 3) 0
        defineLabel finishLabel
        emitLeaveAtomic savedInterruptSlot
        emitLoadLocal (scratch + 3) 0
      else
        emitEnterAtomic (scratch + 12)
        restoreObjectAddress
        emitInstruction .read 0 0 (operandMemoryRegister 2 2)
          "compare-exchange load object scalar"
        emitStoreLocal (scratch + 4) 0
        emitLoadLocal (scratch + 1) 0
        emitInstruction .writeR 0 0 (registerOperand false false 0x06)
          "compare-exchange expected := A2"
        emitInstruction .read 1 0 (operandMemoryImmediate 0 2)
          "compare-exchange load expected scalar"
        emitLoadLocal (scratch + 4) 0
        emitInstruction .notEqual 0 0 (operandR 1) "compare-exchange scalar mismatch"
        emitRetagInt
        emitConditionalBranch .branchNotZero failureLabel
        restoreObjectAddress
        emitLoadLocal (scratch + 16) 1
        emitInstruction .write 0 1 (operandMemoryRegister 2 2)
          "compare-exchange store desired scalar"
        emitBool true "compare-exchange success"
        emitStoreLocal (scratch + 3) 0
        emitBranch .branch 0 finishLabel
        defineLabel failureLabel
        emitLoadLocal (scratch + 1) 0
        emitInstruction .writeR 0 0 (registerOperand false false 0x06)
          "compare-exchange failure expected := A2"
        emitLoadLocal (scratch + 4) 1
        emitInstruction .write 0 1 (operandMemoryImmediate 0 2)
          "compare-exchange update expected scalar"
        emitBool false "compare-exchange failure"
        emitStoreLocal (scratch + 3) 0
        defineLabel finishLabel
        emitLeaveAtomic (scratch + 12)
        emitLoadLocal (scratch + 3) 0
  | .fetch op explicit =>
      let type ← emitObjectPointer
      let valueType := type.toRValue
      emitExpr args[1]! nestedDepth
      emitStoreLocal (scratch + 1) 0
      if explicit then
        validateOrder 2 [0, 1, 2, 3, 4, 5]
        emitOrder 2
      emitEnterAtomic (scratch + 12)
      restoreObjectAddress
      emitInstruction .read 0 0 (operandMemoryRegister 2 2)
        "atomic_fetch load prior value"
      emitStoreLocal (scratch + 2) 0
      emitLoadLocal (scratch + 1) 1
      emitLoadLocal (scratch + 2) 0
      if valueType.isPointer then
        emitPointerOffset valueType.pointerPointee?.get!.wordSize (op == .sub)
      else
        match op with
        | .add | .sub =>
            emitUncheckedIntegerBinary (if op == .add then .add else .sub)
              (scratch + 2) "atomic_fetch arithmetic modulo 2^32"
        | .bitOr => emitInstruction .or 0 0 (operandR 1) "atomic_fetch_or"
        | .bitXor => emitInstruction .xor 0 0 (operandR 1) "atomic_fetch_xor"
        | .bitAnd => emitInstruction .and 0 0 (operandR 1) "atomic_fetch_and"
        | _ => codegenError pos "internal error: invalid atomic fetch operation"
      emitStoreLocal (scratch + 3) 0
      restoreObjectAddress
      emitLoadLocal (scratch + 3) 1
      emitInstruction .write 0 1 (operandMemoryRegister 2 2)
        "atomic_fetch store updated value"
      emitLeaveAtomic (scratch + 12)
      emitLoadLocal (scratch + 2) 0
  | .flagTestAndSet explicit =>
      discard <| emitObjectPointer
      if explicit then
        validateOrder 1 [0, 1, 2, 3, 4, 5]
        emitOrder 1
      emitEnterAtomic (scratch + 12)
      restoreObjectAddress
      emitInstruction .read 0 0 (operandMemoryRegister 2 2)
        "atomic_flag_test_and_set prior value"
      emitNormalizeBoolValue .boolType
      emitStoreLocal (scratch + 2) 0
      emitBool true "atomic flag set value"
      emitMove 1 0
      emitInstruction .write 0 1 (operandMemoryRegister 2 2) "set atomic_flag"
      emitLeaveAtomic (scratch + 12)
      emitLoadLocal (scratch + 2) 0
  | .flagClear explicit =>
      discard <| emitObjectPointer
      if explicit then
        validateOrder 1 [0, 3, 5]
        emitOrder 1
      restoreObjectAddress
      emitBool false "atomic flag clear value"
      emitMove 1 0
      emitInstruction .write 0 1 (operandMemoryRegister 2 2) "clear atomic_flag"
      emitInteger 0 "void atomic_flag_clear result"

 private partial def emitUpdate (op : PostfixOp) (target : Expr) (pos : Pos)
    (depth : Nat) (returnPrior : Bool) : GenM Unit := do
  let objectType ← ensureModifiableLValue target pos
  let bitField? ← bitFieldMember? target
  let valueType := objectType.toRValue
  unless valueType.isInteger || valueType.isPointer do
    codegenError pos "increment/decrement requires an integer or pointer lvalue"
  match valueType.pointerPointee? with
  | some pointee => unless pointee.isObjectType do
      codegenError pos "increment/decrement requires a pointer to an object type"
  | none => pure ()
  let info ← currentFunction
  let scratch := info.scratchBase + depth

  -- Preserve the exact lvalue capability and offset before reading it. This
  -- is required for targets such as a[index++] whose address expression may
  -- have side effects and must be evaluated exactly once.
  emitLValueLocation target (depth + 12)
  emitInstruction .readR 0 0 (registerOperand false false 0x06)
    "save update lvalue capability"
  emitStoreLocal scratch 0
  emitStoreLocal (scratch + 1) 2
  if objectType.isAtomicQualified then emitEnterAtomic (scratch + 11)
  if valueType.isInteger then
    emitForceMemoryRegister 2 2 0 "increment/decrement operand"
    match bitField? with
    | some member => emitExtractBitField member
    | none => pure ()
  else
    emitInstruction .read 0 0 (operandMemoryRegister 2 2)
      "load pointer increment/decrement operand"
  emitStoreLocal (scratch + 2) 0

  if valueType.isInteger then
    let arithmeticType ← promotedExprIntegerType target valueType
    if arithmeticType.isSignedInteger then
      emitInstruction (if op == .inc then .add else .sub) 0 0 (operandImmediate 1)
        (if op == .inc then "signed increment" else "signed decrement")
    else
      emitInteger 1 "unsigned update unit"
      emitMove 1 0
      emitLoadLocal (scratch + 2) 0
      emitUncheckedIntegerBinary (if op == .inc then .add else .sub) (scratch + 4)
        (if op == .inc then "unsigned increment" else "unsigned decrement")
  else
    let pointee := valueType.pointerPointee?.get!
    emitInteger 1 "pointer update displacement"
    emitMove 1 0
    emitLoadLocal (scratch + 2) 0
    emitPointerOffset pointee.wordSize (op == .dec)
  if valueType.isBool then emitNormalizeBoolValue valueType
  emitStoreLocal (scratch + 3) 0

  emitLoadLocal scratch 0
  emitInstruction .writeR 0 0 (registerOperand false false 0x06)
    "restore update lvalue capability"
  emitLoadLocal (scratch + 1) 2
  emitLoadLocal (scratch + 3) 1
  match bitField? with
  | some member =>
      emitStoreBitField member (scratch + 6) "store bit-field increment/decrement result"
      emitStoreLocal (scratch + 3) 0
  | none =>
      emitInstruction .write 0 1 (operandMemoryRegister 2 2)
        "store increment/decrement result"
  if objectType.isAtomicQualified then emitLeaveAtomic (scratch + 11)
  emitLoadLocal (scratch + if returnPrior then 2 else 3) 0

 private partial def emitCompoundAssignment (op : BinaryOp) (target value : Expr)
    (pos : Pos) (depth : Nat) : GenM Unit := do
  let objectType ← ensureModifiableLValue target pos
  let bitField? ← bitFieldMember? target
  let targetType := objectType.toRValue
  let sourceType ← inferExprType value
  let pointerUpdate := targetType.isPointer && (op == .add || op == .sub)
  if pointerUpdate then
    unless sourceType.isInteger do
      codegenError pos "pointer compound assignment requires an integer displacement"
    let pointee := targetType.pointerPointee?.get!
    unless pointee.isObjectType do
      codegenError pos "pointer compound assignment requires a complete object type"
  else
    unless targetType.isInteger && sourceType.isInteger do
      codegenError pos "compound assignment requires integer operands"
    if op == .logicalAnd || op == .logicalOr || op == .eq || op == .ne ||
        op == .lt || op == .le || op == .gt || op == .ge then
      codegenError pos "invalid compound-assignment operator"

  let info ← currentFunction
  let scratch := info.scratchBase + depth
  emitLValueLocation target (depth + 20)
  emitInstruction .readR 0 0 (registerOperand false false 0x06)
    "save compound-assignment lvalue capability"
  emitStoreLocal scratch 0
  emitStoreLocal (scratch + 1) 2
  unless objectType.isAtomicQualified do
    if targetType.isInteger then
      emitForceMemoryRegister 2 2 0 "compound-assignment left operand"
      match bitField? with
      | some member => emitExtractBitField member
      | none => pure ()
    else
      emitInstruction .read 0 0 (operandMemoryRegister 2 2)
        "load pointer compound-assignment left operand"
    emitStoreLocal (scratch + 2) 0
    emitStoreLocal (scratch + 4) 0
  emitExpr value (depth + 20)
  emitMove 1 0
  if objectType.isAtomicQualified then
    emitStoreLocal (scratch + 18) 1
    emitEnterAtomic (scratch + 19)
    emitLoadLocal scratch 0
    emitInstruction .writeR 0 0 (registerOperand false false 0x06)
      "restore atomic compound-assignment lvalue capability"
    emitLoadLocal (scratch + 1) 2
    if targetType.isInteger then
      emitForceMemoryRegister 2 2 0 "atomic compound-assignment left operand"
    else
      emitInstruction .read 0 0 (operandMemoryRegister 2 2)
        "load atomic pointer compound-assignment left operand"
    emitStoreLocal (scratch + 2) 0
    emitStoreLocal (scratch + 4) 0
    emitLoadLocal (scratch + 18) 1

  if pointerUpdate then
    emitLoadLocal (scratch + 2) 0
    let pointee := targetType.pointerPointee?.get!
    emitPointerOffset pointee.wordSize (op == .sub)
  else
    let operationType ←
      if op == .shl || op == .shr then
        promotedExprIntegerType target targetType
      else
        let targetArithmeticType ← promotedExprIntegerType target targetType
        match CType.usualIntegerConversion targetArithmeticType sourceType with
        | some type => pure type
        | none => codegenError pos "internal error computing compound-assignment type"
    let signedOperation := operationType.isSignedInteger
    emitLoadLocal (scratch + 4) 0
    match op with
    | .div | .mod =>
        if signedOperation then emitSignedDivision op (scratch + 4)
        else emitUnsignedDivision op (scratch + 4)
    | .add | .sub | .mul =>
        let opcode := match op with
          | .add => Opcode.add
          | .sub => Opcode.sub
          | _ => Opcode.mul
        if signedOperation then
          emitInstruction opcode 0 0 (operandR 1) "signed compound assignment"
        else
          emitUncheckedIntegerBinary opcode (scratch + 4)
            "unsigned compound assignment modulo 2^32"
    | .shl =>
        if signedOperation then
          emitInstruction .logicalShift 0 0 (operandR 1) "signed compound left shift"
        else
          emitUncheckedIntegerBinary .logicalShift (scratch + 4)
            "unsigned compound left shift modulo 2^32"
    | .shr =>
        emitInstruction .negate 1 0 (operandR 1) "negate compound shift count"
        emitInstruction (if signedOperation then .arithmeticShift else .logicalShift)
          0 0 (operandR 1) "compound right shift"
    | .bitAnd => emitInstruction .and 0 0 (operandR 1) "compound bitwise and"
    | .bitXor => emitInstruction .xor 0 0 (operandR 1) "compound bitwise xor"
    | .bitOr => emitInstruction .or 0 0 (operandR 1) "compound bitwise or"
    | .lt | .le | .gt | .ge | .eq | .ne | .logicalAnd | .logicalOr =>
        codegenError pos "invalid compound-assignment operator"

  emitTargetConversion objectType targetType
  emitStoreLocal (scratch + 3) 0
  emitLoadLocal scratch 0
  emitInstruction .writeR 0 0 (registerOperand false false 0x06)
    "restore compound-assignment lvalue capability"
  emitLoadLocal (scratch + 1) 2
  emitLoadLocal (scratch + 3) 1
  match bitField? with
  | some member =>
      emitStoreBitField member (scratch + 12) "store bit-field compound-assignment result"
      emitStoreLocal (scratch + 3) 0
  | none =>
      emitInstruction .write 0 1 (operandMemoryRegister 2 2)
        "store compound-assignment result"
  if objectType.isAtomicQualified then emitLeaveAtomic (scratch + 19)
  emitLoadLocal (scratch + 3) 0

 private partial def emitLValueLocation (target : Expr) (depth : Nat := 0) : GenM Unit := do
  match target with
  | .variable name pos =>
      emitAddressOfStorage (← lookupStorage name pos)
      emitInstruction .writeR 0 0 (registerOperand false false 0x06) "lvalue base := A2"
      emitInteger 0 "lvalue offset"
      emitMove 2 0
  | .compoundLiteral sourceType initializers _alignment pos =>
      let type ← normalizeType sourceType
      let slot ← allocateAnonymousLocal type
      emitInitializeLocalObject type "compound literal" initializers pos slot none depth
      emitAddressOfStorage (.local slot type false)
      emitInstruction .writeR 0 0 (registerOperand false false 0x06)
        "compound-literal lvalue base := A2"
      emitInteger 0 "compound-literal lvalue offset"
      emitMove 2 0
  | .unary .dereference pointer _ =>
      match ← inferExprType pointer with
      | .pointer _ => pure ()
      | _ => codegenError pointer.pos "dereference operand is not a pointer"
      emitExpr pointer depth
      emitInstruction .writeR 0 0 (registerOperand false false 0x06) "pointer base := A2"
      emitInteger 0 "pointer offset"
      emitMove 2 0
  | .subscript base index pos =>
      let elementType ← match ← inferExprType base with
      | .pointer element | .array element _ => pure element
      | _ => codegenError pos "subscripted value is not a pointer or array"
      let info ← currentFunction
      let scratch := info.scratchBase + depth
      emitExpr base depth
      emitStoreLocal scratch 0
      emitExpr index (depth + 2)
      emitStoreLocal (scratch + 1) 0
      emitLoadLocal scratch 0
      emitInstruction .writeR 0 0 (registerOperand false false 0x06) "array base := A2"
      emitLoadLocal (scratch + 1) 2
      if elementType.wordSize != 1 then
        emitInteger (Int.ofNat elementType.wordSize) "array element width"
        emitInstruction .mul 2 2 (operandR 0) "scale array subscript"
  | .member base name indirect pos =>
      let baseType ← inferExprType base
      let aggregateType ←
        if indirect then
          match baseType with
          | .pointer pointee => pure pointee
          | _ => codegenError pos "'->' requires a pointer to struct or union"
        else pure baseType
      let member ← memberInfo aggregateType name pos
      if indirect then
        emitExpr base depth
        emitInstruction .writeR 0 0 (registerOperand false false 0x06)
          "indirect aggregate base := A2"
        emitInteger (Int.ofNat member.offset) s!"member {name} offset"
        emitMove 2 0
      else
        -- Aggregate rvalues (notably function results and assignment
        -- expressions) are represented internally by an exact ADDR
        -- capability. Lvalue aggregates use the same representation.
        emitExpr base depth
        emitInstruction .writeR 0 0 (registerOperand false false 0x06)
          "aggregate value base := A2"
        emitInteger 0 "aggregate value base offset"
        emitMove 2 0
        if member.offset != 0 then
          if member.offset < 16 then
            emitInstruction .add 2 2 (operandImmediate (Int.ofNat member.offset))
              s!"member {name} offset"
          else
            emitInteger (Int.ofNat member.offset) s!"member {name} offset"
            emitInstruction .add 2 2 (operandR 0) s!"member {name} offset"
  | .genericSelection control associations pos =>
      discard <| inferExprType target
      let selected ← selectGenericAssociation (← inferExprType control) associations pos
      emitLValueLocation selected depth
  | _ => codegenError target.pos "expression is not an assignable lvalue"

 private partial def emitStoreInitializerScalar (target : InitializerSubobject)
    (displayName : String) (slot depth : Nat) (pos : Pos) : GenM Unit := do
  match target.bitWidth with
  | none => emitStoreLocal (slot + target.offset) 0
  | some width =>
      let info ← currentFunction
      let scratch := info.scratchBase + depth
      emitStoreLocal scratch 0
      emitAddressOfStorage (.local (slot + target.offset) .int false)
      emitInstruction .writeR 0 0 (registerOperand false false 0x06)
        s!"{displayName} bit-field base := A2"
      emitInteger 0 s!"{displayName} bit-field word offset"
      emitMove 2 0
      emitLoadLocal scratch 1
      let member : Member := {
        type := target.type, name := displayName, offset := target.offset,
        bitWidth := some width, bitOffset := target.bitOffset, pos := pos }
      emitStoreBitField member scratch s!"initialize {displayName} bit-field"

 private partial def emitInitializeLocalObject (type : CType) (displayName : String)
    (initializer : Initializer Expr) (pos : Pos) (slot : Nat)
    (futureDestination : Option Expr) (depth : Nat := 0) : GenM Unit := do
  if !type.isObjectType then codegenError pos s!"{displayName} has an incomplete object type"
  if type.wordSize > 1023 then
    codegenError pos s!"{displayName} exceeds the MDP ADDR length field"
  let resolution ← resolveInitializer
    (fun value => do pure (some (← inferExprType value)))
    (fun value valuePos => .intLit value .int valuePos)
    (fun name valuePos => .variable name valuePos)
    { type := type, offset := 0 } initializer
  unless resolution.zeroRegions.isEmpty do
    for offset in [0:type.wordSize] do
      let explicitlyInitialized := resolution.actions.any fun action =>
        action.target.bitWidth.isNone && offset >= action.target.offset &&
          offset < action.target.offset + action.target.type.wordSize
      unless explicitlyInitialized do
        let mut zeroType? : Option CType := none
        for region in resolution.zeroRegions do
          if offset >= region.offset && offset < region.offset + region.type.wordSize then
            match ← initializerObjectTypeAt? region.type (offset - region.offset) with
            | some regionType => zeroType? := some regionType
            | none => pure ()
        emitInteger 0 s!"zero-initialize {displayName}"
        match zeroType? with
        | some zeroType => emitTargetConversion zeroType .int
        | none => pure ()
        emitStoreLocal (slot + offset) 0
  for action in resolution.actions do
    let targetType := action.target.type
    let value := action.value
    let rootFutureTarget := action.target.offset == 0 &&
      action.target.type.stripTopQualifiers == type.stripTopQualifiers &&
      resolution.actions.size == 1 && futureDestination.isSome
    if targetType.toRValue.isAggregate then
      match value with
      | .call _ _ (some _) _ | .indirectCall _ _ (some _) _ =>
          if rootFutureTarget then
            modify fun state => { state with futureTarget := futureDestination }
            emitExpr value depth
          else
            emitExpr value depth
            emitCopyAggregateAddressToLocal targetType (slot + action.target.offset)
      | _ =>
          emitExpr value depth
          emitCopyAggregateAddressToLocal targetType (slot + action.target.offset)
    else
      requireValueCompatible targetType value action.pos s!"initializer for {displayName}"
      match value with
      | .call _ _ (some _) _ | .indirectCall _ _ (some _) _ =>
          if rootFutureTarget && targetType.toRValue.isInteger then
            modify fun state => { state with futureTarget := futureDestination }
            emitExpr value depth
          else
            emitExpr value depth
            emitTargetConversion targetType (← inferExprType value)
            emitStoreInitializerScalar action.target displayName slot depth action.pos
      | _ =>
          emitExpr value depth
          emitTargetConversion targetType (← inferExprType value)
          emitStoreInitializerScalar action.target displayName slot depth action.pos

 private partial def emitIndirectCall (callee : Expr) (args : Array Expr)
    (destination : Option Expr) (returnType : CType) (parameters : Array CType)
    (pos : Pos) (depth : Nat) : GenM Unit := do
  match destination with
  | some destinationExpr =>
      let parameterInfos := parameters.map fun type =>
        { type := type, name := "", pos := pos : Parameter }
      emitRemoteCall (some callee) 0 "indirect call" args destinationExpr
        returnType parameterInfos pos depth
      return
  | none => pure ()
  if args.size != parameters.size then
    codegenError pos s!"function pointer expects {parameters.size} arguments, got {args.size}"
  let caller ← currentFunction
  let scratchBase := caller.scratchBase
  let calleeSlot := scratchBase + depth
  let parameterWords := parameterTypeStorageWords parameters
  let returnWords := aggregateResultWords returnType
  let temporaryWords := 1 + parameterWords + returnWords
  let argumentBase := calleeSlot + 1
  let returnBufferSlot := argumentBase + parameterWords
  emitExpr callee (depth + temporaryWords)
  emitStoreLocal calleeSlot 0
  for index in [0:args.size] do
    let parameterType := parameters[index]!
    requireValueCompatible parameterType args[index]!
      args[index]!.pos s!"argument {index + 1} of indirect call"
    let argumentSlot := argumentBase +
      (parameters.toList.take index |>.foldl (fun total type => total + type.wordSize) 0)
    emitExpr args[index]! (depth + temporaryWords)
    if parameterType.toRValue.isAggregate then
      emitCopyAggregateAddressToLocal parameterType argumentSlot
    else
      emitTargetConversion parameterType (← inferExprType args[index]!)
      emitStoreLocal argumentSlot 0
  if returnType.toRValue.isAggregate then
    emitAddressOfStorage (.local returnBufferSlot (.array .int returnType.wordSize) false)
    emitStoreLocal (caller.frameSize + 1) 0
  for index in [0:args.size] do
    let parameterType := parameters[index]!
    let sourceSlot := argumentBase +
      (parameters.toList.take index |>.foldl (fun total type => total + type.wordSize) 0)
    let targetSlot := caller.frameSize + parameterSlotFromTypes
      (← get).aggregates returnType parameters index
    for offset in [0:parameterType.wordSize] do
      emitLoadLocal (sourceSlot + offset) 0
      emitStoreLocal (targetSlot + offset) 0
  emitLoadLocal calleeSlot 2
  emitInstruction .sub 2 2 (operandImmediate 1)
    "decode non-null function pointer CALL-vector index"
  emitInteger (Int.ofNat caller.frameSize) "advance stack frame"
  emitInstruction .add 3 3 (operandR 0) "sp += frame size"
  emitInstruction .call 0 0 (operandR 2) "indirect call through CALL vector index"
  emitInteger (-Int.ofNat caller.frameSize) "restore stack frame"
  emitInstruction .add 3 3 (operandR 0) "sp -= frame size"
  if returnType.toRValue.isAggregate then
    emitAddressOfStorage (.local returnBufferSlot (.array .int returnType.wordSize) false)
  else
    emitMove 0 1
    if returnType.toRValue.isVoid then emitInteger 0 "void indirect-call value"

 private partial def emitRemoteCall (callee : Option Expr) (directId : Nat)
    (displayName : String) (args : Array Expr) (destinationExpr : Expr)
    (returnType : CType) (parameters : Array Parameter) (pos : Pos)
    (depth : Nat) : GenM Unit := do
  let futureTarget := (← get).futureTarget
  modify fun state => { state with futureTarget := none }
  if args.size != parameters.size then
    codegenError pos s!"function '{displayName}' expects {parameters.size} arguments, got {args.size}"
  for index in [0:args.size] do
    requireValueCompatible parameters[index]!.type args[index]!
      args[index]!.pos s!"argument {index + 1} of remote call '{displayName}'"
  if !returnType.toRValue.isInteger && !returnType.toRValue.isVoid &&
      !returnType.toRValue.isAggregate then
    codegenError pos "remote pointer returns require MDC bulk-data marshalling"
  if returnType.toRValue.isAggregate && returnType.wordSize + 3 > 1020 then
    codegenError pos "remote aggregate result exceeds the MDP queue message limit"
  if returnType.toRValue.isAggregate then
    requireRemoteAggregateWords returnType pos
  if futureTarget.isSome && returnType.toRValue.isVoid then
    codegenError pos "void remote call cannot initialize a future destination"
  let mut parameterIndex := 0
  let mut minimumMessageWords := 7
  while parameterIndex < parameters.size do
    if isBulkPairAt parameters parameterIndex then
      minimumMessageWords := minimumMessageWords + 1
      parameterIndex := parameterIndex + 2
    else
      let parameter := parameters[parameterIndex]!
      if !parameter.type.toRValue.isInteger && !parameter.type.toRValue.isAggregate then
        codegenError parameter.pos
          "remote pointers must be int length, int *data parameter pairs"
      if parameter.type.toRValue.isAggregate then
        requireRemoteAggregateWords parameter.type parameter.pos
      minimumMessageWords := minimumMessageWords + parameter.type.wordSize + 1
      parameterIndex := parameterIndex + 1
  if minimumMessageWords > 1020 then
    codegenError pos "remote argument envelopes exceed the MDP queue message limit"
  let caller ← currentFunction
  let scratchBase := caller.scratchBase
  let destinationSlot := scratchBase + depth
  let argumentBase := destinationSlot + 1
  let argumentWords := parameterStorageWords parameters
  let mailboxSlot := argumentBase + argumentWords
  let messageLengthSlot := mailboxSlot + 1
  let loopSlot := mailboxSlot + 2
  let calleeSlot := loopSlot + 2
  let aggregateReturnWords := aggregateResultWords returnType
  let resultBufferSlot := destinationSlot + argumentWords + 16
  let reserved := argumentWords + aggregateReturnWords + 16
  match callee with
  | some expression =>
      emitExpr expression (depth + reserved)
      emitStoreLocal calleeSlot 0
  | none => pure ()
  emitExpr destinationExpr (depth + reserved)
  emitLogicalRankToNnr (loopSlot + 1)
  emitStoreLocal destinationSlot 0
  for index in [0:args.size] do
    let parameterType := parameters[index]!.type
    let argumentSlot := argumentBase +
      (parameters.toList.take index |>.foldl
        (fun total parameter => total + parameter.type.wordSize) 0)
    emitExpr args[index]! (depth + reserved)
    if parameterType.toRValue.isAggregate then
      emitCopyAggregateAddressToLocal parameterType argumentSlot
    else
      emitTargetConversion parameterType (← inferExprType args[index]!)
      emitStoreLocal argumentSlot 0

  -- Seven fixed words precede the historical logical-argument
  -- envelopes. An (int length, int *data) source pair becomes one
  -- logical argument [length, data...], exactly as in MDC.
  emitInteger 7 "initial MDC message length"
  emitStoreLocal messageLengthSlot 0
  parameterIndex := 0
  while parameterIndex < parameters.size do
    if isBulkPairAt parameters parameterIndex then
      let lengthSlot := argumentBase +
        (parameters.toList.take parameterIndex |>.foldl
          (fun total parameter => total + parameter.type.wordSize) 0)
      emitLoadLocal lengthSlot 0
      emitInstruction .less 0 0 (operandImmediate 0)
        "MDC bulk data length is negative"
      emitRetagInt
      emitConditionalBranch .branchNotZero mdcArgumentErrorHandlerLabel
      emitLoadLocal lengthSlot 1
      emitLoadLocal messageLengthSlot 0
      emitInstruction .add 0 0 (operandR 1) "add MDC bulk data length"
      emitInstruction .add 0 0 (operandImmediate 1) "add MDC bulk length word"
      emitStoreLocal messageLengthSlot 0
      parameterIndex := parameterIndex + 2
    else
      let envelopeWords := parameters[parameterIndex]!.type.wordSize + 1
      emitLoadLocal messageLengthSlot 0
      emitInstruction .add 0 0 (operandImmediate (Int.ofNat envelopeWords))
        (if parameters[parameterIndex]!.type.toRValue.isAggregate then
          "add aggregate MDC envelope" else "add scalar MDC envelope")
      emitStoreLocal messageLengthSlot 0
      parameterIndex := parameterIndex + 1

  emitLoadLocal messageLengthSlot 1
  emitInteger 1020 "maximum committed MDC queue message length"
  emitInstruction .greater 0 1 (operandR 0)
    "MDC argument envelope exceeds queue limit"
  emitRetagInt
  emitConditionalBranch .branchNotZero mdcArgumentErrorHandlerLabel

  if !returnType.toRValue.isVoid then
    match futureTarget with
    | some target =>
        let targetType ← ensureModifiableLValue target target.pos
        if returnType.toRValue.isAggregate then
          unless targetType.stripTopQualifiers == returnType.stripTopQualifiers do
            codegenError target.pos
              "remote aggregate future destination must have the exact result type"
        else if !targetType.toRValue.isInteger then
          codegenError target.pos "only integer lvalues can hold scalar MDC futures"
        emitLValueLocation target (depth + reserved)
        emitPhysicalAddressFromA2R2
        emitStoreLocal mailboxSlot 0
        emitLoadLocal mailboxSlot 0
        emitSetAddressRegisterFromInteger 2 returnType.wordSize
        for offset in [0:returnType.wordSize] do
          emitConstantWord (tagged .future 0) "unresolved lvalue future"
          if offset < 64 then
            emitInstruction .write (offset / 16) 0 (operandMemoryImmediate offset 2)
              s!"initialize future destination word {offset}"
          else
            emitMove 1 0
            emitInteger (Int.ofNat offset) "future destination offset"
            emitInstruction .write 0 1 (operandMemoryRegister 0 2)
              s!"initialize future destination word {offset}"
    | none =>
        if returnType.toRValue.isAggregate then
          emitAddressOfStorage (.local resultBufferSlot
            (.array .int returnType.wordSize) false)
          emitPointerBaseAsInteger
          emitStoreLocal mailboxSlot 0
        else
          emitSetAddressRegisterConstant 2 heapPointerAddress 1
          emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
            "allocate remote-result mailbox"
          emitStoreLocal mailboxSlot 0
          emitInstruction .add 0 0
            (operandImmediate (Int.ofNat returnType.wordSize)) "advance heap pointer"
          emitInstruction .write 0 0 (operandMemoryImmediate 0 2)
            "commit heap pointer"
        emitLoadLocal mailboxSlot 0
        emitSetAddressRegisterFromInteger 2 returnType.wordSize
        for offset in [0:returnType.wordSize] do
          emitConstantWord (tagged .future 0) "unresolved remote result"
          if offset < 64 then
            emitInstruction .write (offset / 16) 0 (operandMemoryImmediate offset 2)
              s!"initialize remote-result future word {offset}"
          else
            emitMove 1 0
            emitInteger (Int.ofNat offset) "remote-result future offset"
            emitInstruction .write 0 1 (operandMemoryRegister 0 2)
              s!"initialize remote-result future word {offset}"
  else
    emitInteger 0 "no return mailbox"
    emitStoreLocal mailboxSlot 0

  emitLoadLocal destinationSlot 0
  emitInstruction .send 0 0 (operandR 0) "MDC routing word"
  emitDynamicMessageHeader spawnHandlerLabel messageLengthSlot
  emitInstruction .send 0 0 (operandR 0) "MDC spawn header"
  match callee with
  | some _ =>
      emitLoadLocal calleeSlot 0
      emitInstruction .sub 0 0 (operandImmediate 1)
        "decode remote function pointer CALL-vector index"
  | none => emitInteger (Int.ofNat directId) s!"function id for {displayName}"
  emitInstruction .send 0 0 (operandR 0) "MDC function id"
  emitConstantWord (tagged .sym 0) "receiver temporary storage"
  emitInstruction .send 0 0 (operandR 0) "MDC receiver temporary"
  emitInteger (if !returnType.toRValue.isVoid then Int.ofNat returnType.wordSize else -1)
    "MDC return length"
  emitInstruction .send 0 0 (operandR 0) "MDC return length"
  emitInstruction .readR 0 0 (registerOperand false false 0x14)
    "return computer"
  emitInstruction .send 0 0 (operandR 0) "MDC return computer"
  emitLoadLocal mailboxSlot 0
  emitInstruction .send 0 0 (operandR 0) "MDC return address"
  let logicalArgumentCount := remoteLogicalArgumentCount parameters
  emitInteger (Int.ofNat logicalArgumentCount) "MDC logical argument count"
  emitInstruction (if logicalArgumentCount == 0 then .sendEnd else .send) 0 0 (operandR 0)
    "MDC argument count"
  parameterIndex := 0
  let mut logicalIndex := 0
  while parameterIndex < parameters.size do
    let lastLogical := logicalIndex + 1 == logicalArgumentCount
    if isBulkPairAt parameters parameterIndex then
      let lengthSlot := argumentBase +
        (parameters.toList.take parameterIndex |>.foldl
          (fun total parameter => total + parameter.type.wordSize) 0)
      let pointerSlot := lengthSlot + 1
      if lastLogical then
        let nonemptyLabel ← freshLabel "mdc.bulk.nonempty"
        let bulkDoneLabel ← freshLabel "mdc.bulk.done"
        emitLoadLocal lengthSlot 0
        emitConditionalBranch .branchNotZero nonemptyLabel
        emitLoadLocal lengthSlot 0
        emitInstruction .sendEnd 0 0 (operandR 0)
          s!"MDC bulk argument {logicalIndex} empty length"
        emitBranch .branch 0 bulkDoneLabel
        defineLabel nonemptyLabel
        emitLoadLocal lengthSlot 0
        emitInstruction .send 0 0 (operandR 0)
          s!"MDC bulk argument {logicalIndex} length"
        emitLoadLocal pointerSlot 0
        emitInstruction .writeR 0 0 (registerOperand false false 0x06)
          "MDC bulk source := A2"
        emitInteger 0 "MDC bulk index"
        emitStoreLocal loopSlot 0
        let bulkLoopLabel ← freshLabel "mdc.bulk.loop"
        let lastDataLabel ← freshLabel "mdc.bulk.last"
        defineLabel bulkLoopLabel
        emitLoadLocal lengthSlot 1
        emitLoadLocal loopSlot 0
        emitInstruction .add 0 0 (operandImmediate 1) "next MDC bulk index"
        emitInstruction .equalData 0 0 (operandR 1) "last MDC bulk word"
        emitRetagInt
        emitConditionalBranch .branchNotZero lastDataLabel
        emitLoadLocal loopSlot 0
        emitInstruction .read 1 0 (operandMemoryRegister 0 2)
          "load MDC bulk data"
        emitInstruction .send 0 0 (operandR 1) "send MDC bulk data"
        emitLoadLocal loopSlot 0
        emitInstruction .add 0 0 (operandImmediate 1) "advance MDC bulk index"
        emitStoreLocal loopSlot 0
        emitBranch .branch 0 bulkLoopLabel
        defineLabel lastDataLabel
        emitLoadLocal loopSlot 0
        emitInstruction .read 1 0 (operandMemoryRegister 0 2)
          "load last MDC bulk data"
        emitInstruction .sendEnd 0 0 (operandR 1) "send last MDC bulk data"
        defineLabel bulkDoneLabel
      else
        emitLoadLocal lengthSlot 0
        emitInstruction .send 0 0 (operandR 0)
          s!"MDC bulk argument {logicalIndex} length"
        emitLoadLocal pointerSlot 0
        emitInstruction .writeR 0 0 (registerOperand false false 0x06)
          "MDC bulk source := A2"
        emitInteger 0 "MDC bulk index"
        emitStoreLocal loopSlot 0
        let bulkLoopLabel ← freshLabel "mdc.bulk.loop"
        let bulkDoneLabel ← freshLabel "mdc.bulk.done"
        defineLabel bulkLoopLabel
        emitLoadLocal lengthSlot 1
        emitLoadLocal loopSlot 0
        emitInstruction .less 0 0 (operandR 1) "MDC bulk index < length"
        emitRetagInt
        emitConditionalBranch .branchZero bulkDoneLabel
        emitLoadLocal loopSlot 0
        emitInstruction .read 1 0 (operandMemoryRegister 0 2)
          "load MDC bulk data"
        emitInstruction .send 0 0 (operandR 1) "send MDC bulk data"
        emitLoadLocal loopSlot 0
        emitInstruction .add 0 0 (operandImmediate 1) "advance MDC bulk index"
        emitStoreLocal loopSlot 0
        emitBranch .branch 0 bulkLoopLabel
        defineLabel bulkDoneLabel
      parameterIndex := parameterIndex + 2
    else
      let parameterType := parameters[parameterIndex]!.type
      let argumentSlot := argumentBase +
        (parameters.toList.take parameterIndex |>.foldl
          (fun total parameter => total + parameter.type.wordSize) 0)
      emitInteger (Int.ofNat parameterType.wordSize)
        s!"MDC argument {logicalIndex} length"
      emitInstruction .send 0 0 (operandR 0)
        s!"MDC argument {logicalIndex} length"
      if parameterType.toRValue.isAggregate then
        for offset in [0:parameterType.wordSize] do
          emitLoadLocal (argumentSlot + offset) 0
          let isLastWord := offset + 1 == parameterType.wordSize
          emitInstruction (if lastLogical && isLastWord then .sendEnd else .send)
            0 0 (operandR 0) s!"MDC aggregate argument {logicalIndex} word {offset}"
      else
        emitLoadLocal argumentSlot 0
        emitInstruction (if lastLogical then .sendEnd else .send)
          0 0 (operandR 0) s!"MDC scalar argument {logicalIndex} data"
      parameterIndex := parameterIndex + 1
    logicalIndex := logicalIndex + 1

  if !returnType.toRValue.isVoid then
    match futureTarget with
    | some _ =>
        if returnType.toRValue.isAggregate then
          emitLoadLocal mailboxSlot 0
          emitAddressWordFromInteger returnType.wordSize
        else
          emitConstantWord (tagged .future 0) "deferred MDC expression result"
    | none =>
        emitLoadLocal mailboxSlot 0
        emitSetAddressRegisterFromInteger 2 returnType.wordSize
        let waitLabel ← freshLabel "remote.wait"
        defineLabel waitLabel
        emitInstruction .readTag 0 0 (operandMemoryImmediate 0 2)
          "poll remote-result tag"
        emitInstruction .sub 0 0 (operandImmediate (Int.ofNat Tag.future.encoding))
          "remote result still FUT"
        emitConditionalBranch .branchZero waitLabel
        if returnType.toRValue.isAggregate then
          emitLoadLocal mailboxSlot 0
          emitAddressWordFromInteger returnType.wordSize
        else
          emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
            "load resolved remote result"
  else
    emitInteger 0 "void remote call"
  emitMove 1 0
  emitSetAddressRegisterConstant 2 resultBase 1
  emitMove 0 1

end

private def emitReturn (value : Option Expr) (pos : Pos) : GenM Unit := do
  let info ← currentFunction
  match info.function.returnType.toRValue, value with
  | .void, some _ => codegenError pos "void function cannot return a value"
  | .int, none | .boolType, none | .plainChar, none | .integer .., none =>
      codegenError pos "integer-returning function must return a value"
  | .pointer _, none => codegenError pos "pointer-returning function must return a value"
  | .function .., _ => codegenError pos "functions cannot return a function"
  | .array .., _ => codegenError pos "functions cannot return an array"
  | .structType .., none | .unionType .., none =>
      codegenError pos "aggregate-returning function must return a value"
  | .void, none => emitInteger 0 "void return value"
  | .int, some expression | .boolType, some expression |
      .plainChar, some expression | .integer .., some expression =>
      requireValueCompatible info.function.returnType expression pos "return"
      emitExpr expression
      emitTargetConversion info.function.returnType (← inferExprType expression)
  | .pointer _, some expression =>
      requireValueCompatible info.function.returnType expression pos "return"
      emitExpr expression
      emitTargetConversion info.function.returnType (← inferExprType expression)
  | aggregate@(.structType ..), some expression |
      aggregate@(.unionType ..), some expression =>
      requireValueCompatible info.function.returnType expression pos "return"
      let scratch := info.scratchBase
      emitExpr expression 4
      emitStoreLocal scratch 0
      emitLoadLocal 1 0
      emitStoreLocal (scratch + 1) 0
      for offset in [0:aggregate.wordSize] do
        emitLoadLocal scratch 0
        emitInstruction .writeR 0 0 (registerOperand false false 0x06)
          "aggregate return source := A2"
        emitInteger (Int.ofNat offset) "aggregate return source offset"
        emitInstruction .read 1 0 (operandMemoryRegister 0 2)
          "load aggregate return word"
        emitLoadLocal (scratch + 1) 0
        emitInstruction .writeR 0 0 (registerOperand false false 0x06)
          "aggregate return destination := A2"
        emitInteger (Int.ofNat offset) "aggregate return destination offset"
        emitInstruction .write 0 1 (operandMemoryRegister 0 2)
          "store aggregate return word"
      emitLoadLocal (scratch + 1) 0
  | .enumType .., _ | .qualified .., _ =>
      codegenError pos "internal error: non-canonical function return type"
  emitMove 1 0
  emitSetAddressRegisterConstant 2 resultBase 1
  emitLoadLocal 0 2
  emitMove 0 1
  emitInstruction .loadIp 0 0 (operandR 2) "return"

private partial def staticObjectIsModifiable : CType → Bool
  | .qualified _ qualifiers => !qualifiers.isConst
  | .array element _ => staticObjectIsModifiable element
  | _ => true

private partial def constantInitializerReferences :
    Initializer ConstantInitializer → Array (String × Bool × Pos)
  | .value (.functionDesignator name pos) _ => #[(name, true, pos)]
  | .value (.objectDesignator name _ pos) _ => #[(name, false, pos)]
  | .value (.integer _) _ | .stringLiteral .. => #[]
  | .list elements _ => elements.foldl (fun references element =>
      references ++ constantInitializerReferences element.2) #[]

private def emitAutomaticDeclaration (type : CType) (name : String)
    (initializer : Option (Initializer Expr)) (alignment : AlignmentSpec) (pos : Pos)
    (isRegister : Bool) : GenM Unit := do
  let slot ← declareLocal type name pos isRegister alignment.value
  match initializer with
  | some value =>
      emitInitializeLocalObject type s!"local '{name}'" value pos slot
        (some (.variable name pos))
  | none =>
      if !type.isObjectType then codegenError pos s!"local '{name}' has an incomplete object type"
      if type.wordSize > 1023 then
        codegenError pos s!"local '{name}' exceeds the MDP ADDR length field"

private partial def emitStmt (statement : Stmt) : GenM Unit := do
  match statement with
  | .block statements _ =>
      pushScope
      for stmt in statements do emitStmt stmt
      popScope
  | .declarationGroup declarations _ =>
      for declaration in declarations do emitStmt declaration
  | .declaration type name initializers alignment pos =>
      emitAutomaticDeclaration type name initializers alignment pos false
  | .registerDeclaration type name initializers pos =>
      emitAutomaticDeclaration type name initializers {} pos true
  | .staticDeclaration type name backingName initializer _alignment pos =>
      if (← get).currentFunction.any FunctionInfo.inlineDefinition then
        if staticObjectIsModifiable type then
          codegenError pos
            s!"external inline definition may not define modifiable static object '{name}'"
        match initializer with
        | some value =>
            for (reference, isFunction, referencePos) in
                constantInitializerReferences value do
              if isFunction then
                match ← functionInfo? reference with
                | some _ => pure ()
                | none => codegenError referencePos s!"use of undefined function '{reference}'"
              else if reference != name then
                match ← lookupStorage? reference with
                | some _ => pure ()
                | none => codegenError referencePos s!"use of undeclared identifier '{reference}'"
        | none => pure ()
      if !type.isObjectType then codegenError pos s!"'{name}' has an incomplete object type"
      if type.wordSize > 1023 then
        codegenError pos s!"object '{name}' exceeds the MDP ADDR length field"
      declareStaticLocal type name backingName pos
  | .externDeclaration type name _alignment pos =>
      declareExternObject type name pos
  | .functionDeclaration type name pos =>
      declareBlockFunction type name pos
  | .expression value _ =>
      match value with
      | some (.assign target call@(.call _ _ (some _) _) _)
      | some (.assign target call@(.indirectCall _ _ (some _) _) _) =>
          modify fun state => { state with futureTarget := some target }
          emitExpr call
      | some expression => emitExpr expression
      | none => pure ()
  | .ite condition thenBranch elseBranch _ =>
      let elseLabel ← freshLabel "if.else"
      let endLabel ← freshLabel "if.end"
      let conditionType ← inferExprType condition
      unless conditionType.isInteger || conditionType.isPointer do
        codegenError condition.pos "if condition must have scalar type"
      emitExpr condition
      if conditionType.isPointer then emitNormalizeBoolValue conditionType
      emitConditionalBranch .branchZero elseLabel
      emitStmt thenBranch
      emitBranch .branch 0 endLabel
      defineLabel elseLabel
      match elseBranch with | some branch => emitStmt branch | none => pure ()
      defineLabel endLabel
  | .whileLoop condition body _ =>
      let conditionLabel ← freshLabel "while.condition"
      let endLabel ← freshLabel "while.end"
      let state ← get
      defineLabel conditionLabel
      let conditionType ← inferExprType condition
      unless conditionType.isInteger || conditionType.isPointer do
        codegenError condition.pos "while condition must have scalar type"
      emitExpr condition
      if conditionType.isPointer then emitNormalizeBoolValue conditionType
      emitConditionalBranch .branchZero endLabel
      modify fun current => { current with
        breakTarget := some endLabel
        continueTarget := some conditionLabel }
      emitStmt body
      modify fun current => { current with
        breakTarget := state.breakTarget
        continueTarget := state.continueTarget }
      emitBranch .branch 0 conditionLabel
      defineLabel endLabel
  | .doWhileLoop body condition _ =>
      let bodyLabel ← freshLabel "do.body"
      let conditionLabel ← freshLabel "do.condition"
      let endLabel ← freshLabel "do.end"
      let state ← get
      defineLabel bodyLabel
      modify fun current => { current with
        breakTarget := some endLabel
        continueTarget := some conditionLabel }
      emitStmt body
      modify fun current => { current with
        breakTarget := state.breakTarget
        continueTarget := state.continueTarget }
      defineLabel conditionLabel
      let conditionType ← inferExprType condition
      unless conditionType.isInteger || conditionType.isPointer do
        codegenError condition.pos "do-while condition must have scalar type"
      emitExpr condition
      if conditionType.isPointer then emitNormalizeBoolValue conditionType
      emitConditionalBranch .branchNotZero bodyLabel
      defineLabel endLabel
  | .forLoop init condition step body _ =>
      let conditionLabel ← freshLabel "for.condition"
      let stepLabel ← freshLabel "for.step"
      let endLabel ← freshLabel "for.end"
      pushScope
      match init with | some statement => emitStmt statement | none => pure ()
      defineLabel conditionLabel
      match condition with
      | some expression =>
          let conditionType ← inferExprType expression
          unless conditionType.isInteger || conditionType.isPointer do
            codegenError expression.pos "for condition must have scalar type"
          emitExpr expression
          if conditionType.isPointer then emitNormalizeBoolValue conditionType
          emitConditionalBranch .branchZero endLabel
      | none => pure ()
      let state ← get
      modify fun current => { current with
        breakTarget := some endLabel
        continueTarget := some stepLabel }
      emitStmt body
      modify fun current => { current with
        breakTarget := state.breakTarget
        continueTarget := state.continueTarget }
      defineLabel stepLabel
      match step with | some expression => emitExpr expression | none => pure ()
      emitBranch .branch 0 conditionLabel
      defineLabel endLabel
      popScope
  | .switchStmt value body _ =>
      let info ← currentFunction
      let scratch := info.scratchBase
      let valueType ← inferExprType value
      unless valueType.isInteger do
        codegenError value.pos "switch expression must have integer type"
      emitExpr value 1
      emitStoreLocal scratch 0
      let endLabel ← freshLabel "switch.end"
      let switchLabels := collectSwitchLabels body
      let mut codeLabels : List (Pos × String) := []
      let mut defaultLabel : Option String := none
      let mut seenValues : List Int := []
      for item in switchLabels do
        let label ← freshLabel (if item.1.isSome then "switch.case" else "switch.default")
        match item.1 with
        | some caseValue =>
            if seenValues.contains caseValue then
              codegenError item.2 s!"duplicate switch case value {caseValue}"
            seenValues := caseValue :: seenValues
            emitLoadLocal scratch 1
            emitInteger caseValue "switch case value"
            emitInstruction .equalData 0 1 (operandR 0) "switch case comparison"
            emitRetagInt
            emitConditionalBranch .branchNotZero label
        | none =>
            if defaultLabel.isSome then
              codegenError item.2 "multiple default labels in switch"
            defaultLabel := some label
        codeLabels := (item.2, label) :: codeLabels
      emitBranch .branch 0 (defaultLabel.getD endLabel)
      let state ← get
      modify fun current => { current with
        breakTarget := some endLabel
        switchCaseLabels := codeLabels }
      emitStmt body
      modify fun current => { current with
        breakTarget := state.breakTarget
        switchCaseLabels := state.switchCaseLabels }
      defineLabel endLabel
  | .caseLabel _ body pos =>
      match ← switchCaseCodeLabel? pos with
      | some label =>
          defineLabel label pos
          emitStmt body
      | none => codegenError pos "case label is not within a switch statement"
  | .defaultLabel body pos =>
      match ← switchCaseCodeLabel? pos with
      | some label =>
          defineLabel label pos
          emitStmt body
      | none => codegenError pos "default label is not within a switch statement"
  | .returnStmt value pos => emitReturn value pos
  | .breakStmt pos =>
      match (← get).breakTarget with
      | some target => emitBranch .branch 0 target
      | none => codegenError pos "break statement is not inside a loop"
  | .continueStmt pos =>
      match (← get).continueTarget with
      | some target => emitBranch .branch 0 target
      | none => codegenError pos "continue statement is not inside a loop"
  | .labeled name body pos =>
      defineLabel (← sourceCodeLabel name) pos
      emitStmt body
  | .gotoStmt name _ =>
      emitBranch .branch 0 (← sourceCodeLabel name)

private def emitRecordBulkAllocation : GenM Unit := do
  -- Entry is the allocated physical block base in R0. The process header owns
  -- a compact vector of blocks so suspension can retain them and terminal
  -- completion can return every block to the node-local free list.
  emitStoreLocal 10 0
  emitLoadLocal 10 1
  emitLoadLocal processBulkCountSlot 0
  emitMove 2 0
  emitInteger (Int.ofNat processBulkListSlot) "MDC bulk-list base slot"
  emitInstruction .add 0 2 (operandR 0) "MDC bulk-list slot"
  emitInstruction .add 0 3 (operandR 0) "MDC bulk-list frame offset"
  emitInstruction .write 0 1 (operandMemoryRegister 0 1)
    "record MDC bulk allocation"
  emitLoadLocal processBulkCountSlot 0
  emitInstruction .add 0 0 (operandImmediate 1) "increment MDC bulk allocation count"
  emitStoreLocal processBulkCountSlot 0
  emitLoadLocal 10 0

private def emitReclaimMdcAllocations : GenM Unit := do
  -- Recycle fixed 1024-word payload blocks first. Slot 10 is the current block
  -- base and slot 11 is the reclaim-loop index; argument unmarshalling no
  -- longer needs either scratch location after the C function returns.
  emitInteger 0 "first MDC bulk allocation to reclaim"
  emitStoreLocal 11 0
  let loopLabel ← freshLabel "mdc.reclaim.bulk.loop"
  let bulkDoneLabel ← freshLabel "mdc.reclaim.bulk.done"
  defineLabel loopLabel
  emitLoadLocal processBulkCountSlot 1
  emitLoadLocal 11 0
  emitInstruction .less 0 0 (operandR 1) "bulk reclaim index < count"
  emitRetagInt
  emitConditionalBranch .branchZero bulkDoneLabel
  emitLoadLocal 11 0
  emitMove 2 0
  emitInteger (Int.ofNat processBulkListSlot) "MDC bulk-list base slot"
  emitInstruction .add 0 2 (operandR 0) "MDC bulk-list slot"
  emitInstruction .add 0 3 (operandR 0) "MDC bulk-list frame offset"
  emitInstruction .read 0 0 (operandMemoryRegister 0 1)
    "load reclaimed MDC bulk block"
  emitStoreLocal 10 0
  emitSetAddressRegisterConstant 2 bulkFreeHeadAddress 1
  emitInstruction .read 2 0 (operandMemoryImmediate 0 2)
    "load MDC bulk free-list head"
  emitLoadLocal 10 0
  emitAddressWordFromInteger 1
  emitInstruction .writeR 0 0 (registerOperand false false 0x06)
    "reclaimed MDC bulk block := A2"
  emitInstruction .write 0 2 (operandMemoryImmediate 0 2)
    "link reclaimed MDC bulk block"
  emitLoadLocal 10 1
  emitSetAddressRegisterConstant 2 bulkFreeHeadAddress 1
  emitInstruction .write 0 1 (operandMemoryImmediate 0 2)
    "publish MDC bulk free-list head"
  emitLoadLocal 11 0
  emitInstruction .add 0 0 (operandImmediate 1) "next MDC bulk allocation"
  emitStoreLocal 11 0
  emitBranch .branch 0 loopLabel
  defineLabel bulkDoneLabel

  -- The process block is fixed-size and can therefore use an independent
  -- intrusive free list. After block[0] is overwritten no further A1-relative
  -- access is permitted on this path.
  emitAddressRegisterBaseAsInteger 1
  emitStoreLocal 10 0
  emitSetAddressRegisterConstant 2 processFreeHeadAddress 1
  emitInstruction .read 2 0 (operandMemoryImmediate 0 2)
    "load MDC process free-list head"
  emitLoadLocal 10 0
  emitAddressWordFromInteger 1
  emitInstruction .writeR 0 0 (registerOperand false false 0x06)
    "reclaimed MDC process block := A2"
  emitInstruction .write 0 2 (operandMemoryImmediate 0 2)
    "link reclaimed MDC process block"
  emitLoadLocal 10 1
  emitSetAddressRegisterConstant 2 processFreeHeadAddress 1
  emitInstruction .write 0 1 (operandMemoryImmediate 0 2)
    "publish MDC process free-list head"

private def emitSendScratchLoad (slot destination : Nat) : GenM Unit := do
  -- R3 is the selected execution context's retry-frame base. A0 addressing is
  -- absolute throughout compiler-generated code, so its architectural value
  -- can safely park the pre-fault R0 while these accesses use register offsets.
  let addressRegister := if destination == 0 then 2 else 0
  emitMove addressRegister 3
  if slot != 0 then
    emitInstruction .add addressRegister addressRegister
      (operandImmediate (Int.ofNat slot)) s!"SEND retry-frame slot {slot}"
  emitInstruction .read destination 0
    (operandMemoryRegister addressRegister 0)
    s!"load SEND retry frame[{slot}], r{destination}"

private def emitSendScratchStore (slot source : Nat) : GenM Unit := do
  let addressRegister := if source == 0 then 2 else 0
  emitMove addressRegister 3
  if slot != 0 then
    emitInstruction .add addressRegister addressRegister
      (operandImmediate (Int.ofNat slot)) s!"SEND retry-frame slot {slot}"
  emitInstruction .write 0 source
    (operandMemoryRegister addressRegister 0)
    s!"store r{source}, SEND retry frame[{slot}]"

private def emitSendContextEntry (base : Nat) (commonLabel : String) : GenM Unit := do
  -- The inline context-selection branches reach this code without touching
  -- R1-R3. Save them into entry-only slots before using any of them as scratch.
  for (source, slot) in [(1, 13), (2, 14), (3, 15)] do
    emitInteger (Int.ofNat (base + slot)) s!"SEND entry slot {slot}"
    emitInstruction .write 0 source (operandMemoryRegister 0 0)
      s!"save entry r{source}"
  emitInstruction .readR 1 0 (registerOperand false false 0x04)
    "recover entry R0 parked in A0"
  emitInteger (Int.ofNat (base + 12)) "SEND entry slot 12"
  emitInstruction .write 0 1 (operandMemoryRegister 0 0) "save entry r0"
  emitInteger (Int.ofNat base) "selected SEND retry-frame base"
  emitMove 3 0
  emitBranch .branch 0 commonLabel

private def emitSendFaultRegisters (backgroundRelative : Bool) : GenM Unit := do
  emitInstruction .readR 1 0 (registerOperand backgroundRelative false 0x0e)
    "save faulting SEND operand 0"
  emitSendScratchStore 9 1
  emitInstruction .readR 1 0 (registerOperand backgroundRelative false 0x0f)
    "save faulting SEND operand 1"
  emitSendScratchStore 10 1
  emitInstruction .readR 1 0 (registerOperand backgroundRelative false 0x0d)
    "save faulting SEND instruction"
  emitSendScratchStore 11 1

private def emitSendFirBitBranch (mask : Nat) (target : String) : GenM Unit := do
  emitSendScratchLoad 11 1
  emitInteger (Int.ofNat mask) s!"SEND FIR mask 0x{toHex 4 mask}"
  emitInstruction .and 0 1 (operandR 0) "test SEND FIR bit"
  emitConditionalBranch .branchNotZero target

private def emitSendRetry (opcode : Opcode) (priority : Nat)
    (twoWords : Bool) (cleanupLabel : String) : GenM Unit := do
  if twoWords then emitSendScratchLoad 10 1
  emitSendScratchLoad 9 0
  emitInstruction opcode priority (if twoWords then 1 else 0) (operandR 0)
    s!"retry faulting {repr opcode}, priority {priority}"
  emitBranch .branch 0 cleanupLabel

private def emitSendFaultHandler : GenM Unit := do
  defineLabel sendFaultHandlerLabel
  let backgroundEntry ← freshLabel "send.fault.background"
  let priority1Entry ← freshLabel "send.fault.priority1"
  let commonEntry ← freshLabel "send.fault.common"
  let saveBackgroundFault ← freshLabel "send.fault.save.background"
  let faultSaved ← freshLabel "send.fault.saved"
  let countFault ← freshLabel "send.fault.count"
  let retryTwo ← freshLabel "send.fault.retry.two"
  let retrySingleEnd ← freshLabel "send.fault.retry.single.end"
  let retrySinglePriority1 ← freshLabel "send.fault.retry.single.p1"
  let retrySingleEndPriority1 ← freshLabel "send.fault.retry.single.end.p1"
  let retryTwoEnd ← freshLabel "send.fault.retry.two.end"
  let retryTwoPriority1 ← freshLabel "send.fault.retry.two.p1"
  let retryTwoEndPriority1 ← freshLabel "send.fault.retry.two.end.p1"
  let retrySendPriority0 ← freshLabel "send.fault.instruction.send.p0"
  let retrySendPriority1 ← freshLabel "send.fault.instruction.send.p1"
  let retrySendEndPriority0 ← freshLabel "send.fault.instruction.sende.p0"
  let retrySendEndPriority1 ← freshLabel "send.fault.instruction.sende.p1"
  let retrySend2Priority0 ← freshLabel "send.fault.instruction.send2.p0"
  let retrySend2Priority1 ← freshLabel "send.fault.instruction.send2.p1"
  let retrySend2EndPriority0 ← freshLabel "send.fault.instruction.send2e.p0"
  let retrySend2EndPriority1 ← freshLabel "send.fault.instruction.send2e.p1"
  let cleanup ← freshLabel "send.fault.cleanup"

  -- The vector is unchecked, permitting A0 to hold any tagged R0 value. Set I
  -- before touching shared state, then choose one of three disjoint frames.
  emitInstruction .writeR 0 0 (registerOperand false false 0x04)
    "park fault-context R0 in reserved A0"
  emitConstantWord (boolean true) "mask dispatch during SEND recovery"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1a) "I := true"
  emitInstruction .readR 0 0 (registerOperand false false 0x19)
    "select background SEND retry frame"
  emitInlineBranch .branchNotZero 0 backgroundEntry
  emitInstruction .readR 0 0 (registerOperand false false 0x18)
    "select priority SEND retry frame"
  emitInlineBranch .branchNotZero 0 priority1Entry

  emitSendContextEntry sendRetryPriority0Base commonEntry
  defineLabel priority1Entry
  emitSendContextEntry sendRetryPriority1Base commonEntry
  defineLabel backgroundEntry
  emitSendContextEntry sendRetryBackgroundBase commonEntry

  defineLabel commonEntry
  emitSendScratchLoad 0 0
  emitConditionalBranch .branchNotZero countFault

  -- First entry owns the continuation and complete register image. Re-entry
  -- after another full-buffer fault leaves these slots untouched.
  for register in [0:4] do
    emitSendScratchLoad (12 + register) 1
    emitSendScratchStore (1 + register) 1
  for (register, slot) in [(5, 5), (6, 6), (7, 7)] do
    emitInstruction .readR 1 0 (registerOperand false false register)
      s!"save A{register - 4} for SEND retry"
    emitSendScratchStore slot 1
  emitInstruction .readR 1 0 (registerOperand false false 0x0c)
    "save original SEND continuation FIP"
  emitSendScratchStore 8 1
  emitInstruction .readR 0 0 (registerOperand false false 0x19)
    "background fault-register bank selection"
  emitInlineBranch .branchNotZero 0 saveBackgroundFault
  emitSendFaultRegisters false
  emitBranch .branch 0 faultSaved
  defineLabel saveBackgroundFault
  -- FIR/FOP exist per priority, not for the background context. A background-
  -- relative register operand selects the current priority bank only here.
  emitSendFaultRegisters true
  defineLabel faultSaved
  emitInteger 1 "mark SEND retry frame active"
  emitSendScratchStore 0 0

  defineLabel countFault
  emitSetAddressRegisterConstant 2 sendFaultCountAddress 1
  emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
    "load architectural SEND-fault count"
  emitInstruction .add 0 0 (operandImmediate 1) "count architectural SEND fault"
  emitInstruction .write 0 0 (operandMemoryImmediate 0 2)
    "store architectural SEND-fault count"

  -- FIR low bits are the 17-bit instruction: opcode[1] selects SEND2, opcode[0]
  -- selects end-of-message, and op2[0] is the output priority.
  emitSendFirBitBranch 0x1000 retryTwo
  emitSendFirBitBranch 0x0800 retrySingleEnd
  emitSendFirBitBranch 0x0200 retrySinglePriority1
  emitBranch .branch 0 retrySendPriority0
  defineLabel retrySinglePriority1
  emitBranch .branch 0 retrySendPriority1
  defineLabel retrySingleEnd
  emitSendFirBitBranch 0x0200 retrySingleEndPriority1
  emitBranch .branch 0 retrySendEndPriority0
  defineLabel retrySingleEndPriority1
  emitBranch .branch 0 retrySendEndPriority1

  defineLabel retryTwo
  emitSendFirBitBranch 0x0800 retryTwoEnd
  emitSendFirBitBranch 0x0200 retryTwoPriority1
  emitBranch .branch 0 retrySend2Priority0
  defineLabel retryTwoPriority1
  emitBranch .branch 0 retrySend2Priority1
  defineLabel retryTwoEnd
  emitSendFirBitBranch 0x0200 retryTwoEndPriority1
  emitBranch .branch 0 retrySend2EndPriority0
  defineLabel retryTwoEndPriority1
  emitBranch .branch 0 retrySend2EndPriority1

  defineLabel retrySendPriority0
  emitSendRetry .send 0 false cleanup
  defineLabel retrySendPriority1
  emitSendRetry .send 1 false cleanup
  defineLabel retrySendEndPriority0
  emitSendRetry .sendEnd 0 false cleanup
  defineLabel retrySendEndPriority1
  emitSendRetry .sendEnd 1 false cleanup
  defineLabel retrySend2Priority0
  emitSendRetry .send2 0 true cleanup
  defineLabel retrySend2Priority1
  emitSendRetry .send2 1 true cleanup
  defineLabel retrySend2EndPriority0
  emitSendRetry .send2End 0 true cleanup
  defineLabel retrySend2EndPriority1
  emitSendRetry .send2End 1 true cleanup

  defineLabel cleanup
  emitInteger 0 "release SEND retry frame"
  emitSendScratchStore 0 0
  for (register, slot) in [(5, 5), (6, 6), (7, 7)] do
    emitSendScratchLoad slot 0
    emitInstruction .writeR 0 0 (registerOperand false false register)
      s!"restore A{register - 4} after SEND retry"
  emitSendScratchLoad 8 0
  emitInstruction .writeR 0 0 (registerOperand false false 0x0c)
    "restore original SEND continuation FIP"
  emitSendScratchLoad 1 0
  emitInstruction .writeR 0 0 (registerOperand false false 0x04)
    "park restored R0 in reserved A0"
  emitSendScratchLoad 2 1
  emitSendScratchLoad 3 2
  emitSendScratchLoad 4 3
  emitInstruction .readR 0 0 (registerOperand false false 0x04)
    "restore R0 from reserved A0"
  emitInstruction .loadIpR 0 0 (registerOperand false false 0x0c)
    "resume after faulting SEND"

private def emitRuntimeHandlers (applicationWords : Nat) : GenM Unit := do
  defineLabel spawnHandlerLabel
  let freshProcessLabel ← freshLabel "mdc.process.fresh"
  let processAllocatedLabel ← freshLabel "mdc.process.allocated"
  emitSetAddressRegisterConstant 2 processFreeHeadAddress 1
  emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
    "load MDC process free-list head"
  emitConditionalBranch .branchZero freshProcessLabel
  emitMove 3 1
  emitMove 0 3
  emitAddressWordFromInteger 1
  emitInstruction .writeR 0 0 (registerOperand false false 0x06)
    "reused MDC process block := A2"
  emitInstruction .read 2 0 (operandMemoryImmediate 0 2)
    "pop MDC process free-list link"
  emitSetAddressRegisterConstant 2 processFreeHeadAddress 1
  emitInstruction .write 0 2 (operandMemoryImmediate 0 2)
    "commit MDC process free-list pop"
  emitMove 0 3
  emitMove 1 0
  emitBranch .branch 0 processAllocatedLabel
  defineLabel freshProcessLabel
  emitSetAddressRegisterConstant 2 heapPointerAddress 1
  emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
    "allocate fresh MDC process stack"
  emitMove 2 0
  emitMove 1 0
  emitInteger (Int.ofNat processStackWords) "MDC process stack words"
  emitInstruction .add 0 1 (operandR 0) "advance MDC process heap"
  emitInstruction .write 0 0 (operandMemoryImmediate 0 2)
    "commit fresh MDC process stack allocation"
  emitMove 0 2
  emitMove 1 0
  defineLabel processAllocatedLabel
  emitMove 0 1
  emitAddressWordFromInteger processStackWords
  emitInstruction .writeR 0 0 (registerOperand false false 0x05)
    "MDC process stack := A1"
  emitInteger 0 "MDC handler frame offset"
  emitMove 3 0
  emitInstruction .readR 0 0 (registerOperand false false 0x07)
    "save message A3"
  emitStoreLocal processMessageSlot 0
  emitInteger 0 "no owned MDC bulk blocks"
  emitStoreLocal processBulkCountSlot 0

  -- Application code is software-cached independently on every node. Node 0
  -- is the code home. A priority-0 miss keeps this spawn context live while a
  -- priority-1 installer can preempt it, write chunks, and publish readiness.
  let codeReadyLabel ← freshLabel "mdc.code.ready"
  let codeWaitLabel ← freshLabel "mdc.code.wait"
  emitSetAddressRegisterConstant 2 codeCacheReadyAddress 1
  emitInstruction .read 0 0 (operandMemoryImmediate 0 2) "load application-code cache state"
  emitConditionalBranch .branchNotZero codeReadyLabel
  emitInteger 0 "application-code home node"
  emitInstruction .send 0 0 (operandR 0) "route application-code request"
  emitMessageHeader codeRequestHandlerLabel 2
  emitInstruction .send 0 0 (operandR 0) "application-code request header"
  emitInstruction .readR 0 0 (registerOperand false false 0x14)
    "application-code requester node"
  emitInstruction .sendEnd 0 0 (operandR 0) "finish application-code request"
  defineLabel codeWaitLabel
  emitSetAddressRegisterConstant 2 codeCacheReadyAddress 1
  emitInstruction .read 0 0 (operandMemoryImmediate 0 2) "poll application-code cache state"
  emitConditionalBranch .branchZero codeWaitLabel
  defineLabel codeReadyLabel

  emitLoadMessage 1 0
  emitStoreLocal 4 0
  emitLoadMessage 3 0
  emitStoreLocal 1 0
  emitLoadMessage 4 0
  emitStoreLocal 2 0
  emitLoadMessage 5 0
  emitStoreLocal 3 0
  emitLoadMessage 6 0
  emitStoreLocal 6 0

  -- The wire-level count is the number of logical arguments. A scalar is
  -- [1,value]. An MDC (int length, int *data) source pair is one logical
  -- [length,data...] argument and is expanded back into two C parameters.
  -- Bulk payloads are copied out of the circular hardware queue into the
  -- node-local heap before the queue message is released.
  let functions := (← get).functions
  let invokeLabel ← freshLabel "mdc.invoke"
  let malformedLabel ← freshLabel "mdc.malformed"
  let mut argumentLabels := #[]
  for info in functions do
    let label ← freshLabel s!"mdc.args.{info.id}"
    argumentLabels := argumentLabels.push label
    emitLoadLocal 4 0
    emitInstruction .sub 0 0 (operandImmediate (Int.ofNat info.id))
      s!"MDC function id == {info.id}"
    emitConditionalBranch .branchZero label
  emitBranch .branch 0 malformedLabel

  for functionIndex in [0:functions.size] do
    let info := functions[functionIndex]!
    defineLabel argumentLabels[functionIndex]!
    if info.hasAggregateResult then
      emitLoadLocal 1 0
      emitInstruction .sub 0 0
        (operandImmediate (Int.ofNat info.function.returnType.wordSize))
        "validate aggregate MDC return envelope width"
      emitConditionalBranch .branchNotZero malformedLabel
      let freshResultLabel ← freshLabel "mdc.result.fresh"
      let resultAllocatedLabel ← freshLabel "mdc.result.allocated"
      emitSetAddressRegisterConstant 2 bulkFreeHeadAddress 1
      emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
        "load aggregate-result free-list head"
      emitConditionalBranch .branchZero freshResultLabel
      emitStoreLocal 10 1
      emitLoadLocal 10 0
      emitAddressWordFromInteger 1
      emitInstruction .writeR 0 0 (registerOperand false false 0x06)
        "reused aggregate-result block := A2"
      emitInstruction .read 2 0 (operandMemoryImmediate 0 2)
        "pop aggregate-result free-list link"
      emitSetAddressRegisterConstant 2 bulkFreeHeadAddress 1
      emitInstruction .write 0 2 (operandMemoryImmediate 0 2)
        "commit aggregate-result free-list pop"
      emitLoadLocal 10 0
      emitMove 1 0
      emitBranch .branch 0 resultAllocatedLabel
      defineLabel freshResultLabel
      emitSetAddressRegisterConstant 2 heapPointerAddress 1
      emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
        "load aggregate-result heap pointer"
      emitMove 2 0
      emitMove 1 0
      emitInteger (Int.ofNat bulkBlockWords) "aggregate-result block words"
      emitInstruction .add 0 1 (operandR 0) "reserve aggregate-result block"
      emitInstruction .write 0 0 (operandMemoryImmediate 0 2)
        "commit aggregate-result heap pointer"
      emitMove 0 2
      emitMove 1 0
      defineLabel resultAllocatedLabel
      emitMove 0 1
      emitRecordBulkAllocation
      emitStoreLocal 12 0
      emitInteger (Int.ofNat info.function.returnType.wordSize)
        "aggregate-result width"
      emitMove 1 0
      emitLoadLocal 12 0
      emitAddressWordFromBaseAndLength
      emitStoreLocal (runtimeFrameSize + 1) 0
      emitInteger 1 "aggregate MDC result kind"
      emitStoreLocal 14 0
    else
      emitInteger 0 "scalar or void MDC result kind"
      emitStoreLocal 14 0
    emitLoadLocal 6 0
    emitInstruction .sub 0 0
      (operandImmediate (Int.ofNat (remoteLogicalArgumentCount info.function.parameters)))
      "validate MDC logical argument count"
    emitConditionalBranch .branchNotZero malformedLabel
    emitInteger 7 "first MDC logical argument"
    emitStoreLocal 8 0
    let mut parameterIndex := 0
    while parameterIndex < info.function.parameters.size do
      emitLoadMessageDynamic 8 0
      emitStoreLocal 9 0
      emitLoadLocal 8 0
      emitInstruction .add 0 0 (operandImmediate 1) "advance past MDC length"
      emitStoreLocal 8 0
      if isBulkPairAt info.function.parameters parameterIndex then
        -- Reconstruct the source-level length argument.
        emitLoadLocal 9 0
        emitStoreLocal (runtimeFrameSize + info.parameterSlot parameterIndex) 0

        -- Allocate a fixed-size bulk block so it can be reclaimed without
        -- fragmentation even when suspended processes finish out of order.
        let freshBulkLabel ← freshLabel "mdc.bulk.fresh"
        let bulkAllocatedLabel ← freshLabel "mdc.bulk.allocated"
        emitSetAddressRegisterConstant 2 bulkFreeHeadAddress 1
        emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
          "load MDC bulk free-list head"
        emitConditionalBranch .branchZero freshBulkLabel
        emitStoreLocal 10 1
        emitLoadLocal 10 0
        emitAddressWordFromInteger 1
        emitInstruction .writeR 0 0 (registerOperand false false 0x06)
          "reused MDC bulk block := A2"
        emitInstruction .read 2 0 (operandMemoryImmediate 0 2)
          "pop MDC bulk free-list link"
        emitSetAddressRegisterConstant 2 bulkFreeHeadAddress 1
        emitInstruction .write 0 2 (operandMemoryImmediate 0 2)
          "commit MDC bulk free-list pop"
        emitLoadLocal 10 0
        emitMove 1 0
        emitBranch .branch 0 bulkAllocatedLabel
        defineLabel freshBulkLabel
        emitSetAddressRegisterConstant 2 heapPointerAddress 1
        emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
          "load receiving MDC heap pointer"
        emitMove 2 0
        emitMove 1 0
        emitInteger (Int.ofNat bulkBlockWords) "MDC bulk block words"
        emitInstruction .add 0 1 (operandR 0) "reserve fixed MDC bulk block"
        emitInstruction .write 0 0 (operandMemoryImmediate 0 2)
          "commit receiving MDC heap pointer"
        emitMove 0 2
        emitMove 1 0
        defineLabel bulkAllocatedLabel
        emitMove 0 1
        emitRecordBulkAllocation
        emitStoreLocal 10 0
        emitLoadLocal 9 1
        emitLoadLocal 10 0
        emitAddressWordFromBaseAndLength
        emitStoreLocal (runtimeFrameSize + info.parameterSlot (parameterIndex + 1)) 0
        emitInstruction .writeR 0 0 (registerOperand false false 0x06)
          "receiving MDC bulk destination := A2"

        emitInteger 0 "receiving MDC bulk index"
        emitStoreLocal 11 0
        let copyLoopLabel ← freshLabel "mdc.copy.loop"
        let copyDoneLabel ← freshLabel "mdc.copy.done"
        defineLabel copyLoopLabel
        emitLoadLocal 9 1
        emitLoadLocal 11 0
        emitInstruction .less 0 0 (operandR 1) "MDC copy index < length"
        emitRetagInt
        emitConditionalBranch .branchZero copyDoneLabel
        emitLoadLocal 8 1
        emitLoadLocal 11 0
        emitInstruction .add 0 0 (operandR 1) "MDC source message offset"
        emitInstruction .read 1 0 (operandMemoryRegister 0 3)
          "read MDC bulk payload from queue"
        emitLoadLocal 11 0
        emitInstruction .write 0 1 (operandMemoryRegister 0 2)
          "copy MDC bulk payload to heap"
        emitLoadLocal 11 0
        emitInstruction .add 0 0 (operandImmediate 1) "advance MDC copy index"
        emitStoreLocal 11 0
        emitBranch .branch 0 copyLoopLabel
        defineLabel copyDoneLabel
        emitLoadLocal 9 1
        emitLoadLocal 8 0
        emitInstruction .add 0 0 (operandR 1) "advance past MDC bulk payload"
        emitStoreLocal 8 0
        parameterIndex := parameterIndex + 2
      else
        let parameterType := info.function.parameters[parameterIndex]!.type
        if parameterType.toRValue.isAggregate then
          emitLoadLocal 9 0
          emitInstruction .sub 0 0
            (operandImmediate (Int.ofNat parameterType.wordSize))
            "aggregate MDC length matches parameter width"
          emitConditionalBranch .branchNotZero malformedLabel
          for offset in [0:parameterType.wordSize] do
            emitLoadMessageDynamic 8 0
            emitStoreLocal (runtimeFrameSize + info.parameterSlot parameterIndex + offset) 0
            emitLoadLocal 8 0
            emitInstruction .add 0 0 (operandImmediate 1)
              "advance through MDC aggregate payload"
            emitStoreLocal 8 0
        else
          emitLoadLocal 9 0
          emitInstruction .sub 0 0 (operandImmediate 1) "scalar MDC length == 1"
          emitConditionalBranch .branchNotZero malformedLabel
          emitLoadMessageDynamic 8 0
          emitTargetConversion parameterType .int
          emitStoreLocal (runtimeFrameSize + info.parameterSlot parameterIndex) 0
          emitLoadLocal 8 0
          emitInstruction .add 0 0 (operandImmediate 1) "advance past MDC scalar"
          emitStoreLocal 8 0
        parameterIndex := parameterIndex + 1
    emitBranch .branch 0 invokeLabel

  defineLabel malformedLabel
  emitReclaimMdcAllocations
  emitInstruction .suspend 0 0 (operandR 0) "discard malformed MDC spawn message"

  defineLabel invokeLabel

  emitLoadLocal 4 2
  emitInteger (Int.ofNat runtimeFrameSize) "advance MDC runtime frame"
  emitInstruction .add 3 3 (operandR 0) "MDC sp += runtime frame"
  emitConstantWord (boolean false) "disable queue-relative A3 for C globals"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1d)
    "Q := false"
  emitSetAddressRegisterConstant 3 globalBase
  emitInstruction .call 0 0 (operandR 2) "invoke MDC function id"
  emitMove 1 0
  emitInteger (-Int.ofNat runtimeFrameSize) "restore MDC runtime frame"
  emitInstruction .add 3 3 (operandR 0) "MDC sp -= runtime frame"
  emitMove 0 1
  emitStoreLocal 5 0

  let noResponseLabel ← freshLabel "mdc.no.response"
  let aggregateResponseLabel ← freshLabel "mdc.aggregate.response"
  let responseFinishedLabel ← freshLabel "mdc.response.finished"
  emitLoadLocal 1 0
  emitInstruction .sub 0 0 (operandImmediate (-1)) "MDC return length == -1"
  emitConditionalBranch .branchZero noResponseLabel
  emitLoadLocal 14 0
  emitConditionalBranch .branchNotZero aggregateResponseLabel
  emitLoadLocal 2 0
  emitInstruction .send 1 0 (operandR 0) "MDC response routing word"
  emitMessageHeader responseHandlerLabel 3 true
  emitInstruction .send 1 0 (operandR 0) "MDC SET header"
  emitLoadLocal 3 0
  emitInstruction .send 1 0 (operandR 0) "MDC return address"
  emitLoadLocal 5 0
  emitInstruction .sendEnd 1 0 (operandR 0) "MDC return value"
  emitBranch .branch 0 responseFinishedLabel

  defineLabel aggregateResponseLabel
  emitLoadLocal 1 0
  emitInstruction .add 0 0 (operandImmediate 3)
    "aggregate SET header, address, count, and data length"
  emitStoreLocal 13 0
  emitLoadLocal 2 0
  emitInstruction .send 1 0 (operandR 0) "aggregate MDC response routing word"
  emitDynamicMessageHeader aggregateResponseHandlerLabel 13
  emitInstruction .send 1 0 (operandR 0) "aggregate MDC SET header"
  emitLoadLocal 3 0
  emitInstruction .send 1 0 (operandR 0) "aggregate MDC return address"
  emitLoadLocal 1 0
  emitInstruction .send 1 0 (operandR 0) "aggregate MDC return word count"
  emitInteger 0 "first aggregate MDC return word"
  emitStoreLocal 11 0
  let aggregateSendLoopLabel ← freshLabel "mdc.aggregate.response.loop"
  let aggregateSendLastLabel ← freshLabel "mdc.aggregate.response.last"
  defineLabel aggregateSendLoopLabel
  emitLoadLocal 1 1
  emitLoadLocal 12 0
  emitAddressWordFromBaseAndLength
  emitInstruction .writeR 0 0 (registerOperand false false 0x06)
    "aggregate MDC return source := A2"
  emitLoadLocal 11 0
  emitInstruction .read 1 0 (operandMemoryRegister 0 2)
    "load aggregate MDC return word"
  emitStoreLocal 10 1
  emitLoadLocal 1 1
  emitLoadLocal 11 0
  emitInstruction .add 0 0 (operandImmediate 1) "next aggregate return index"
  emitInstruction .equalData 0 0 (operandR 1) "last aggregate return word"
  emitRetagInt
  emitConditionalBranch .branchNotZero aggregateSendLastLabel
  emitLoadLocal 10 0
  emitInstruction .send 1 0 (operandR 0) "send aggregate MDC return word"
  emitLoadLocal 11 0
  emitInstruction .add 0 0 (operandImmediate 1) "advance aggregate return index"
  emitStoreLocal 11 0
  emitBranch .branch 0 aggregateSendLoopLabel
  defineLabel aggregateSendLastLabel
  emitLoadLocal 10 0
  emitInstruction .sendEnd 1 0 (operandR 0) "send final aggregate MDC return word"
  defineLabel responseFinishedLabel
  defineLabel noResponseLabel
  emitLoadLocal processMessageSlot 0
  emitInstruction .writeR 0 0 (registerOperand false false 0x07)
    "restore message A3"
  emitReclaimMdcAllocations
  emitConstantWord (boolean true) "restore queue-relative A3"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1d)
    "Q := true"
  emitInstruction .suspend 0 0 (operandR 0) "release MDC spawn message"

  defineLabel responseHandlerLabel
  emitLoadMessage 2 2
  emitLoadMessage 1 0
  emitSetAddressRegisterFromInteger 1
  emitConstantWord (boolean true) "inspect FUT waiter list unchecked"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := true"
  emitInstruction .read 0 0 (operandMemoryImmediate 0 1)
    "load FUT waiter-list head"
  emitInstruction .writeTag 0 0 (operandImmediate (Int.ofNat Tag.int.encoding))
    "extract FUT waiter-list head"
  emitMove 3 0
  emitConstantWord (boolean false) "finish FUT waiter-list inspection"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := false"
  emitInstruction .write 0 2 (operandMemoryImmediate 0 1)
    "resolve MDC result future"
  let wakeLoopLabel ← freshLabel "mdc.wake.loop"
  let wakeDoneLabel ← freshLabel "mdc.wake.done"
  defineLabel wakeLoopLabel
  emitMove 0 3
  emitConditionalBranch .branchZero wakeDoneLabel
  emitInstruction .readR 0 0 (registerOperand false false 0x14)
    "wake routing computer"
  emitInstruction .send 0 0 (operandR 0) "MDC wake routing word"
  emitMessageHeader wakeHandlerLabel 2
  emitInstruction .send 0 0 (operandR 0) "MDC wake header"
  emitInstruction .sendEnd 0 0 (operandR 3) "MDC suspended-process address"
  emitMove 0 3
  emitSetAddressRegisterFromInteger 2 processStackWords
  emitInstruction .read 3 (processNextWaiterSlot / 16)
    (operandMemoryImmediate processNextWaiterSlot 2) "next FUT waiter"
  emitBranch .branch 0 wakeLoopLabel
  defineLabel wakeDoneLabel
  emitInstruction .suspend 0 0 (operandR 0) "release MDC SET message"

  defineLabel aggregateResponseHandlerLabel
  emitLoadMessage 1 1
  emitSetAddressRegisterConstant 2 aggregateSetBaseAddress 1
  emitInstruction .write 0 1 (operandMemoryImmediate 0 2)
    "save aggregate SET destination base"
  emitLoadMessage 2 1
  emitSetAddressRegisterConstant 2 aggregateSetCountAddress 1
  emitInstruction .write 0 1 (operandMemoryImmediate 0 2)
    "save aggregate SET word count"
  emitSetAddressRegisterConstant 2 aggregateSetIndexAddress 1
  emitInteger 0 "first aggregate SET word"
  emitInstruction .write 0 0 (operandMemoryImmediate 0 2)
    "initialize aggregate SET index"
  let aggregateSetLoopLabel ← freshLabel "mdc.aggregate.set.loop"
  let aggregateSetDoneLabel ← freshLabel "mdc.aggregate.set.done"
  let aggregateWakeLoopLabel ← freshLabel "mdc.aggregate.wake.loop"
  let aggregateWakeDoneLabel ← freshLabel "mdc.aggregate.wake.done"
  defineLabel aggregateSetLoopLabel
  emitSetAddressRegisterConstant 2 aggregateSetCountAddress 1
  emitInstruction .read 1 0 (operandMemoryImmediate 0 2)
    "load aggregate SET word count"
  emitSetAddressRegisterConstant 2 aggregateSetIndexAddress 1
  emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
    "load aggregate SET index"
  emitInstruction .less 0 0 (operandR 1) "aggregate SET index < count"
  emitRetagInt
  emitConditionalBranch .branchZero aggregateSetDoneLabel

  emitSetAddressRegisterConstant 2 aggregateSetBaseAddress 1
  emitInstruction .read 1 0 (operandMemoryImmediate 0 2)
    "load aggregate SET destination base"
  emitSetAddressRegisterConstant 2 aggregateSetIndexAddress 1
  emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
    "load aggregate SET destination index"
  emitInstruction .add 0 0 (operandR 1) "aggregate SET destination word"
  emitSetAddressRegisterFromInteger 1
  emitConstantWord (boolean true) "inspect aggregate FUT waiter list unchecked"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := true"
  emitInstruction .read 0 0 (operandMemoryImmediate 0 1)
    "load aggregate FUT waiter-list head"
  emitInstruction .writeTag 0 0 (operandImmediate (Int.ofNat Tag.int.encoding))
    "extract aggregate FUT waiter-list head"
  emitMove 3 0
  emitConstantWord (boolean false) "finish aggregate FUT waiter-list inspection"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := false"

  emitSetAddressRegisterConstant 2 aggregateSetIndexAddress 1
  emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
    "load aggregate SET source index"
  emitInstruction .add 0 0 (operandImmediate 3)
    "aggregate SET message data offset"
  emitInstruction .read 2 0 (operandMemoryRegister 0 3)
    "load aggregate SET data word"
  emitInstruction .write 0 2 (operandMemoryImmediate 0 1)
    "resolve aggregate MDC result future"

  defineLabel aggregateWakeLoopLabel
  emitMove 0 3
  emitConditionalBranch .branchZero aggregateWakeDoneLabel
  emitInstruction .readR 0 0 (registerOperand false false 0x14)
    "aggregate wake routing computer"
  emitInstruction .send 0 0 (operandR 0) "aggregate MDC wake routing word"
  emitMessageHeader wakeHandlerLabel 2
  emitInstruction .send 0 0 (operandR 0) "aggregate MDC wake header"
  emitInstruction .sendEnd 0 0 (operandR 3) "aggregate MDC suspended-process address"
  emitMove 0 3
  emitSetAddressRegisterFromInteger 2 processStackWords
  emitInstruction .read 3 (processNextWaiterSlot / 16)
    (operandMemoryImmediate processNextWaiterSlot 2) "next aggregate FUT waiter"
  emitBranch .branch 0 aggregateWakeLoopLabel
  defineLabel aggregateWakeDoneLabel
  emitSetAddressRegisterConstant 2 aggregateSetIndexAddress 1
  emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
    "reload aggregate SET index"
  emitInstruction .add 0 0 (operandImmediate 1) "advance aggregate SET index"
  emitInstruction .write 0 0 (operandMemoryImmediate 0 2)
    "commit aggregate SET index"
  emitBranch .branch 0 aggregateSetLoopLabel
  defineLabel aggregateSetDoneLabel
  emitInstruction .suspend 0 0 (operandR 0) "release aggregate MDC SET message"

  defineLabel wakeHandlerLabel
  emitLoadMessage 1 0
  emitAddressWordFromInteger processStackWords
  emitInstruction .writeR 0 0 (registerOperand false false 0x05)
    "restore suspended process A1"
  emitInstruction .readR 0 0 (registerOperand false false 0x07)
    "capture wake-message A3"
  emitStoreProcessSlot processMessageSlot 0
  emitConstantWord (boolean false) "leave queue-relative wake-message addressing"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1d) "Q := false"
  emitLoadProcessSlot processA0Slot 0
  emitInstruction .writeR 0 0 (registerOperand false false 0x04) "restore A0"
  emitLoadProcessSlot processA2Slot 0
  emitInstruction .writeR 0 0 (registerOperand false false 0x06) "restore A2"
  emitLoadProcessSlot processA3Slot 0
  emitInstruction .writeR 0 0 (registerOperand false false 0x07) "restore A3"
  emitLoadProcessSlot processR1Slot 1
  emitLoadProcessSlot processR2Slot 2
  emitLoadProcessSlot processR3Slot 3
  emitLoadProcessSlot processR0Slot 0
  emitInstruction .loadIp (processResumeIpSlot / 16) 0
    (operandMemoryImmediate processResumeIpSlot 1) "resume suspended process"

  defineLabel futureFaultHandlerLabel
  -- MAR is the only architectural record of the memory cell whose FUT was
  -- moved before the forcing EQ.  Capture it before *any* process-header
  -- access changes MAR.  The compiler always forces with EQ R0,R0, so FOP0
  -- supplies the displaced R0 value after the address has been secured.
  emitInstruction .readR 0 0 (registerOperand false false 0x15)
    "capture future-fault memory address before changing MAR"
  emitStoreProcessSlot processFutureAddressSlot 0
  emitInstruction .readR 0 0 (registerOperand false false 0x0e)
    "recover faulting R0 from FOP0"
  emitStoreProcessSlot processR0Slot 0
  -- Direct stores preserve the remaining complete register set before scratch.
  emitStoreProcessSlot processR1Slot 1
  emitStoreProcessSlot processR2Slot 2
  emitStoreProcessSlot processR3Slot 3
  emitInstruction .readR 0 0 (registerOperand false false 0x0c)
    "read future-fault FIP"
  emitStoreProcessSlot processResumeIpSlot 0
  emitInstruction .readR 0 0 (registerOperand false false 0x04) "save A0"
  emitStoreProcessSlot processA0Slot 0
  emitInstruction .readR 0 0 (registerOperand false false 0x06) "save A2"
  emitStoreProcessSlot processA2Slot 0
  emitInstruction .readR 0 0 (registerOperand false false 0x07) "save A3"
  emitStoreProcessSlot processA3Slot 0
  emitSetAddressRegisterConstant 2 futureFaultCountAddress 1
  emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
    "load architectural FUT-fault count"
  emitInstruction .add 0 0 (operandImmediate 1) "count architectural FUT fault"
  emitInstruction .write 0 0 (operandMemoryImmediate 0 2)
    "store architectural FUT-fault count"
  emitLoadProcessSlot processFutureAddressSlot 0
  emitSetAddressRegisterFromInteger 2

  emitConstantWord (boolean true) "read unresolved FUT data unchecked"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := true"
  emitInstruction .read 0 0 (operandMemoryImmediate 0 2) "load prior FUT waiter"
  emitInstruction .writeTag 0 0 (operandImmediate (Int.ofNat Tag.int.encoding))
    "extract prior FUT waiter"
  emitMove 1 0
  emitConstantWord (boolean false) "finish unresolved FUT data read"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := false"
  emitMove 0 1
  emitStoreProcessSlot processNextWaiterSlot 0

  emitAddressRegisterBaseAsInteger 1
  emitInstruction .writeTag 0 0 (operandImmediate (Int.ofNat Tag.future.encoding))
    "link process into FUT waiter list"
  emitInstruction .write 0 0 (operandMemoryImmediate 0 2)
    "commit FUT waiter-list head"
  emitLoadProcessSlot processMessageSlot 0
  emitInstruction .writeR 0 0 (registerOperand false false 0x07)
    "restore active process message A3"
  emitConstantWord (boolean true) "restore queue-relative process message"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1d) "Q := true"
  emitInstruction .suspend 0 0 (operandR 0) "suspend process on unresolved FUT"

  defineLabel codeRequestHandlerLabel
  emitSetAddressRegisterConstant 2 codeRequestCountAddress 1
  emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
    "load application-code request count"
  emitInstruction .add 0 0 (operandImmediate 1) "count application-code request"
  emitInstruction .write 0 0 (operandMemoryImmediate 0 2)
    "store application-code request count"
  emitSetAddressRegisterConstant 2 codeAckCountAddress 1
  emitInteger 0 "reset application-code chunk acknowledgement count"
  emitInstruction .write 0 0 (operandMemoryImmediate 0 2)
    "reset application-code chunk acknowledgement count"
  let chunkCount := (applicationWords + codeChunkWords - 1) / codeChunkWords
  for chunkIndex in [0:chunkCount] do
    let chunkOffset := chunkIndex * codeChunkWords
    let chunkLength := min codeChunkWords (applicationWords - chunkOffset)
    emitLoadMessage 1 0
    emitInstruction .send 1 0 (operandR 0) "route application-code chunk"
    emitMessageHeader codeInstallHandlerLabel (4 + chunkLength) true
    emitInstruction .send 1 0 (operandR 0) "application-code chunk header"
    emitInteger (Int.ofNat chunkOffset) "application-code cache offset"
    emitInstruction .send 1 0 (operandR 0) "send application-code cache offset"
    emitInteger (Int.ofNat chunkLength) "application-code chunk length"
    emitInstruction .send 1 0 (operandR 0) "send application-code chunk length"
    emitInteger (if chunkIndex + 1 == chunkCount then 1 else 0)
      "application-code final chunk flag"
    emitInstruction .send 1 0 (operandR 0) "send application-code final flag"
    emitSetAddressRegisterConstant 2
      (codeCacheBase + chunkOffset) chunkLength
    emitInteger 0 "application-code source index"
    emitMove 2 0
    emitInteger (Int.ofNat (chunkLength - 1)) "last application-code source index"
    emitMove 3 0
    let copyLoopLabel ← freshLabel "mdc.code.send.loop"
    let copyLastLabel ← freshLabel "mdc.code.send.last"
    defineLabel copyLoopLabel
    emitInstruction .equalData 0 2 (operandR 3) "last application-code word"
    emitRetagInt
    emitConditionalBranch .branchNotZero copyLastLabel
    emitInstruction .read 0 0 (operandMemoryRegister 2 2)
      "load application-code word"
    emitInstruction .send 1 0 (operandR 0) "send application-code word"
    emitInstruction .add 2 2 (operandImmediate 1) "next application-code word"
    emitBranch .branch 0 copyLoopLabel
    defineLabel copyLastLabel
    emitInstruction .read 0 0 (operandMemoryRegister 2 2)
      "load final application-code word"
    emitInstruction .sendEnd 1 0 (operandR 0) "finish application-code chunk"
    -- The MDP output unit owns a single tail-delimited message stream.  Wait
    -- until the destination has consumed this chunk before beginning another
    -- message; otherwise the next routing word architecturally raises SEND.
    let ackWaitLabel ← freshLabel "mdc.code.ack.wait"
    defineLabel ackWaitLabel
    emitSetAddressRegisterConstant 2 codeAckCountAddress 1
    emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
      "load application-code chunk acknowledgement count"
    emitInstruction .sub 0 0 (operandImmediate (Int.ofNat (chunkIndex + 1)))
      "await application-code chunk acknowledgement"
    emitConditionalBranch .branchNotZero ackWaitLabel
  emitInstruction .suspend 0 0 (operandR 0) "release application-code request"

  defineLabel codeInstallHandlerLabel
  emitSetAddressRegisterConstant 2 codeInstallCountAddress 1
  emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
    "load application-code installed-chunk count"
  emitInstruction .add 0 0 (operandImmediate 1)
    "count installed application-code chunk"
  emitInstruction .write 0 0 (operandMemoryImmediate 0 2)
    "store application-code installed-chunk count"
  -- Dispatch is wormhole: the four-word header can make a message runnable
  -- while the body is still arriving.  Do not touch a not-yet-committed queue
  -- row; an architectural EARLY fault there would recursively fault because
  -- this priority-1 runtime handler has no process frame to suspend.  QHL's
  -- low ten bits are the committed queue occupancy, including this message.
  let chunkArrivedLabel ← freshLabel "mdc.code.install.arrived"
  defineLabel chunkArrivedLabel
  emitInstruction .readR 0 0 (registerOperand false false 0x11)
    "load current-priority queue head/length"
  emitRetagInt
  emitMove 1 0
  emitInteger 0x3ff "queue occupancy mask"
  emitInstruction .and 0 0 (operandR 1) "extract committed queue occupancy"
  emitMove 2 0
  emitLoadMessage 2 0
  emitInstruction .add 0 0 (operandImmediate 7)
    "application-code aligned message length bias"
  emitInstruction .and 0 0 (operandImmediate (-4))
    "application-code aligned message length"
  emitMove 1 0
  emitInstruction .less 0 2 (operandR 1)
    "committed queue occupancy < application-code message length"
  emitRetagInt
  emitConditionalBranch .branchNotZero chunkArrivedLabel

  emitLoadMessage 1 1
  emitInteger (Int.ofNat codeCacheBase) "application-code cache base"
  emitInstruction .add 0 0 (operandR 1) "application-code chunk destination"
  emitAddressWordFromInteger 0
  emitInstruction .writeR 0 0 (registerOperand false false 0x06)
    "application-code chunk destination := A2"
  emitLoadMessage 2 3
  emitInteger 0 "application-code install index"
  emitMove 2 0
  let installLoopLabel ← freshLabel "mdc.code.install.loop"
  let installDoneLabel ← freshLabel "mdc.code.install.done"
  defineLabel installLoopLabel
  emitInstruction .less 0 2 (operandR 3) "application-code install index < length"
  emitRetagInt
  emitConditionalBranch .branchZero installDoneLabel
  emitMove 0 2
  emitInstruction .add 0 0 (operandImmediate 4) "application-code message offset"
  emitInstruction .read 1 0 (operandMemoryRegister 0 3)
    "load transported application-code word"
  emitInstruction .write 0 1 (operandMemoryRegister 2 2)
    "install application-code word"
  emitInstruction .add 2 2 (operandImmediate 1) "next installed application-code word"
  emitBranch .branch 0 installLoopLabel
  defineLabel installDoneLabel
  emitLoadMessage 3 0
  let installCompleteLabel ← freshLabel "mdc.code.install.complete"
  emitConditionalBranch .branchZero installCompleteLabel
  -- Application functions are linked at codeCacheBase on every node. CALL
  -- vectors can therefore be installed with the common image and become live
  -- atomically when the final transported chunk publishes cache readiness.
  emitSetAddressRegisterConstant 2 codeCacheReadyAddress 1
  emitInteger 1 "application-code cache ready"
  emitInstruction .write 0 0 (operandMemoryImmediate 0 2)
    "publish application-code cache readiness"
  defineLabel installCompleteLabel
  emitInteger 0 "application-code home node"
  emitInstruction .send 1 0 (operandR 0)
    "route application-code chunk acknowledgement"
  emitMessageHeader codeAckHandlerLabel 2 true
  emitInstruction .send 1 0 (operandR 0)
    "application-code chunk acknowledgement header"
  emitLoadMessage 1 0
  emitInstruction .sendEnd 1 0 (operandR 0)
    "finish application-code chunk acknowledgement"
  emitInstruction .suspend 0 0 (operandR 0) "release application-code chunk"

  defineLabel codeAckHandlerLabel
  emitSetAddressRegisterConstant 2 codeAckCountAddress 1
  emitInstruction .read 0 0 (operandMemoryImmediate 0 2)
    "load application-code chunk acknowledgement count"
  emitInstruction .add 0 0 (operandImmediate 1)
    "count application-code chunk acknowledgement"
  emitInstruction .write 0 0 (operandMemoryImmediate 0 2)
    "store application-code chunk acknowledgement count"
  emitInstruction .suspend 0 0 (operandR 0)
    "release application-code chunk acknowledgement"

  -- Dynamic bulk lengths are known only at the call site. Abort the node
  -- before sending any routing word or truncated ten-bit MSG length if the
  -- logical envelope is negative or exceeds the 1020-word committed-message
  -- limit. The status word makes this fail-stop state observable to a host or
  -- future FPGA supervisor.
  defineLabel mdcArgumentErrorHandlerLabel
  emitSetAddressRegisterConstant 2 mdcArgumentErrorAddress 1
  emitInteger 1 "MDC argument envelope runtime error"
  emitInstruction .write 0 0 (operandMemoryImmediate 0 2)
    "publish MDC argument envelope runtime error"
  let mdcArgumentErrorHalt ← freshLabel "mdc.argument.error.halt"
  defineLabel mdcArgumentErrorHalt
  emitBranch .branch 0 mdcArgumentErrorHalt

  emitSendFaultHandler

private def emitBootstrap (main : FunctionInfo) : GenM Unit := do
  emitConstantWord (boolean false) "checked execution"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1c) "U := false"
  emitSetAddressRegisterConstant 2 nodeIdentityAddress 1
  emitInstruction .read 0 0 (operandMemoryImmediate 0 2) "load image node identity"
  emitInstruction .writeR 0 0 (registerOperand false false 0x14) "NNR := node identity"
  emitInteger 0 "initial stack offset"
  emitMove 3 0
  emitConstantWord (address false false stackBase 0) "stack base"
  emitInstruction .writeR 0 0 (registerOperand false false 0x05) "A1 := stack"
  emitConstantWord (address false false resultBase 1) "result base"
  emitInstruction .writeR 0 0 (registerOperand false false 0x06) "A2 := result"
  emitConstantWord (address false false globalBase 0) "global base"
  emitInstruction .writeR 0 0 (registerOperand false false 0x07) "A3 := globals"
  emitConstantWord (address false false queue0Base queueMask) "priority-0 queue base/mask"
  emitInstruction .writeR 0 0 (registerOperand false false 0x10) "QBM0 := queue 0"
  emitConstantWord (address false false queue0Base 0) "priority-0 queue head/length"
  emitInstruction .writeR 0 0 (registerOperand false false 0x11) "QHL0 := empty"
  emitConstantWord (address false false queue1Base queueMask) "priority-1 queue base/mask"
  emitInstruction .writeR 0 0 (registerOperand false true 0x10) "QBM1 := queue 1"
  emitConstantWord (address false false queue1Base 0) "priority-1 queue head/length"
  emitInstruction .writeR 0 0 (registerOperand false true 0x11) "QHL1 := empty"
  emitConstantWord (boolean false) "enable message dispatch"
  emitInstruction .writeR 0 0 (registerOperand false false 0x1a) "I := false"
  let halt ← freshLabel "halt"
  emitInstruction .readR 0 0 (registerOperand false false 0x14) "read node number"
  emitConditionalBranch .branchNotZero halt
  emitInstruction .call 0 0 (operandImmediate (Int.ofNat main.id)) "call main"
  emitInstruction .write 0 0 (operandMemoryImmediate 0 2) "store main result"
  defineLabel halt
  emitBranch .branch 0 halt

private def emitFunction (info : FunctionInfo) : GenM Unit := do
  defineLabel info.linkName info.function.pos
  let parameterScope := Id.run do
    let mut scope := []
    for index in [0:info.function.parameters.size] do
      let parameter := info.function.parameters[index]!
      scope := (parameter.name, Storage.local (info.parameterSlot index)
        parameter.type parameter.isRegister) :: scope
    return scope
  modify fun state => { state with
    currentFunction := some info
    scopes := [parameterScope]
    nextLocal := info.localBase
    breakTarget := none
    continueTarget := none
    switchCaseLabels := [] }
  emitInstruction .readR 0 0 (registerOperand false false 0x0c) "read return IP"
  emitStoreLocal 0 0
  -- A function's parameters and its outermost compound statement share a C
  -- scope. Nested compound statements still pass through `emitStmt` and push
  -- their own scopes.
  match info.function.body with
  | .block statements _ => for statement in statements do emitStmt statement
  | statement => emitStmt statement
  if info.effectiveNoreturn then
    let trap := s!"{info.linkName}.noreturn.fallthrough"
    defineLabel trap
    emitBranch .branch 0 trap
  else if info.hasAggregateResult then
    -- Reaching the closing brace of a non-main value-returning function is
    -- undefined C behavior. Emit a deterministic zero aggregate only for the
    -- unreachable fallthrough epilogue, just as scalar functions use zero.
    emitLoadLocal 1 0
    emitInstruction .writeR 0 0 (registerOperand false false 0x06)
      "implicit aggregate return destination := A2"
    for offset in [0:info.function.returnType.wordSize] do
      emitInteger 0 "implicit aggregate return zero"
      emitMove 1 0
      emitInteger (Int.ofNat offset) "implicit aggregate return offset"
      emitInstruction .write 0 1 (operandMemoryRegister 0 2)
        "store implicit aggregate return word"
    emitLoadLocal 1 0
    emitMove 1 0
    emitSetAddressRegisterConstant 2 resultBase 1
    emitLoadLocal 0 2
    emitMove 0 1
    emitInstruction .loadIp 0 0 (operandR 2) "implicit aggregate return"
  else
    emitReturn (if !info.function.returnType.toRValue.isVoid then
        some (.intLit 0 .int info.function.pos) else none) info.function.pos

private def sameLinkedIdentity (lhsName : String) (lhsLinkage : Linkage)
    (lhsUnit : Nat) (rhsName : String) (rhsLinkage : Linkage)
    (rhsUnit : Nat) : Bool :=
  lhsName == rhsName && lhsLinkage == rhsLinkage &&
    (lhsLinkage == .external || lhsUnit == rhsUnit)

private def functionDeclarationIdentity (lhs rhs : FunctionDeclaration) : Bool :=
  sameLinkedIdentity lhs.name lhs.linkage lhs.translationUnit
    rhs.name rhs.linkage rhs.translationUnit

private def declarationFunctionIdentity (declaration : FunctionDeclaration)
    (function : Function) : Bool :=
  sameLinkedIdentity declaration.name declaration.linkage declaration.translationUnit
    function.name function.linkage function.translationUnit

private def functionIdentity (lhs rhs : Function) : Bool :=
  sameLinkedIdentity lhs.name lhs.linkage lhs.translationUnit
    rhs.name rhs.linkage rhs.translationUnit

private def globalIdentity (lhs rhs : Global) : Bool :=
  sameLinkedIdentity lhs.name lhs.linkage lhs.translationUnit
    rhs.name rhs.linkage rhs.translationUnit

private def isInlineDefinition (program : Program) (function : Function) : Bool :=
  if function.linkage != .external || !function.specifiers.isInline ||
      function.explicitExtern then false
  else
    (program.declarations.filter fun declaration =>
      declaration.fileScope && declaration.name == function.name &&
        declaration.translationUnit == function.translationUnit).all fun declaration =>
      declaration.specifiers.isInline && !declaration.explicitExtern

private def effectiveNoreturn (program : Program) (function : Function) : Bool :=
  function.specifiers.isNoreturn || program.declarations.any fun declaration =>
    declarationFunctionIdentity declaration function && declaration.specifiers.isNoreturn

private partial def containsReturn : Stmt → Bool
  | .block statements _ | .declarationGroup statements _ =>
      statements.any containsReturn
  | .ite _ thenBranch elseBranch _ =>
      containsReturn thenBranch || (elseBranch.map containsReturn |>.getD false)
  | .whileLoop _ body _ | .doWhileLoop body _ _ => containsReturn body
  | .forLoop init _ _ body _ =>
      (init.map containsReturn |>.getD false) || containsReturn body
  | .switchStmt _ body _ | .caseLabel _ body _ | .defaultLabel body _ |
      .labeled _ body _ => containsReturn body
  | .returnStmt .. => true
  | _ => false

private def linkedFunctionName (function : Function) (inlineDefinition : Bool) : String :=
  if function.linkage == .internal then
    s!"__jmc.tu{function.translationUnit}.{function.name}"
  else if inlineDefinition then
    s!"__jmc.inline.tu{function.translationUnit}.{function.name}"
  else function.name

private def validateProgram (program : Program) (file : String) :
    Except CompileError (Array FunctionInfo × Array GlobalInfo × FunctionInfo) := do
  let sameParameters (lhs rhs : Array Parameter) : Bool :=
    lhs.size == rhs.size && (List.zip lhs.toList rhs.toList).all fun pair =>
      pair.1.type.toRValue == pair.2.type.toRValue
  let mut priorDeclarations : Array FunctionDeclaration := #[]
  for declaration in program.declarations do
    if declaration.name == "main" && declaration.specifiers != {} then
      throw {
        file := file, pos := declaration.pos,
        message := "function specifiers are not permitted on main" }
    if declaration.specifiers.isInline && declaration.linkage == .external &&
        !(program.functions.any fun function =>
          function.name == declaration.name &&
            function.translationUnit == declaration.translationUnit &&
            function.linkage == .external) then
      throw {
        file := file, pos := declaration.pos,
        message := s!"external inline function '{declaration.name}' must be defined in the same translation unit" }
    if (priorDeclarations.toList.find? fun prior =>
        prior.name == declaration.name &&
          prior.translationUnit == declaration.translationUnit &&
          prior.linkage != declaration.linkage).isSome then
      throw {
        file := file, pos := declaration.pos,
        message := s!"conflicting linkage for function '{declaration.name}'" }
    match priorDeclarations.toList.find? fun prior =>
        functionDeclarationIdentity prior declaration with
    | some prior =>
        if prior.returnType.toRValue != declaration.returnType.toRValue ||
            !sameParameters prior.parameters declaration.parameters then
          throw {
            file := file, pos := declaration.pos,
            message := s!"conflicting declarations for function '{declaration.name}'" }
    | none => priorDeclarations := priorDeclarations.push declaration
    if (program.functions.toList.find? fun function =>
        function.name == declaration.name &&
          function.translationUnit == declaration.translationUnit &&
          function.linkage != declaration.linkage).isSome then
      throw {
        file := file, pos := declaration.pos,
        message := s!"conflicting linkage for function '{declaration.name}'" }
    match program.functions.toList.find? fun function =>
        declarationFunctionIdentity declaration function with
    | some function =>
        if function.returnType.toRValue != declaration.returnType.toRValue ||
            !sameParameters function.parameters declaration.parameters then
          throw {
            file := file, pos := declaration.pos,
            message := s!"declaration of '{declaration.name}' does not match its definition" }
    | none => pure ()
  let mut functions := #[]
  let callWordsForFunction (function : Function) : Nat :=
    localCallTemporaryWords function.returnType
      (function.parameters.map fun parameter => parameter.type)
  let callWordsForDeclaration (declaration : FunctionDeclaration) : Nat :=
    localCallTemporaryWords declaration.returnType
      (declaration.parameters.map fun parameter => parameter.type)
  let indirectCallWords :=
    max (program.functions.foldl (fun maximum function =>
          max maximum (callWordsForFunction function)) 0)
      (program.declarations.foldl (fun maximum declaration =>
          max maximum (callWordsForDeclaration declaration)) 0)
  let aggregateAlignment := program.aggregates.foldl
    (fun maximum aggregate => max maximum aggregate.alignment) 1
  let globalAlignment := program.globals.foldl
    (fun maximum global => max maximum global.alignment.value) 1
  let functionAlignment := program.functions.foldl
    (fun maximum function => max maximum (statementMaximumAlignment function.body)) 1
  let programAlignment := max aggregateAlignment (max globalAlignment functionAlignment)
  let atomicAggregateSpillWords :=
    match programAtomicAggregateWords program with
    | 0 => 0
    | words => 3 * words + 3
  for function in program.functions do
    let inlineDefinition := isInlineDefinition program function
    let noreturn := effectiveNoreturn program function
    if function.name == "main" && function.specifiers != {} then
      throw {
        file := file, pos := function.pos,
        message := "function specifiers are not permitted on main" }
    if (functions.toList.find? fun info =>
        info.function.name == function.name &&
          info.function.translationUnit == function.translationUnit &&
          info.function.linkage != function.linkage).isSome then
      throw {
        file := file
        pos := function.pos
        message := s!"conflicting linkage for function '{function.name}'" }
    if (functions.toList.find? fun info =>
        info.function.name == function.name &&
          info.function.linkage == function.linkage &&
          info.function.translationUnit == function.translationUnit).isSome then
      throw {
        file := file
        pos := function.pos
        message := s!"duplicate function definition '{function.name}'" }
    if function.linkage == .external then
      match functions.toList.find? fun info =>
          info.function.name == function.name && info.function.linkage == .external with
      | some prior =>
          if prior.function.returnType.toRValue != function.returnType.toRValue ||
              !sameParameters prior.function.parameters function.parameters then
            throw {
              file := file, pos := function.pos,
              message := s!"conflicting definitions for function '{function.name}'" }
          if !prior.inlineDefinition && !inlineDefinition then
            throw {
              file := file, pos := function.pos,
              message := s!"duplicate external definition of function '{function.name}'" }
      | none => pure ()
    if noreturn && containsReturn function.body then
      throw {
        file := file, pos := function.pos,
        message := s!"_Noreturn function '{function.name}' contains a return statement" }
    if function.parameters.size > 31 then
      throw { file := file, pos := function.pos, message := "at most 31 parameters are supported" }
    match function.returnType.toRValue with
    | .array .. =>
        throw { file := file, pos := function.pos, message := "functions cannot return arrays" }
    | aggregate@(.structType ..) | aggregate@(.unionType ..) =>
        if aggregate.wordSize == 0 then
          throw {
            file := file, pos := function.pos,
            message := "function return type is an incomplete aggregate" }
    | _ => pure ()
    let mut parameterNames : List String := []
    for parameter in function.parameters do
      if parameter.type.wordSize > 1023 then
        throw {
          file := file, pos := parameter.pos,
          message := "parameter exceeds the MDP ADDR length field" }
      if parameterNames.contains parameter.name then
        throw {
          file := file
          pos := parameter.pos
          message := s!"duplicate parameter name '{parameter.name}'" }
      parameterNames := parameter.name :: parameterNames
    let sourceLabels := collectSourceLabels function.body
    let mut seenSourceLabels : List String := []
    for (name, pos) in sourceLabels do
      if seenSourceLabels.contains name then
        throw {
          file := file
          pos := pos
          message := s!"duplicate label '{name}' in function '{function.name}'" }
      seenSourceLabels := name :: seenSourceLabels
    for (name, pos) in collectSourceGotos function.body do
      unless seenSourceLabels.contains name do
        throw {
          file := file
          pos := pos
          message := s!"goto to undefined label '{name}' in function '{function.name}'" }
    let locals := countLocals function.body
    let directCallWords (name : String) : Nat :=
      if name == "computer" || name == "computers" then 0
      else
        let internal := program.functions.toList.find? fun candidate =>
          candidate.name == name && candidate.linkage == .internal &&
            candidate.translationUnit == function.translationUnit
        let external := program.functions.toList.find? fun candidate =>
          candidate.name == name && candidate.linkage == .external &&
            !isInlineDefinition program candidate
        match internal.orElse (fun _ => external) with
        | some target =>
            -- A block-scope function-pointer object may shadow a linked
            -- function with the same spelling. Reserve at least the largest
            -- linked signature so the later semantic lookup cannot outgrow
            -- this statically allocated spill window.
            max (callWordsForFunction target) indirectCallWords
        | none => indirectCallWords
    let spills := stmtSpills directCallWords indirectCallWords function.body +
      atomicAggregateSpillWords
    let hiddenResultWords := if function.returnType.toRValue.isAggregate then 1 else 0
    let layout := parameterLayout program.aggregates function.returnType
      (function.parameters.map fun parameter => parameter.type)
    let rawFrameSize := 1 + hiddenResultWords + layout.words + locals + spills
    let frameSize := alignUp rawFrameSize programAlignment
    functions := functions.push {
      function := function
      linkName := linkedFunctionName function inlineDefinition
      inlineDefinition := inlineDefinition
      effectiveNoreturn := noreturn
      id := functions.size
      parameterSlots := layout.slots
      parameterStorageWords := layout.words
      localCount := locals
      spillCount := spills
      frameSize := frameSize }
  if functions.size > 64 then
    throw { file := file, pos := default, message := "MDP CALL vector supports at most 64 functions" }
  match functions.toList.find? fun info =>
      info.function.name == "main" && info.function.linkage == .internal with
  | some info =>
      throw { file := file, pos := info.function.pos, message := "main must have external linkage" }
  | none => pure ()
  let main ← match functions.toList.find? fun info =>
      info.function.name == "main" && info.function.linkage == .external &&
        !info.inlineDefinition with
    | some info => pure info
    | none => throw { file := file, pos := default, message := "program has no main function" }
  if !main.function.parameters.isEmpty then
    throw { file := file, pos := main.function.pos, message := "main must not take parameters" }
  if main.function.returnType.stripTopQualifiers != .int then
    throw { file := file, pos := main.function.pos, message := "main must return int" }
  let mut globals := #[]
  let mut nextGlobalSlot := 0
  for global in program.globals do
    if (program.globals.toList.find? fun prior =>
        prior.name == global.name &&
          prior.translationUnit == global.translationUnit &&
          prior.linkage != global.linkage).isSome then
      throw {
        file := file, pos := global.pos,
        message := s!"conflicting linkage for global '{global.name}'" }
  for declaration in program.globals do
    for prior in program.globals do
      if globalIdentity prior declaration &&
          prior.isThreadLocal != declaration.isThreadLocal then
        throw {
          file := file, pos := declaration.pos,
          message := s!"declarations of global '{declaration.name}' disagree on '_Thread_local'" }
      if globalIdentity prior declaration && prior.alignment.specified &&
          declaration.alignment.specified &&
          prior.alignment.value != declaration.alignment.value then
        throw {
          file := file, pos := declaration.pos,
          message := s!"declaration of global '{declaration.name}' has a conflicting alignment" }
    if declaration.declarationOnly then
      match program.globals.toList.find? fun definition =>
          !definition.declarationOnly && globalIdentity declaration definition with
      | some definition =>
          if definition.type != declaration.type then
            throw {
              file := file, pos := declaration.pos,
              message := s!"extern declaration of '{declaration.name}' has a conflicting type" }
      | none =>
          for prior in program.globals do
            if prior.declarationOnly && globalIdentity prior declaration &&
                prior.type != declaration.type then
              throw {
                file := file, pos := declaration.pos,
                message := s!"extern declaration of '{declaration.name}' has a conflicting type" }
  let mut processedGlobals : Array Global := #[]
  for global in program.globals do
    if global.declarationOnly then continue
    if !global.type.isObjectType then
      throw { file := file, pos := global.pos, message := "global has an incomplete object type" }
    if global.type.wordSize > 1023 then
      throw {
        file := file
        pos := global.pos
        message := "global object exceeds the MDP ADDR length field" }
    if processedGlobals.any fun prior => globalIdentity prior global then continue
    let group := program.globals.filter fun candidate =>
      !candidate.declarationOnly && globalIdentity candidate global
    for candidate in group do
      if candidate.type != global.type then
        throw {
          file := file, pos := candidate.pos,
          message := s!"conflicting declarations for global '{global.name}'" }
    if global.linkage == .external &&
        group.any fun candidate => candidate.translationUnit != global.translationUnit then
      throw {
        file := file, pos := global.pos,
        message := s!"duplicate external global definition '{global.name}'" }
    let initialized := group.filter fun candidate => candidate.hasInitializer
    if initialized.size > 1 then
      throw {
        file := file, pos := initialized[1]!.pos,
        message := s!"duplicate initialized global definition '{global.name}'" }
    let allDeclarations := program.globals.filter fun candidate =>
      globalIdentity candidate global
    let explicitAlignments := allDeclarations.filter fun candidate =>
      candidate.alignment.specified
    let definitionAlignment :=
      match initialized[0]? with
      | some definition => definition.alignment
      | none =>
          (group.find? fun candidate => candidate.alignment.specified).map
            (fun candidate => candidate.alignment) |>.getD {}
    if !definitionAlignment.specified && !explicitAlignments.isEmpty then
      throw {
        file := file
        pos := explicitAlignments[0]!.pos
        message := s!"definition of global '{global.name}' has no alignment specifier" }
    for declaration in explicitAlignments do
      if declaration.alignment.value != definitionAlignment.value then
        throw {
          file := file
          pos := declaration.pos
          message := s!"declaration of global '{global.name}' has a conflicting alignment" }
    let representativeBase := initialized[0]?.getD global
    let representative := { representativeBase with alignment := definitionAlignment }
    processedGlobals := processedGlobals.push representative
    if (functions.toList.find? fun info =>
        info.function.name == representative.name &&
          ((info.function.linkage == .external && representative.linkage == .external) ||
           info.function.translationUnit == representative.translationUnit)).isSome then
      throw {
        file := file
        pos := representative.pos
        message := s!"global '{representative.name}' conflicts with a function" }
    nextGlobalSlot := alignUp nextGlobalSlot representative.alignment.value
    if nextGlobalSlot + representative.type.wordSize > codeBase - globalBase then
      throw {
        file := file
        pos := representative.pos
        message := "global data would overlap the protected code image" }
    globals := globals.push { global := representative, slot := nextGlobalSlot }
    nextGlobalSlot := nextGlobalSlot + representative.type.wordSize
  pure (functions, globals, main)

private def linkedAddress (applicationRange : Nat × Nat) (index : Nat) : Nat :=
  if index < applicationRange.1 then codeBase + index
  else if index < applicationRange.2 then codeCacheBase + index - applicationRange.1
  else codeBase + index - (applicationRange.2 - applicationRange.1)

private def resolveWord (state : GeneratorState) (applicationRange : Nat × Nat)
    (index : Nat) (word : CodeWord) :
    Except CompileError ImageWord := do
  let addressOf := linkedAddress applicationRange
  let value ← match word.pending with
    | .literal value => pure value
    | .branchDisplacement target =>
        let targetIndex ← match lookupByName? state.labels target with
          | some found => pure found
          | none => throw {
              file := state.file
              pos := default
              message := s!"internal error: unresolved label '{target}'" }
        let displacement := Int.ofNat (addressOf targetIndex) -
          Int.ofNat (addressOf (index + 1) + 1)
        pure (integer displacement)
    | .inlineBranch opcode conditionRegister target =>
        let targetIndex ← match lookupByName? state.labels target with
          | some found => pure found
          | none => throw {
              file := state.file
              pos := default
              message := s!"internal error: unresolved inline branch label '{target}'" }
        let displacement := Int.ofNat (addressOf targetIndex) -
          Int.ofNat (addressOf index + 1)
        if displacement < -64 || displacement > 63 then
          throw {
            file := state.file
            pos := default
            message := s!"inline branch to '{target}' is out of signed 7-bit range ({displacement})" }
        let encoded := intData displacement &&& 0x7f
        let op2 := (encoded >>> 5) &&& 0x3
        let op0 := 0x20 ||| (encoded &&& 0x1f)
        pure (instructionPair (instruction opcode op2 conditionRegister op0))
    | .messageHeader target length unchecked =>
        let targetIndex ← match lookupByName? state.labels target with
          | some found => pure found
          | none => throw {
              file := state.file
              pos := default
              message := s!"internal error: unresolved message handler '{target}'" }
        pure (message unchecked false (addressOf targetIndex) length)
  pure { address := addressOf index, value := value, annotation := word.annotation }

private def buildListing (symbols : List (String × Nat)) (words : Array ImageWord) : String :=
  let symbolLines := symbols.reverse.map fun entry =>
    s!"{entry.1} = 0x{toHex 5 entry.2}\n"
  let wordLines := words.toList.map fun word =>
    s!"{toHex 5 word.address}  {toHex 9 word.value}  {word.annotation}\n"
  String.join (symbolLines ++ ["\n"] ++ wordLines)

private def normalizeTopology (file : String) (options : CompilerOptions) :
    Except CompileError CompilerOptions := do
  let meshSpecified := options.meshX != 0 || options.meshY != 0 || options.meshZ != 0
  if !meshSpecified then
    if options.nodeCount > 32 then
      throw {
        file := file
        pos := default
        message := "node counts above 32 require an explicit --mesh XxYxZ topology" }
    pure { options with meshX := options.nodeCount, meshY := 1, meshZ := 1 }
  else
    if options.meshX == 0 || options.meshY == 0 || options.meshZ == 0 then
      throw {
        file := file
        pos := default
        message := "mesh dimensions must all be nonzero" }
    if options.meshX > 32 || options.meshY > 32 || options.meshZ > 64 then
      throw {
        file := file
        pos := default
        message := "mesh dimensions exceed the MDP NNR limits X<=32, Y<=32, Z<=64" }
    if options.meshX * options.meshY * options.meshZ != options.nodeCount then
      throw {
        file := file
        pos := default
        message := s!"mesh {options.meshX}x{options.meshY}x{options.meshZ} does not contain {options.nodeCount} nodes" }
    pure options

private def nnrForRank (options : CompilerOptions) (rank : Nat) : Nat :=
  let x := rank % options.meshX
  let planeRank := rank / options.meshX
  let y := planeRank % options.meshY
  let z := planeRank / options.meshY
  x ||| (y <<< 5) ||| (z <<< 10)

private def functionInfoForTranslationUnit? (functions : Array FunctionInfo)
    (name : String) (translationUnit : Nat) : Option FunctionInfo :=
  match functions.toList.find? fun info =>
      info.function.name == name && info.function.linkage == .internal &&
        info.function.translationUnit == translationUnit with
  | some info => some info
  | none => functions.toList.find? fun info =>
      info.function.name == name && info.function.linkage == .external &&
        !info.inlineDefinition

private def globalInfoForTranslationUnit? (globals : Array GlobalInfo)
    (name : String) (translationUnit : Nat) : Option GlobalInfo :=
  match globals.toList.find? fun info =>
      info.global.name == name && info.global.linkage == .internal &&
        info.global.translationUnit == translationUnit with
  | some info => some info
  | none => globals.toList.find? fun info =>
      info.global.name == name && info.global.linkage == .external

private def zeroInitializerWord (type : CType) : Word :=
  if type.toRValue.isFunctionPointer then integer 0
  else match type.toRValue with
    | .pointer _ => address false true 0 0
    | _ => integer 0

private def resolveGlobalInitializer (state : GeneratorState) (info : GlobalInfo)
    (offset : Nat) : Except CompileError Word := do
  let ((resolution, zeroType?), _) ← (do
    let resolution : InitializerResolution ConstantInitializer ←
      match info.global.initializer with
      | some initializer =>
          resolveInitializer (fun _ => pure none)
            (fun value _ => ConstantInitializer.integer value)
            (fun name pos => ConstantInitializer.objectDesignator name true pos)
            { type := info.global.type, offset := 0 } initializer
      | none => pure {
          zeroRegions := #[{ type := info.global.type, offset := 0 }] }
    let mut zeroType? : Option CType := none
    for region in resolution.zeroRegions do
      if offset >= region.offset && offset < region.offset + region.type.wordSize then
        match ← initializerObjectTypeAt? region.type (offset - region.offset) with
        | some regionType => zeroType? := some regionType
        | none => pure ()
    pure (resolution, zeroType?)).run state
  let action? := resolution.actions.toList.reverse.find? fun action =>
    action.target.offset == offset
  let wordActions := resolution.actions.filter fun action =>
    action.target.offset == offset
  let mergeableIntegerActions := !wordActions.isEmpty && wordActions.all fun action =>
    action.target.type.wordSize == 1 && action.target.type.toRValue.isInteger &&
      match action.value with
      | .integer _ => true
      | _ => false
  if mergeableIntegerActions &&
      (wordActions.size > 1 || wordActions.any fun action =>
        action.target.bitWidth.isSome) then
    let mut data : Nat := 0
    for action in wordActions do
      let value := match action.value with
        | .integer value => value
        | _ => 0
      match action.target.bitWidth with
      | none =>
          let converted :=
            if action.target.type.toRValue.isBool then
              if value == 0 then 0 else 1
            else Int.emod value 0x100000000
          data := converted.toNat
      | some width =>
          let lowMask : Nat :=
            if width == 32 then 0xffffffff else (1 <<< width) - 1
          let fieldMask := lowMask <<< action.target.bitOffset
          let converted :=
            if action.target.type.toRValue.isBool then
              if value == 0 then 0 else 1
            else Int.emod value (Int.ofNat (1 <<< width))
          data := (data &&& (0xffffffff - fieldMask)) |||
            ((converted.toNat &&& lowMask) <<< action.target.bitOffset)
    return integer (Int.ofNat data)
  let objectType := match action? with
    | some action => action.target.type.toRValue
    | none => zeroType?.map CType.toRValue |>.getD .int
  match action?.map (fun action => action.value) with
  | none => pure (zeroInitializerWord objectType)
  | some (ConstantInitializer.integer value) =>
      if objectType.isBool then pure (integer (if value == 0 then 0 else 1))
      else if objectType.isInteger then pure (integer value)
      else match objectType with
        | .pointer _ =>
            if value == 0 then pure (zeroInitializerWord objectType)
            else throw {
              file := state.file, pos := info.global.pos,
              message := "a pointer constant initializer must be null or a function designator" }
        | _ => throw {
            file := state.file, pos := info.global.pos,
            message := "integer constant is incompatible with initialized object" }
  | some (.functionDesignator name pos) =>
      let functionInfo ← match functionInfoForTranslationUnit? state.functions name
          info.global.translationUnit with
        | some found => pure found
        | none => throw {
            file := state.file, pos := pos,
            message := s!"initializer refers to undefined function '{name}'" }
      let (sourceType, _) ← (normalizeType (.pointer (functionType functionInfo))).run state
      if objectType.isBool then
        pure (integer 1)
      else match objectType.pointerPointee?, sourceType.pointerPointee? with
      | some targetPointee, some sourcePointee =>
          unless targetPointee.isFunction &&
              pointerValueCompatible targetPointee sourcePointee do
            throw {
              file := state.file, pos := pos,
              message := s!"function '{name}' has an incompatible initializer type" }
          pure (integer (Int.ofNat (functionInfo.id + 1)))
      | _, _ => throw {
          file := state.file, pos := pos,
          message := "a function designator requires a function-pointer object" }
  | some (.objectDesignator name decay pos) =>
      let sourceInfo ← match globalInfoForTranslationUnit? state.globals name
          info.global.translationUnit with
        | some found => pure found
        | none => throw {
            file := state.file, pos := pos,
            message := s!"initializer refers to undefined object '{name}'" }
      let (sourceObjectType, _) ← (normalizeType sourceInfo.global.type).run state
      let sourcePointee ←
        if decay then
          match sourceObjectType.stripTopQualifiers with
          | .array element _ => pure element
          | _ => throw {
              file := state.file, pos := pos,
              message := s!"object '{name}' is not an array designator" }
        else pure sourceObjectType
      if objectType.isBool then pure (integer 1)
      else match objectType.pointerPointee? with
      | some targetPointee =>
          unless pointerValueCompatible targetPointee sourcePointee do
            throw {
              file := state.file, pos := pos,
              message := s!"object '{name}' has an incompatible address initializer type" }
          pure (address false false (globalBase + sourceInfo.slot) sourceInfo.global.type.wordSize)
      | none => throw {
          file := state.file, pos := pos,
          message := "an object address constant requires an object-pointer or _Bool initializer" }

def compileProgramWithOptions (program : Program) (file : String)
    (options : CompilerOptions) : Except CompileError Compilation := do
  if options.nodeCount == 0 || options.nodeCount > 65536 then
    throw { file := file, pos := default, message := "node count must be in 1..65536" }
  let options ← normalizeTopology file options
  let (functions, globals, main) ← validateProgram program file
  let initial : GeneratorState := {
    file, options, functions, globals, sourceGlobals := program.globals,
    aggregates := program.aggregates }
  let (applicationRange, generated) ← (do
    emitBootstrap main
    let applicationStartIndex := (← get).items.size
    for info in functions do emitFunction info
    let applicationEndIndex := (← get).items.size
    emitRuntimeHandlers (applicationEndIndex - applicationStartIndex)
    pure (applicationStartIndex, applicationEndIndex)).run initial
  let applicationWords := applicationRange.2 - applicationRange.1
  let residentWords := generated.items.size - applicationWords
  if codeBase + residentWords > 0x2000 then
    throw {
      file := file
      pos := default
      message := "compiler runtime exceeds the MDP's 0x1000-word protected code region" }
  if codeCacheBase + applicationWords > 1 <<< 20 then
    throw {
      file := file
      pos := default
      message := "compiled application code exceeds the MDP external code region" }
  let mut localWords := #[]
  for info in functions do
    let functionIndex ← match lookupByName? generated.labels info.linkName with
      | some found => pure found
      | none => throw {
          file := file
          pos := info.function.pos
          message := "internal error: missing function label" }
    localWords := localWords.push {
      address := 0x80 + info.id
      value := instructionPointer false false
        (linkedAddress applicationRange functionIndex) false true
      annotation := s!"CALL vector for {info.function.name}" }
  let futureFaultIndex ← match lookupByName? generated.labels futureFaultHandlerLabel with
    | some found => pure found
    | none => throw {
        file := file
        pos := default
        message := "internal error: missing MDC FUT fault handler" }
  localWords := localWords.push {
    address := 0x4d
    value := instructionPointer false false
      (linkedAddress applicationRange futureFaultIndex) false true
    annotation := "priority-0 FUT fault vector" }
  let sendFaultIndex ← match lookupByName? generated.labels sendFaultHandlerLabel with
    | some found => pure found
    | none => throw {
        file := file
        pos := default
        message := "internal error: missing MDC SEND fault handler" }
  for (address, priority) in [(0x43, 0), (0x63, 1)] do
    localWords := localWords.push {
      address
      value := instructionPointer true false
        (linkedAddress applicationRange sendFaultIndex) false true
      annotation := s!"priority-{priority} SEND fault vector" }
  localWords := localWords.push {
    address := resultBase
    value := tagged .sym 0
    annotation := "main result mailbox" }
  for info in globals do
    for offset in [0:info.global.type.wordSize] do
      localWords := localWords.push {
        address := globalBase + info.slot + offset
        value := ← resolveGlobalInitializer generated info offset
        annotation := s!"global {info.global.name}[{offset}]" }
  for index in [0:generated.items.size] do
    localWords := localWords.push
      (← resolveWord generated applicationRange index generated.items[index]!)
  localWords := localWords.push {
    address := heapPointerAddress
    value := integer (Int.ofNat heapBase)
    annotation := "MDC node-local heap bump pointer" }
  localWords := localWords.push {
    address := processFreeHeadAddress
    value := integer 0
    annotation := "MDC process-block free-list head" }
  localWords := localWords.push {
    address := bulkFreeHeadAddress
    value := integer 0
    annotation := "MDC bulk-block free-list head" }
  localWords := localWords.push {
    address := codeRequestCountAddress
    value := integer 0
    annotation := "application-code transport request count" }
  localWords := localWords.push {
    address := codeInstallCountAddress
    value := integer 0
    annotation := "application-code installed-chunk count" }
  localWords := localWords.push {
    address := codeAckCountAddress
    value := integer 0
    annotation := "application-code acknowledged-chunk count" }
  localWords := localWords.push {
    address := futureFaultCountAddress
    value := integer 0
    annotation := "architectural FUT-fault count" }
  localWords := localWords.push {
    address := sendFaultCountAddress
    value := integer 0
    annotation := "architectural SEND-fault count" }
  localWords := localWords.push {
    address := mdcArgumentErrorAddress
    value := integer 0
    annotation := "MDC argument-envelope runtime error" }
  for (address, context) in
      [(sendRetryBackgroundBase, "background"),
       (sendRetryPriority0Base, "priority-0"),
       (sendRetryPriority1Base, "priority-1")] do
    localWords := localWords.push {
      address
      value := integer 0
      annotation := s!"inactive {context} SEND retry frame" }
  let mut words := #[]
  let mut nodeSpecificWords := #[]
  for node in [0:options.nodeCount] do
    for word in localWords do words := words.push { word with node := node }
    let identityWord : ImageWord := {
      node := node
      address := nodeIdentityAddress
      value := integer (Int.ofNat (nnrForRank options node))
      annotation := "image-assigned packed X/Y/Z architectural NNR" }
    words := words.push identityWord
    nodeSpecificWords := nodeSpecificWords.push identityWord
    let cacheReadyWord : ImageWord := {
      node := node
      address := codeCacheReadyAddress
      value := integer
        (if options.codePlacement == .replicated || node == 0 then 1 else 0)
      annotation :=
        if options.codePlacement == .replicated then "replicated application code is ready"
        else if node == 0 then "application code home is ready"
        else "application code cache starts empty" }
    words := words.push cacheReadyWord
    nodeSpecificWords := nodeSpecificWords.push cacheReadyWord
  let symbols := generated.labels.map fun entry =>
    (entry.1, linkedAddress applicationRange entry.2)
  pure {
    words := words
    broadcastWords := localWords
    nodeSpecificWords := nodeSpecificWords
    symbols := symbols
    listing := buildListing symbols localWords
    resultAddress := resultBase
    applicationStart := codeCacheBase
    applicationEnd := codeCacheBase + applicationWords }

def compileProgram (program : Program) (file : String) : Except CompileError Compilation :=
  compileProgramWithOptions program file {}

private def aggregateLayoutEqual (lhs rhs : Aggregate) : Bool :=
  lhs.kind == rhs.kind && lhs.name == rhs.name && lhs.size == rhs.size &&
    lhs.containsFlexibleArray == rhs.containsFlexibleArray &&
    lhs.members.size == rhs.members.size &&
    (List.zip lhs.members.toList rhs.members.toList).all fun pair =>
      pair.1.name == pair.2.name && pair.1.type == pair.2.type &&
        pair.1.offset == pair.2.offset && pair.1.bitWidth == pair.2.bitWidth &&
        pair.1.bitOffset == pair.2.bitOffset

def mergePrograms (programs : Array Program) (file : String := "<link>") :
    Except CompileError Program := do
  let mut merged : Program := {}
  for translationUnit in [0:programs.size] do
    let sourceProgram := programs[translationUnit]!
    let program : Program := { sourceProgram with
      functions := sourceProgram.functions.map fun function =>
        { function with translationUnit := translationUnit }
      declarations := sourceProgram.declarations.map fun declaration =>
        { declaration with translationUnit := translationUnit }
      globals := sourceProgram.globals.map fun global =>
        { global with translationUnit := translationUnit } }
    for aggregate in program.aggregates do
      match merged.aggregates.toList.find? fun prior =>
          prior.kind == aggregate.kind && prior.name == aggregate.name with
      | some prior =>
          if prior.size == 0 then
            merged := { merged with aggregates := merged.aggregates.map fun item =>
              if item.kind == aggregate.kind && item.name == aggregate.name then aggregate
              else item }
          else if aggregate.size != 0 && !aggregateLayoutEqual prior aggregate then
            throw {
              file := file, pos := aggregate.pos,
              message := s!"conflicting cross-file definition of aggregate '{aggregate.name}'" }
      | none => merged := { merged with aggregates := merged.aggregates.push aggregate }
    merged := { merged with
      functions := merged.functions ++ program.functions
      declarations := merged.declarations ++ program.declarations
      globals := merged.globals ++ program.globals }
  pure merged

def compileCSourcesWithOptions (sources : Array (String × String))
    (options : CompilerOptions) : Except CompileError Compilation := do
  if sources.isEmpty then
    throw { file := "<link>", pos := default, message := "no C input files" }
  let mut programs := #[]
  for source in sources do
    programs := programs.push (← parseC source.1 source.2)
  compileProgramWithOptions (← mergePrograms programs) "<link>" options

def compileCWithOptions (source file : String) (options : CompilerOptions) :
    Except CompileError Compilation := do
  compileProgramWithOptions (← parseC source file) file options

def compileC (source file : String) : Except CompileError Compilation := do
  compileCWithOptions source file {}

def imageText (compilation : Compilation) : String :=
  let header := "# NODE  ADDRESS  36-BIT-WORD\n"
  header ++ String.join (compilation.words.toList.map fun word =>
    s!"{word.node}  {toHex 5 word.address}  {toHex 9 word.value}  # {word.annotation}\n")

def broadcastImageText (compilation : Compilation) : String :=
  let header := "# NODE (* = broadcast)  ADDRESS  36-BIT-WORD\n"
  let common := String.join (compilation.broadcastWords.toList.map fun word =>
    s!"*  {toHex 5 word.address}  {toHex 9 word.value}  # {word.annotation}\n")
  let specific := String.join (compilation.nodeSpecificWords.toList.map fun word =>
    s!"{word.node}  {toHex 5 word.address}  {toHex 9 word.value}  # {word.annotation}\n")
  header ++ common ++ specific

def distributedCodeImageText (compilation : Compilation) : String :=
  let header := "# NODE (* = broadcast)  ADDRESS  36-BIT-WORD\n"
  let isApplication (word : ImageWord) :=
    word.address >= compilation.applicationStart &&
      word.address < compilation.applicationEnd
  let common := String.join
    ((compilation.broadcastWords.filter fun word => !isApplication word).toList.map fun word =>
      s!"*  {toHex 5 word.address}  {toHex 9 word.value}  # {word.annotation}\n")
  let homeCode := String.join
    ((compilation.broadcastWords.filter isApplication).toList.map fun word =>
      s!"0  {toHex 5 word.address}  {toHex 9 word.value}  # code-home {word.annotation}\n")
  let specific := String.join (compilation.nodeSpecificWords.toList.map fun word =>
    s!"{word.node}  {toHex 5 word.address}  {toHex 9 word.value}  # {word.annotation}\n")
  header ++ common ++ homeCode ++ specific

end JMachineC
