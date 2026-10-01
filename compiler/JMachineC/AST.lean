module

public section

namespace JMachineC

structure Pos where
  line : Nat
  column : Nat
deriving Repr, BEq, Inhabited

structure CompileError where
  file : String
  pos : Pos
  message : String
deriving Repr, BEq

instance : ToString CompileError where
  toString e := s!"{e.file}:{e.pos.line}:{e.pos.column}: {e.message}"

structure TypeQualifiers where
  isConst : Bool := false
  isVolatile : Bool := false
  isRestrict : Bool := false
  isAtomic : Bool := false
deriving Repr, BEq, Inhabited

inductive IntegerRank where
  | boolRank
  | charRank
  | shortRank
  | intRank
  | longRank
deriving Repr, BEq, Inhabited

def IntegerRank.level : IntegerRank → Nat
  | .boolRank => 0
  | .charRank => 1
  | .shortRank => 2
  | .intRank => 3
  | .longRank => 4

def IntegerRank.higher (lhs rhs : IntegerRank) : IntegerRank :=
  if lhs.level >= rhs.level then lhs else rhs

def TypeQualifiers.isEmpty (qualifiers : TypeQualifiers) : Bool :=
  !qualifiers.isConst && !qualifiers.isVolatile && !qualifiers.isRestrict &&
    !qualifiers.isAtomic

def TypeQualifiers.merge (lhs rhs : TypeQualifiers) : TypeQualifiers := {
  isConst := lhs.isConst || rhs.isConst
  isVolatile := lhs.isVolatile || rhs.isVolatile
  isRestrict := lhs.isRestrict || rhs.isRestrict
  isAtomic := lhs.isAtomic || rhs.isAtomic
}

inductive CType where
  | int
  | boolType
  | plainChar
  | integer (rank : IntegerRank) (isSigned : Bool)
  | void
  | pointer (pointee : CType)
  | array (element : CType) (length : Nat)
  | function (returnType : CType) (parameters : Array CType)
  | structType (name : String) (size : Nat)
  | unionType (name : String) (size : Nat)
  | enumType (name : String)
  | qualified (base : CType) (qualifiers : TypeQualifiers)
deriving Repr, BEq, Inhabited

inductive LiteralEncoding where
  | ordinary
  | utf8
  | utf16
  | utf32
  | wide
deriving Repr, BEq, Inhabited

inductive LiteralUnit where
  | scalar (value : Nat)
  | codeUnit (value : Nat)
deriving Repr, BEq, Inhabited

def LiteralEncoding.elementType : LiteralEncoding → CType
  | .ordinary | .utf8 => .plainChar
  | .utf16 => .integer .shortRank false
  | .utf32 => .integer .intRank false
  | .wide => .int

def LiteralEncoding.characterType : LiteralEncoding → CType
  | .ordinary => .int
  | encoding => encoding.elementType

def LiteralEncoding.prefix : LiteralEncoding → String
  | .ordinary => ""
  | .utf8 => "u8"
  | .utf16 => "u"
  | .utf32 => "U"
  | .wide => "L"

private def appendUtf8Scalar (value : Nat) (values : Array Int) : Array Int :=
  if value <= 0x7f then values.push (Int.ofNat value)
  else if value <= 0x7ff then
    values.push (Int.ofNat (0xc0 ||| (value >>> 6)))
      |>.push (Int.ofNat (0x80 ||| (value &&& 0x3f)))
  else if value <= 0xffff then
    values.push (Int.ofNat (0xe0 ||| (value >>> 12)))
      |>.push (Int.ofNat (0x80 ||| ((value >>> 6) &&& 0x3f)))
      |>.push (Int.ofNat (0x80 ||| (value &&& 0x3f)))
  else
    values.push (Int.ofNat (0xf0 ||| (value >>> 18)))
      |>.push (Int.ofNat (0x80 ||| ((value >>> 12) &&& 0x3f)))
      |>.push (Int.ofNat (0x80 ||| ((value >>> 6) &&& 0x3f)))
      |>.push (Int.ofNat (0x80 ||| (value &&& 0x3f)))

def LiteralEncoding.encodeUnits (encoding : LiteralEncoding)
    (units : Array LiteralUnit) : Array Int :=
  units.foldl (fun values unit => match unit with
    | .scalar value =>
        if encoding == .utf8 then appendUtf8Scalar value values
        else values.push (Int.ofNat value)
    | .codeUnit value => values.push (Int.ofNat value)) #[]

