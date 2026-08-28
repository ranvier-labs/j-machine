#include <verilated.h>
#include "Vj_machine_verilator_top.h"
#include "../golden/mdp_golden.hpp"

#include <array>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>

double sc_time_stamp() { return 0.0; }

namespace {
constexpr uint8_t TAG_SYM = 0x0;
constexpr uint8_t TAG_INT = 0x1;
constexpr uint8_t TAG_BOOL = 0x2;
constexpr uint8_t TAG_ADDR = 0x3;
constexpr uint8_t TAG_IP = 0x4;
constexpr uint8_t TAG_MSG = 0x5;
constexpr uint8_t FAULT_INTERRUPT = 0x01;
constexpr uint8_t FAULT_QUEUE = 0x02;
constexpr uint8_t FAULT_DRAMERR = 0x05;
constexpr uint8_t FAULT_TYPE = 0x12;

constexpr uint8_t OP_NOP = 0x00;
constexpr uint8_t OP_READ = 0x01;
constexpr uint8_t OP_WRITE = 0x02;
constexpr uint8_t OP_READR = 0x03;
constexpr uint8_t OP_WRITER = 0x04;
constexpr uint8_t OP_RTAG = 0x05;
constexpr uint8_t OP_WTAG = 0x06;
constexpr uint8_t OP_LDIP = 0x07;
constexpr uint8_t OP_LDIPR = 0x08;
constexpr uint8_t OP_CHECK = 0x09;
constexpr uint8_t OP_CARRY = 0x0a;
constexpr uint8_t OP_ADD = 0x0b;
constexpr uint8_t OP_SUB = 0x0c;
constexpr uint8_t OP_MULH = 0x0e;
constexpr uint8_t OP_MUL = 0x0f;
constexpr uint8_t OP_ASH = 0x10;
constexpr uint8_t OP_LSH = 0x11;
constexpr uint8_t OP_ROT = 0x12;
constexpr uint8_t OP_AND = 0x18;
constexpr uint8_t OP_OR = 0x19;
constexpr uint8_t OP_XOR = 0x1a;
constexpr uint8_t OP_FFB = 0x1b;
constexpr uint8_t OP_NOT = 0x1c;
constexpr uint8_t OP_NEG = 0x1d;
constexpr uint8_t OP_LT = 0x20;
constexpr uint8_t OP_LE = 0x21;
constexpr uint8_t OP_GE = 0x22;
constexpr uint8_t OP_GT = 0x23;
constexpr uint8_t OP_EQUAL = 0x24;
constexpr uint8_t OP_NEQUAL = 0x25;
constexpr uint8_t OP_EQ = 0x26;
constexpr uint8_t OP_NEQ = 0x27;
constexpr uint8_t OP_XLATE = 0x28;
constexpr uint8_t OP_ENTER = 0x29;
constexpr uint8_t OP_INVAL = 0x2a;
constexpr uint8_t OP_PROBE = 0x2d;
constexpr uint8_t OP_SUSPEND = 0x30;
constexpr uint8_t OP_CALL = 0x31;
constexpr uint8_t OP_SEND = 0x34;
constexpr uint8_t OP_SEND2E = 0x37;
constexpr uint8_t OP_BR = 0x38;
constexpr uint8_t OP_BNIL = 0x3a;
constexpr uint8_t OP_BNNIL = 0x3b;
constexpr uint8_t OP_BF = 0x3c;
constexpr uint8_t OP_BT = 0x3d;
constexpr uint8_t OP_BZ = 0x3e;
constexpr uint8_t OP_BNZ = 0x3f;

uint64_t word(uint8_t tag, uint32_t data) {
  return (uint64_t(tag) << 32) | data;
}

uint64_t integer(uint32_t value) { return word(TAG_INT, value); }
uint64_t boolean(bool value) { return word(TAG_BOOL, value ? 1 : 0); }
uint64_t address(bool relocatable, bool invalid, uint32_t base, uint16_t length) {
  const uint32_t data = (uint32_t(relocatable) << 31)
                      | (uint32_t(invalid) << 30)
                      | ((base & 0xfffff) << 10) | (length & 0x3ff);
  return word(TAG_ADDR, data);
}
uint64_t message(bool unchecked, bool fault, uint32_t handler, uint16_t length) {
  const uint32_t data = (uint32_t(unchecked) << 31)
                      | (uint32_t(fault) << 30)
                      | ((handler & 0xfffff) << 10) | (length & 0x3ff);
  return word(TAG_MSG, data);
}
uint64_t instruction_pointer(bool unchecked, bool fault, uint32_t offset,
                             bool phase, bool absolute_a0) {
  const uint32_t data = (uint32_t(unchecked) << 31)
                      | (uint32_t(fault) << 30)
                      | ((offset & 0xfffff) << 10)
                      | (uint32_t(phase) << 9)
                      | (uint32_t(absolute_a0) << 8);
  return word(TAG_IP, data);
}
uint32_t instruction(uint8_t opcode, uint8_t op2, uint8_t op1, uint8_t op0) {
  return (uint32_t(opcode & 0x3f) << 11) | (uint32_t(op2 & 3) << 9)
       | (uint32_t(op1 & 3) << 7) | (op0 & 0x7f);
}
uint64_t pair(uint32_t high, uint32_t low = 0) {
  return (uint64_t(3) << 34) | (uint64_t(high & 0x1ffff) << 17)
       | uint64_t(low & 0x1ffff);
}
uint8_t op_r(unsigned number) { return number & 3; }
uint8_t op_a(unsigned number) { return 0x04 | (number & 3); }
uint8_t op_mem_i(unsigned offset, unsigned address_register) {
  return 0x40 | ((offset & 0xf) << 2) | (address_register & 3);
}
uint8_t op_imm5(int value) { return 0x20 | (value & 0x1f); }
uint8_t regop(bool background, bool relative_priority, uint8_t number) {
  return (uint8_t(background) << 6) | (uint8_t(relative_priority) << 5)
       | (number & 0x1f);
}

struct Simulator {
  Vj_machine_verilator_top top;
  jmachine::golden::Machine golden{2};

