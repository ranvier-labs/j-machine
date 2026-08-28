import JMachineC.AST

namespace JMachineC

inductive IntegerLiteralBase where
  | decimal
  | octal
  | hexadecimal
deriving Repr, BEq

structure IntegerToken where
  value : Int
  base : IntegerLiteralBase
  isUnsigned : Bool := false
  isLong : Bool := false
deriving Repr, BEq

inductive TokenKind where
  | identifier (value : String)
  | number (literal : IntegerToken)
  | character (value : Int) (encoding : LiteralEncoding)
  | stringLiteral (units : Array LiteralUnit) (encoding : LiteralEncoding)
  | symbol (value : String)
  | eof
deriving Repr, BEq

structure Token where
  kind : TokenKind
  pos : Pos
deriving Repr, BEq

private structure LexerState where
  input : Array Char
  index : Nat := 0
  line : Nat := 1
  column : Nat := 1
  atLineStart : Bool := true
  macros : List (String × IntegerToken) := []
  tokens : Array Token := #[]
  resumeInputs : List (Array Char × Nat × Nat × Nat × Bool) := []
  stdatomicIncluded : Bool := false

private def LexerState.pos (state : LexerState) : Pos :=
  { line := state.line, column := state.column }

private def current? (state : LexerState) : Option Char := state.input[state.index]?
private def peek? (state : LexerState) (distance : Nat := 1) : Option Char :=
  state.input[state.index + distance]?

private def advance (state : LexerState) : LexerState :=
  match current? state with
  | none => state
  | some '\n' =>
      { state with
        index := state.index + 1
        line := state.line + 1
        column := 1
        atLineStart := true }
  | some c =>
      { state with
        index := state.index + 1
        column := state.column + 1
        atLineStart := state.atLineStart && (c == ' ' || c == '\t' || c == '\r') }

private def isIdentStart (c : Char) : Bool := c.isAlpha || c == '_'
private def isIdentRest (c : Char) : Bool := c.isAlphanum || c == '_'

private partial def takeWhileLoop (predicate : Char → Bool) (state : LexerState)
    (chars : List Char) : String × LexerState :=
  match current? state with
  | some c => if predicate c then takeWhileLoop predicate (advance state) (c :: chars)
              else (String.ofList chars.reverse, state)
  | none => (String.ofList chars.reverse, state)

private def takeWhile (state : LexerState) (predicate : Char → Bool) : String × LexerState :=
  takeWhileLoop predicate state []

private def digitValue? (base : Nat) (c : Char) : Option Nat :=
  let value :=
    if c >= '0' && c <= '9' then some (c.toNat - '0'.toNat)
    else if c >= 'a' && c <= 'f' then some (10 + c.toNat - 'a'.toNat)
    else if c >= 'A' && c <= 'F' then some (10 + c.toNat - 'A'.toNat)
    else none
  value.bind fun n => if n < base then some n else none

private def parseDigits (file : String) (pos : Pos) (base : Nat)
    (digits : String) : Except CompileError Nat := do
  if digits.isEmpty then
    throw { file := file, pos := pos, message := "expected digits in integer literal" }
  let mut value := 0
  for c in digits.toList do
    match digitValue? base c with
    | none => throw {
        file := file
        pos := pos
        message := s!"invalid digit '{c}' in integer literal" }
    | some digit => value := value * base + digit
  pure value

private def parseIntegerSuffix (file : String) (pos : Pos) (suffix : String) :
    Except CompileError (Bool × Bool) := do
  let normalized := suffix.toLower
  if normalized == "" then pure (false, false)
  else if normalized == "u" then pure (true, false)
  else if normalized == "l" then pure (false, true)
  else if normalized == "ul" || normalized == "lu" then pure (true, true)
  else if normalized.contains "ll" then
    throw {
      file := file, pos := pos,
      message := "long long integer literals are not implemented by the 32-bit MDC target ABI" }
  else
    throw { file := file, pos := pos, message := s!"invalid integer literal suffix '{suffix}'" }

