import { describeWord } from './runtime.js';

// MDP Architecture Version 11, instruction summary (p. 27) and encoding (pp. 23–26).
const OPS = {
  0x00: ['NOP', 'none', 'Do nothing.'],
  0x01: ['READ', 'read', 'Copy the source word, including its tag, into the destination data register.'],
  0x02: ['WRITE', 'write', 'Store the source data register, including its tag, in memory.'],
  0x03: ['READR', 'read-register', 'Read a processor register into a data register.'],
  0x04: ['WRITER', 'write-register', 'Write a data register into a processor register.'],
  0x05: ['RTAG', 'read', 'Read the source word’s four-bit type tag as an integer.'],
  0x06: ['WTAG', 'three', 'Keep the source register’s data bits and replace its tag with the supplied tag number.'],
  0x07: ['LDIP', 'one', 'Load an instruction pointer and jump to it. Its flags select checked execution and addressing.'],
  0x08: ['LDIPR', 'register', 'Load the instruction pointer from a processor register, for example the saved fault instruction pointer.'],
  0x09: ['CHECK', 'three', 'Test whether the source register has the supplied tag number; write a Boolean result.'],
  0x0a: ['CARRY', 'three', 'Add the operands and write the carry bit as an integer.'],
  0x0b: ['ADD', 'three', 'Add the source register and the source operand; write the result to the destination register.'],
  0x0c: ['SUB', 'three', 'Subtract the source operand from the source register; write the result to the destination register.'],
  0x0e: ['MULH', 'three', 'Multiply signed integers and write the high 32 bits of the product.'],
  0x0f: ['MUL', 'three', 'Multiply signed integers and write the low 32 bits of the product.'],
  0x10: ['ASH', 'three', 'Shift the source register left for a positive count, or right with sign extension for a negative count.'],
  0x11: ['LSH', 'three', 'Shift the source register left for a positive count, or right with zero fill for a negative count.'],
  0x12: ['ROT', 'three', 'Rotate the source register’s 32 data bits left by the supplied count, wrapping bits around.'],
  0x18: ['AND', 'three', 'Write the bitwise AND of the operands.'],
  0x19: ['OR', 'three', 'Write the bitwise OR of the operands.'],
  0x1a: ['XOR', 'three', 'Write the bitwise exclusive OR of the operands.'],
  0x1b: ['FFB', 'read', 'Count the leading data bits that match the sign bit, for normalization.'],
  0x1c: ['NOT', 'read', 'Invert the source operand’s data bits.'],
  0x1d: ['NEG', 'read', 'Negate the source integer.'],
  0x20: ['LT', 'three', 'Compare whether the source register is less than the source operand; write a Boolean.'],
  0x21: ['LE', 'three', 'Compare whether the source register is less than or equal to the source operand; write a Boolean.'],
  0x22: ['GE', 'three', 'Compare whether the source register is greater than or equal to the source operand; write a Boolean.'],
  0x23: ['GT', 'three', 'Compare whether the source register is greater than the source operand; write a Boolean.'],
  0x24: ['EQUAL', 'three', 'Compare the data values of compatible integers, Booleans, or symbols for equality.'],
  0x25: ['NEQUAL', 'three', 'Compare the data values of compatible integers, Booleans, or symbols for inequality.'],
  0x26: ['EQ', 'three', 'Compare whole tagged words for equality. An unresolved future faults in checked mode.'],
  0x27: ['NEQ', 'three', 'Compare whole tagged words for inequality. An unresolved future faults in checked mode.'],
  0x28: ['XLATE', 'lookup', 'Look up the source register’s key in the associative table and write the result to the destination. A missing or NIL entry faults.'],
  0x29: ['ENTER', 'enter', 'Insert the supplied key and the source register’s data into the associative table.'],
  0x2a: ['INVAL', 'none', 'Invalidate relocatable address registers in the message contexts so their objects must be translated again.'],
  0x2d: ['PROBE', 'probe', 'Look up the source register’s key in the associative table; return NIL on a miss.'],
  0x30: ['SUSPEND', 'none', 'Finish the current message handler, remove its message from the queue, and allow another message or background code to run.'],
  0x31: ['CALL', 'one', 'Call through the system-call vector table and save the return instruction pointer in FIP.'],
  0x34: ['SEND', 'send', 'Append one word to an outgoing message at the specified priority. The first word identifies the destination node.'],
  0x35: ['SENDE', 'send', 'Append the final word and end the outgoing message, clearing the interrupt mask.'],
  0x36: ['SEND2', 'send-two', 'Append two words to an outgoing message at the specified priority.'],
  0x37: ['SEND2E', 'send-two', 'Append the final two words and end the outgoing message, clearing the interrupt mask.'],
  0x38: ['BR', 'one', 'Branch by a signed word displacement relative to the word containing this instruction.'],
  0x3a: ['BNIL', 'branch', 'Branch by the supplied word displacement if the source register is NIL.'],
  0x3b: ['BNNIL', 'branch', 'Branch by the supplied word displacement if the source register is not NIL.'],
  0x3c: ['BF', 'branch', 'Branch by the supplied word displacement if the source Boolean is false.'],
  0x3d: ['BT', 'branch', 'Branch by the supplied word displacement if the source Boolean is true.'],
  0x3e: ['BZ', 'branch', 'Branch by the supplied word displacement if the source integer is zero.'],
  0x3f: ['BNZ', 'branch', 'Branch by the supplied word displacement if the source integer is not zero.'],
};