  void half_cycle(bool clock) {
    top.clk = clock;
    top.eval();
  }
  void cycle() {
    half_cycle(false);
    half_cycle(true);
  }
  void write(unsigned node, uint32_t location, uint64_t value) {
    top.debug_node = node;
    top.debug_address = location;
    top.debug_wdata = value;
    top.debug_write = 1;
    cycle();
    top.debug_write = 0;
    golden.loaderWrite(node, location, value);
  }
  uint64_t read(unsigned node, uint32_t location) {
    top.debug_node = node;
    top.debug_address = location;
    top.eval();
    return top.debug_rdata;
  }
  void insn(unsigned node, uint32_t location, uint32_t encoded) {
    write(node, location, pair(encoded, instruction(OP_NOP, 0, 0, 0)));
  }
};

[[noreturn]] void fail(Simulator& sim, const char* reason);
[[noreturn]] void fail_golden(Simulator& sim, const char* reason);

uint32_t load_common(Simulator& sim, unsigned node, uint16_t nnr) {
  uint32_t pc = 0x1000;
  sim.write(node, pc++, integer(nnr));
  sim.insn(node, pc++, instruction(OP_WRITER, 0, 0, regop(false, false, 0x14)));
  sim.write(node, pc++, address(false, false, 0x200, 0x03f));
  sim.insn(node, pc++, instruction(OP_WRITER, 0, 0, regop(false, false, 0x10)));
  sim.write(node, pc++, address(false, false, 0x200, 0));
  sim.insn(node, pc++, instruction(OP_WRITER, 0, 0, regop(false, false, 0x11)));
  sim.write(node, pc++, address(false, false, 0x240, 0x03f));
  sim.insn(node, pc++, instruction(OP_WRITER, 0, 0, regop(false, true, 0x10)));
  sim.write(node, pc++, address(false, false, 0x240, 0));
  sim.insn(node, pc++, instruction(OP_WRITER, 0, 0, regop(false, true, 0x11)));
  sim.write(node, pc++, address(false, false, 0x300, 0x00f));
  sim.insn(node, pc++, instruction(OP_WRITER, 0, 0, regop(false, false, 0x13)));
  sim.write(node, pc++, address(false, false, 0x400, 0x010));
  sim.insn(node, pc++, instruction(OP_WRITER, 0, 0, regop(true, true, 0x05)));
  sim.write(node, pc++, boolean(false));
  sim.insn(node, pc++, instruction(OP_WRITER, 0, 0, regop(false, false, 0x1c)));
  sim.insn(node, pc++, instruction(OP_WRITER, 0, 0, regop(false, false, 0x1a)));
  return pc;
}

void load_programs(Simulator& sim) {
  uint32_t pc = load_common(sim, 0, 0);
  sim.write(0, pc++, integer(7));
  sim.insn(0, pc++, instruction(OP_READ, 1, 0, op_r(0)));
  sim.write(0, pc++, integer(5));
  sim.insn(0, pc++, instruction(OP_ADD, 2, 1, op_r(0)));
  sim.write(0, pc++, address(false, false, 0x400, 0x010));
  sim.insn(0, pc++, instruction(OP_WRITER, 0, 0, regop(false, false, 0x05)));
  sim.insn(0, pc++, instruction(OP_WRITE, 0, 2, op_mem_i(0, 1)));
  sim.write(0, pc++, integer(77));
  sim.insn(0, pc++, instruction(OP_READ, 1, 0, op_r(0)));
  sim.write(0, pc++, address(true, false, 0x500, 8));
  sim.insn(0, pc++, instruction(OP_READ, 2, 0, op_r(0)));
  sim.insn(0, pc++, instruction(OP_ENTER, 0, 2, op_r(1)));
  sim.insn(0, pc++, instruction(OP_XLATE, 0, 1, op_a(2)));
  sim.insn(0, pc++, instruction(OP_READ, 3, 0, op_a(2)));
  sim.insn(0, pc++, instruction(OP_WRITE, 0, 3, op_mem_i(1, 1)));
  sim.write(0, pc++, integer(1));
  sim.insn(0, pc++, instruction(OP_SEND, 1, 0, op_r(0)));
  sim.write(0, pc++, message(false, false, 0x1100, 2));
  sim.insn(0, pc++, instruction(OP_READ, 1, 0, op_r(0)));
  sim.write(0, pc++, integer(42));
  sim.insn(0, pc++, instruction(OP_READ, 2, 0, op_r(0)));
  sim.insn(0, pc++, instruction(OP_SEND2E, 1, 2, op_r(1)));
  sim.insn(0, pc, instruction(OP_BR, 3, 0, op_imm5(-1)));

  pc = load_common(sim, 1, 1);
  sim.insn(1, pc, instruction(OP_BR, 3, 0, op_imm5(-1)));
  pc = 0x1100;
  sim.insn(1, pc++, instruction(OP_READ, 0, 0, op_mem_i(1, 3)));
  sim.insn(1, pc++, instruction(OP_WRITE, 0, 0, op_mem_i(2, 1)));
  sim.insn(1, pc, instruction(OP_SUSPEND, 0, 0, 0));
}

void load_type_fault_program(Simulator& sim) {
  uint32_t pc = 0x1000;
  sim.write(0, 0x40 + FAULT_TYPE,
            instruction_pointer(false, true, 0x1200, false, true));
  sim.write(0, pc++, boolean(false));
  sim.insn(0, pc++, instruction(OP_WRITER, 0, 0, regop(false, false, 0x1c)));
  sim.write(0, pc++, boolean(true));
  sim.insn(0, pc++, instruction(OP_READ, 1, 0, op_r(0)));
  sim.write(0, pc++, integer(1));
  sim.insn(0, pc, instruction(OP_ADD, 2, 1, op_r(0)));
  sim.insn(0, 0x1200, instruction(OP_BR, 3, 0, op_imm5(-1)));
}

void load_fault_record_handler(Simulator& sim, uint8_t fault,
                               uint32_t handler, uint32_t record,
                               bool record_mar) {
  sim.write(0, 0x40 + fault,
            instruction_pointer(false, true, handler, false, true));
  uint32_t pc = handler;
  sim.write(0, pc++, address(false, false, record, 1));
  sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                regop(false, false, 0x06)));
  sim.insn(0, pc++, instruction(OP_READR, 0, 0,
                                regop(false, false,
                                      record_mar ? 0x15 : 0x0c)));
  sim.insn(0, pc++, instruction(OP_WRITE, 0, 0, op_mem_i(0, 2)));
  if (record_mar) {
    sim.write(0, pc++, address(false, false, record + 1, 1));
    sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                  regop(false, false, 0x06)));
    sim.insn(0, pc++, instruction(OP_READR, 0, 0,
                                  regop(false, false, 0x0c)));
    sim.insn(0, pc++, instruction(OP_WRITE, 0, 0, op_mem_i(0, 2)));
  }
  sim.insn(0, pc, instruction(OP_BR, 3, 0, op_imm5(-1)));
}