private def finishIntegerToken (file : String) (pos : Pos) (value : Nat)
    (base : IntegerLiteralBase) (state : LexerState) :
    Except CompileError (IntegerToken × LexerState) := do
  let (suffix, rest) := takeWhile state isIdentRest
  let (isUnsigned, isLong) ← parseIntegerSuffix file pos suffix
  if value > 0xffffffff then
    throw {
      file := file, pos := pos,
      message := "integer literal is outside the 32-bit MDC scalar range" }
  let literal : IntegerToken := {
    value := Int.ofNat value
    base := base
    isUnsigned := isUnsigned
    isLong := isLong }
  pure (literal, rest)

private def readNumber (file : String) (state : LexerState) :
    Except CompileError (IntegerToken × LexerState) := do
  let pos := state.pos
  if current? state == some '0' && (peek? state == some 'x' || peek? state == some 'X') then
    let afterPrefix := advance (advance state)
    let (digits, rest) := takeWhile afterPrefix fun c => (digitValue? 16 c).isSome
    finishIntegerToken file pos (← parseDigits file pos 16 digits) .hexadecimal rest
  else if current? state == some '0' then
    let (digits, rest) := takeWhile state (fun c => c.isDigit)
    finishIntegerToken file pos (← parseDigits file pos 8 digits) .octal rest
  else
    let (digits, rest) := takeWhile state (fun c => c.isDigit)
    finishIntegerToken file pos (← parseDigits file pos 10 digits) .decimal rest

private def simpleEscape? (c : Char) : Option Nat :=
  match c with
  | '\'' => some 0x27
  | '"' => some 0x22
  | '?' => some 0x3f
  | '\\' => some 0x5c
  | 'a' => some 0x07
  | 'b' => some 0x08
  | 'f' => some 0x0c
  | 'n' => some 0x0a
  | 'r' => some 0x0d
  | 't' => some 0x09
  | 'v' => some 0x0b
  | _ => none

private def readFixedHex (file : String) (pos : Pos) (count : Nat)
    (state : LexerState) : Except CompileError (Nat × LexerState) := do
  let mut cursor := state
  let mut value := 0
  for _ in [0:count] do
    let digit ← match current? cursor with
      | some c => match digitValue? 16 c with
        | some digit => pure digit
        | none => throw {
            file := file, pos := cursor.pos,
            message := s!"universal character name requires exactly {count} hexadecimal digits" }
      | none => throw {
          file := file, pos := pos,
          message := "unterminated universal character name" }
    value := value * 16 + digit
    cursor := advance cursor
  pure (value, cursor)

private def validateUniversalCharacter (file : String) (pos : Pos) (value : Nat) :
    Except CompileError Unit := do
  if value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff) then
    throw {
      file := file, pos := pos,
      message := "universal character name does not denote a Unicode scalar value" }
  if value < 0xa0 && value != 0x24 && value != 0x40 && value != 0x60 then
    throw {
      file := file, pos := pos,
      message := "universal character name below U+00A0 may denote only $, @, or `" }

private def readEscapeValue (file : String) (pos : Pos) (state : LexerState) :
    Except CompileError (LiteralUnit × LexerState) := do
  match current? state with
  | none => throw { file := file, pos := pos, message := "unterminated escape sequence" }
  | some 'u' | some 'U' =>
      let count := if current? state == some 'u' then 4 else 8
      let (value, rest) ← readFixedHex file pos count (advance state)
      validateUniversalCharacter file pos value
      pure (.scalar value, rest)
  | some 'x' =>
      let digitsStart := advance state
      let (digits, rest) := takeWhile digitsStart fun c => (digitValue? 16 c).isSome
      pure (.codeUnit (← parseDigits file pos 16 digits), rest)
  | some c =>
      if c >= '0' && c <= '7' then
        let rec takeOctal : Nat → LexerState → List Char → String × LexerState
          | 0, cursor, digits => (String.ofList digits.reverse, cursor)
          | remaining + 1, cursor, digits => match current? cursor with
            | some digit =>
                if digit >= '0' && digit <= '7' then
                  takeOctal remaining (advance cursor) (digit :: digits)
                else (String.ofList digits.reverse, cursor)
            | none => (String.ofList digits.reverse, cursor)
        let (digits, rest) := takeOctal 3 state []
        pure (.codeUnit (← parseDigits file pos 8 digits), rest)
      else match simpleEscape? c with
        | some escapedValue => pure (.codeUnit escapedValue, advance state)
        | none => throw {
            file := file, pos := state.pos,
            message := s!"unknown character escape '\\{c}'" }

