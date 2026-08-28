#include "Vj_fpu_hardfloat.h"
#include "verilated.h"

extern "C" {
#include "softfloat.h"
}

#include <bit>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <limits>
#include <memory>
#include <random>
#include <sstream>
#include <string>

double sc_time_stamp() { return 0.0; }

namespace {

enum Operation : std::uint8_t {
  Add = 0,
  Sub = 1,
  Mul = 2,
  Fma = 3,
  Div = 4,
  Sqrt = 5,
  Compare = 6,
  I32ToFloat = 7,
  U32ToFloat = 8,
  FloatToI32 = 9,
  FloatToU32 = 10,
  F32ToF64 = 11,
  F64ToF32 = 12,
};

enum Format : std::uint8_t { Binary32 = 0, Binary64 = 1 };

struct Result {
  std::uint64_t bits;
  std::uint8_t flags;
  std::uint8_t compare;
};

[[noreturn]] void fail(const std::string& message) {
  std::cerr << "HARDFLOAT TEST FAIL: " << message << '\n';
  std::exit(1);
}

std::string hex(std::uint64_t value) {
  std::ostringstream out;
  out << "0x" << std::hex << value;
  return out.str();
}

class Fixture {
 public:
  Fixture() : dut_{std::make_unique<Vj_fpu_hardfloat>(&context_)} {
    dut_->clk = 0;
    dut_->reset = 1;
    dut_->request_valid = 0;
    dut_->response_ready = 0;
    for (int i = 0; i < 3; ++i) tick();
    dut_->reset = 0;
    tick();
  }

  Result run(Operation operation, Format format, std::uint64_t a,
             std::uint64_t b = 0, std::uint64_t c = 0,
             std::uint8_t rounding = 0) {
    dut_->request_operation = operation;
    dut_->request_format = format;
    dut_->request_rounding = rounding;
    dut_->request_tininess_after_rounding = 1;
    dut_->request_a = a;
    dut_->request_b = b;
    dut_->request_c = c;
    dut_->request_valid = 1;

    for (int cycles = 0; !dut_->request_ready; ++cycles) {
      if (cycles == 512) fail("request did not become ready");
      tick();
    }
    tick();
    dut_->request_valid = 0;

    for (int cycles = 0; !dut_->response_valid; ++cycles) {
      if (cycles == 512) fail("response did not become valid");
      tick();
    }
    const Result result{
        dut_->response_result,
        static_cast<std::uint8_t>(dut_->response_exception_flags),
        static_cast<std::uint8_t>(dut_->response_compare),
    };

    // The service contract retains every response field under backpressure.
    tick();
    if (!dut_->response_valid || dut_->response_result != result.bits ||
        dut_->response_exception_flags != result.flags ||
        dut_->response_compare != result.compare) {
      fail("response changed while response_ready was low");
    }
    dut_->response_ready = 1;
    tick();
    dut_->response_ready = 0;
    if (dut_->response_valid) fail("accepted response remained valid");
    return result;
  }

 private:
  void tick() {
    dut_->clk = 0;
    dut_->eval();
    context_.timeInc(1);
    dut_->clk = 1;
    dut_->eval();
    context_.timeInc(1);
  }