uint64_t load_interrupt_fault_program(Simulator& sim, uint32_t record) {
  load_fault_record_handler(sim, FAULT_INTERRUPT, 0x1220, record, false);
  uint32_t pc = 0x1000;
  sim.write(0, pc++, boolean(false));
  const uint32_t unmask_instruction = pc;
  sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                regop(false, false, 0x1a)));
  sim.insn(0, pc, instruction(OP_BR, 3, 0, op_imm5(-1)));
  return instruction_pointer(true, false, unmask_instruction, true, true);
}

uint64_t load_dram_fault_program(Simulator& sim, uint32_t fault_address,
                                 uint32_t record) {
  load_fault_record_handler(sim, FAULT_DRAMERR, 0x1240, record, true);
  uint32_t pc = 0x1000;
  sim.write(0, pc++, address(false, false, fault_address, 1));
  sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                regop(false, false, 0x05)));
  const uint32_t read_instruction = pc;
  sim.insn(0, pc++, instruction(OP_READ, 1, 0, op_mem_i(0, 1)));
  sim.insn(0, pc, instruction(OP_BR, 3, 0, op_imm5(-1)));
  return instruction_pointer(true, false, read_instruction, true, true);
}

uint64_t load_queue_fault_program(Simulator& sim, uint32_t record) {
  constexpr uint32_t message_handler = 0x1100;
  load_fault_record_handler(sim, FAULT_QUEUE, 0x1260, record, false);
  uint32_t pc = load_common(sim, 0, 0);

  // A single committed QRB row fills this four-word priority-0 queue. The
  // two-word message is padded to a complete row by the architectural queue
  // machinery, dispatched, and then raises QUEUE before its first fetch.
  sim.write(0, pc++, address(false, false, 0x200, 3));
  sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                regop(false, false, 0x10)));
  sim.write(0, pc++, address(false, false, 0x200, 0));
  sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                regop(false, false, 0x11)));
  sim.write(0, pc++, integer(0));
  sim.insn(0, pc++, instruction(OP_SEND, 0, 0, op_r(0)));
  sim.write(0, pc++, message(false, false, message_handler, 2));
  sim.insn(0, pc++, instruction(OP_READ, 1, 0, op_r(0)));
  sim.write(0, pc++, integer(99));
  sim.insn(0, pc++, instruction(OP_READ, 2, 0, op_r(0)));
  sim.insn(0, pc++, instruction(OP_SEND2E, 0, 2, op_r(1)));
  sim.insn(0, pc, instruction(OP_BR, 3, 0, op_imm5(-1)));
  sim.insn(0, message_handler, instruction(OP_BR, 3, 0, op_imm5(-1)));
  return instruction_pointer(false, false, message_handler, false, true);
}

void reset_fixture(Simulator& sim) {
  sim.top.reset = 1;
  sim.top.run_enable = 0;
  sim.top.external_interrupt = 0;
  sim.top.dram_error_inject = 0;
  sim.cycle();
  sim.golden.reset();
}

void run_fixture(Simulator& sim, unsigned golden_events = 512,
                 unsigned rtl_cycles = 1024) {
  sim.golden.run(golden_events);
  sim.top.reset = 0;
  sim.top.run_enable = 1;
  for (unsigned cycle = 0; cycle < rtl_cycles; ++cycle) sim.cycle();
  sim.top.run_enable = 0;
  sim.top.eval();
}

void emit_store_literal(Simulator& sim, uint32_t& pc, uint64_t value,
                        uint32_t destination) {
  sim.write(0, pc++, value);
  sim.insn(0, pc++, instruction(OP_READ, 2, 0, op_r(0)));
  sim.write(0, pc++, address(false, false, destination, 1));
  sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                regop(false, false, 0x05)));
  sim.insn(0, pc++, instruction(OP_WRITE, 0, 2, op_mem_i(0, 1)));
}