def CType.wordSize : CType → Nat
  | .void | .function .. => 0
  | .int | .boolType | .plainChar | .integer .. | .enumType _ | .pointer _ => 1
  | .array element length => element.wordSize * length
  | .structType _ size | .unionType _ size => size
  | .qualified base _ => base.wordSize

def CType.decay : CType → CType
  | .array element _ => .pointer element
  | function@(.function ..) => .pointer function
  | other => other

def CType.topQualifiers : CType → TypeQualifiers
  | .qualified _ qualifiers => qualifiers
  | _ => {}

def CType.stripTopQualifiers : CType → CType
  | .qualified base _ => base
  | other => other

def CType.withQualifiers (type : CType) (qualifiers : TypeQualifiers) : CType :=
  if qualifiers.isEmpty then type
  else match type with
    | .qualified base prior => .qualified base (prior.merge qualifiers)
    -- In C17 and earlier, an array acquires qualifications through its
    -- element type rather than becoming a separately qualified array type.
    | .array element length => .array (element.withQualifiers qualifiers) length
    | other => .qualified other qualifiers

def CType.toRValue : CType → CType
  | .array element _ => .pointer element
  | function@(.function ..) => .pointer function
  | .qualified base _ => base.toRValue
  | .enumType _ => .int
  | other => other

def CType.isConstQualified (type : CType) : Bool :=
  type.topQualifiers.isConst

def CType.isVolatileQualified (type : CType) : Bool :=
  type.topQualifiers.isVolatile

def CType.isRestrictQualified (type : CType) : Bool :=
  type.topQualifiers.isRestrict

def CType.isAtomicQualified (type : CType) : Bool :=
  type.topQualifiers.isAtomic

def CType.isInt (type : CType) : Bool :=
  type.stripTopQualifiers == .int

def CType.integerInfo? (type : CType) : Option (IntegerRank × Bool) :=
  match type.stripTopQualifiers with
  | .int => some (.intRank, true)
  | .boolType => some (.boolRank, true)
  | .plainChar => some (.charRank, true)
  | .integer rank isSigned => some (rank, isSigned)
  | .enumType _ => some (.intRank, true)
  | _ => none

def CType.isInteger (type : CType) : Bool := type.integerInfo?.isSome

def CType.isSignedInteger (type : CType) : Bool :=
  type.integerInfo?.map Prod.snd |>.getD false

def CType.integerRank? (type : CType) : Option IntegerRank :=
  type.integerInfo?.map Prod.fst

def CType.cInteger (rank : IntegerRank) (isSigned : Bool) : CType :=
  if rank == .boolRank then .boolType
  else if rank == .intRank && isSigned then .int
  else .integer rank isSigned

def CType.isBool (type : CType) : Bool :=
  type.stripTopQualifiers == .boolType

def CType.integerPromotion (type : CType) : CType :=
  match type.integerInfo? with
  | some (rank, isSigned) =>
      if rank.level < IntegerRank.intRank.level then
        -- Every scalar object occupies one 32-bit addressed MDP word.  A
        -- signed narrow-rank type therefore fits in int; an unsigned one has
        -- the full unsigned word range and promotes to unsigned int.
        CType.cInteger .intRank isSigned
      else CType.cInteger rank isSigned
  | none => type.toRValue

def CType.usualIntegerConversion (lhs rhs : CType) : Option CType := do
  let lhs := lhs.integerPromotion
  let rhs := rhs.integerPromotion
  let (lhsRank, lhsSigned) ← lhs.integerInfo?
  let (rhsRank, rhsSigned) ← rhs.integerInfo?
  if lhsSigned == rhsSigned then
    pure (CType.cInteger (lhsRank.higher rhsRank) lhsSigned)
  else
    -- All four ranks have the same 32-bit representation width in the MDC
    -- word-addressed ABI.  No signed rank can represent the full range of an
    -- unsigned rank, so the usual conversion selects the unsigned form of
    -- the higher rank.
    pure (CType.cInteger (lhsRank.higher rhsRank) false)

def CType.isVoid (type : CType) : Bool :=
  type.stripTopQualifiers == .void

def CType.pointerPointee? (type : CType) : Option CType :=
  match type.stripTopQualifiers with
  | .pointer pointee => some pointee
  | _ => none

def CType.isPointer (type : CType) : Bool := type.pointerPointee?.isSome

def CType.arrayElement? (type : CType) : Option (CType × Nat) :=
  match type.stripTopQualifiers with
  | .array element length => some (element, length)
  | _ => none

def CType.isArray (type : CType) : Bool := type.arrayElement?.isSome

def CType.isAggregate (type : CType) : Bool :=
  match type.stripTopQualifiers with
  | .structType .. | .unionType .. => true
  | _ => false

