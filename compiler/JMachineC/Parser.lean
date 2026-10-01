module

public import JMachineC.Lexer

public section

namespace JMachineC

private inductive IdentifierBinding where
  | ordinary (type : Option CType) (pos : Pos)
  | typedefName (type : CType) (pos : Pos)
  | enumConstant (value : Int) (pos : Pos)
deriving Repr

private structure EnumTag where
  name : String
  complete : Bool
  pos : Pos

private abbrev IdentifierScope := List (String × IdentifierBinding)

private structure DeclarationSpecifiers where
  storageClass : Option String := none
  isThreadLocal : Bool := false
  function : FunctionSpecifiers := {}
  alignmentOperands : Array (Array Token) := #[]
  alignment : AlignmentSpec := {}
deriving Repr, Inhabited

private structure ParserState where
  tokens : Array Token
  file : String
  index : Nat := 0
  aggregates : Array Aggregate := #[]
  enumTags : Array EnumTag := #[]
  nextAnonymousEnum : Nat := 0
  staticGlobals : Array Global := #[]
  blockGlobals : Array Global := #[]
  blockFunctionDeclarations : Array FunctionDeclaration := #[]
  nextStaticGlobal : Nat := 0
  nextStringLiteral : Nat := 0
  fileLinkages : List (String × Linkage) := []
  functionNames : List String := []
  identifierScopes : List IdentifierScope := [[]]
  pendingDeclarationSpecifiers : Option DeclarationSpecifiers := none

private abbrev ParserM := StateT ParserState (Except CompileError)

private def current : ParserM Token := do
  let state ← get
  pure <| state.tokens[state.index]?.getD { kind := .eof, pos := default }

private def advance : ParserM Token := do
  let token ← current
  modify fun state => { state with index := state.index + 1 }
  pure token

private def failAt (pos : Pos) (message : String) : ParserM α := do
  let state ← get
  throw { file := state.file, pos := pos, message := message }

private def failHere (message : String) : ParserM α := do
  failAt (← current).pos message

private def symbol? (value : String) : ParserM Bool := do
  pure <| match (← current).kind with
    | .symbol actual => actual == value
    | _ => false

private def identifier? (value : String) : ParserM Bool := do
  pure <| match (← current).kind with
    | .identifier actual => actual == value
    | _ => false

private def acceptSymbol (value : String) : ParserM Bool := do
  if ← symbol? value then
    discard advance
    pure true
  else pure false

private def acceptIdentifier (value : String) : ParserM Bool := do
  if ← identifier? value then
    discard advance
    pure true
  else pure false

private def expectSymbol (value : String) : ParserM Token := do
  if ← symbol? value then advance
  else failHere s!"expected '{value}'"

private def expectName : ParserM (String × Pos) := do
  let token ← advance
  match token.kind with
  | .identifier name => pure (name, token.pos)
  | _ => failAt token.pos "expected identifier"

private def lookupBindingInScopes? (name : String) : List IdentifierScope →
    Option IdentifierBinding
  | [] => none
  | scope :: outer =>
      match scope.find? fun entry => entry.1 == name with
      | some entry => some entry.2
      | none => lookupBindingInScopes? name outer

private def lookupBinding? (name : String) : ParserM (Option IdentifierBinding) := do
  pure <| lookupBindingInScopes? name (← get).identifierScopes

private def currentScopeBinding? (name : String) : ParserM (Option IdentifierBinding) := do
  let scopes := (← get).identifierScopes
  pure <| match scopes with
    | scope :: _ => (scope.find? fun entry => entry.1 == name).map fun entry => entry.2
    | [] => none

private def pushIdentifierScope : ParserM Unit :=
  modify fun state => { state with identifierScopes := [] :: state.identifierScopes }

private def popIdentifierScope : ParserM Unit := do
  let state ← get
  match state.identifierScopes with
  | _ :: outer@(_ :: _) => set { state with identifierScopes := outer }
  | _ => failHere "internal parser error: attempted to leave the file scope"

private def insertCurrentBinding (name : String) (binding : IdentifierBinding) : ParserM Unit :=
  modify fun state =>
    match state.identifierScopes with
    | scope :: outer => { state with identifierScopes := ((name, binding) :: scope) :: outer }
    | [] => { state with identifierScopes := [[(name, binding)]] }

private def declareOrdinary (name : String) (pos : Pos)
    (allowOrdinaryRedeclaration : Bool := false)
    (type : Option CType := none) : ParserM Unit := do
  match ← currentScopeBinding? name with
  | some (.typedefName _ _) | some (.enumConstant _ _) =>
      failAt pos s!"'{name}' is redeclared as an ordinary identifier in the same scope"
  | some (.ordinary _ _) =>
      unless allowOrdinaryRedeclaration do
        failAt pos s!"redeclaration of ordinary identifier '{name}'"
  | none => insertCurrentBinding name (.ordinary type pos)

private def declareTypedef (name : String) (type : CType) (pos : Pos) : ParserM Unit := do
  match ← currentScopeBinding? name with
  | some (.ordinary _ _) | some (.enumConstant _ _) =>
      failAt pos s!"'{name}' is redeclared as a typedef name in the same scope"
  | some (.typedefName prior priorPos) =>
      unless prior == type do
        failAt pos s!"conflicting typedef for '{name}' (previous declaration at {priorPos.line}:{priorPos.column})"
  | none => insertCurrentBinding name (.typedefName type pos)

private def declareEnumConstant (name : String) (value : Int) (pos : Pos) : ParserM Unit := do
  match ← currentScopeBinding? name with
  | some _ => failAt pos s!"redeclaration of enumerator '{name}'"
  | none => insertCurrentBinding name (.enumConstant value pos)

private def typeStart : ParserM Bool := do
  match (← current).kind with
  | .identifier name =>
      if name == "char" || name == "short" || name == "int" || name == "long" ||
          name == "signed" || name == "unsigned" || name == "_Bool" ||
          name == "void" || name == "struct" || name == "union" ||
          name == "enum" || name == "_Atomic" ||
          name == "const" || name == "volatile" || name == "restrict" then
        pure true
      else
        pure <| match ← lookupBinding? name with
          | some (.typedefName ..) => true
          | _ => false
  | _ => pure false

private def declarationSpecifierKeyword (name : String) : Bool :=
  name == "typedef" || name == "extern" || name == "static" ||
    name == "auto" || name == "register" || name == "inline" ||
    name == "_Thread_local" || name == "_Noreturn" || name == "_Alignas"

private def declarationStart : ParserM Bool := do
  if ← typeStart then return true
  match (← current).kind with
  | .identifier name => pure (declarationSpecifierKeyword name)
  | _ => pure false

private def consumePendingDeclarationSpecifier : ParserM Bool := do
  let token ← current
  let some pending := (← get).pendingDeclarationSpecifiers | pure false
  let some name := (match token.kind with
    | .identifier name => some name
    | _ => none) | pure false
  if name == "_Alignas" then
    discard advance
    discard <| expectSymbol "("
    let mut depth := 0
    let mut operand := #[]
    while true do
      let item ← current
      match item.kind with
      | .eof => failAt token.pos "unterminated _Alignas operand"
      | .symbol "(" =>
          depth := depth + 1
          operand := operand.push (← advance)
      | .symbol ")" =>
          if depth == 0 then
            discard advance
            break
          depth := depth - 1
          operand := operand.push (← advance)
      | _ => operand := operand.push (← advance)
    if operand.isEmpty then failAt token.pos "_Alignas requires an operand"
    modify fun state => { state with
      pendingDeclarationSpecifiers := some {
        pending with alignmentOperands := pending.alignmentOperands.push operand } }
    return true
  else if name == "inline" then
    modify fun state => { state with
      pendingDeclarationSpecifiers := some {
        pending with function := { pending.function with isInline := true } } }
  else if name == "_Noreturn" then
    modify fun state => { state with
      pendingDeclarationSpecifiers := some {
        pending with function := { pending.function with isNoreturn := true } } }
  else if name == "_Thread_local" then
    if pending.isThreadLocal then
      failAt token.pos "duplicate '_Thread_local' storage-class specifier"
    modify fun state => { state with
      pendingDeclarationSpecifiers := some { pending with isThreadLocal := true } }
  else if name == "typedef" || name == "extern" || name == "static" ||
      name == "auto" || name == "register" then
    if pending.storageClass.isSome then
      failAt token.pos "a declaration may have only one storage-class specifier"
    modify fun state => { state with
      pendingDeclarationSpecifiers := some { pending with storageClass := some name } }
  else
    return false
  discard advance
  pure true

private def atomicTypeSpecifierStart : ParserM Bool := do
  unless ← identifier? "_Atomic" do return false
  let state ← get
  pure <| match state.tokens[state.index + 1]?.map (fun token => token.kind) with
    | some (TokenKind.symbol "(") => true
    | _ => false

private def parseTypeQualifiers : ParserM TypeQualifiers := do
  let mut qualifiers : TypeQualifiers := {}
  let mut parsing := true
  while parsing do
    if ← acceptIdentifier "const" then
      qualifiers := { qualifiers with isConst := true }
    else if ← acceptIdentifier "volatile" then
      qualifiers := { qualifiers with isVolatile := true }
    else if ← acceptIdentifier "restrict" then
      qualifiers := { qualifiers with isRestrict := true }
    else if ← identifier? "_Atomic" then
      if ← atomicTypeSpecifierStart then
        parsing := false
      else
        discard advance
        qualifiers := { qualifiers with isAtomic := true }
    else if ← consumePendingDeclarationSpecifier then
      pure ()
    else
      parsing := false
  pure qualifiers

private def qualifyType (type : CType) (qualifiers : TypeQualifiers) (pos : Pos) : ParserM CType := do
  if qualifiers.isRestrict && type.pointerPointee?.isNone then
    failAt pos "'restrict' may qualify only a pointer type"
  if qualifiers.isAtomic && (type.isArray || type.isFunction) then
    failAt pos "'_Atomic' may not qualify an array or function type"
  if type.isFunction && !qualifiers.isEmpty then
    failAt pos "a function type cannot be qualified"
  pure (type.withQualifiers qualifiers)

private def aggregateKindName : AggregateKind → String
  | .structKind => "struct"
  | .unionKind => "union"

private def aggregateType (kind : AggregateKind) (name : String) (size : Nat) : CType :=
  match kind with
  | .structKind => .structType name size
  | .unionKind => .unionType name size

private def findAggregate? (kind : AggregateKind) (name : String) : ParserM (Option Aggregate) := do
  pure <| (← get).aggregates.toList.find? fun item =>
    item.kind == kind && item.name == name

private def installAggregate (aggregate : Aggregate) : ParserM Unit := do
  let state ← get
  if state.aggregates.any fun item => item.kind == aggregate.kind && item.name == aggregate.name then
    modify fun current => { current with aggregates := current.aggregates.map fun item =>
      if item.kind == aggregate.kind && item.name == aggregate.name then aggregate else item }
  else
    modify fun current => { current with aggregates := current.aggregates.push aggregate }