void run_translation_and_invalidation_fixture(Simulator& sim) {
  constexpr uint32_t output = 0x3400;
  constexpr uint32_t table_base = 0x0360;
  constexpr uint32_t table_row = 0x036c;
  constexpr uint64_t key0 = (uint64_t{TAG_INT} << 32) | 77;
  constexpr uint64_t key1 = (uint64_t{TAG_INT} << 32) | 93;
  constexpr uint64_t missing_key = (uint64_t{TAG_INT} << 32) | 109;
  const uint64_t data0 = address(true, false, 0x500, 8);
  const uint64_t data1 = address(true, false, 0x600, 9);
  const uint64_t foreground_before = address(true, false, 0x700, 4);
  const uint64_t foreground_after = address(true, true, 0x700, 4);

  reset_fixture(sim);
  for (uint32_t index = 0; index < 6; ++index) {
    sim.write(0, output + index, word(0xb, 0x5a5a0000u + index));
  }

  uint32_t pc = 0x1000;
  sim.write(0, pc++, address(false, false, table_base, 0x00f));
  sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                regop(false, false, 0x13)));
  sim.write(0, pc++, address(false, false, output, 7));
  sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                regop(false, false, 0x05)));

  sim.write(0, pc++, data0);
  sim.insn(0, pc++, instruction(OP_READ, 2, 0, op_r(0)));
  sim.write(0, pc++, key0);
  sim.insn(0, pc++, instruction(OP_READ, 1, 0, op_r(0)));
  sim.insn(0, pc++, instruction(OP_ENTER, 0, 2, op_r(1)));

  sim.write(0, pc++, data1);
  sim.insn(0, pc++, instruction(OP_READ, 2, 0, op_r(0)));
  sim.write(0, pc++, key1);
  sim.insn(0, pc++, instruction(OP_READ, 1, 0, op_r(0)));
  sim.insn(0, pc++, instruction(OP_ENTER, 0, 2, op_r(1)));

  sim.write(0, pc++, key0);
  sim.insn(0, pc++, instruction(OP_READ, 1, 0, op_r(0)));
  sim.insn(0, pc++, instruction(OP_PROBE, 0, 1, op_r(3)));
  sim.insn(0, pc++, instruction(OP_WRITE, 0, 3, op_mem_i(0, 1)));
  sim.write(0, pc++, key1);
  sim.insn(0, pc++, instruction(OP_READ, 1, 0, op_r(0)));
  sim.insn(0, pc++, instruction(OP_PROBE, 0, 1, op_r(3)));
  sim.insn(0, pc++, instruction(OP_WRITE, 0, 3, op_mem_i(1, 1)));
  sim.write(0, pc++, missing_key);
  sim.insn(0, pc++, instruction(OP_READ, 1, 0, op_r(0)));
  sim.insn(0, pc++, instruction(OP_PROBE, 0, 1, op_r(3)));
  sim.insn(0, pc++, instruction(OP_WRITE, 0, 3, op_mem_i(2, 1)));

  sim.write(0, pc++, key0);
  sim.insn(0, pc++, instruction(OP_READ, 1, 0, op_r(0)));
  sim.insn(0, pc++, instruction(OP_XLATE, 0, 1, op_a(2)));
  sim.insn(0, pc++, instruction(OP_READ, 3, 0, op_a(2)));
  sim.insn(0, pc++, instruction(OP_WRITE, 0, 3, op_mem_i(3, 1)));

  sim.write(0, pc++, foreground_before);
  sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                regop(true, false, 0x04)));
  sim.insn(0, pc++, instruction(OP_INVAL, 0, 0, 0));
  sim.insn(0, pc++, instruction(OP_READR, 3, 0,
                                regop(true, false, 0x04)));
  sim.insn(0, pc++, instruction(OP_WRITE, 0, 3, op_mem_i(4, 1)));
  sim.insn(0, pc++, instruction(OP_READR, 3, 0,
                                regop(false, false, 0x06)));
  sim.insn(0, pc++, instruction(OP_WRITE, 0, 3, op_mem_i(5, 1)));
  sim.insn(0, pc, instruction(OP_BR, 3, 0, op_imm5(-1)));

  run_fixture(sim);
  const std::array<uint64_t, 6> expected = {
      data0, data1, word(TAG_SYM, 0), data0,
      foreground_after, data0};
  for (uint32_t index = 0; index < expected.size(); ++index) {
    if (sim.golden.readMemory(0, output + index) != expected[index])
      fail_golden(sim, "PROBE/XLATE/INVAL result mismatch");
    if (sim.read(0, output + index) != expected[index])
      fail(sim, "PROBE/XLATE/INVAL result mismatch");
  }
  const std::array<uint64_t, 4> expected_row = {data0, key0, data1, key1};
  for (uint32_t index = 0; index < expected_row.size(); ++index) {
    if (sim.golden.readMemory(0, table_row + index) != expected_row[index]
        || sim.read(0, table_row + index) != expected_row[index]) {
      fail(sim, "two-way translation-table row mismatch");
    }
  }
  if (sim.top.node0_catastrophe || sim.golden.view(0).catastrophe)
    fail(sim, "translation/invalidation fixture asserted catastrophe");
}