private def validateLiteralUnit (file : String) (pos : Pos) (encoding : LiteralEncoding)
    (unit : LiteralUnit) : Except CompileError Unit := do
  match unit with
  | .scalar _ => pure ()
  | .codeUnit value =>
      if value > 0xffffffff then
        throw {
          file := file, pos := pos,
          message := s!"{encoding.prefix} literal escape exceeds its 32-bit element type" }

private def signedLiteralWord (value : Nat) : Int :=
  if value >= 0x80000000 then Int.ofNat value - 0x100000000 else Int.ofNat value

private def packMulticharacterValue (values : Array Int) : Nat :=
  values.foldl (fun result value =>
    ((result <<< 8) ||| ((Int.emod value 0x100).toNat)) &&& 0xffffffff) 0

private def readCharacter (file : String) (encoding : LiteralEncoding)
    (state : LexerState) : Except CompileError (Int × LexerState) := do
  let pos := state.pos
  let mut cursor := advance state
  let mut units := #[]
  while current? cursor != some '\'' do
    if current? cursor == some '\\' && current? (advance cursor) == some '\n' then
      cursor := advance (advance cursor)
      continue
    let (unit, rest) ← match current? cursor with
      | none | some '\n' =>
          throw { file := file, pos := pos, message := "unterminated character constant" }
      | some '\\' => readEscapeValue file pos (advance cursor)
      | some c => pure (.scalar c.toNat, advance cursor)
    validateLiteralUnit file pos encoding unit
    units := units.push unit
    cursor := rest
  if units.isEmpty then
    throw { file := file, pos := pos, message := "empty character constant" }
  let values := encoding.encodeUnits units
  let rawValue :=
    if values.size == 1 then (Int.emod values[0]! 0x100000000).toNat
    else packMulticharacterValue values
  let value :=
    if encoding.characterType.isSignedInteger then signedLiteralWord rawValue
    else Int.ofNat rawValue
  pure (value, advance cursor)

private partial def readStringLoop (file : String) (pos : Pos)
    (encoding : LiteralEncoding)
    (cursor : LexerState) (units : Array LiteralUnit) :
    Except CompileError (Array LiteralUnit × LexerState) := do
  match current? cursor with
  | none | some '\n' =>
      throw { file := file, pos := pos, message := "unterminated string literal" }
  | some '"' => pure (units, advance cursor)
  | some '\\' =>
      let escaped := advance cursor
      if current? escaped == some '\n' then
        readStringLoop file pos encoding (advance escaped) units
      else
        let (unit, rest) ← readEscapeValue file pos escaped
        validateLiteralUnit file pos encoding unit
        readStringLoop file pos encoding rest (units.push unit)
  | some c =>
      readStringLoop file pos encoding (advance cursor) (units.push (.scalar c.toNat))

private def readString (file : String) (encoding : LiteralEncoding) (state : LexerState) :
    Except CompileError (Array LiteralUnit × LexerState) :=
  readStringLoop file state.pos encoding (advance state) #[]

private def macroValue? (state : LexerState) (name : String) : Option IntegerToken :=
  state.macros.findSome? fun entry => if entry.1 == name then some entry.2 else none

private partial def skipHorizontal (state : LexerState) : LexerState :=
  match current? state with
  | some c => if c == ' ' || c == '\t' || c == '\r'
              then skipHorizontal (advance state) else state
  | none => state

