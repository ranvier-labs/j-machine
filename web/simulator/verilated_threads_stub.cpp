#include "verilated_threads.h"

VlThreadPool::VlThreadPool(VerilatedContext*, unsigned) {}

VlThreadPool::~VlThreadPool() = default;

#ifdef __EMSCRIPTEN__
#include <cstddef>
#include <pthread.h>

// Verilator probes host CPU affinity even in a single-threaded Wasm build.
// Emscripten declares this Linux compatibility function but does not define it.
int pthread_getaffinity_np(pthread_t, size_t, struct cpu_set_t*) { return 0; }
#endif