void run_ip_control_fixture(Simulator& sim) {
  constexpr uint32_t output = 0x3440;
  constexpr uint32_t direct_target = 0x1100;
  constexpr uint32_t register_target = 0x1120;
  constexpr uint32_t callee = 0x1140;
  constexpr uint32_t call_index = 5;

  reset_fixture(sim);
  for (uint32_t index = 0; index < 3; ++index) {
    sim.write(0, output + index, word(0xb, 0x6b6b0000u + index));
  }
  sim.write(0, 0x80 + call_index,
            instruction_pointer(true, false, callee, false, true));

  uint32_t pc = 0x1000;
  sim.write(0, pc++, instruction_pointer(true, false, direct_target,
                                          false, true));
  sim.insn(0, pc, instruction(OP_LDIP, 0, 0, op_r(0)));

  pc = direct_target;
  emit_store_literal(sim, pc, integer(200), output);
  sim.write(0, pc++, instruction_pointer(true, false, register_target,
                                          false, true));
  sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                regop(false, false, 0x0c)));
  sim.insn(0, pc, instruction(OP_LDIPR, 0, 0,
                              regop(false, false, 0x0c)));

  pc = register_target;
  sim.write(0, pc++, integer(call_index));
  sim.insn(0, pc++, instruction(OP_CALL, 0, 0, op_r(0)));
  emit_store_literal(sim, pc, integer(202), output + 2);
  sim.insn(0, pc, instruction(OP_BR, 3, 0, op_imm5(-1)));

  pc = callee;
  emit_store_literal(sim, pc, integer(201), output + 1);
  sim.insn(0, pc, instruction(OP_LDIPR, 0, 0,
                              regop(false, false, 0x0c)));

  run_fixture(sim);
  for (uint32_t index = 0; index < 3; ++index) {
    const uint64_t expected = integer(200 + index);
    if (sim.golden.readMemory(0, output + index) != expected)
      fail_golden(sim, "LDIP/LDIPR/CALL control-flow mismatch");
    if (sim.read(0, output + index) != expected)
      fail(sim, "LDIP/LDIPR/CALL control-flow mismatch");
  }
  if (sim.top.node0_catastrophe || sim.golden.view(0).catastrophe)
    fail(sim, "IP-control fixture asserted catastrophe");
}

void run_branch_fixtures(Simulator& sim) {
  struct BranchCase {
    uint8_t opcode;
    uint64_t condition;
    bool taken;
  };
  const std::array<BranchCase, 13> cases = {{
      {OP_BR, integer(0), true},
      {OP_BNIL, word(TAG_SYM, 0), true},
      {OP_BNIL, integer(0), false},
      {OP_BNNIL, integer(0), true},
      {OP_BNNIL, word(TAG_SYM, 0), false},
      {OP_BF, boolean(false), true},
      {OP_BF, boolean(true), false},
      {OP_BT, boolean(true), true},
      {OP_BT, boolean(false), false},
      {OP_BZ, integer(0), true},
      {OP_BZ, integer(1), false},
      {OP_BNZ, integer(1), true},
      {OP_BNZ, integer(0), false},
  }};
  constexpr uint32_t output = 0x3480;
  constexpr uint64_t failure = (uint64_t{0xa} << 32) | 0xbad0bad0u;

  for (uint32_t index = 0; index < cases.size(); ++index) {
    reset_fixture(sim);
    const uint64_t expected = integer(300 + index);
    sim.write(0, output + index, failure);
    uint32_t pc = 0x1000;
    sim.write(0, pc++, address(false, false, output + index, 1));
    sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                  regop(false, false, 0x05)));
    sim.write(0, pc++, cases[index].taken ? failure : expected);
    sim.insn(0, pc++, instruction(OP_READ, 2, 0, op_r(0)));
    sim.write(0, pc++, cases[index].taken ? expected : failure);
    sim.insn(0, pc++, instruction(OP_READ, 3, 0, op_r(0)));
    sim.write(0, pc++, cases[index].condition);
    sim.insn(0, pc++, instruction(OP_READ, 1, 0, op_r(0)));
    sim.write(0, pc++, boolean(false));
    sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                  regop(false, false, 0x1c)));
    sim.insn(0, pc++, instruction(cases[index].opcode, 0, 1, op_imm5(2)));
    sim.insn(0, pc++, instruction(OP_WRITE, 0, 2, op_mem_i(0, 1)));
    sim.insn(0, pc++, instruction(OP_BR, 0, 0, op_imm5(1)));
    sim.insn(0, pc++, instruction(OP_WRITE, 0, 3, op_mem_i(0, 1)));
    sim.insn(0, pc, instruction(OP_BR, 3, 0, op_imm5(-1)));

    run_fixture(sim, 128, 256);
    if (sim.golden.readMemory(0, output + index) != expected)
      fail_golden(sim, "conditional branch outcome mismatch");
    if (sim.read(0, output + index) != expected)
      fail(sim, "conditional branch outcome mismatch");
    if (sim.top.node0_catastrophe || sim.golden.view(0).catastrophe)
      fail(sim, "branch fixture asserted catastrophe");
  }
}

[[noreturn]] void fail(Simulator& sim, const char* reason) {
  std::cerr << "FAIL: " << reason
            << " ip=" << std::hex << sim.top.node0_ip << "/" << sim.top.node1_ip
            << " fault=" << unsigned(sim.top.node0_last_fault) << "/"
            << unsigned(sim.top.node1_last_fault)
            << " retired=" << std::dec << sim.top.node0_retired << "/"
            << sim.top.node1_retired
            << " q=" << unsigned(sim.top.node0_queue_pending) << "/"
            << unsigned(sim.top.node1_queue_pending)
            << " n=" << std::hex << sim.top.node0_number << "/"
            << sim.top.node1_number
            << " rows=" << sim.read(0, 0x200) << "/" << sim.read(0, 0x240)
            << "/" << sim.read(1, 0x200) << "/" << sim.read(1, 0x240)
            << '\n';
  std::exit(1);
}

[[noreturn]] void fail_golden(Simulator& sim, const char* reason) {
  const auto node0 = sim.golden.view(0);
  const auto node1 = sim.golden.view(1);
  std::cerr << "GOLDEN FAIL: " << reason
            << " ip=" << std::hex << node0.ip << "/" << node1.ip
            << " fault=" << unsigned(node0.lastFault) << "/"
            << unsigned(node1.lastFault)
            << " retired=" << std::dec << node0.retiredInstructions << "/"
            << node1.retiredInstructions
            << " trace-events=" << sim.golden.trace().size() << '\n';
  std::exit(1);
}