private partial def skipLine (state : LexerState) : LexerState :=
  match current? state with
  | none => state
  | some '\n' => advance state
  | some _ => skipLine (advance state)

private partial def skipBlockComment (file : String) (start : Pos) (state : LexerState) :
    Except CompileError LexerState :=
  match current? state, peek? state with
  | none, _ => throw { file := file, pos := start, message := "unterminated block comment" }
  | some '*', some '/' => pure (advance (advance state))
  | _, _ => skipBlockComment file start (advance state)

private def stdatomicHeader : String :=
  "typedef enum {\n" ++
  "  memory_order_relaxed = 0, memory_order_consume = 1,\n" ++
  "  memory_order_acquire = 2, memory_order_release = 3,\n" ++
  "  memory_order_acq_rel = 4, memory_order_seq_cst = 5\n" ++
  "} memory_order;\n" ++
  "typedef _Atomic _Bool atomic_flag;\n" ++
  "typedef _Atomic _Bool atomic_bool;\n" ++
  "typedef _Atomic char atomic_char;\n" ++
  "typedef _Atomic signed char atomic_schar;\n" ++
  "typedef _Atomic unsigned char atomic_uchar;\n" ++
  "typedef _Atomic short atomic_short;\n" ++
  "typedef _Atomic unsigned short atomic_ushort;\n" ++
  "typedef _Atomic int atomic_int;\n" ++
  "typedef _Atomic unsigned int atomic_uint;\n" ++
  "typedef _Atomic long atomic_long;\n" ++
  "typedef _Atomic unsigned long atomic_ulong;\n" ++
  "typedef unsigned short char16_t;\n" ++
  "typedef unsigned int char32_t;\n" ++
  "typedef signed int wchar_t;\n" ++
  "typedef _Atomic unsigned short atomic_char16_t;\n" ++
  "typedef _Atomic unsigned int atomic_char32_t;\n" ++
  "typedef _Atomic signed int atomic_wchar_t;\n" ++
  "typedef _Atomic signed char atomic_int_least8_t;\n" ++
  "typedef _Atomic unsigned char atomic_uint_least8_t;\n" ++
  "typedef _Atomic signed short atomic_int_least16_t;\n" ++
  "typedef _Atomic unsigned short atomic_uint_least16_t;\n" ++
  "typedef _Atomic signed int atomic_int_least32_t;\n" ++
  "typedef _Atomic unsigned int atomic_uint_least32_t;\n" ++
  "typedef _Atomic signed char atomic_int_fast8_t;\n" ++
  "typedef _Atomic unsigned char atomic_uint_fast8_t;\n" ++
  "typedef _Atomic signed short atomic_int_fast16_t;\n" ++
  "typedef _Atomic unsigned short atomic_uint_fast16_t;\n" ++
  "typedef _Atomic signed int atomic_int_fast32_t;\n" ++
  "typedef _Atomic unsigned int atomic_uint_fast32_t;\n" ++
  "typedef _Atomic signed long atomic_intptr_t;\n" ++
  "typedef _Atomic unsigned long atomic_uintptr_t;\n" ++
  "typedef _Atomic unsigned long atomic_size_t;\n" ++
  "typedef _Atomic signed long atomic_ptrdiff_t;\n" ++
  "typedef _Atomic signed long atomic_intmax_t;\n" ++
  "typedef _Atomic unsigned long atomic_uintmax_t;\n" ++
  "#define ATOMIC_FLAG_INIT 0\n" ++
  "#define ATOMIC_BOOL_LOCK_FREE 2\n" ++
  "#define ATOMIC_CHAR_LOCK_FREE 2\n" ++
  "#define ATOMIC_CHAR16_T_LOCK_FREE 2\n" ++
  "#define ATOMIC_CHAR32_T_LOCK_FREE 2\n" ++
  "#define ATOMIC_WCHAR_T_LOCK_FREE 2\n" ++
  "#define ATOMIC_SHORT_LOCK_FREE 2\n" ++
  "#define ATOMIC_INT_LOCK_FREE 2\n" ++
  "#define ATOMIC_LONG_LOCK_FREE 2\n" ++
  "#define ATOMIC_LLONG_LOCK_FREE 0\n" ++
  "#define ATOMIC_POINTER_LOCK_FREE 2\n"

