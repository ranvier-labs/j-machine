import JMachineC.AST

namespace JMachineC.MDP

abbrev Word := Nat
abbrev Instruction := Nat

def addressMask : Nat := 0xfffff
def wordMask : Nat := 0xfffffffff

inductive Tag where
  | sym | int | bool | addr | ip | msg | cFuture | future
  | tag8 | tag9 | tagA | tagB | inst0 | inst1 | inst2 | inst3
deriving Repr, BEq

def Tag.encoding : Tag → Nat
  | .sym => 0x0 | .int => 0x1 | .bool => 0x2 | .addr => 0x3
  | .ip => 0x4 | .msg => 0x5 | .cFuture => 0x6 | .future => 0x7
  | .tag8 => 0x8 | .tag9 => 0x9 | .tagA => 0xa | .tagB => 0xb
  | .inst0 => 0xc | .inst1 => 0xd | .inst2 => 0xe | .inst3 => 0xf

inductive Opcode where
  | nop | read | write | readR | writeR | readTag | writeTag
  | loadIp | loadIpR | check | carry | add | sub | mulHigh | mul
  | arithmeticShift | logicalShift | rotate | and | or | xor
  | findFirstBit | not | negate | less | lessEqual | greaterEqual
  | greater | equalData | notEqualData | equal | notEqual | translate
  | enter | invalidate | probe | suspend | call | send | sendEnd
  | send2 | send2End | branch | branchNil | branchNotNil | branchFalse
  | branchTrue | branchZero | branchNotZero
deriving Repr, BEq

def Opcode.encoding : Opcode → Nat
  | .nop => 0x00 | .read => 0x01 | .write => 0x02
  | .readR => 0x03 | .writeR => 0x04 | .readTag => 0x05
  | .writeTag => 0x06 | .loadIp => 0x07 | .loadIpR => 0x08
  | .check => 0x09 | .carry => 0x0a | .add => 0x0b | .sub => 0x0c
  | .mulHigh => 0x0e | .mul => 0x0f | .arithmeticShift => 0x10
  | .logicalShift => 0x11 | .rotate => 0x12 | .and => 0x18
  | .or => 0x19 | .xor => 0x1a | .findFirstBit => 0x1b
  | .not => 0x1c | .negate => 0x1d | .less => 0x20
  | .lessEqual => 0x21 | .greaterEqual => 0x22 | .greater => 0x23
  | .equalData => 0x24 | .notEqualData => 0x25 | .equal => 0x26
  | .notEqual => 0x27 | .translate => 0x28 | .enter => 0x29
  | .invalidate => 0x2a | .probe => 0x2d | .suspend => 0x30
  | .call => 0x31 | .send => 0x34 | .sendEnd => 0x35
  | .send2 => 0x36 | .send2End => 0x37 | .branch => 0x38
  | .branchNil => 0x3a | .branchNotNil => 0x3b | .branchFalse => 0x3c
  | .branchTrue => 0x3d | .branchZero => 0x3e | .branchNotZero => 0x3f

def tagged (tag : Tag) (data : Nat) : Word :=
  ((tag.encoding <<< 32) ||| (data &&& 0xffffffff)) &&& wordMask

def intData (value : Int) : Nat :=
  Int.toNat (value % (Int.ofNat (2 ^ 32)))

def integer (value : Int) : Word := tagged .int (intData value)
def boolean (value : Bool) : Word := tagged .bool (if value then 1 else 0)

def address (relocatable invalid : Bool) (base length : Nat) : Word :=
  tagged .addr (((if relocatable then 1 else 0) <<< 31) |||
    ((if invalid then 1 else 0) <<< 30) |||
    ((base &&& addressMask) <<< 10) ||| (length &&& 0x3ff))

def instructionPointer (unchecked fault : Bool) (offset : Nat)
    (phase absoluteA0 : Bool) : Word :=
  tagged .ip (((if unchecked then 1 else 0) <<< 31) |||
    ((if fault then 1 else 0) <<< 30) |||
    ((offset &&& addressMask) <<< 10) |||
    ((if phase then 1 else 0) <<< 9) |||
    ((if absoluteA0 then 1 else 0) <<< 8))

def message (unchecked fault : Bool) (handler length : Nat) : Word :=
  tagged .msg (((if unchecked then 1 else 0) <<< 31) |||
    ((if fault then 1 else 0) <<< 30) |||
    ((handler &&& addressMask) <<< 10) ||| (length &&& 0x3ff))

def instruction (opcode : Opcode) (op2 op1 op0 : Nat) : Instruction :=
  ((opcode.encoding &&& 0x3f) <<< 11) ||| ((op2 &&& 3) <<< 9) |||
    ((op1 &&& 3) <<< 7) ||| (op0 &&& 0x7f)

def instructionPair (high : Instruction) (low : Instruction := 0) : Word :=
  (3 <<< 34) ||| ((high &&& 0x1ffff) <<< 17) ||| (low &&& 0x1ffff)

def operandR (number : Nat) : Nat := number &&& 3
def operandA (number : Nat) : Nat := 0x04 ||| (number &&& 3)
def operandMemoryRegister (offsetRegister addressRegister : Nat) : Nat :=
  0x10 ||| ((offsetRegister &&& 3) <<< 2) ||| (addressRegister &&& 3)
def operandImmediate (value : Int) : Nat := 0x20 ||| (intData value &&& 0x1f)
def operandMemoryImmediate (offset addressRegister : Nat) : Nat :=
  0x40 ||| ((offset &&& 0xf) <<< 2) ||| (addressRegister &&& 3)
def registerOperand (backgroundRelative priorityRelative : Bool)
    (number : Nat) : Nat :=
  ((if backgroundRelative then 1 else 0) <<< 6) |||
    ((if priorityRelative then 1 else 0) <<< 5) ||| (number &&& 0x1f)

private def hexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n)
  else Char.ofNat ('a'.toNat + n - 10)

private def hexDigits : Nat → Nat → List Char
  | 0, _ => []
  | n + 1, value => hexDigits n (value / 16) ++ [hexDigit (value % 16)]

def toHex (width value : Nat) : String := String.ofList (hexDigits width value)

end JMachineC.MDP