[[noreturn]] void fail_matrix(uint8_t opcode, uint8_t left_tag,
                              uint8_t right_tag, const char* reason,
                              uint64_t rtl_value, uint64_t golden_value,
                              uint8_t rtl_fault, uint8_t golden_fault) {
  std::cerr << "MATRIX FAIL: " << reason
            << " opcode=0x" << std::hex << unsigned(opcode)
            << " tags=0x" << unsigned(left_tag) << "/0x"
            << unsigned(right_tag)
            << " value=0x" << rtl_value << "/0x" << golden_value
            << " fault=0x" << unsigned(rtl_fault) << "/0x"
            << unsigned(golden_fault) << '\n';
  std::exit(1);
}

void run_checked_alu_tag_matrix(Simulator& sim) {
  constexpr uint32_t result_address = 0x3300;
  constexpr uint32_t operand_address = 0x3310;
  constexpr uint32_t handler_base = 0x1800;
  constexpr uint64_t sentinel = (uint64_t{0xb} << 32) | 0x5a5a5a5a;
  constexpr std::array<uint8_t, 26> opcodes = {
      OP_NOP, OP_RTAG, OP_WTAG, OP_CHECK, OP_CARRY, OP_ADD, OP_SUB,
      OP_MULH, OP_MUL, OP_ASH, OP_LSH, OP_ROT, OP_AND, OP_OR, OP_XOR,
      OP_FFB, OP_NOT, OP_NEG, OP_LT, OP_LE, OP_GE, OP_GT, OP_EQUAL,
      OP_NEQUAL, OP_EQ, OP_NEQ};

  sim.top.reset = 1;
  sim.top.run_enable = 0;
  sim.top.external_interrupt = 0;
  sim.top.dram_error_inject = 0;
  sim.cycle();
  sim.golden.reset();
  for (uint8_t fault = 1; fault <= FAULT_TYPE; ++fault) {
    const uint32_t handler = handler_base + uint32_t(fault) * 2;
    sim.write(0, 0x40 + fault,
              instruction_pointer(true, true, handler, false, true));
    sim.insn(0, handler, instruction(OP_BR, 3, 0, op_imm5(-1)));
  }

  for (const uint8_t opcode : opcodes) {
    for (uint8_t left_tag = 0; left_tag < 16; ++left_tag) {
      for (uint8_t right_tag = 0; right_tag < 16; ++right_tag) {
        sim.top.reset = 1;
        sim.top.run_enable = 0;
        sim.cycle();
        sim.golden.reset();
        sim.write(0, result_address, sentinel);
        sim.write(0, operand_address, word(left_tag, 1));
        sim.write(0, operand_address + 1, word(right_tag, 2));

        uint32_t pc = 0x1000;
        sim.write(0, pc++, address(false, false, result_address, 1));
        sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                      regop(false, false, 0x05)));
        sim.write(0, pc++, address(false, false, operand_address, 2));
        sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                      regop(false, false, 0x06)));
        sim.insn(0, pc++, instruction(OP_READ, 1, 0, op_mem_i(0, 2)));
        sim.insn(0, pc++, instruction(OP_READ, 3, 0, op_mem_i(1, 2)));
        sim.write(0, pc++, boolean(false));
        sim.insn(0, pc++, instruction(OP_WRITER, 0, 0,
                                      regop(false, false, 0x1c)));
        sim.insn(0, pc++, instruction(opcode, 2, 1, op_r(3)));
        sim.insn(0, pc++, instruction(OP_WRITE, 0, 2, op_mem_i(0, 1)));
        sim.insn(0, pc, instruction(OP_BR, 3, 0, op_imm5(-1)));

        sim.golden.run(96);
        const auto golden_view = sim.golden.view(0);
        const uint8_t golden_fault = golden_view.lastFault;
        const uint64_t golden_value
            = sim.golden.readMemory(0, result_address);

        sim.top.reset = 0;
        sim.top.run_enable = 1;
        for (unsigned cycle = 0; cycle < 192; ++cycle) sim.cycle();
        sim.top.run_enable = 0;
        sim.top.eval();
        const uint8_t rtl_fault = sim.top.node0_last_fault;
        const uint64_t rtl_value = sim.read(0, result_address);

        if (sim.top.node0_catastrophe != golden_view.catastrophe) {
          fail_matrix(opcode, left_tag, right_tag, "catastrophe mismatch",
                      rtl_value, golden_value, rtl_fault, golden_fault);
        }
        if (rtl_fault != golden_fault) {
          fail_matrix(opcode, left_tag, right_tag, "fault precedence mismatch",
                      rtl_value, golden_value, rtl_fault, golden_fault);
        }
        if (rtl_value != golden_value) {
          fail_matrix(opcode, left_tag, right_tag, "result mismatch",
                      rtl_value, golden_value, rtl_fault, golden_fault);
        }
      }
    }
  }
}
}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Simulator sim;
  sim.top.reset = 1;
  sim.top.run_enable = 0;
  sim.top.external_interrupt = 0;
  sim.top.dram_error_inject = 0;
  sim.top.dram_error_address = 0;
  sim.top.debug_write = 0;
  sim.cycle();
  sim.golden.reset();
  load_programs(sim);

  bool golden_completed = false;
  for (unsigned event = 0; event < 5000; ++event) {
    if (!sim.golden.step()) break;
    const auto node1 = sim.golden.view(1);
    if (sim.golden.readMemory(1, 0x402) == integer(42)
        && !node1.queuePending[0] && !node1.queuePending[1]) {
      golden_completed = true;
      break;
    }
  }
  if (!golden_completed) fail_golden(sim, "message program did not complete");
  if (sim.golden.readMemory(0, 0x400) != integer(12))
    fail_golden(sim, "checked ADD/WRITE mismatch");
  if (sim.golden.readMemory(0, 0x401) != address(true, false, 0x500, 8))
    fail_golden(sim, "ENTER/XLATE mismatch");
  if (sim.golden.readMemory(1, 0x402) != integer(42))
    fail_golden(sim, "message argument mismatch");

  sim.top.reset = 0;
  sim.top.run_enable = 1;

  bool completed = false;
  for (unsigned cycle = 0; cycle < 5000; ++cycle) {
    sim.cycle();
    if (sim.read(1, 0x402) == integer(42)
        && sim.top.node1_queue_pending == 0) {
      completed = true;
      break;
    }
  }
  sim.top.run_enable = 0;
  sim.top.eval();

  if (!completed) fail(sim, "timeout waiting for routed message and SUSPEND");
  if (sim.read(0, 0x400) != integer(12)) fail(sim, "checked ADD/WRITE mismatch");
  if (sim.read(0, 0x401) != address(true, false, 0x500, 8))
    fail(sim, "ENTER/XLATE mismatch");
  if (sim.read(1, 0x402) != integer(42)) fail(sim, "message argument mismatch");
  if (sim.top.node0_catastrophe || sim.top.node1_catastrophe)
    fail(sim, "catastrophe asserted");
  if (sim.top.node0_number != 0 || sim.top.node1_number != 1)
    fail(sim, "NNR initialization mismatch");
  if (sim.read(0, 0x400) != sim.golden.readMemory(0, 0x400)
      || sim.read(0, 0x401) != sim.golden.readMemory(0, 0x401)
      || sim.read(1, 0x402) != sim.golden.readMemory(1, 0x402)) {
    fail(sim, "RTL/golden architectural memory mismatch");
  }
  const auto golden_node0 = sim.golden.view(0);
  const auto golden_node1 = sim.golden.view(1);
  if (sim.top.node0_number != golden_node0.nodeNumber
      || sim.top.node1_number != golden_node1.nodeNumber) {
    fail(sim, "RTL/golden NNR mismatch");
  }
  const auto packed_flags = [](const std::array<bool, 2>& flags) {
    return unsigned(flags[0]) | (unsigned(flags[1]) << 1);
  };
  if (sim.top.node0_ip != golden_node0.ip
      || sim.top.node1_ip != golden_node1.ip
      || sim.top.node0_r0 != golden_node0.registers[0]
      || sim.top.node1_r0 != golden_node1.registers[0]) {
    fail(sim, "RTL/golden current-context register mismatch");
  }
  if (sim.top.node0_background != golden_node0.background
      || sim.top.node1_background != golden_node1.background
      || sim.top.node0_priority != golden_node0.priority
      || sim.top.node1_priority != golden_node1.priority
      || sim.top.node0_interrupt_mask != golden_node0.interruptMask
      || sim.top.node1_interrupt_mask != golden_node1.interruptMask
      || sim.top.node0_fault_mode != golden_node0.faultMode
      || sim.top.node1_fault_mode != golden_node1.faultMode
      || sim.top.node0_unchecked_mode != golden_node0.unchecked
      || sim.top.node1_unchecked_mode != golden_node1.unchecked) {
    fail(sim, "RTL/golden current-context flag mismatch");
  }
  if (sim.top.node0_queue_pending != packed_flags(golden_node0.queuePending)
      || sim.top.node1_queue_pending != packed_flags(golden_node1.queuePending)
      || sim.top.node0_queue_full != packed_flags(golden_node0.queueFull)
      || sim.top.node1_queue_full != packed_flags(golden_node1.queueFull)) {
    fail(sim, "RTL/golden queue-status mismatch");
  }

  sim.top.reset = 1;
  sim.cycle();
  sim.top.run_enable = 0;
  sim.golden.reset();
  load_type_fault_program(sim);

  bool golden_fault_dispatched = false;
  for (unsigned event = 0; event < 1000; ++event) {
    if (!sim.golden.step()) break;
    if (sim.golden.view(0).lastFault == FAULT_TYPE) {
      golden_fault_dispatched = true;
      break;
    }
  }
  if (!golden_fault_dispatched)
    fail_golden(sim, "checked tag mismatch did not raise TYPE fault");
  if (sim.golden.view(0).catastrophe)
    fail_golden(sim, "TYPE fault did not vector cleanly");

  sim.top.reset = 0;
  sim.top.run_enable = 1;
  bool fault_dispatched = false;
  for (unsigned cycle = 0; cycle < 1000; ++cycle) {
    sim.cycle();
    if (sim.top.node0_last_fault == FAULT_TYPE) {
      fault_dispatched = true;
      break;
    }
  }
  sim.top.run_enable = 0;
  sim.top.eval();
  if (!fault_dispatched) fail(sim, "checked tag mismatch did not raise TYPE fault");
  if (sim.top.node0_catastrophe) fail(sim, "TYPE fault did not vector cleanly");
  if (sim.top.node0_last_fault != sim.golden.view(0).lastFault)
    fail(sim, "RTL/golden TYPE fault mismatch");

  constexpr uint32_t interrupt_record = 0x3200;
  sim.top.reset = 1;
  sim.top.run_enable = 0;
  sim.top.external_interrupt = 0;
  sim.top.dram_error_inject = 0;
  sim.cycle();
  sim.golden.reset();
  const uint64_t interrupt_fip
      = load_interrupt_fault_program(sim, interrupt_record);
  sim.top.external_interrupt = 1;
  sim.golden.setExternalInterrupt(0, true);

  bool golden_interrupt_dispatched = false;
  for (unsigned event = 0; event < 1000; ++event) {
    if (!sim.golden.step()) break;
    const auto view = sim.golden.view(0);
    if (view.lastFault == FAULT_INTERRUPT && view.faultMode
        && sim.golden.readMemory(0, interrupt_record) == interrupt_fip) {
      golden_interrupt_dispatched = true;
      break;
    }
  }
  if (!golden_interrupt_dispatched)
    fail_golden(sim, "external interrupt did not record its continuation");
  if (sim.golden.view(0).contexts[2].faultIp != interrupt_fip)
    fail_golden(sim, "external interrupt FIP mismatch");

  sim.top.reset = 0;
  sim.top.run_enable = 1;
  bool interrupt_dispatched = false;
  for (unsigned cycle = 0; cycle < 1000; ++cycle) {
    sim.cycle();
    if (sim.top.node0_last_fault == FAULT_INTERRUPT
        && sim.top.node0_fault_mode
        && sim.read(0, interrupt_record) == interrupt_fip) {
      interrupt_dispatched = true;
      break;
    }
  }
  sim.top.run_enable = 0;
  sim.top.external_interrupt = 0;
  sim.top.eval();
  if (!interrupt_dispatched)
    fail(sim, "external interrupt did not record its continuation");
  if (sim.top.node0_catastrophe)
    fail(sim, "external interrupt did not vector cleanly");
  if (sim.read(0, interrupt_record)
      != sim.golden.readMemory(0, interrupt_record)) {
    fail(sim, "RTL/golden external-interrupt FIP mismatch");
  }

  constexpr uint32_t dram_fault_address = 0x3000;
  constexpr uint32_t dram_record = 0x3210;
  sim.top.reset = 1;
  sim.top.run_enable = 0;
  sim.top.dram_error_inject = 0;
  sim.cycle();
  sim.golden.setExternalInterrupt(0, false);
  sim.golden.reset();
  const uint64_t dram_fip
      = load_dram_fault_program(sim, dram_fault_address, dram_record);
  sim.top.dram_error_address = dram_fault_address;
  sim.top.dram_error_inject = 1;
  sim.golden.setDramError(0, true, dram_fault_address);

  bool golden_dram_dispatched = false;
  for (unsigned event = 0; event < 1000; ++event) {
    if (!sim.golden.step()) break;
    const auto view = sim.golden.view(0);
    if (view.lastFault == FAULT_DRAMERR && view.faultMode
        && sim.golden.readMemory(0, dram_record)
            == integer(dram_fault_address)
        && sim.golden.readMemory(0, dram_record + 1) == dram_fip) {
      golden_dram_dispatched = true;
      break;
    }
  }
  if (!golden_dram_dispatched)
    fail_golden(sim, "DRAM error did not record MAR and FIP");
  if (sim.golden.view(0).contexts[2].faultIp != dram_fip)
    fail_golden(sim, "DRAM error FIP mismatch");

  sim.top.reset = 0;
  sim.top.run_enable = 1;
  bool dram_dispatched = false;
  for (unsigned cycle = 0; cycle < 2000; ++cycle) {
    sim.cycle();
    if (sim.top.node0_last_fault == FAULT_DRAMERR
        && sim.top.node0_fault_mode
        && sim.read(0, dram_record) == integer(dram_fault_address)
        && sim.read(0, dram_record + 1) == dram_fip) {
      dram_dispatched = true;
      break;
    }
  }
  sim.top.run_enable = 0;
  sim.top.dram_error_inject = 0;
  sim.top.eval();
  if (!dram_dispatched) fail(sim, "DRAM error did not record MAR and FIP");
  if (sim.top.node0_catastrophe) fail(sim, "DRAM error did not vector cleanly");
  if (sim.read(0, dram_record) != sim.golden.readMemory(0, dram_record)
      || sim.read(0, dram_record + 1)
          != sim.golden.readMemory(0, dram_record + 1)) {
    fail(sim, "RTL/golden DRAM-error state mismatch");
  }

  constexpr uint32_t queue_record = 0x3220;
  reset_fixture(sim);
  const uint64_t queue_fip = load_queue_fault_program(sim, queue_record);

  bool golden_queue_dispatched = false;
  for (unsigned event = 0; event < 2000; ++event) {
    if (!sim.golden.step()) break;
    const auto view = sim.golden.view(0);
    if (view.lastFault == FAULT_QUEUE && view.faultMode
        && view.queueFull[0]
        && sim.golden.readMemory(0, queue_record) == queue_fip) {
      golden_queue_dispatched = true;
      break;
    }
  }
  if (!golden_queue_dispatched)
    fail_golden(sim, "full active queue did not record its pre-fetch continuation");
  if (sim.golden.view(0).contexts[0].faultIp != queue_fip)
    fail_golden(sim, "QUEUE fault FIP mismatch");

  sim.top.reset = 0;
  sim.top.run_enable = 1;
  bool queue_dispatched = false;
  for (unsigned cycle = 0; cycle < 4000; ++cycle) {
    sim.cycle();
    if (sim.top.node0_last_fault == FAULT_QUEUE
        && sim.top.node0_fault_mode
        && (sim.top.node0_queue_full & 1u) != 0
        && sim.read(0, queue_record) == queue_fip) {
      queue_dispatched = true;
      break;
    }
  }
  sim.top.run_enable = 0;
  sim.top.eval();
  if (!queue_dispatched)
    fail(sim, "full active queue did not record its pre-fetch continuation");
  if (sim.top.node0_catastrophe)
    fail(sim, "QUEUE fault did not vector cleanly");
  if (sim.read(0, queue_record)
      != sim.golden.readMemory(0, queue_record)) {
    fail(sim, "RTL/golden QUEUE-fault FIP mismatch");
  }

  run_translation_and_invalidation_fixture(sim);
  run_ip_control_fixture(sim);
  run_branch_fixtures(sim);
  run_checked_alu_tag_matrix(sim);

  std::cout << "PASS: independent C++ golden/RTL differential; MDP v11 "
               "encoding, 6,656-case checked ALU/tag matrix, "
               "TYPE/INTERRUPT/QUEUE/DRAMERR vectors, "
               "two-way ENTER/XLATE/PROBE/INVAL, LDIP/LDIPR/CALL, "
               "all branch outcomes, J-network routing, priority dispatch, "
               "queue wrap, and SUSPEND\n";
  return 0;
}