private def parseDirective (file : String) (state : LexerState) :
    Except CompileError LexerState := do
  let directivePos := state.pos
  let afterHash := skipHorizontal (advance state)
  let (directive, afterDirective) := takeWhile afterHash isIdentRest
  if directive == "include" then
    let beforeHeader := skipHorizontal afterDirective
    unless current? beforeHeader == some '<' do
      throw {
        file := file
        pos := beforeHeader.pos
        message := "only the built-in <stdatomic.h> system header is supported" }
    let (header, afterHeader) := takeWhile (advance beforeHeader) fun c => c != '>' && c != '\n'
    unless current? afterHeader == some '>' do
      throw {
        file := file
        pos := beforeHeader.pos
        message := "unterminated #include header name" }
    unless header == "stdatomic.h" do
      throw {
        file := file
        pos := beforeHeader.pos
        message := s!"unsupported system header <{header}>" }
    let tail := skipHorizontal (advance afterHeader)
    unless current? tail == some '\n' || current? tail == none do
      throw { file := file, pos := tail.pos, message := "unexpected tokens after #include" }
    let resume := skipLine tail
    if state.stdatomicIncluded then
      return resume
    return {
      state with
      input := stdatomicHeader.toList.toArray
      index := 0
      column := 1
      atLineStart := true
      stdatomicIncluded := true
      resumeInputs :=
        (resume.input, resume.index, resume.line, resume.column, resume.atLineStart) ::
          state.resumeInputs }
  if directive != "define" then
    throw {
      file := file
      pos := directivePos
      message := s!"unsupported preprocessor directive '#{directive}'" }
  let beforeName := skipHorizontal afterDirective
  let namePos := beforeName.pos
  let (name, afterName) := takeWhile beforeName isIdentRest
  if name.isEmpty then
    throw { file := file, pos := namePos, message := "expected macro name after #define" }
  let beforeValue := skipHorizontal afterName
  let (negative, numberStart) :=
    if current? beforeValue == some '-' then (true, advance beforeValue)
    else (false, beforeValue)
  let (literal, afterNumber) ← readNumber file numberStart
  let tail := skipHorizontal afterNumber
  match current? tail with
  | none | some '\n' =>
      let literal := if negative then { literal with value := -literal.value } else literal
      pure { skipLine tail with macros := (name, literal) :: state.macros }
  | some _ =>
      throw {
        file := file
        pos := tail.pos
        message := "only object-like integer #define values are supported" }

private def twoCharacterSymbol? (first second : Char) : Option String :=
  let pair := String.ofList [first, second]
  if ["==", "!=", "<=", ">=", "<<", ">>", "&&", "||", "++", "--", "->",
      "+=", "-=", "*=", "/=", "%=", "&=", "^=", "|="].contains pair
  then some pair else none

private def threeCharacterSymbol? (first second third : Char) : Option String :=
  let symbol := String.ofList [first, second, third]
  if ["<<=", ">>="].contains symbol then some symbol else none

private def isSingleSymbol (c : Char) : Bool :=
  "(){}[];,:.?=+-*/%!~<>&^|@".toList.contains c

private def prefixedStringStart? (state : LexerState) : Option (LiteralEncoding × Nat) :=
  match current? state, peek? state, peek? state 2 with
  | some 'u', some '8', some '"' => some (.utf8, 2)
  | some 'u', some '"', _ => some (.utf16, 1)
  | some 'U', some '"', _ => some (.utf32, 1)
  | some 'L', some '"', _ => some (.wide, 1)
  | _, _, _ => none