def CType.isEnum (type : CType) : Bool :=
  match type.stripTopQualifiers with
  | .enumType _ => true
  | _ => false

def CType.functionSignature? (type : CType) : Option (CType × Array CType) :=
  match type.stripTopQualifiers with
  | .function returnType parameters => some (returnType, parameters)
  | _ => none

def CType.isFunction (type : CType) : Bool := type.functionSignature?.isSome

def CType.functionPointerSignature? (type : CType) : Option (CType × Array CType) :=
  type.pointerPointee?.bind CType.functionSignature?

def CType.isFunctionPointer (type : CType) : Bool :=
  type.functionPointerSignature?.isSome

def CType.isObjectType : CType → Bool
  | .void | .function .. => false
  | .int | .boolType | .plainChar | .integer .. | .enumType _ | .pointer _ => true
  | .array element length => length > 0 && element.isObjectType
  | .structType _ size | .unionType _ size => size > 0
  | .qualified base _ => base.isObjectType

structure AlignmentSpec where
  specified : Bool := false
  value : Nat := 1
deriving Repr, BEq, Inhabited

inductive AggregateKind where
  | structKind
  | unionKind
deriving Repr, BEq, Inhabited

structure Member where
  type : CType
  name : String
  offset : Nat
  bitWidth : Option Nat := none
  bitOffset : Nat := 0
  alignment : AlignmentSpec := {}
  pos : Pos
deriving Repr, Inhabited

structure Aggregate where
  kind : AggregateKind
  name : String
  members : Array Member
  size : Nat
  alignment : Nat := 1
  containsFlexibleArray : Bool := false
  pos : Pos
deriving Repr, Inhabited

inductive UnaryOp where
  | neg
  | logicalNot
  | bitNot
  | addressOf
  | dereference
deriving Repr, BEq

inductive BinaryOp where
  | add | sub | mul | div | mod
  | shl | shr
  | lt | le | gt | ge | eq | ne
  | bitAnd | bitXor | bitOr
  | logicalAnd | logicalOr
deriving Repr, BEq

inductive PostfixOp where
  | inc | dec
deriving Repr, BEq

inductive Linkage where
  | external
  | internal
deriving Repr, BEq, Inhabited

inductive InitializerDesignator where
  | member (name : String) (pos : Pos)
  | index (value : Int) (pos : Pos)
deriving Repr, Inhabited

inductive Initializer (α : Type) where
  | value (value : α) (pos : Pos)
  | stringLiteral (values : Array Int) (encoding : LiteralEncoding)
      (storageName : String) (pos : Pos)
  | list (elements : Array (Array InitializerDesignator × Initializer α)) (pos : Pos)
deriving Repr, Inhabited

def Initializer.pos : Initializer α → Pos
  | .value _ pos | .stringLiteral _ _ _ pos | .list _ pos => pos

inductive Expr where
  | intLit (value : Int) (type : CType) (pos : Pos)
  | variable (name : String) (pos : Pos)
  | call (name : String) (args : Array Expr) (destination : Option Expr) (pos : Pos)
  | indirectCall (callee : Expr) (args : Array Expr) (destination : Option Expr) (pos : Pos)
  | assign (target : Expr) (value : Expr) (pos : Pos)
  | compoundAssign (op : BinaryOp) (target : Expr) (value : Expr) (pos : Pos)
  | conditional (condition thenValue elseValue : Expr) (pos : Pos)
  | comma (lhs rhs : Expr) (pos : Pos)
  | unary (op : UnaryOp) (value : Expr) (pos : Pos)
  | binary (op : BinaryOp) (lhs rhs : Expr) (pos : Pos)
  | subscript (base index : Expr) (pos : Pos)
  | member (base : Expr) (name : String) (indirect : Bool) (pos : Pos)
  | cast (type : CType) (value : Expr) (pos : Pos)
  | genericSelection (control : Expr)
      (associations : Array (Option CType × Expr)) (pos : Pos)
  | compoundLiteral (type : CType) (initializer : Initializer Expr)
      (alignment : Nat) (pos : Pos)
  | sizeofExpr (value : Expr) (pos : Pos)
  | sizeofType (type : CType) (pos : Pos)
  | alignofType (type : CType) (pos : Pos)
  | postfix (op : PostfixOp) (target : Expr) (pos : Pos)
  | prefix (op : PostfixOp) (target : Expr) (pos : Pos)
deriving Repr, Inhabited

inductive ConstantInitializer where
  | integer (value : Int)
  | functionDesignator (name : String) (pos : Pos)
  | objectDesignator (name : String) (decay : Bool) (pos : Pos)
deriving Repr, Inhabited