private def findEnumTag? (name : String) : ParserM (Option EnumTag) := do
  pure <| (← get).enumTags.toList.find? fun tag => tag.name == name

private def installEnumTag (tag : EnumTag) : ParserM Unit := do
  let state ← get
  if state.enumTags.any fun prior => prior.name == tag.name then
    modify fun current => { current with enumTags := current.enumTags.map fun prior =>
      if prior.name == tag.name then tag else prior }
  else
    modify fun current => { current with enumTags := current.enumTags.push tag }

private def freshAnonymousEnumName : ParserM String := do
  let state ← get
  modify fun current => { current with nextAnonymousEnum := current.nextAnonymousEnum + 1 }
  pure s!"<anonymous-enum:{state.file}:{state.nextAnonymousEnum}>"

private def freshStaticBackingName (sourceName : String) : ParserM String := do
  let state ← get
  modify fun current => { current with nextStaticGlobal := current.nextStaticGlobal + 1 }
  pure s!"__jmc.static.{state.nextStaticGlobal}.{sourceName}"

private def installStringLiteral (values : Array Int) (encoding : LiteralEncoding)
    (pos : Pos) : ParserM String := do
  let state ← get
  let name := s!"__jmc.string.{state.nextStringLiteral}"
  let terminated := values.push 0
  let elements := terminated.map fun value =>
    (#[], Initializer.value (ConstantInitializer.integer value) pos)
  modify fun current => {
    current with
      nextStringLiteral := current.nextStringLiteral + 1
      staticGlobals := current.staticGlobals.push {
        type := .array encoding.elementType terminated.size
        name := name
        initializer := some (.list elements pos)
        pos := pos
        hasInitializer := true
        linkage := .internal } }
  pure name

private def mergeLiteralEncodings (prior next : LiteralEncoding) (pos : Pos) :
    ParserM LiteralEncoding := do
  if prior == .ordinary then return next
  if next == .ordinary || prior == next then return prior
  if prior == .utf8 || next == .utf8 then
    failAt pos "an adjacent string sequence may not combine UTF-8 and wide literals"
  failAt pos s!"this target does not concatenate differently-prefixed '{prior.prefix}' and '{next.prefix}' wide literals"

private def consumeAdjacentStringLiterals :
    ParserM (Array Int × LiteralEncoding × Pos) := do
  let first ← current
  let mut units := #[]
  let mut encoding := LiteralEncoding.ordinary
  let mut consumed := false
  while true do
    match (← current).kind with
    | .stringLiteral part partEncoding =>
        encoding ← if consumed then mergeLiteralEncodings encoding partEncoding (← current).pos
          else pure partEncoding
        consumed := true
        units := units ++ part
        discard advance
    | _ => break
  unless consumed do failAt first.pos "expected string literal"
  pure (encoding.encodeUnits units, encoding, first.pos)

private partial def inferredInitializerWords (elementWords : Nat)
    (valueConsumesElement : α → ParserM Bool) : Initializer α → ParserM Nat
  | .stringLiteral values _ _ _ => pure (values.size + 1)
  | .value value _ => do
      pure (if ← valueConsumesElement value then elementWords else 1)
  | .list elements _ => do
      let mut cursor := 0
      let mut maximum := 0
      for (designators, initializer) in elements do
        match designators[0]? with
        | some (InitializerDesignator.index value _) =>
            if value >= 0 then cursor := value.toNat * elementWords
        | _ => pure ()
        let width ← match initializer with
          | .list .. => pure elementWords
          | .stringLiteral values _ _ _ => pure (max elementWords (values.size + 1))
          | .value value _ =>
              pure (if ← valueConsumesElement value then elementWords else 1)
        maximum := max maximum (cursor + width)
        cursor := cursor + width
      pure maximum

private def completeArrayFromInitializer (type : CType) (initializer : Initializer α)
    (valueConsumesElement : α → ParserM Bool) (pos : Pos) : ParserM CType := do
  match type with
  | .array element 0 =>
      let elementWords := element.wordSize
      if elementWords == 0 then failAt pos "cannot infer an array of incomplete elements"
      let words ← inferredInitializerWords elementWords valueConsumesElement initializer
      if words == 0 then failAt pos "cannot infer an array bound from an empty initializer"
      pure (.array element ((words + elementWords - 1) / elementWords))
  | _ => pure type

private def fileLinkage? (name : String) : ParserM (Option Linkage) := do
  pure <| (← get).fileLinkages.findSome? fun entry =>
    if entry.1 == name then some entry.2 else none

private def rememberFileLinkage (name : String) (linkage : Linkage) : ParserM Unit :=
  modify fun state =>
    if state.fileLinkages.any fun entry => entry.1 == name then state
    else { state with fileLinkages := (name, linkage) :: state.fileLinkages }

private def rememberFunctionName (name : String) : ParserM Unit :=
  modify fun state =>
    if state.functionNames.contains name then state
    else { state with functionNames := name :: state.functionNames }

private def isFunctionName (name : String) : ParserM Bool := do
  pure (name ∈ (← get).functionNames)

private def resolveFileLinkage (name : String) (explicitStatic : Bool)
    (pos : Pos) : ParserM Linkage := do
  let prior ← fileLinkage? name
  if explicitStatic then
    match prior with
    | some .external => failAt pos s!"conflicting linkage for '{name}'"
    | some .internal => pure .internal
    | none =>
        rememberFileLinkage name .internal
        pure .internal
  else
    match prior with
    | some linkage => pure linkage
    | none =>
        rememberFileLinkage name .external
        pure .external

private structure EnumConstInfixInfo where
  precedence : Nat
  op : BinaryOp

private def enumConstInfixInfo? : TokenKind → Option EnumConstInfixInfo
  | .symbol "||" => some { precedence := 1, op := .logicalOr }
  | .symbol "&&" => some { precedence := 2, op := .logicalAnd }
  | .symbol "|" => some { precedence := 3, op := .bitOr }
  | .symbol "^" => some { precedence := 4, op := .bitXor }
  | .symbol "&" => some { precedence := 5, op := .bitAnd }
  | .symbol "==" => some { precedence := 6, op := .eq }
  | .symbol "!=" => some { precedence := 6, op := .ne }
  | .symbol "<" => some { precedence := 7, op := .lt }
  | .symbol "<=" => some { precedence := 7, op := .le }
  | .symbol ">" => some { precedence := 7, op := .gt }
  | .symbol ">=" => some { precedence := 7, op := .ge }
  | .symbol "<<" => some { precedence := 8, op := .shl }
  | .symbol ">>" => some { precedence := 8, op := .shr }
  | .symbol "+" => some { precedence := 9, op := .add }
  | .symbol "-" => some { precedence := 9, op := .sub }
  | .symbol "*" => some { precedence := 10, op := .mul }
  | .symbol "/" => some { precedence := 10, op := .div }
  | .symbol "%" => some { precedence := 10, op := .mod }
  | _ => none

private def intOfBool (value : Bool) : Int := if value then 1 else 0

private def signedIntOfUInt32 (value : UInt32) : Int :=
  let magnitude := value.toNat
  if magnitude >= 0x80000000 then Int.ofNat magnitude - 0x100000000
  else Int.ofNat magnitude

private def uint32OfInt (value : Int) : UInt32 :=
  (Int.emod value 0x100000000).toNat.toUInt32

private def integerLiteralType (literal : IntegerToken) (pos : Pos) : ParserM CType := do
  let rank := if literal.isLong then IntegerRank.longRank else IntegerRank.intRank
  if literal.isUnsigned then
    pure (CType.cInteger rank false)
  else if literal.value >= -2147483648 && literal.value <= 2147483647 then
    pure (CType.cInteger rank true)
  else if literal.base != .decimal then
    -- C permits an unsuffixed octal/hexadecimal literal to select the first
    -- unsigned type of sufficient width.  int and long are both 32-bit words
    -- in this target ABI, so that type is unsigned int/long respectively.
    pure (CType.cInteger rank false)
  else
    failAt pos "decimal integer literal requires an unimplemented long long type"

private def requireSignedEnumInt (value : Int) (pos : Pos) : ParserM Unit := do
  if value < -2147483648 || value > 2147483647 then
    failAt pos "signed 32-bit overflow in integer constant expression"

private def signedEnumResult (value : Int) (pos : Pos) : ParserM Int := do
  requireSignedEnumInt value pos
  pure value

private structure IntegerSpecifiers where
  sign : Option Bool := none
  rank : Option IntegerRank := none
  sawInt : Bool := false

private def isIntegerSpecifier (name : String) : Bool :=
  name == "char" || name == "short" || name == "int" || name == "long" ||
    name == "signed" || name == "unsigned" || name == "_Bool"

private def IntegerSpecifiers.add (specifiers : IntegerSpecifiers) (name : String)
    (pos : Pos) : ParserM IntegerSpecifiers := do
  if name == "signed" || name == "unsigned" then
    if specifiers.sign.isSome then
      failAt pos "duplicate or conflicting signedness specifier"
    pure { specifiers with sign := some (name == "signed") }
  else if name == "int" then
    if specifiers.sawInt then failAt pos "duplicate 'int' type specifier"
    pure { specifiers with sawInt := true }
  else
    let rank :=
      if name == "_Bool" then IntegerRank.boolRank
      else if name == "char" then IntegerRank.charRank
      else if name == "short" then IntegerRank.shortRank
      else IntegerRank.longRank
    if specifiers.rank.isSome then
      if name == "long" && specifiers.rank == some .longRank then
        failAt pos "'long long' is not implemented by the 32-bit MDC target ABI"
      else
        failAt pos "conflicting integer type-width specifiers"
    pure { specifiers with rank := some rank }

private def parseIntegerBase (first : String) (firstPos : Pos)
    (initialQualifiers : TypeQualifiers) : ParserM (CType × TypeQualifiers) := do
  let mut specifiers ← ({} : IntegerSpecifiers).add first firstPos
  let mut qualifiers := initialQualifiers
  let mut scanning := true
  while scanning do
    match (← current).kind with
    | .identifier name =>
        if isIntegerSpecifier name then
          let token ← advance
          specifiers ← specifiers.add name token.pos
        else
          let declarationSpecifierAllowed :=
            (← get).pendingDeclarationSpecifiers.isSome && declarationSpecifierKeyword name
          if name == "const" || name == "volatile" || name == "restrict" ||
              declarationSpecifierAllowed then
            let extra ← parseTypeQualifiers
            qualifiers := qualifiers.merge extra
          else scanning := false
    | _ => scanning := false
  let rank := specifiers.rank.getD .intRank
  if rank == .boolRank && (specifiers.sign.isSome || specifiers.sawInt) then
    failAt firstPos "'_Bool' cannot be combined with a signedness or 'int' specifier"
  if rank == .charRank && specifiers.sawInt then
    failAt firstPos "'char' cannot be combined with 'int'"
  let type :=
    if rank == .boolRank then CType.boolType
    else if rank == .charRank && specifiers.sign.isNone then CType.plainChar
    else CType.cInteger rank (specifiers.sign.getD true)
  pure (type, qualifiers)

private partial def parserTypeContainsFlexibleArray (type : CType) : ParserM Bool := do
  match type.stripTopQualifiers with
  | .structType name _ =>
      pure ((← findAggregate? .structKind name).any (fun aggregate =>
        aggregate.containsFlexibleArray))
  | .unionType name _ =>
      pure ((← findAggregate? .unionKind name).any (fun aggregate =>
        aggregate.containsFlexibleArray))
  | .array element _ => parserTypeContainsFlexibleArray element
  | _ => pure false

private inductive DeclaratorShape where
  | name (name : Option String) (pos : Pos)
  | pointer (qualifiers : TypeQualifiers) (pos : Pos) (child : DeclaratorShape)
  | array (length : Nat) (pos : Pos) (child : DeclaratorShape)
  | function (parameters : Array Parameter) (pos : Pos) (child : DeclaratorShape)
deriving Inhabited

private structure ParsedDeclarator where
  type : CType
  name : Option String
  pos : Pos
  entityParameters : Option (Array Parameter) := none
deriving Inhabited

private partial def DeclaratorShape.applyType (shape : DeclaratorShape)
    (base : CType) : ParserM ParsedDeclarator := do
  match shape with
  | .name declaredName pos => pure { type := base, name := declaredName, pos := pos }
  | .pointer qualifiers pos child =>
      child.applyType (← qualifyType (.pointer base) qualifiers pos)
  | .array length pos child =>
      unless base.isObjectType do
        failAt pos "array element type must be a complete object type"
      if ← parserTypeContainsFlexibleArray base then
        failAt pos "an array element type may not contain a flexible array member"
      child.applyType (.array base length)
  | .function parameters pos child =>
      if base.isArray || base.isFunction then
        failAt pos "a function cannot return an array or function type"
      let parameterTypes := parameters.map fun parameter => parameter.type.decay
      child.applyType (.function base parameterTypes)

private partial def DeclaratorShape.entityParameters? : DeclaratorShape → Option (Array Parameter)
  | .name .. => none
  | .function parameters _ (.name ..) => some parameters
  | .pointer _ _ (.name ..) | .array _ _ (.name ..) => none
  | .pointer _ _ child | .array _ _ child | .function _ _ child => child.entityParameters?

private def peekToken (offset : Nat) : ParserM Token := do
  let state ← get
  pure <| state.tokens[state.index + offset]?.getD { kind := .eof, pos := default }

private def tokenCanStartType (token : Token) : ParserM Bool := do
  match token.kind with
  | .identifier name =>
      if name == "char" || name == "short" || name == "int" || name == "long" ||
          name == "signed" || name == "unsigned" ||
          name == "void" || name == "struct" || name == "union" ||
          name == "enum" || name == "_Atomic" ||
          name == "const" || name == "volatile" || name == "restrict" then
        pure true
      else
        pure <| match ← lookupBinding? name with
          | some (.typedefName ..) => true
          | _ => false
  | _ => pure false

private def parserAlignUp (value alignment : Nat) : Nat :=
  if alignment <= 1 then value else ((value + alignment - 1) / alignment) * alignment

private partial def parserTypeAlignment (type : CType) : ParserM Nat := do
  match type.stripTopQualifiers with
  | .array element _ => parserTypeAlignment element
  | .structType name _ =>
      pure ((← findAggregate? .structKind name).map (fun item => item.alignment) |>.getD 1)
  | .unionType name _ =>
      pure ((← findAggregate? .unionKind name).map (fun item => item.alignment) |>.getD 1)
  | _ => pure 1

private def applyEnumConstBinary (op : BinaryOp) (lhs rhs : Int) (pos : Pos) : ParserM Int := do
  requireSignedEnumInt lhs pos
  requireSignedEnumInt rhs pos
  match op with
  | .add => signedEnumResult (lhs + rhs) pos
  | .sub => signedEnumResult (lhs - rhs) pos
  | .mul => signedEnumResult (lhs * rhs) pos
  | .div =>
      if rhs == 0 then failAt pos "division by zero in enumerator constant expression"
      signedEnumResult (Int.tdiv lhs rhs) pos
  | .mod =>
      if rhs == 0 then failAt pos "remainder by zero in enumerator constant expression"
      if lhs == -2147483648 && rhs == -1 then
        failAt pos "signed 32-bit overflow in integer constant expression"
      pure (Int.tmod lhs rhs)
  | .shl | .shr =>
      if rhs < 0 || rhs >= 32 then
        failAt pos "enumerator shift count must be in 0..31"
      signedEnumResult (if op == .shl then lhs <<< rhs.toNat else lhs >>> rhs.toNat) pos
  | .lt => pure (intOfBool (lhs < rhs))
  | .le => pure (intOfBool (lhs <= rhs))
  | .gt => pure (intOfBool (lhs > rhs))
  | .ge => pure (intOfBool (lhs >= rhs))
  | .eq => pure (intOfBool (lhs == rhs))
  | .ne => pure (intOfBool (lhs != rhs))
  | .bitAnd => pure (signedIntOfUInt32 (uint32OfInt lhs &&& uint32OfInt rhs))
  | .bitXor => pure (signedIntOfUInt32 (uint32OfInt lhs ^^^ uint32OfInt rhs))
  | .bitOr => pure (signedIntOfUInt32 (uint32OfInt lhs ||| uint32OfInt rhs))
  | .logicalAnd => pure (intOfBool (lhs != 0 && rhs != 0))
  | .logicalOr => pure (intOfBool (lhs != 0 || rhs != 0))

mutual
  private partial def parseEnumConstPrec (minimum : Nat) (evaluate : Bool := true) : ParserM Int := do
    let mut lhs ← parseEnumConstPrefix evaluate
    let mut parsing := true
    while parsing do
      let token ← current
      match enumConstInfixInfo? token.kind with
      | some info =>
          if info.precedence < minimum then
            parsing := false
          else
            discard advance
            let shortCircuit := evaluate &&
              ((info.op == .logicalAnd && lhs == 0) ||
               (info.op == .logicalOr && lhs != 0))
            let rhs ← parseEnumConstPrec (info.precedence + 1)
              (evaluate && !shortCircuit)
            if evaluate then
              if shortCircuit then lhs := intOfBool (info.op == .logicalOr)
              else lhs ← applyEnumConstBinary info.op lhs rhs token.pos
            else
              lhs := 0
      | none => parsing := false
    pure lhs

  private partial def parseEnumConstPrefix (evaluate : Bool) : ParserM Int := do
    let token ← advance
    match token.kind with
    | .number literal => pure (if evaluate then literal.value else 0)
    | .character value _ => pure (if evaluate then value else 0)
    | .identifier "_Alignof" =>
        discard <| expectSymbol "("
        let (base, typePos) ← parseBaseType
        let parsed ←
          if ← symbol? ")" then
            pure { type := base, name := none, pos := typePos }
          else
            parseDeclaratorFull base true
        if parsed.name.isSome then
          failAt parsed.pos "_Alignof requires a type name, not a named declarator"
        discard <| expectSymbol ")"
        unless parsed.type.isObjectType do
          failAt typePos "_Alignof requires a complete object type"
        if evaluate then parserTypeAlignment parsed.type else pure 0
    | .identifier name =>
        match ← lookupBinding? name with
        | some (.enumConstant value _) => pure (if evaluate then value else 0)
        | _ => failAt token.pos s!"'{name}' is not an enumerator constant"
    | .symbol "+" => parseEnumConstPrec 11 evaluate
    | .symbol "-" =>
        let value ← parseEnumConstPrec 11 evaluate
        if evaluate then signedEnumResult (-value) token.pos else pure 0
    | .symbol "~" =>
        let value ← parseEnumConstPrec 11 evaluate
        if evaluate then
          requireSignedEnumInt value token.pos
          pure (~~~value)
        else pure 0
    | .symbol "!" =>
        let value ← parseEnumConstPrec 11 evaluate
        if evaluate then
          requireSignedEnumInt value token.pos
          pure (intOfBool (value == 0))
        else pure 0
    | .symbol "(" =>
        let value ← parseEnumConstPrec 0 evaluate
        discard <| expectSymbol ")"
        pure value
    | _ => failAt token.pos "expected an integer constant expression"
  private partial def parseBaseType : ParserM (CType × Pos) := do
    let leadingQualifiers ← parseTypeQualifiers
    let token ← advance
    let (base, qualifiers) ← match token.kind with
      | .identifier keyword =>
          if isIntegerSpecifier keyword then
            parseIntegerBase keyword token.pos leadingQualifiers
          else
            let base ← match keyword with
              | "void" => pure CType.void
              | "_Atomic" =>
                  discard <| expectSymbol "("
                  let (atomicBase, atomicPos) ← parseBaseType
                  let parsed ←
                    if ← symbol? ")" then
                      pure { type := atomicBase, name := none, pos := atomicPos }
                    else
                      parseDeclaratorFull atomicBase true
                  if parsed.name.isSome then
                    failAt parsed.pos "_Atomic requires a type name, not a named declarator"
                  discard <| expectSymbol ")"
                  if parsed.type.isArray || parsed.type.isFunction ||
                      parsed.type.isAtomicQualified ||
                      !parsed.type.topQualifiers.isEmpty then
                    failAt atomicPos
                      "_Atomic type specifier requires an unqualified non-array object type"
                  unless parsed.type.isObjectType do
                    failAt atomicPos "_Atomic type specifier requires a complete object type"
                  pure (parsed.type.withQualifiers { isAtomic := true })
              | "enum" =>
                  let (name, tagPos, named) ←
                    match (← current).kind with
                    | .identifier _ =>
                        let (name, pos) ← expectName
                        pure (name, pos, true)
                    | _ => pure (← freshAnonymousEnumName, token.pos, false)
                  if ← acceptSymbol "{" then
                    match ← findEnumTag? name with
                    | some prior =>
                        if prior.complete then
                          failAt tagPos s!"redefinition of enum '{name}'"
                    | none => pure ()
                    let mut nextValue : Int := 0
                    let mut count := 0
                    while !(← symbol? "}") do
                      let (enumerator, enumeratorPos) ← expectName
                      let value ←
                        if ← acceptSymbol "=" then parseEnumConstPrec 0
                        else pure nextValue
                      if value < -2147483648 || value > 2147483647 then
                        failAt enumeratorPos s!"enumerator '{enumerator}' is outside the signed 32-bit int range"
                      declareEnumConstant enumerator value enumeratorPos
                      nextValue := value + 1
                      count := count + 1
                      if ← acceptSymbol "," then
                        if ← symbol? "}" then break
                      else if !(← symbol? "}") then
                        failHere "expected ',' or '}' after enumerator"
                    if count == 0 then failAt token.pos "an enum definition requires an enumerator"
                    discard <| expectSymbol "}"
                    installEnumTag { name := name, complete := true, pos := tagPos }
                    pure (.enumType name)
                  else
                    if !named then failAt token.pos "anonymous enum requires a definition"
                    match ← findEnumTag? name with
                    | some prior =>
                        if !prior.complete then failAt tagPos s!"enum '{name}' is incomplete"
                        pure (.enumType name)
                    | none => failAt tagPos s!"use of undeclared enum tag '{name}'"
              | _ =>
                  let kind? :=
                    if keyword == "struct" then some AggregateKind.structKind
                    else if keyword == "union" then some AggregateKind.unionKind
                    else none
                  match kind? with
                  | none =>
                      match ← lookupBinding? keyword with
                      | some (.typedefName type _) => pure type
                      | _ => failAt token.pos "expected a C type specifier"
                  | some kind =>
                      let (name, _) ← expectName
                      if ← acceptSymbol "{" then
                        match ← findAggregate? kind name with
                        | some prior =>
                            if prior.size != 0 || !prior.members.isEmpty then
                              failAt token.pos s!"redefinition of {aggregateKindName kind} '{name}'"
                        | none => pure ()
                        installAggregate {
                          kind := kind, name := name, members := #[], size := 0, pos := token.pos }
                        let mut members := #[]
                        let mut structSize := 0
                        let mut structBitCursor := 0
                        let mut unionSize := 0
                        let mut aggregateAlignment := 1
                        let mut namedMemberCount := 0
                        let mut sawFlexibleArray := false
                        let mut aggregateContainsFlexibleArray := false
                        while !(← symbol? "}") do
                          if sawFlexibleArray then
                            failHere "a flexible array member must be the last member"
                          let pendingSpecifiers := (← get).pendingDeclarationSpecifiers
                          modify fun state => { state with pendingDeclarationSpecifiers := none }
                          let (memberBase, memberTypePos, memberSpecifiers) ←
                            parseDeclarationBaseType
                          modify fun state => {
                            state with pendingDeclarationSpecifiers := pendingSpecifiers }
                          if memberSpecifiers.storageClass.isSome then
                            failAt memberTypePos "a struct or union member may not have a storage class"
                          if memberSpecifiers.isThreadLocal then
                            failAt memberTypePos "a member may not be declared '_Thread_local'"
                          unless memberSpecifiers.function == {} do
                            failAt memberTypePos "a struct or union member may not have function specifiers"
                          let mut moreMembers := true
                          while moreMembers do
                            if sawFlexibleArray then
                              failHere "a flexible array member must be the last member"
                            let unnamedBitField := ← symbol? ":"
                            let (memberType, memberName, memberPos) ←
                              if unnamedBitField then
                                pure (memberBase, "", (← current).pos)
                              else
                                parseDeclarator memberBase
                            let bitWidth? ←
                              if ← acceptSymbol ":" then
                                let widthPos := (← current).pos
                                let width ← parseEnumConstPrec 0
                                if width < 0 then
                                  failAt widthPos "bit-field width must be nonnegative"
                                pure (some width.toNat)
                              else
                                if unnamedBitField then
                                  failAt memberPos "an unnamed member must be a bit-field"
                                pure none
                            let isFlexibleArray := match memberType.stripTopQualifiers with
                              | .array _ 0 => true
                              | _ => false
                            if memberType.isVoid ||
                                (!memberType.isObjectType && !isFlexibleArray) then
                              failAt memberTypePos s!"member '{memberName}' has incomplete type"
                            if isFlexibleArray then
                              if kind != .structKind then
                                failAt memberTypePos
                                  "a flexible array member is permitted only in a structure"
                              if memberName == "" then
                                failAt memberTypePos "a flexible array member must be named"
                              if bitWidth?.isSome then
                                failAt memberTypePos "a flexible array member may not be a bit-field"
                            if memberName != "" && members.any fun member =>
                                member.name == memberName then
                              failAt memberPos s!"duplicate member '{memberName}'"
                            if memberName != "" then namedMemberCount := namedMemberCount + 1
                            if isFlexibleArray && namedMemberCount < 2 then
                              failAt memberTypePos
                                "a flexible array member requires another named member"
                            let memberContainsFlexible ←
                              if isFlexibleArray then pure true
                              else parserTypeContainsFlexibleArray memberType
                            if kind == .structKind && memberContainsFlexible &&
                                !isFlexibleArray then
                              failAt memberTypePos
                                "a structure member type may not contain a flexible array member"
                            if memberContainsFlexible then
                              aggregateContainsFlexibleArray := true
                            let naturalAlignment ← parserTypeAlignment memberType
                            if memberSpecifiers.alignment.specified &&
                                memberSpecifiers.alignment.value < naturalAlignment then
                              failAt memberTypePos
                                "_Alignas may not weaken the natural alignment of a member"
                            let alignment := max naturalAlignment memberSpecifiers.alignment.value
                            aggregateAlignment := max aggregateAlignment alignment
                            match bitWidth? with
                            | some width =>
                                if memberSpecifiers.alignment.specified then
                                  failAt memberTypePos
                                    "_Alignas may not be applied to a bit-field"
                                if memberType.isAtomicQualified then
                                  failAt memberTypePos "an atomic type may not be used for a bit-field"
                                let bitCapacity ←
                                  match memberType.stripTopQualifiers with
                                  | .boolType => pure 1
                                  | .int | .integer .intRank _ => pure 32
                                  | _ => failAt memberTypePos "a bit-field must have type _Bool, signed int, or unsigned int"
                                if width > bitCapacity then
                                  failAt memberPos s!"bit-field width exceeds its {bitCapacity}-bit type"
                                if width == 0 && memberName != "" then
                                  failAt memberPos "a zero-width bit-field must be unnamed"
                                let (offset, bitOffset) :=
                                  if kind == .unionKind then
                                    (0, 0)
                                  else if width == 0 then
                                    (structSize, 0)
                                  else if structBitCursor != 0 &&
                                      structBitCursor + width <= 32 then
                                    (structSize - 1, structBitCursor)
                                  else
                                    (parserAlignUp structSize alignment, 0)
                                members := members.push {
                                  type := memberType, name := memberName, offset := offset,
                                  bitWidth := some width, bitOffset := bitOffset,
                                  alignment := { value := alignment }, pos := memberPos }
                                if kind == .unionKind then
                                  if width != 0 then unionSize := max unionSize 1
                                else if width == 0 then
                                  structBitCursor := 0
                                else
                                  if bitOffset == 0 then structSize := offset + 1
                                  let nextBit := bitOffset + width
                                  structBitCursor := if nextBit == 32 then 0 else nextBit
                            | none =>
                                structBitCursor := 0
                                let offset :=
                                  if kind == .structKind then
                                    parserAlignUp structSize alignment
                                  else 0
                                members := members.push {
                                  type := memberType, name := memberName, offset := offset,
                                  alignment := {
                                    memberSpecifiers.alignment with value := alignment },
                                  pos := memberPos }
                                if isFlexibleArray then
                                  structSize := offset
                                  sawFlexibleArray := true
                                else if kind == .structKind then
                                  structSize := offset + memberType.wordSize
                                else unionSize := max unionSize memberType.wordSize
                            moreMembers := ← acceptSymbol ","
                          discard <| expectSymbol ";"
                        discard <| expectSymbol "}"
                        let rawSize := if kind == .structKind then structSize else unionSize
                        let size := parserAlignUp rawSize aggregateAlignment
                        if namedMemberCount == 0 then
                          failAt token.pos
                            s!"{aggregateKindName kind} '{name}' requires a named member"
                        let aggregate := {
                          kind := kind, name := name, members := members, size := size,
                          alignment := aggregateAlignment,
                          containsFlexibleArray := aggregateContainsFlexibleArray,
                          pos := token.pos }
                        installAggregate aggregate
                        pure (aggregateType kind name size)
                      else
                        let size := (← findAggregate? kind name).map (fun item => item.size) |>.getD 0
                        pure (aggregateType kind name size)
            let trailingQualifiers ← parseTypeQualifiers
            pure (base, leadingQualifiers.merge trailingQualifiers)
      | _ => failAt token.pos "expected a C type specifier"
    pure (← qualifyType base qualifiers token.pos, token.pos)

  private partial def parseDeclaratorShape (allowAbstract : Bool) : ParserM DeclaratorShape := do
    let mut pointers : Array (TypeQualifiers × Pos) := #[]
    while ← acceptSymbol "*" do
      let pointerPos := (← current).pos
      let qualifiers ← parseTypeQualifiers
      pointers := pointers.push (qualifiers, pointerPos)

    let token ← current
    let mut shape ← match token.kind with
      | .identifier name =>
          discard advance
          pure (.name (some name) token.pos)
      | .symbol "(" =>
          let startsParameterList ← tokenCanStartType (← peekToken 1)
          if allowAbstract && startsParameterList then
            pure (.name none token.pos)
          else
            discard advance
            let nested ← parseDeclaratorShape allowAbstract
            discard <| expectSymbol ")"
            pure nested
      | _ =>
          if allowAbstract then pure (.name none token.pos)
          else failAt token.pos "expected identifier or parenthesized declarator"

    let mut suffixes := true
    while suffixes do
      if ← acceptSymbol "[" then
        let lengthPos := (← current).pos
        let lengthValue ←
          if ← symbol? "]" then pure 0
          else
            let value ← parseEnumConstPrec 0
            if value <= 0 then failAt lengthPos "array length must be positive"
            pure value.toNat
        discard <| expectSymbol "]"
        shape := .array lengthValue lengthPos shape
      else if ← acceptSymbol "(" then
        let functionPos := token.pos
        let parameters ← parseParameterList
        discard <| expectSymbol ")"
        shape := .function parameters functionPos shape
      else
        suffixes := false

    for (qualifiers, pointerPos) in pointers.reverse do
      shape := .pointer qualifiers pointerPos shape
    pure shape

  private partial def parseDeclaratorFull (base : CType) (allowAbstract : Bool := false) :
      ParserM ParsedDeclarator := do
    let shape ← parseDeclaratorShape allowAbstract
    let parsed ← shape.applyType base
    pure { parsed with entityParameters := shape.entityParameters? }

  private partial def parseDeclarator (base : CType) : ParserM (CType × String × Pos) := do
    let parsed ← parseDeclaratorFull base
    match parsed.name with
    | some name => pure (parsed.type, name, parsed.pos)
    | none => failAt parsed.pos "declaration requires an identifier"

  private partial def parseParameterList : ParserM (Array Parameter) := do
    let mut parameters := #[]
    unless ← symbol? ")" do
      let mut more := true
      while more do
        let isRegister ← acceptIdentifier "register"
        if ← identifier? "_Thread_local" then
          failHere "'_Thread_local' may not be used in a parameter declaration"
        if ← identifier? "_Alignas" then
          failHere "_Alignas may not be used in a parameter declaration"
        if ← identifier? "auto" then
          failHere "'auto' is not permitted in a parameter declaration"
        let (base, typePos) ← parseBaseType
        let parsed ←
          if (← symbol? ",") || (← symbol? ")") then
            pure { type := base, name := none, pos := typePos }
          else
            parseDeclaratorFull base true
        if parsed.type.isVoid then
          if parameters.isEmpty && parsed.name.isNone && (← symbol? ")") then
            return #[]
          failAt typePos "'void' must be the only unnamed parameter"
        let parameterType := parsed.type.decay
        unless parameterType.isObjectType do
          failAt typePos "parameter type must adjust to a complete object type"
        let name := parsed.name.getD ""
        if !name.isEmpty && parameters.any fun parameter => parameter.name == name then
          failAt parsed.pos s!"duplicate parameter '{name}'"
        parameters := parameters.push {
          type := parameterType, name := name, pos := typePos, isRegister := isRegister }
        more := ← acceptSymbol ","
    pure parameters

  private partial def parseDeclarationBaseType :
      ParserM (CType × Pos × DeclarationSpecifiers) := do
    if (← get).pendingDeclarationSpecifiers.isSome then
      failHere "internal parser error: nested declaration-specifier context"
    modify fun state => { state with pendingDeclarationSpecifiers := some {} }
    let (type, pos) ← parseBaseType
    let mut specifiers := (← get).pendingDeclarationSpecifiers.getD {}
    modify fun state => { state with pendingDeclarationSpecifiers := none }
    let mut requestedAlignment := 1
    for operand in specifiers.alignmentOperands do
      let outer ← get
      let eofPos := operand.back?.map (fun token => token.pos) |>.getD pos
      set { outer with
        tokens := operand.push { kind := .eof, pos := eofPos }
        index := 0
        pendingDeclarationSpecifiers := none }
      let alignment ←
        if ← typeStart then
          let (base, alignmentPos) ← parseBaseType
          let parsed ←
            if (← current).kind == .eof then
              pure { type := base, name := none, pos := alignmentPos }
            else
              parseDeclaratorFull base true
          if parsed.name.isSome then
            failAt parsed.pos "_Alignas requires a type name, not a named declarator"
          unless (← current).kind == .eof do
            failHere "unexpected token after _Alignas type name"
          unless parsed.type.isObjectType do
            failAt alignmentPos "_Alignas type operand must be a complete object type"
          parserTypeAlignment parsed.type
        else
          let alignmentPos := (← current).pos
          let value ← parseEnumConstPrec 0
          unless (← current).kind == .eof do
            failHere "unexpected token after _Alignas constant expression"
          if value < 0 then failAt alignmentPos "_Alignas value must be nonnegative"
          pure value.toNat
      let inner ← get
      set { inner with
        tokens := outer.tokens
        index := outer.index
        pendingDeclarationSpecifiers := outer.pendingDeclarationSpecifiers }
      if alignment != 0 then
        let mut quotient := alignment
        while quotient > 1 do
          if quotient % 2 != 0 then
            failAt pos "_Alignas value must be zero or a power of two"
          quotient := quotient / 2
        if alignment > 64 then
          failAt pos "_Alignas values above 64 words are not supported by the MDC process ABI"
        requestedAlignment := max requestedAlignment alignment
    specifiers := { specifiers with alignment := {
      specified := !specifiers.alignmentOperands.isEmpty
      value := requestedAlignment } }
    pure (type, pos, specifiers)
end

private def effectiveObjectAlignment (type : CType) (alignment : AlignmentSpec)
    (pos : Pos) : ParserM AlignmentSpec := do
  let natural ← parserTypeAlignment type
  if alignment.specified && alignment.value < natural then
    failAt pos "_Alignas may not weaken the natural alignment of an object"
  pure { alignment with value := max alignment.value natural }

private def parseTypedefDeclarators (base : CType) (typePos : Pos) : ParserM Unit := do
  let mut more := true
  while more do
    let (type, name, namePos) ← parseDeclarator base
    match type.arrayElement? with
    | some (element, _) =>
        unless element.isObjectType do
          failAt typePos s!"typedef '{name}' has an invalid array element type"
    | none => pure ()
    if ← symbol? "=" then
      failHere "a typedef declaration cannot have an initializer"
    declareTypedef name type namePos
    more := ← acceptSymbol ","
  discard <| expectSymbol ";"

private inductive InfixOp where
  | comma
  | assign
  | compoundAssign (op : BinaryOp)
  | binary (op : BinaryOp)

private structure InfixInfo where
  precedence : Nat
  rightAssociative : Bool := false
  op : InfixOp

private def infixInfo? : TokenKind → Option InfixInfo
  | .symbol "," => some { precedence := 0, op := .comma }
  | .symbol "=" => some { precedence := 1, rightAssociative := true, op := .assign }
  | .symbol "+=" => some { precedence := 1, rightAssociative := true, op := .compoundAssign .add }
  | .symbol "-=" => some { precedence := 1, rightAssociative := true, op := .compoundAssign .sub }
  | .symbol "*=" => some { precedence := 1, rightAssociative := true, op := .compoundAssign .mul }
  | .symbol "/=" => some { precedence := 1, rightAssociative := true, op := .compoundAssign .div }
  | .symbol "%=" => some { precedence := 1, rightAssociative := true, op := .compoundAssign .mod }
  | .symbol "<<=" => some { precedence := 1, rightAssociative := true, op := .compoundAssign .shl }
  | .symbol ">>=" => some { precedence := 1, rightAssociative := true, op := .compoundAssign .shr }
  | .symbol "&=" => some { precedence := 1, rightAssociative := true, op := .compoundAssign .bitAnd }
  | .symbol "^=" => some { precedence := 1, rightAssociative := true, op := .compoundAssign .bitXor }
  | .symbol "|=" => some { precedence := 1, rightAssociative := true, op := .compoundAssign .bitOr }
  | .symbol "||" => some { precedence := 3, op := .binary .logicalOr }
  | .symbol "&&" => some { precedence := 4, op := .binary .logicalAnd }
  | .symbol "|" => some { precedence := 5, op := .binary .bitOr }
  | .symbol "^" => some { precedence := 6, op := .binary .bitXor }
  | .symbol "&" => some { precedence := 7, op := .binary .bitAnd }
  | .symbol "==" => some { precedence := 8, op := .binary .eq }
  | .symbol "!=" => some { precedence := 8, op := .binary .ne }
  | .symbol "<" => some { precedence := 9, op := .binary .lt }
  | .symbol "<=" => some { precedence := 9, op := .binary .le }
  | .symbol ">" => some { precedence := 9, op := .binary .gt }
  | .symbol ">=" => some { precedence := 9, op := .binary .ge }
  | .symbol "<<" => some { precedence := 10, op := .binary .shl }
  | .symbol ">>" => some { precedence := 10, op := .binary .shr }
  | .symbol "+" => some { precedence := 11, op := .binary .add }
  | .symbol "-" => some { precedence := 11, op := .binary .sub }
  | .symbol "*" => some { precedence := 12, op := .binary .mul }
  | .symbol "/" => some { precedence := 12, op := .binary .div }
  | .symbol "%" => some { precedence := 12, op := .binary .mod }
  | _ => none

private def parseInitializerDesignators : ParserM (Array InitializerDesignator) := do
  let mut designators := #[]
  let mut parsing := true
  while parsing do
    if ← acceptSymbol "." then
      let (name, pos) ← expectName
      designators := designators.push (.member name pos)
    else if ← acceptSymbol "[" then
      let pos := (← current).pos
      let value ← parseEnumConstPrec 0
      if value < 0 then failAt pos "array designator index must be nonnegative"
      discard <| expectSymbol "]"
      designators := designators.push (.index value pos)
    else
      parsing := false
  pure designators

private def parsedMemberType? (aggregateType : CType) (name : String) :
    ParserM (Option CType) := do
  let aggregate? ← match aggregateType.stripTopQualifiers with
    | .structType tag _ => findAggregate? .structKind tag
    | .unionType tag _ => findAggregate? .unionKind tag
    | _ => pure none
  pure <| aggregate?.bind fun aggregate =>
    (aggregate.members.find? fun member => member.name == name).map fun member => member.type

mutual
  private partial def parsedExprType? : Expr → ParserM (Option CType)
    | .intLit _ type _ => pure (some type)
    | .variable name _ => do
        pure <| match ← lookupBinding? name with
          | some (.ordinary (some type) _) => some type.toRValue
          | _ => none
    | .call name _ _ _ => do
        pure <| match ← lookupBinding? name with
          | some (.ordinary (some type) _) =>
              match type.functionSignature? with
              | some (returnType, _) => some returnType.toRValue
              | none => type.toRValue.functionPointerSignature?.map fun signature =>
                  signature.1.toRValue
          | _ => none
    | .indirectCall callee _ _ _ => do
        pure <| (← parsedExprType? callee).bind fun type =>
          type.toRValue.functionPointerSignature?.map fun signature => signature.1.toRValue
    | .assign target _ _ | .compoundAssign _ target _ _ |
        .postfix _ target _ | .prefix _ target _ => do
          pure <| (← parsedLValueType? target).map CType.toRValue
    | .conditional _ thenValue elseValue _ => do
        let thenType ← parsedExprType? thenValue
        let elseType ← parsedExprType? elseValue
        pure <| match thenType, elseType with
          | some lhs, some rhs => if lhs.stripTopQualifiers == rhs.stripTopQualifiers then some lhs else none
          | _, _ => none
    | .comma _ rhs _ => parsedExprType? rhs
    | .cast type _ _ => pure (some type.toRValue)
    | .genericSelection control associations _ => do
        match ← parsedExprType? control with
        | none => pure none
        | some controlType =>
            let key := controlType.toRValue.stripTopQualifiers
            let selected? := associations.findSome? fun association =>
              association.1.bind fun type =>
                if type.stripTopQualifiers == key then some association.2 else none
            let default? := associations.findSome? fun association =>
              if association.1.isNone then some association.2 else none
            match selected?.orElse (fun _ => default?) with
            | some selected => parsedExprType? selected
            | none => pure none
    | .compoundLiteral type _ _ _ => pure (some type.toRValue)
    | .unary .addressOf value _ => do
        pure <| (← parsedLValueType? value).map CType.pointer
    | .unary .dereference value _ => do
        pure <| (← parsedExprType? value).bind CType.pointerPointee? |>.map CType.toRValue
    | .unary .. | .binary .. => pure (some .int)
    | .sizeofExpr .. | .sizeofType .. | .alignofType .. =>
        pure (some (CType.cInteger .longRank false))
    | .subscript base _ _ => do
        pure <| (← parsedExprType? base).bind CType.pointerPointee? |>.map CType.toRValue
    | .member base name indirect _ => do
        let aggregateType? ←
          if indirect then
            pure <| (← parsedExprType? base).bind CType.pointerPointee?
          else
            match ← parsedLValueType? base with
            | some type => pure (some type)
            | none => parsedExprType? base
        match aggregateType? with
        | some type => pure <| (← parsedMemberType? type name).map CType.toRValue
        | none => pure none

  private partial def parsedLValueType? : Expr → ParserM (Option CType)
    | .variable name _ => do
        pure <| match ← lookupBinding? name with
          | some (.ordinary (some type) _) => some type
          | _ => none
    | .compoundLiteral type _ _ _ => pure (some type)
    | .unary .dereference value _ => do
        pure <| (← parsedExprType? value).bind CType.pointerPointee?
    | .subscript base _ _ => do
        pure <| (← parsedExprType? base).bind CType.pointerPointee?
    | .member base name indirect _ => do
        let aggregateType? ←
          if indirect then pure <| (← parsedExprType? base).bind CType.pointerPointee?
          else parsedLValueType? base
        match aggregateType? with
        | some type => parsedMemberType? type name
        | none => pure none
    | .genericSelection control associations _ => do
        match ← parsedExprType? control with
        | none => pure none
        | some controlType =>
            let key := controlType.toRValue.stripTopQualifiers
            let selected? := associations.findSome? fun association =>
              association.1.bind fun type =>
                if type.stripTopQualifiers == key then some association.2 else none
            let default? := associations.findSome? fun association =>
              if association.1.isNone then some association.2 else none
            match selected?.orElse (fun _ => default?) with
            | some selected => parsedLValueType? selected
            | none => pure none
    | _ => pure none
end

private def automaticInitializerConsumesElement (element : CType) (value : Expr) :
    ParserM Bool := do
  if !element.toRValue.isAggregate then return false
  match ← parsedExprType? value with
  | some source => pure (source.stripTopQualifiers == element.stripTopQualifiers)
  | none => pure false

mutual
  private partial def parseAutomaticInitializer : ParserM (Initializer Expr) := do
    let token ← current
    if ← acceptSymbol "{" then
      parseAutomaticInitializerList token.pos
    else
      match token.kind with
      | .stringLiteral _ _ =>
          let (values, encoding, pos) ← consumeAdjacentStringLiterals
          let name ← installStringLiteral values encoding pos
          pure (.stringLiteral values encoding name pos)
      | _ => pure (.value (← parseExprPrec 1) token.pos)

  private partial def parseAutomaticInitializerList (pos : Pos) :
      ParserM (Initializer Expr) := do
    let mut elements := #[]
    unless ← symbol? "}" do
      let mut more := true
      while more do
        let designators ← parseInitializerDesignators
        unless designators.isEmpty do discard <| expectSymbol "="
        let initializer ← parseAutomaticInitializer
        elements := elements.push (designators, initializer)
        if ← acceptSymbol "," then
          more := !(← symbol? "}")
        else
          more := false
    discard <| expectSymbol "}"
    pure (.list elements pos)

  private partial def parseExprPrec (minimum : Nat) : ParserM Expr := do
    let mut lhs ← parsePrefix
    let mut looping := true
    while looping do
      let token ← current
      if token.kind == .symbol "?" && minimum <= 2 then
        discard advance
        let thenValue ← parseExprPrec 0
        discard <| expectSymbol ":"
        let elseValue ← parseExprPrec 2
        lhs := .conditional lhs thenValue elseValue token.pos
      else
        match infixInfo? token.kind with
        | none => looping := false
        | some info =>
            if info.precedence < minimum then
              looping := false
            else
              discard advance
              let rhs ← parseExprPrec (if info.rightAssociative then info.precedence
                                       else info.precedence + 1)
              match info.op with
              | .comma => lhs := .comma lhs rhs token.pos
              | .assign =>
                  lhs := .assign lhs rhs lhs.pos
              | .compoundAssign op =>
                  lhs := .compoundAssign op lhs rhs token.pos
              | .binary op => lhs := .binary op lhs rhs token.pos
    pure lhs

  private partial def parsePrefix : ParserM Expr := do
    let token ← advance
    let value ← match token.kind with
      | .symbol "-" => pure (.unary .neg (← parseExprPrec 13) token.pos)
      | .symbol "!" => pure (.unary .logicalNot (← parseExprPrec 13) token.pos)
      | .symbol "~" => pure (.unary .bitNot (← parseExprPrec 13) token.pos)
      | .symbol "&" => pure (.unary .addressOf (← parseExprPrec 13) token.pos)
      | .symbol "*" => pure (.unary .dereference (← parseExprPrec 13) token.pos)
      | .symbol "+" => parseExprPrec 13
      | .symbol "++" => pure (.prefix .inc (← parseExprPrec 13) token.pos)
      | .symbol "--" => pure (.prefix .dec (← parseExprPrec 13) token.pos)
      | .number literal => pure (.intLit literal.value (← integerLiteralType literal token.pos) token.pos)
      | .character value encoding =>
          pure (.intLit value encoding.characterType token.pos)
      | .stringLiteral first firstEncoding =>
          let mut units := first
          let mut encoding := firstEncoding
          while true do
            match (← current).kind with
            | .stringLiteral part partEncoding =>
                encoding ← mergeLiteralEncodings encoding partEncoding (← current).pos
                units := units ++ part
                discard advance
            | _ => break
          let name ← installStringLiteral (encoding.encodeUnits units) encoding token.pos
          pure (.variable name token.pos)
      | .identifier name =>
          if name == "ATOMIC_VAR_INIT" then
            discard <| expectSymbol "("
            let value ← parseExprPrec 0
            discard <| expectSymbol ")"
            pure value
          else if name == "sizeof" then
            discard <| expectSymbol "("
            let result ←
              if ← typeStart then
                let (base, _) ← parseBaseType
                let type ←
                  if ← symbol? ")" then pure base
                  else pure (← parseDeclaratorFull base true).type
                pure (.sizeofType type token.pos)
              else
                pure (.sizeofExpr (← parseExprPrec 0) token.pos)
            discard <| expectSymbol ")"
            pure result
          else if name == "_Alignof" then
            discard <| expectSymbol "("
            unless ← typeStart do
              failAt token.pos "_Alignof requires a parenthesized type name"
            let (base, typePos) ← parseBaseType
            let parsed ←
              if ← symbol? ")" then
                pure { type := base, name := none, pos := typePos }
              else
                parseDeclaratorFull base true
            if parsed.name.isSome then
              failAt parsed.pos "_Alignof requires a type name, not a named declarator"
            discard <| expectSymbol ")"
            pure (.alignofType parsed.type token.pos)
          else if name == "_Generic" then
            discard <| expectSymbol "("
            let control ← parseExprPrec 1
            discard <| expectSymbol ","
            let mut associations : Array (Option CType × Expr) := #[]
            let mut sawDefault := false
            let mut more := true
            while more do
              let associationType? ←
                if ← acceptIdentifier "default" then
                  if sawDefault then
                    failAt token.pos "a generic association list may contain only one default"
                  sawDefault := true
                  pure none
                else
                  unless ← typeStart do
                    failHere "expected a type name or 'default' in generic association"
                  let (base, typePos) ← parseBaseType
                  let parsed ←
                    if ← symbol? ":" then
                      pure { type := base, name := none, pos := typePos }
                    else
                      parseDeclaratorFull base true
                  if parsed.name.isSome then
                    failAt parsed.pos
                      "a generic association requires a type name, not a named declarator"
                  unless parsed.type.isObjectType do
                    failAt typePos
                      "a generic association type must be a complete object type"
                  if associations.any fun association =>
                      association.1.any fun prior => prior == parsed.type then
                    failAt typePos
                      "a generic association list may not contain compatible duplicate types"
                  pure (some parsed.type)
              discard <| expectSymbol ":"
              let result ← parseExprPrec 1
              associations := associations.push (associationType?, result)
              more := ← acceptSymbol ","
            discard <| expectSymbol ")"
            pure (.genericSelection control associations token.pos)
          else
            match ← lookupBinding? name with
            | some (.enumConstant constant _) => pure (.intLit constant .int token.pos)
            | _ =>
                if ← acceptSymbol "(" then
                  let mut args := #[]
                  unless ← symbol? ")" do
                    args := args.push (← parseExprPrec 1)
                    while ← acceptSymbol "," do
                      args := args.push (← parseExprPrec 1)
                  discard <| expectSymbol ")"
                  let destination ←
                    if ← acceptSymbol "@" then pure (some (← parseExprPrec 13)) else pure none
                  pure (.call name args destination token.pos)
                else pure (.variable name token.pos)
      | .symbol "(" =>
          if ← typeStart then
            let (base, _) ← parseBaseType
            let type ←
              if ← symbol? ")" then pure base
              else pure (← parseDeclaratorFull base true).type
            discard <| expectSymbol ")"
            if ← symbol? "{" then
              let initializer ← parseAutomaticInitializer
              let completedType ← completeArrayFromInitializer type initializer
                (fun value => match type.arrayElement? with
                  | some (element, _) => automaticInitializerConsumesElement element value
                  | none => pure false) token.pos
              pure (.compoundLiteral completedType initializer
                (← parserTypeAlignment completedType) token.pos)
            else
              pure (.cast type (← parseExprPrec 13) token.pos)
          else
            let nested ← parseExprPrec 0
            discard <| expectSymbol ")"
            pure nested
      | _ => failAt token.pos "expected expression"
    let mut result := value
    let mut looping := true
    while looping do
      if ← acceptSymbol "(" then
        let callPos := result.pos
        let mut args := #[]
        unless ← symbol? ")" do
          args := args.push (← parseExprPrec 1)
          while ← acceptSymbol "," do
            args := args.push (← parseExprPrec 1)
        discard <| expectSymbol ")"
        let destination ←
          if ← acceptSymbol "@" then pure (some (← parseExprPrec 13)) else pure none
        result := .indirectCall result args destination callPos
      else if ← acceptSymbol "[" then
        let index ← parseExprPrec 0
        discard <| expectSymbol "]"
        result := .subscript result index result.pos
      else if ← acceptSymbol "." then
        let (name, memberPos) ← expectName
        result := .member result name false memberPos
      else if ← acceptSymbol "->" then
        let (name, memberPos) ← expectName
        result := .member result name true memberPos
      else if ← acceptSymbol "++" then
        result := .postfix .inc result result.pos
        looping := false
      else if ← acceptSymbol "--" then
        result := .postfix .dec result result.pos
        looping := false
      else looping := false
    pure result
end

private def parseExpr : ParserM Expr := parseExprPrec 0

private def parseConstantInitializer : ParserM ConstantInitializer := do
  if ← acceptSymbol "&" then
    let (name, pos) ← expectName
    if ← isFunctionName name then pure (.functionDesignator name pos)
    else
      match ← lookupBinding? name with
      | some (.ordinary _ _) => pure (.objectDesignator name false pos)
      | _ => failAt pos s!"'{name}' is not an object or function constant"
  else
    let token ← current
    match token.kind with
    | .stringLiteral _ _ => failAt token.pos "internal parser error: unclassified string initializer"
    | .identifier name =>
        match ← lookupBinding? name with
        | some (.ordinary _ _) =>
            unless ← isFunctionName name do
              failAt token.pos s!"'{name}' is not an enumerator constant"
            discard advance
            pure (.functionDesignator name token.pos)
        | _ => pure (.integer (← parseEnumConstPrec 0))
    | _ => pure (.integer (← parseEnumConstPrec 0))

private partial def parseStaticInitializer : ParserM (Initializer ConstantInitializer) := do
  let token ← current
  if token.kind == .identifier "ATOMIC_VAR_INIT" then
    discard advance
    discard <| expectSymbol "("
    let initializer ← parseStaticInitializer
    discard <| expectSymbol ")"
    pure initializer
  else if ← acceptSymbol "{" then
    let mut elements := #[]
    unless ← symbol? "}" do
      let mut more := true
      while more do
        let designators ← parseInitializerDesignators
        unless designators.isEmpty do discard <| expectSymbol "="
        let initializer ← parseStaticInitializer
        elements := elements.push (designators, initializer)
        if ← acceptSymbol "," then more := !(← symbol? "}")
        else more := false
    discard <| expectSymbol "}"
    pure (.list elements token.pos)
  else
    match token.kind with
    | .stringLiteral _ _ =>
        let (values, encoding, pos) ← consumeAdjacentStringLiterals
        let name ← installStringLiteral values encoding pos
        pure (.stringLiteral values encoding name pos)
    | _ => pure (.value (← parseConstantInitializer) token.pos)

private def parseStaticInitialValues (type : CType) :
    ParserM (Bool × CType × Option (Initializer ConstantInitializer)) := do
  let hasInitializer ← acceptSymbol "="
  if hasInitializer then
    let initializer ← parseStaticInitializer
    let completedType ← completeArrayFromInitializer type initializer
      (fun _ => pure false) initializer.pos
    pure (true, completedType, some initializer)
  else
    pure (false, type, none)

private def parseAutomaticInitialValues (declaredType : CType) :
    ParserM (CType × Option (Initializer Expr)) := do
  let hasInitializer ← acceptSymbol "="
  if hasInitializer then
    let initializer ← parseAutomaticInitializer
    let type ← completeArrayFromInitializer declaredType initializer
      (fun value => match declaredType.arrayElement? with
        | some (element, _) => automaticInitializerConsumesElement element value
        | none => pure false) initializer.pos
    pure (type, some initializer)
  else
    pure (declaredType, none)

private def parseStaticAssertion : ParserM Unit := do
  let token ← advance
  unless token.kind == .identifier "_Static_assert" do
    failAt token.pos "internal parser error: expected _Static_assert"
  discard <| expectSymbol "("
  let condition ← parseEnumConstPrec 0
  discard <| expectSymbol ","
  let messageToken ← current
  let (messageValues, _, _) ← match messageToken.kind with
    | .stringLiteral _ _ => consumeAdjacentStringLiterals
    | _ => failAt messageToken.pos "_Static_assert requires a string literal message"
  discard <| expectSymbol ")"
  discard <| expectSymbol ";"
  if condition == 0 then
    let message := messageValues.foldl
      (fun result value => result.push (Char.ofNat value.toNat)) ""
    failAt token.pos s!"static assertion failed: {message}"

private def finishDeclarationGroup (declarations : Array Stmt) (pos : Pos) : Stmt :=
  if declarations.size == 1 then declarations[0]!
  else .declarationGroup declarations pos

private def parseAutomaticDeclarators (base : CType) (typePos declarationPos : Pos)
    (allowFunctionDeclarations : Bool := true) (isRegister : Bool := false)
    (functionSpecifiers : FunctionSpecifiers := {}) (alignment : AlignmentSpec := {}) :
    ParserM Stmt := do
  let mut declarations := #[]
  let mut more := true
  while more do
    let (parsedType, name, namePos) ← parseDeclarator base
    match parsedType.functionSignature? with
    | some (returnType, parameterTypes) =>
        if alignment.specified then
          failAt typePos "_Alignas may not be used in a function declaration"
        unless allowFunctionDeclarations && !isRegister do
          failAt namePos "a declaration in this context may declare only objects"
        if ← symbol? "=" then
          failAt namePos "a function declaration cannot have an initializer"
        declareOrdinary name namePos true (some parsedType)
        rememberFunctionName name
        let linkage ← resolveFileLinkage name false namePos
        let parameters := parameterTypes.map fun type =>
          { type := type, name := "", pos := typePos }
        modify fun state => { state with
          blockFunctionDeclarations := state.blockFunctionDeclarations.push {
            returnType := returnType, name := name, parameters := parameters,
            pos := typePos, linkage := linkage, specifiers := functionSpecifiers,
            fileScope := false } }
        declarations := declarations.push (.functionDeclaration parsedType name namePos)
    | none =>
        unless functionSpecifiers == {} do
          failAt typePos "function specifiers may be used only in a function declaration"
        if isRegister && alignment.specified then
          failAt typePos "_Alignas may not be used on a register object"
        if parsedType.isVoid then failAt typePos "local variable cannot have type void"
        declareOrdinary name namePos false (some parsedType)
        let (type, initializers) ← parseAutomaticInitialValues parsedType
        unless type.isObjectType do
          failAt typePos "local declaration must have a complete object type"
        let alignment ← effectiveObjectAlignment type alignment typePos
        declarations := declarations.push <|
          if isRegister then .registerDeclaration type name initializers namePos
          else .declaration type name initializers alignment namePos
    more := ← acceptSymbol ","
  discard <| expectSymbol ";"
  pure (finishDeclarationGroup declarations declarationPos)

private def parseExternBlockDeclarators (base : CType) (typePos declarationPos : Pos)
    (functionSpecifiers : FunctionSpecifiers := {}) (alignment : AlignmentSpec := {})
    (isThreadLocal : Bool := false) :
    ParserM Stmt := do
  let mut declarations := #[]
  let mut more := true
  while more do
    let (parsedType, name, namePos) ← parseDeclarator base
    if ← symbol? "=" then
      failAt namePos "a block-scope extern declaration cannot have an initializer"
    declareOrdinary name namePos true (some parsedType)
    let linkage ← resolveFileLinkage name false namePos
    match parsedType.functionSignature? with
    | some (returnType, parameterTypes) =>
        if isThreadLocal then
          failAt typePos "'_Thread_local' may not be applied to a function"
        if alignment.specified then
          failAt typePos "_Alignas may not be used in a function declaration"
        rememberFunctionName name
        let parameters := parameterTypes.map fun type =>
          { type := type, name := "", pos := typePos }
        modify fun state => { state with
          blockFunctionDeclarations := state.blockFunctionDeclarations.push {
            returnType := returnType, name := name, parameters := parameters,
            pos := typePos, linkage := linkage, specifiers := functionSpecifiers,
            explicitExtern := true, fileScope := false } }
        declarations := declarations.push (.functionDeclaration parsedType name namePos)
    | none =>
        unless functionSpecifiers == {} do
          failAt typePos "function specifiers may be used only in a function declaration"
        unless parsedType.isObjectType do
          failAt typePos "block-scope extern declaration requires a complete object type"
        let alignment ← effectiveObjectAlignment parsedType alignment typePos
        modify fun state => { state with blockGlobals := state.blockGlobals.push {
          type := parsedType, name := name, initializer := none, pos := typePos,
          declarationOnly := true, hasInitializer := false, linkage := linkage,
          isThreadLocal := isThreadLocal, alignment := alignment } }
        declarations := declarations.push (.externDeclaration parsedType name alignment namePos)
    more := ← acceptSymbol ","
  discard <| expectSymbol ";"
  pure (finishDeclarationGroup declarations declarationPos)

private def parseStaticLocalDeclarators (base : CType) (typePos declarationPos : Pos)
    (functionSpecifiers : FunctionSpecifiers := {}) (alignment : AlignmentSpec := {})
    (isThreadLocal : Bool := false) :
    ParserM Stmt := do
  let mut declarations := #[]
  let mut more := true
  while more do
    let (parsedType, name, namePos) ← parseDeclarator base
    if parsedType.isFunction then
      failAt typePos "block-scope static function declarations are not permitted"
    unless functionSpecifiers == {} do
      failAt typePos "function specifiers may be used only in a function declaration"
    if parsedType.isVoid then failAt typePos "static local variable cannot have type void"
    declareOrdinary name namePos false (some parsedType)
    let (hasInitializer, type, initializer) ← parseStaticInitialValues parsedType
    unless type.isObjectType do
      failAt typePos "static local variable must have a complete object type"
    let alignment ← effectiveObjectAlignment type alignment typePos
    let backingName ← freshStaticBackingName name
    modify fun state => { state with staticGlobals := state.staticGlobals.push {
      type := type, name := backingName, initializer := initializer,
      pos := typePos, hasInitializer := hasInitializer, linkage := .internal,
      isThreadLocal := isThreadLocal, alignment := alignment } }
    declarations := declarations.push
      (.staticDeclaration type name backingName initializer alignment namePos)
    more := ← acceptSymbol ","
  discard <| expectSymbol ";"
  pure (finishDeclarationGroup declarations declarationPos)

mutual
  private partial def parseBlock (start : Pos) : ParserM Stmt := do
    let mut statements := #[]
    while !(← symbol? "}") do
      match (← current).kind with
      | .eof => failAt start "unterminated block"
      | _ => statements := statements.push (← parseStmt)
    discard <| expectSymbol "}"
    pure (.block statements start)

  private partial def parseStmt : ParserM Stmt := do
    let token ← current
    if ← acceptSymbol "{" then
      pushIdentifierScope
      let block ← parseBlock token.pos
      popIdentifierScope
      pure block
    else if ← identifier? "_Static_assert" then
      parseStaticAssertion
      pure (.expression none token.pos)
    else if ← acceptIdentifier "case" then
      let value ← parseEnumConstPrec 0
      discard <| expectSymbol ":"
      pure (.caseLabel value (← parseStmt) token.pos)
    else if ← acceptIdentifier "default" then
      discard <| expectSymbol ":"
      pure (.defaultLabel (← parseStmt) token.pos)
    else if match token.kind, (← peekToken 1).kind with
        | .identifier _, .symbol ":" => true
        | _, _ => false then
      let (name, pos) ← expectName
      discard <| expectSymbol ":"
      pure (.labeled name (← parseStmt) pos)
    else if ← declarationStart then
      let (base, typePos, specifiers) ← parseDeclarationBaseType
      match specifiers.storageClass with
      | some "typedef" =>
        if specifiers.isThreadLocal then
          failAt typePos "'_Thread_local' may not be combined with 'typedef'"
        unless specifiers.function == {} do
          failAt typePos "function specifiers may not appear in a typedef declaration"
        if specifiers.alignment.specified then
          failAt typePos "_Alignas may not be used in a typedef declaration"
        parseTypedefDeclarators base typePos
        pure (.expression none token.pos)
      | some "extern" =>
        parseExternBlockDeclarators base typePos token.pos specifiers.function
          specifiers.alignment specifiers.isThreadLocal
      | some "auto" =>
        if specifiers.isThreadLocal then
          failAt typePos "block-scope '_Thread_local' requires 'static' or 'extern'"
        parseAutomaticDeclarators base typePos token.pos false false specifiers.function specifiers.alignment
      | some "register" =>
        if specifiers.isThreadLocal then
          failAt typePos "block-scope '_Thread_local' requires 'static' or 'extern'"
        parseAutomaticDeclarators base typePos token.pos false true specifiers.function specifiers.alignment
      | some "static" =>
        parseStaticLocalDeclarators base typePos token.pos specifiers.function
          specifiers.alignment specifiers.isThreadLocal
      | none =>
        if specifiers.isThreadLocal then
          failAt typePos "block-scope '_Thread_local' requires 'static' or 'extern'"
        if ← acceptSymbol ";" then
          unless specifiers.function == {} do
            failAt typePos "function specifiers require a function declarator"
          if specifiers.alignment.specified then
            failAt typePos "_Alignas requires an object declarator"
          match base.stripTopQualifiers with
          | .structType .. | .unionType .. | .enumType .. =>
              pure (.expression none token.pos)
          | _ => failAt typePos "declaration requires a declarator"
        else
          parseAutomaticDeclarators base typePos token.pos true false specifiers.function specifiers.alignment
      | some storage =>
        failAt typePos s!"unsupported block-scope storage class '{storage}'"
    else if ← acceptIdentifier "if" then
      discard <| expectSymbol "("
      let condition ← parseExpr
      discard <| expectSymbol ")"
      let thenBranch ← parseStmt
      let elseBranch ← if ← acceptIdentifier "else" then pure (some (← parseStmt)) else pure none
      pure (.ite condition thenBranch elseBranch token.pos)
    else if ← acceptIdentifier "while" then
      discard <| expectSymbol "("
      let condition ← parseExpr
      discard <| expectSymbol ")"
      pure (.whileLoop condition (← parseStmt) token.pos)
    else if ← acceptIdentifier "do" then
      let body ← parseStmt
      unless ← acceptIdentifier "while" do
        failHere "expected 'while' after do-loop body"
      discard <| expectSymbol "("
      let condition ← parseExpr
      discard <| expectSymbol ")"
      discard <| expectSymbol ";"
      pure (.doWhileLoop body condition token.pos)
    else if ← acceptIdentifier "for" then
      discard <| expectSymbol "("
      pushIdentifierScope
      let init ←
        if ← acceptSymbol ";" then pure none
        else if ← declarationStart then
          let declarationPos := (← current).pos
          let (base, typePos, specifiers) ← parseDeclarationBaseType
          match specifiers.storageClass with
          | some "typedef" =>
            if specifiers.isThreadLocal then
              failAt typePos "'_Thread_local' may not be combined with 'typedef'"
            unless specifiers.function == {} do
              failAt typePos "function specifiers may not appear in a typedef declaration"
            if specifiers.alignment.specified then
              failAt typePos "_Alignas may not be used in a typedef declaration"
            parseTypedefDeclarators base typePos
            pure (some (.expression none declarationPos))
          | some "extern" =>
              pure (some (← parseExternBlockDeclarators base typePos declarationPos
                specifiers.function specifiers.alignment specifiers.isThreadLocal))
          | some "static" =>
              pure (some (← parseStaticLocalDeclarators base typePos declarationPos
                specifiers.function specifiers.alignment specifiers.isThreadLocal))
          | some "register" =>
              if specifiers.isThreadLocal then
                failAt typePos "block-scope '_Thread_local' requires 'static' or 'extern'"
              pure (some (← parseAutomaticDeclarators base typePos declarationPos false true
                specifiers.function specifiers.alignment))
          | some "auto" | none =>
              if specifiers.isThreadLocal then
                failAt typePos "block-scope '_Thread_local' requires 'static' or 'extern'"
              pure (some (← parseAutomaticDeclarators base typePos declarationPos false false
                specifiers.function specifiers.alignment))
          | some storage =>
              failAt typePos s!"unsupported for-init storage class '{storage}'"
        else
          let expression ← parseExpr
          discard <| expectSymbol ";"
          pure (some (.expression (some expression) expression.pos))
      let condition ← if ← symbol? ";" then pure none else pure (some (← parseExpr))
      discard <| expectSymbol ";"
      let step ← if ← symbol? ")" then pure none else pure (some (← parseExpr))
      discard <| expectSymbol ")"
      let body ← parseStmt
      popIdentifierScope
      pure (.forLoop init condition step body token.pos)
    else if ← acceptIdentifier "switch" then
      discard <| expectSymbol "("
      let value ← parseExpr
      discard <| expectSymbol ")"
      pure (.switchStmt value (← parseStmt) token.pos)
    else if ← acceptIdentifier "return" then
      let value ← if ← symbol? ";" then pure none else pure (some (← parseExpr))
      discard <| expectSymbol ";"
      pure (.returnStmt value token.pos)
    else if ← acceptIdentifier "break" then
      discard <| expectSymbol ";"
      pure (.breakStmt token.pos)
    else if ← acceptIdentifier "continue" then
      discard <| expectSymbol ";"
      pure (.continueStmt token.pos)
    else if ← acceptIdentifier "goto" then
      let (name, pos) ← expectName
      discard <| expectSymbol ";"
      pure (.gotoStmt name pos)
    else if ← acceptSymbol ";" then
      pure (.expression none token.pos)
    else
      let value ← parseExpr
      discard <| expectSymbol ";"
      pure (.expression (some value) token.pos)
end

private partial def parseProgramM : ParserM Program := do
  let mut program : Program := {}
  while (← current).kind != .eof do
    if ← identifier? "_Static_assert" then
      parseStaticAssertion
      continue
    let declarationPos := (← current).pos
    let (baseType, typePos, declarationSpecifiers) ← parseDeclarationBaseType
    let storageClass := declarationSpecifiers.storageClass
    let isThreadLocal := declarationSpecifiers.isThreadLocal
    if storageClass == some "auto" || storageClass == some "register" then
      failAt declarationPos s!"'{storageClass.getD ""}' is not permitted at file scope"
    let isTypedef := storageClass == some "typedef"
    let isExtern := storageClass == some "extern"
    let isStatic := storageClass == some "static"
    if isTypedef then
      if isThreadLocal then
        failAt typePos "'_Thread_local' may not be combined with 'typedef'"
      unless declarationSpecifiers.function == {} do
        failAt typePos "function specifiers may not appear in a typedef declaration"
      if declarationSpecifiers.alignment.specified then
        failAt typePos "_Alignas may not be used in a typedef declaration"
      parseTypedefDeclarators baseType typePos
      continue
    if ← acceptSymbol ";" then
      if isThreadLocal then
        failAt typePos "'_Thread_local' requires an object declarator"
      unless declarationSpecifiers.function == {} do
        failAt typePos "function specifiers require a function declarator"
      if declarationSpecifiers.alignment.specified then
        failAt typePos "_Alignas requires an object declarator"
      match baseType.stripTopQualifiers with
      | .structType .. | .unionType .. | .enumType .. => continue
      | _ => failAt typePos "declaration requires a declarator"
    let mut moreDeclarators := true
    let mut sawDeclarator := false
    while moreDeclarators do
      let parsed ← parseDeclaratorFull baseType
      let name ← match parsed.name with
        | some name => pure name
        | none => failAt parsed.pos "declaration requires an identifier"
      let namePos := parsed.pos
      declareOrdinary name namePos true (some parsed.type)
      let linkage ← resolveFileLinkage name isStatic namePos
      match parsed.type.functionSignature? with
      | some (returnType, parameterTypes) =>
        if isThreadLocal then
          failAt typePos "'_Thread_local' may not be applied to a function"
        if declarationSpecifiers.alignment.specified then
          failAt typePos "_Alignas may not be used in a function declaration"
        rememberFunctionName name
        let parameters := parsed.entityParameters.getD <|
          parameterTypes.map fun type => { type := type, name := "", pos := typePos }
        if ← symbol? "{" then
          if sawDeclarator then
            failAt namePos "a function definition cannot appear in a declarator list"
          for parameter in parameters do
            if parameter.name.isEmpty then
              failAt parameter.pos "a parameter name is required in a function definition"
          pushIdentifierScope
          for parameter in parameters do
            declareOrdinary parameter.name parameter.pos false (some parameter.type)
          discard <| expectSymbol "{"
          let body ← parseBlock namePos
          program := { program with functions := program.functions.push {
            returnType := returnType, name := name, parameters := parameters,
            body := body, pos := typePos, linkage := linkage,
            specifiers := declarationSpecifiers.function,
            explicitExtern := isExtern } }
          popIdentifierScope
          moreDeclarators := false
        else
          program := { program with declarations := program.declarations.push {
            returnType := returnType, name := name, parameters := parameters,
            pos := typePos, linkage := linkage,
            specifiers := declarationSpecifiers.function,
            explicitExtern := isExtern } }
          sawDeclarator := true
          if ← acceptSymbol "," then pure ()
          else
            discard <| expectSymbol ";"
            moreDeclarators := false
      | none =>
        unless declarationSpecifiers.function == {} do
          failAt typePos "function specifiers may be used only in a function declaration"
        if parsed.type.isVoid then failAt typePos "global variable cannot have type void"
        let (hasInitializer, declaredType, initializer) ←
          parseStaticInitialValues parsed.type
        if hasInitializer && isExtern then
          failAt typePos "extern declaration cannot have an initializer"
        unless declaredType.isObjectType do
          failAt typePos "global variable must have a complete object type"
        let alignment ← effectiveObjectAlignment declaredType
          declarationSpecifiers.alignment typePos
        program := { program with globals := program.globals.push {
          type := declaredType, name := name,
          initializer := initializer, pos := typePos,
          declarationOnly := isExtern, hasInitializer := hasInitializer,
          linkage := linkage, isThreadLocal := isThreadLocal,
          alignment := alignment } }
        sawDeclarator := true
        if ← acceptSymbol "," then pure ()
        else
          discard <| expectSymbol ";"
          moreDeclarators := false
  let state ← get
  let finalProgram := { program with
    aggregates := state.aggregates
    declarations := program.declarations ++ state.blockFunctionDeclarations }
  pure { finalProgram with
    globals := finalProgram.globals ++ state.staticGlobals ++ state.blockGlobals }

def parse (tokens : Array Token) (file : String) : Except CompileError Program :=
  (parseProgramM.run' { tokens := tokens, file := file })

def parseC (source file : String) : Except CompileError Program := do
  parse (← lex source file) file

end JMachineC
