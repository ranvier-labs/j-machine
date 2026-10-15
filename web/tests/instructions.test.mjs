import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { decodeInstruction, decodeWord, instructionAddress } from '../site/instructions.js';

const instruction = (op, op2 = 0, op1 = 0, op0 = 0) => (op << 11) | (op2 << 9) | (op1 << 7) | op0;
const pair = (high, low = 0) => (3n << 34n) | (BigInt(high) << 17n) | BigInt(low);

test('decodes both packed instruction phases and tagged literal loads', () => {
  const rows = decodeWord(pair(instruction(0x0b, 2, 1, 0x23), instruction(0x35, 1, 0, 2)));
  assert.deepEqual(rows.map(r => [r.phase, r.text]), [[0, 'ADD R1, 3, R2'], [1, 'SENDE R2, P1']]);
  assert.match(rows[1].explanation, /end the outgoing message/);
  assert.equal(decodeWord(0x10000002an)[0].text, 'LITERAL INT(42)');
  assert.match(decodeWord(0x1ffffffffn)[0].explanation, /loaded into R0/);
});

test('decodes extended signed immediates, memory offsets, special constants and registers', () => {
  assert.equal(decodeInstruction(instruction(1, 2, 3, 0x3f)).text, 'READ -1, R2');
  assert.equal(decodeInstruction(instruction(1, 2, 2, 0x20)).text, 'READ -64, R2');
  assert.equal(decodeInstruction(instruction(1, 2, 3, 0x7e)).text, 'READ [A2 + 63], R2');
  assert.equal(decodeInstruction(instruction(2, 2, 1, 0x7e)).text, 'WRITE R1, [A2 + 47]');
  assert.equal(decodeInstruction(instruction(1, 2, 0, 0x1b)).text, 'READ [A3 + R2], R2');
  assert.equal(decodeInstruction(instruction(1, 2, 0, 0x0c)).text, 'READ 0xff, R2');
  assert.equal(decodeInstruction(instruction(3, 2, 0, 0x14)).text, 'READR NNR, R2');
  assert.equal(decodeInstruction(instruction(4, 0, 1, 0x26)).text, 'WRITER R1, A2[P xor 1]');
  assert.equal(decodeInstruction(instruction(8, 0, 0, 0x4c)).text, 'LDIPR FIP[B xor 1]');
  assert.equal(decodeInstruction(instruction(0x3e, 3, 1, 0x3f)).text, 'BZ R1, -1');
  assert.equal(decodeInstruction(instruction(0x28, 1, 2, 6)).text, 'XLATE R2, A2, 1');
  assert.match(decodeInstruction(instruction(0x0d)).text, /ILLEGAL/);
});

test('every opcode emitted by the compiler has a decoder and explanation', async () => {
  const mdp = await readFile(new URL('../../compiler/JMachineC/MDP.lean', import.meta.url), 'utf8');
  const encodings = mdp.split('def Opcode.encoding')[1].split('def tagged')[0];
  const codes = [...encodings.matchAll(/=> (0x[0-9a-f]+)/g)].map(match => Number(match[1]));
  assert.ok(codes.length > 40);
  for (const code of codes) {
    const decoded = decodeInstruction(instruction(code));
    assert.ok(!decoded.text.startsWith('ILLEGAL'), `missing opcode ${code.toString(16)}`);
    assert.ok(decoded.explanation.length > 15);
  }
});

test('the existing compiled factorial image decodes from its encoded words', async () => {
  const image = await readFile(new URL('fixtures/factorial_2node.image', import.meta.url), 'utf8');
  const words = new Map(image.split('\n').filter(line => /^0\s/.test(line)).map(line => { const fields = line.trim().split(/\s+/); return [fields[1], BigInt('0x' + fields[2])]; }));
  assert.equal(decodeWord(words.get('3000a'))[0].text, 'READ R0, R1');
  assert.equal(decodeWord(words.get('3002d'))[0].text, 'LDIP R2');
});

test('resolves fetch addresses through A0 and priority-switched low memory', () => {
  const node = { ip: (0x12n << 10n) | 0x100n, priority: 1, registers: [0n, 0n, 0n, 0n, 0x300040000n] };
  assert.equal(instructionAddress(node), 0x32);
  node.ip = 5n << 10n;
  assert.equal(instructionAddress(node), 0x105);
  node.ip = (0x30000n << 10n) | 0x100n;
  assert.equal(instructionAddress(node), 0x30000);
});