def Expr.pos : Expr → Pos
  | .intLit _ _ p | .variable _ p | .call _ _ _ p | .indirectCall _ _ _ p | .assign _ _ p
  | .compoundAssign _ _ _ p
  | .conditional _ _ _ p
  | .comma _ _ p
  | .unary _ _ p | .binary _ _ _ p | .subscript _ _ p
  | .member _ _ _ p
  | .cast _ _ p | .genericSelection _ _ p | .compoundLiteral _ _ _ p |
      .sizeofExpr _ p | .sizeofType _ p
  | .alignofType _ p
  | .postfix _ _ p
  | .prefix _ _ p => p

inductive Stmt where
  | block (statements : Array Stmt) (pos : Pos)
  | declarationGroup (declarations : Array Stmt) (pos : Pos)
  | declaration (type : CType) (name : String)
      (initializer : Option (Initializer Expr)) (alignment : AlignmentSpec) (pos : Pos)
  | registerDeclaration (type : CType) (name : String)
      (initializer : Option (Initializer Expr)) (pos : Pos)
  | staticDeclaration (type : CType) (name backingName : String)
      (initializer : Option (Initializer ConstantInitializer))
      (alignment : AlignmentSpec) (pos : Pos)
  | externDeclaration (type : CType) (name : String)
      (alignment : AlignmentSpec) (pos : Pos)
  | functionDeclaration (type : CType) (name : String) (pos : Pos)
  | expression (value : Option Expr) (pos : Pos)
  | ite (condition : Expr) (thenBranch : Stmt) (elseBranch : Option Stmt)
      (pos : Pos)
  | whileLoop (condition : Expr) (body : Stmt) (pos : Pos)
  | doWhileLoop (body : Stmt) (condition : Expr) (pos : Pos)
  | forLoop (init : Option Stmt) (condition step : Option Expr) (body : Stmt) (pos : Pos)
  | switchStmt (value : Expr) (body : Stmt) (pos : Pos)
  | caseLabel (value : Int) (body : Stmt) (pos : Pos)
  | defaultLabel (body : Stmt) (pos : Pos)
  | returnStmt (value : Option Expr) (pos : Pos)
  | breakStmt (pos : Pos)
  | continueStmt (pos : Pos)
  | labeled (name : String) (body : Stmt) (pos : Pos)
  | gotoStmt (name : String) (pos : Pos)
deriving Repr, Inhabited

def Stmt.pos : Stmt → Pos
  | .block _ p | .declarationGroup _ p | .declaration _ _ _ _ p
  | .registerDeclaration _ _ _ p
  | .staticDeclaration _ _ _ _ _ p
  | .externDeclaration _ _ _ p | .functionDeclaration _ _ p
  | .expression _ p
  | .ite _ _ _ p | .whileLoop _ _ p | .doWhileLoop _ _ p | .forLoop _ _ _ _ p
  | .switchStmt _ _ p
  | .caseLabel _ _ p | .defaultLabel _ p
  | .returnStmt _ p | .breakStmt p | .continueStmt p
  | .labeled _ _ p | .gotoStmt _ p => p

structure Parameter where
  type : CType
  name : String
  pos : Pos
  isRegister : Bool := false
deriving Repr, Inhabited

structure FunctionSpecifiers where
  isInline : Bool := false
  isNoreturn : Bool := false
deriving Repr, BEq, Inhabited

structure Function where
  returnType : CType
  name : String
  parameters : Array Parameter
  body : Stmt
  pos : Pos
  linkage : Linkage := .external
  specifiers : FunctionSpecifiers := {}
  explicitExtern : Bool := false
  translationUnit : Nat := 0
deriving Repr, Inhabited

structure FunctionDeclaration where
  returnType : CType
  name : String
  parameters : Array Parameter
  pos : Pos
  linkage : Linkage := .external
  specifiers : FunctionSpecifiers := {}
  explicitExtern : Bool := false
  fileScope : Bool := true
  translationUnit : Nat := 0
deriving Repr, Inhabited

structure Global where
  type : CType
  name : String
  initializer : Option (Initializer ConstantInitializer)
  pos : Pos
  declarationOnly : Bool := false
  hasInitializer : Bool := false
  linkage : Linkage := .external
  isThreadLocal : Bool := false
  alignment : AlignmentSpec := {}
  translationUnit : Nat := 0
deriving Repr, Inhabited

structure Program where
  functions : Array Function := #[]
  declarations : Array FunctionDeclaration := #[]
  globals : Array Global := #[]
  aggregates : Array Aggregate := #[]
deriving Repr, Inhabited

end JMachineC