  VerilatedContext context_;
  std::unique_ptr<Vj_fpu_hardfloat> dut_;
};

void expectBits(const std::string& name, std::uint64_t expected,
                const Result& actual) {
  if (actual.bits != expected) {
    fail(name + " expected " + hex(expected) + ", got " + hex(actual.bits));
  }
}

void expectFlags(const std::string& name, std::uint8_t expected,
                 const Result& actual) {
  if (actual.flags != expected) {
    fail(name + " flags expected " + hex(expected) + ", got " +
         hex(actual.flags));
  }
}

std::uint32_t f32Bits(float value) {
  return std::bit_cast<std::uint32_t>(value);
}

std::uint64_t f64Bits(double value) {
  return std::bit_cast<std::uint64_t>(value);
}

void directedTests(Fixture& fixture) {
  Result result = fixture.run(Add, Binary32, f32Bits(1.5f), f32Bits(2.25f));
  expectBits("binary32 add", f32Bits(3.75f), result);
  expectFlags("binary32 add", 0, result);

  result = fixture.run(Sub, Binary64, f64Bits(7.0), f64Bits(2.5));
  expectBits("binary64 sub", f64Bits(4.5), result);
  expectFlags("binary64 sub", 0, result);

  result = fixture.run(Mul, Binary32, f32Bits(-3.0f), f32Bits(0.5f));
  expectBits("binary32 mul", f32Bits(-1.5f), result);
  expectFlags("binary32 mul", 0, result);

  result = fixture.run(Fma, Binary64, f64Bits(1.5), f64Bits(4.0), f64Bits(-1.0));
  expectBits("binary64 fma", f64Bits(5.0), result);
  expectFlags("binary64 fma", 0, result);

  result = fixture.run(Div, Binary32, f32Bits(7.0f), f32Bits(2.0f));
  expectBits("binary32 div", f32Bits(3.5f), result);
  expectFlags("binary32 div", 0, result);

  result = fixture.run(Sqrt, Binary64, f64Bits(81.0));
  expectBits("binary64 sqrt", f64Bits(9.0), result);
  expectFlags("binary64 sqrt", 0, result);

  result = fixture.run(Div, Binary64, f64Bits(1.0), f64Bits(0.0));
  expectBits("divide by zero", f64Bits(std::numeric_limits<double>::infinity()), result);
  expectFlags("divide by zero", 0b01000, result);

  result = fixture.run(Sqrt, Binary32, f32Bits(-1.0f));
  if ((result.bits & 0x7f800000u) != 0x7f800000u ||
      (result.bits & 0x007fffffu) == 0) {
    fail("sqrt(-1) did not produce a binary32 NaN");
  }
  expectFlags("sqrt invalid", 0b10000, result);

  result = fixture.run(Mul, Binary32, 0x7f7fffffu, f32Bits(2.0f));
  expectBits("binary32 overflow", 0x7f800000u, result);
  expectFlags("binary32 overflow", 0b00101, result);

  result = fixture.run(Compare, Binary64, f64Bits(-2.0), f64Bits(3.0));
  if (result.compare != 0b0001 || result.flags != 0) {
    fail("ordered comparison did not report less-than");
  }
  result = fixture.run(Compare, Binary32, 0x7fc00000u, f32Bits(3.0f));
  if (result.compare != 0b1000 || result.flags != 0) {
    fail("quiet-NaN comparison did not report unordered without invalid");
  }

  result = fixture.run(I32ToFloat, Binary32, 0x01000001u);
  expectBits("i32 to binary32", 0x4b800000u, result);
  expectFlags("i32 to binary32", 0b00001, result);

  result = fixture.run(U32ToFloat, Binary64, 0xffffffffu);
  expectBits("u32 to binary64", f64Bits(4294967295.0), result);
  expectFlags("u32 to binary64", 0, result);

  result = fixture.run(FloatToI32, Binary32, f32Bits(3.75f), 0, 0, 1);
  expectBits("binary32 to i32", 3, result);
  expectFlags("binary32 to i32", 0b00001, result);

  result = fixture.run(F32ToF64, Binary32, f32Bits(-6.25f));
  expectBits("binary32 to binary64", f64Bits(-6.25), result);
  expectFlags("binary32 to binary64", 0, result);

  result = fixture.run(F64ToF32, Binary64, f64Bits(1.0 / 10.0));
  expectBits("binary64 to binary32", f32Bits(static_cast<float>(1.0 / 10.0)), result);
  expectFlags("binary64 to binary32", 0b00001, result);
}

void randomizedRoundToNearestTests(Fixture& fixture) {
  std::mt19937_64 random{0x4a4d414348494e45ull};
  softfloat_roundingMode = softfloat_round_near_even;
  softfloat_detectTininess = softfloat_tininess_afterRounding;
  for (int index = 0; index < 1000; ++index) {
    std::uint32_t aBits = static_cast<std::uint32_t>(random());
    std::uint32_t bBits = static_cast<std::uint32_t>(random());
    std::uint32_t cBits = static_cast<std::uint32_t>(random());
    // Keep operands finite; subnormals and signed zero remain in the sample.
    aBits &= 0xfeffffffu;
    bBits &= 0xfeffffffu;
    cBits &= 0xfeffffffu;
    const float32_t a{aBits};
    const float32_t b{bBits};
    const float32_t c{cBits};
    for (Operation operation : {Add, Sub, Mul, Div, Fma}) {
      softfloat_exceptionFlags = 0;
      float32_t expected{0};
      if (operation == Add) expected = f32_add(a, b);
      if (operation == Sub) expected = f32_sub(a, b);
      if (operation == Mul) expected = f32_mul(a, b);
      if (operation == Div) expected = f32_div(a, b);
      if (operation == Fma) expected = f32_mulAdd(a, b, c);
      const std::uint8_t expectedFlags = softfloat_exceptionFlags;
      const Result result = fixture.run(operation, Binary32, aBits, bBits, cBits);
      const bool bothNaN = (expected.v & 0x7f800000u) == 0x7f800000u &&
          (expected.v & 0x007fffffu) != 0 &&
          (result.bits & 0x7f800000u) == 0x7f800000u &&
          (result.bits & 0x007fffffu) != 0;
      if (!bothNaN && result.bits != expected.v) {
        fail("random binary32 operation " + std::to_string(operation) +
             " mismatch at vector " + std::to_string(index));
      }
      if (result.flags != expectedFlags) {
        fail("random binary32 operation " + std::to_string(operation) +
             " flag mismatch at vector " + std::to_string(index));
      }
    }
    const std::uint32_t positiveBits = aBits & 0x7fffffffu;
    softfloat_exceptionFlags = 0;
    const float32_t expectedSqrt = f32_sqrt(float32_t{positiveBits});
    const std::uint8_t expectedSqrtFlags = softfloat_exceptionFlags;
    const Result sqrtResult = fixture.run(Sqrt, Binary32, positiveBits);
    if (sqrtResult.bits != expectedSqrt.v ||
        sqrtResult.flags != expectedSqrtFlags) {
      fail("random binary32 sqrt mismatch at vector " + std::to_string(index));
    }
  }

  for (int index = 0; index < 300; ++index) {
    std::uint64_t aBits = random() & 0xffdfffffffffffffull;
    std::uint64_t bBits = random() & 0xffdfffffffffffffull;
    std::uint64_t cBits = random() & 0xffdfffffffffffffull;
    const float64_t a{aBits};
    const float64_t b{bBits};
    const float64_t c{cBits};
    for (Operation operation : {Add, Sub, Mul, Div, Fma}) {
      softfloat_exceptionFlags = 0;
      float64_t expected{0};
      if (operation == Add) expected = f64_add(a, b);
      if (operation == Sub) expected = f64_sub(a, b);
      if (operation == Mul) expected = f64_mul(a, b);
      if (operation == Div) expected = f64_div(a, b);
      if (operation == Fma) expected = f64_mulAdd(a, b, c);
      const std::uint8_t expectedFlags = softfloat_exceptionFlags;
      const Result result = fixture.run(operation, Binary64, aBits, bBits, cBits);
      const bool bothNaN =
          (expected.v & 0x7ff0000000000000ull) == 0x7ff0000000000000ull &&
          (expected.v & 0x000fffffffffffffull) != 0 &&
          (result.bits & 0x7ff0000000000000ull) == 0x7ff0000000000000ull &&
          (result.bits & 0x000fffffffffffffull) != 0;
      if (!bothNaN && result.bits != expected.v) {
        fail("random binary64 operation " + std::to_string(operation) +
             " mismatch at vector " + std::to_string(index));
      }
      if (result.flags != expectedFlags) {
        fail("random binary64 operation " + std::to_string(operation) +
             " flag mismatch at vector " + std::to_string(index));
      }
    }
    const std::uint64_t positiveBits = aBits & 0x7fffffffffffffffull;
    softfloat_exceptionFlags = 0;
    const float64_t expectedSqrt = f64_sqrt(float64_t{positiveBits});
    const std::uint8_t expectedSqrtFlags = softfloat_exceptionFlags;
    const Result sqrtResult = fixture.run(Sqrt, Binary64, positiveBits);
    if (sqrtResult.bits != expectedSqrt.v ||
        sqrtResult.flags != expectedSqrtFlags) {
      fail("random binary64 sqrt mismatch at vector " + std::to_string(index));
    }
  }
}

}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Fixture fixture;
  directedTests(fixture);
  randomizedRoundToNearestTests(fixture);
  std::cout << "PASS: HardFloat binary32/binary64 service, conversions, "
               "exceptions, backpressure, and randomized IEEE results\n";
  return 0;
}