const REGISTERS = ['R0', 'R1', 'R2', 'R3', 'A0', 'A1', 'A2', 'A3', 'ID0', 'ID1', 'ID2', 'ID3', 'FIP', 'FIR', 'FOP0', 'FOP1', 'QBM', 'QHL', 'IP', 'TBM', 'NNR', 'MAR'];
const FLAGS = { 24: 'P', 25: 'B', 26: 'I', 27: 'F', 28: 'U', 29: 'Q' };
function registerOperand(value) {
  const name = REGISTERS[value & 31] ?? FLAGS[value & 31] ?? `reserved(${value & 31})`;
  return `${name}${value & 64 ? '[B xor 1]' : ''}${value & 32 ? '[P xor 1]' : ''}`;
}
function operand(value, extension) {
  if (value < 8) return REGISTERS[value];
  if (value < 16) return ['NIL', 'FALSE', 'TRUE', 'INT_MIN', '0xff', '0x3ff', '0xffff', '0xfffff'][value - 8];
  if (value < 32) return `[A${value & 3} + R${(value >> 2) & 3}]`;
  if (value < 64) { const n = (extension << 5) | (value & 31); return `${n & 64 ? n - 128 : n}`; }
  return `[A${value & 3} + ${(extension << 4) | ((value >> 2) & 15)}]`;
}

export function decodeInstruction(bits) {
  const opcode = bits >> 11, op2 = (bits >> 9) & 3, op1 = (bits >> 7) & 3, op0 = bits & 127;
  const definition = OPS[opcode];
  if (!definition) return { text: `ILLEGAL 0x${bits.toString(16).padStart(5, '0')}`, explanation: 'This opcode is not defined by MDP Version 11; executing it raises an illegal-instruction fault.' };
  const [name, form, explanation] = definition;
  const extension = ['read', 'send'].includes(form) ? op1 : ['one', 'branch', 'write'].includes(form) ? op2 : 0;
  const src = operand(op0, extension), rs = `R${op1}`, rd = `R${op2}`, priority = `P${op2}`;
  const args = {
    none: '', read: `${src}, ${rd}`, write: `${rs}, ${src}`,
    'read-register': `${registerOperand(op0)}, ${rd}`, 'write-register': `${rs}, ${registerOperand(op0)}`,
    register: registerOperand(op0), one: src, three: `${rs}, ${src}, ${rd}`,
    lookup: `${rs}, ${src}, ${op2}`, probe: `${rs}, ${src}`, enter: `${src}, ${rs}`,
    send: `${src}, ${priority}`, 'send-two': `${src}, ${rs}, ${priority}`, branch: `${rs}, ${src}`,
  }[form];
  return { text: `${name}${args ? ` ${args}` : ''}`, explanation: `${explanation} R0–R3 hold tagged data; A0–A3 address memory. Brackets mean a memory access. Checked execution validates operand tags and can fault.` };
}

export function decodeWord(word) {
  if ((word >> 34n) === 3n) return [0, 1].map(phase => ({ phase, ...decodeInstruction(Number((word >> (phase ? 0n : 17n)) & 0x1ffffn)) }));
  return [{ phase: 0, text: `LITERAL ${describeWord(word)}`, explanation: `When fetched in the instruction stream, this tagged constant is loaded into R0 and execution advances to the next word. It is not an opcode.` }];
}

export function instructionAddress(node) {
  let address = Number((node.ip >> 10n) & 0xfffffn);
  if (!(node.ip & 0x100n)) address = (address + Number((node.registers[4] >> 10n) & 0xfffffn)) & 0xfffff;
  if (address < 0x40 && node.priority) address ^= 0x20;
  return address;
}