private def prefixedCharacterStart? (state : LexerState) : Option (LiteralEncoding × Nat) :=
  match current? state, peek? state with
  | some 'u', some '\'' => some (.utf16, 1)
  | some 'U', some '\'' => some (.utf32, 1)
  | some 'L', some '\'' => some (.wide, 1)
  | _, _ => none

private def advanceBy : Nat → LexerState → LexerState
  | 0, state => state
  | count + 1, state => advanceBy count (advance state)

private partial def scan (file : String) (state : LexerState) :
    Except CompileError LexerState := do
  match current? state with
  | none =>
      match state.resumeInputs with
      | (input, index, line, column, atLineStart) :: rest =>
          scan file { state with input, index, line, column, atLineStart, resumeInputs := rest }
      | [] => pure { state with tokens := state.tokens.push { kind := .eof, pos := state.pos } }
  | some c =>
      if c.isWhitespace then
        scan file (advance state)
      else if c == '/' && peek? state == some '/' then
        scan file (skipLine (advance (advance state)))
      else if c == '/' && peek? state == some '*' then
        scan file (← skipBlockComment file state.pos (advance (advance state)))
      else if c == '#' && state.atLineStart then
        scan file (← parseDirective file state)
      else if c == 'u' && peek? state == some '8' && peek? state 2 == some '\'' then
        throw {
          file := file, pos := state.pos,
          message := "C11 does not permit the u8 prefix on a character constant" }
      else if let some (encoding, prefixLength) := prefixedStringStart? state then
        let quoteState := advanceBy prefixLength state
        let pos := state.pos
        let (values, rest) ← readString file encoding quoteState
        scan file { rest with tokens := rest.tokens.push {
          kind := .stringLiteral values encoding, pos } }
      else if let some (encoding, prefixLength) := prefixedCharacterStart? state then
        let quoteState := advanceBy prefixLength state
        let pos := state.pos
        let (value, rest) ← readCharacter file encoding quoteState
        scan file { rest with tokens := rest.tokens.push {
          kind := .character value encoding, pos } }
      else if isIdentStart c then
        let pos := state.pos
        let (name, rest) := takeWhile state isIdentRest
        let kind := match macroValue? state name with
          | some literal => TokenKind.number literal
          | none => TokenKind.identifier name
        scan file { rest with tokens := rest.tokens.push { kind, pos } }
      else if c.isDigit then
        let pos := state.pos
        let (literal, rest) ← readNumber file state
        scan file { rest with tokens := rest.tokens.push { kind := .number literal, pos } }
      else if c == '\'' then
        let pos := state.pos
        let (value, rest) ← readCharacter file .ordinary state
        scan file { rest with tokens := rest.tokens.push {
          kind := .character value .ordinary, pos } }
      else if c == '"' then
        let pos := state.pos
        let (values, rest) ← readString file .ordinary state
        scan file { rest with tokens := rest.tokens.push {
          kind := .stringLiteral values .ordinary, pos } }
      else
        match (peek? state).bind fun second =>
            (peek? state 2).bind (threeCharacterSymbol? c second) with
        | some symbol =>
            let rest := advance (advance (advance state))
            scan file { rest with tokens := rest.tokens.push {
              kind := .symbol symbol, pos := state.pos } }
        | none =>
          match peek? state >>= twoCharacterSymbol? c with
          | some symbol =>
              let rest := advance (advance state)
              scan file { rest with tokens := rest.tokens.push {
                kind := .symbol symbol, pos := state.pos } }
          | none =>
              if isSingleSymbol c then
                let rest := advance state
                scan file { rest with tokens := rest.tokens.push {
                  kind := .symbol (String.singleton c), pos := state.pos } }
              else
                throw {
                  file := file
                  pos := state.pos
                  message := s!"unexpected character '{c}'" }

def lex (source file : String) : Except CompileError (Array Token) := do
  let state ← scan file { input := source.toList.toArray }
  pure state.tokens

end JMachineC
