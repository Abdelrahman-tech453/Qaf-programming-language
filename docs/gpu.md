# GPU support roadmap

Qaf is a small, dependency-free language with first-class floats and a JIT
that already emits native x86-64 code. This document is the design and
implementation plan for GPU-accelerated compute.

## Why this is the right foundation

* **Floats are first-class** — 64-bit IEEE-754 doubles with the full set of
  conversion builtins. GPU kernels mostly want floats.
* **Numbers live in mutable lists** — `list()` + `push` + `len` + indexing
  already give us growable buffers the exact same shape a host-side compute
  buffer wants.
* **The JIT already `call`s arbitrary addresses.** Compiling a function calls
  runtime helper addresses directly. Calling *any* address — including one
  handed to us by `dlsym` — is the same mechanism. The hard part is getting
  to `dlsym` at all (see below).
* **No libc, no dynamic loader.** `qafc` is a static, pure-syscall binary, so
  `dlopen`/`dlsym` are not simply linkable. We must link a shared object
  ourselves.

## API comparison

| | OpenCL | Vulkan (compute) | OpenGL / ES 3.1 (compute shaders) |
|---|---|---|---|
| Purpose | Compute-only, headless | Full graphics + compute | Graphics, with compute shaders |
| Kernel format | C-like source, **compiled by the driver at runtime** | precompiled **SPIR-V** | GLSL source (similar to OpenCL style) |
| Boilerplate | ~12 calls to run a kernel | hundreds of calls, queues, command buffers, descriptor sets | moderate; needs a (headless EGL) context |
| Vendor availability on Linux | NVIDIA/AMD/Intel — the widest | excellent | excellent |
| Fit for an interpreter | **excellent**: kernel is a `str` | poor: strings must ship through an SPIR-V compiler we'd have to bundle | good |
| Maturity of model | exactly what we want (buffers + N-dim grid) | powerful but deep | fine as fallback |

**Decision: OpenCL first.** A kernel is a plain string handed to
`clBuildProgram` — the vendor's driver compiles it. That maps perfectly onto a
language whose programs are already text. Vulkan is the long-term path for
raw performance; OpenGL compute is the fallback.

## Phases

### Phase 1 — a minimal dynamic loader (`src/dl.s`, ~700 lines)

Give `qafc` the ability to resolve symbols in shared objects without libc:

1. **Builtin `dlopen(path)`** — open the `.so`, parse its ELF header.
2. Load and map its program segments (syscall `mmap`).
3. Process declared dependencies (`DT_NEEDED`) recursively — `libOpenCL.so.1`
   needs `libc`, `libdl`, `libm`; libc needs `ld-linux` and `libpthread`.
4. Apply relocations:
   - `R_X86_64_GLOB_DAT`, `R_X86_64_JUMP_SLOT`, `R_X86_64_64` (absolute),
     `R_X86_64_RELATIVE`, `R_X86_64_TLS*` (PC-relative handling as needed)
   - resolve symbols through `DT_HASH`/`DT_GNU_HASH` with the standard
     interposition order (own → deps).
5. Run `DT_INIT`/`DT_INIT_ARRAY` (constructors) — required for real drivers.
6. **Builtin `dlsym(handle, name)`** → returns the function's address as an
   int (the tag representation already stores raw values; a pointer is just an
   integer).

Because the JIT already emits direct calls to runtime helpers, a resolved
`dlsym` address is no different: the JIT can emit `mov rax,<addr>; call rax`.

### Phase 2 — native call bridge

* **Builtin `call_native(addr, arg0, arg1, ...)`** — SysV x86-64 ABI:
  integer args in `rdi rsi rdx rcx r8 r9`, float args in `xmm0..7`, return in
  `rax`/`xmm0`. Marked types (string/list) are passed as their raw pointer so
  handle-based APIs (`cl_context`, `cl_mem`, …) work directly.
* **`addr_to_ptr` / `ptr_to_addr`** — the flip side for `clEnqueueReadBuffer`
  destinations and host pointers.
* Strings are already NUL-safe byte containers; a `str` can be handed to an
  API expecting `char*` with zero copy (strip the tag, pass `ptr`).

### Phase 3 — OpenCL host bindings written in Qaf (`lib/opencl.qf`)

`s3ocl` loads the driver once with `dlopen("libOpenCL.so.1")`, fetches the ~14
entry points with `dlsym`, and exposes a compact, Qaf-idiomatic API:

```qf
from opencl import *;

# pick the first device
ocl.pickDevice();                       # -> context + command queue

# upload float data
xs = list(1.0, 2.0, 3.0, 4.0);
a_buf = ocl.buf(xs);                    # cl_mem handle
b_buf = ocl.buf(4);                     # 4 floats of output space

kern = "
  __kernel void mul2(__global const float* a, __global float* b) {
    size_t i = get_global_id(0);
    b[i] = a[i] * 2.0f;
  }
";

ocl.run(kern, list(a_buf, b_buf), 4);   # clCreateProgram+Build+Kernel+NDRange
out = ocl.read_floats(b_buf, 4);        # clEnqueueReadBuffer -> Qaf list
print out;                              # [2, 4, 6, 8]
```

`ocl.run` expands internally to: `clCreateProgramWithSource`,
`clBuildProgram`, `clCreateKernel`, `clSetKernelArg` per buffer,
`clEnqueueNDRangeKernel`, `clFinish`.

### Phase 4 (roadmap) — Vulkan / OpenGL

* **Vulkan:** once `dl` works, load `libvulkan.so.1` and wrap the compute
  surface (instance → device → command pool → shader SPIR-V → descriptor set →
  one-shot compute). Requires shipping/bundling `glslangValidator` output, or
  a tiny offline SPIR-V converter, since kernels arrive as text.
* **OpenGL/EGL:** headless `EGL` compute context + GLSL compute shaders with
  `CL`-like packaging. Lower priority than Vulkan.

## Non-goals today

* No GPU calls until **Phase 1/2 land** (the loader + bridge) — everything
  GPU-specific is then pure Qaf in `lib/`.
* No automatic conversion of Qaf lists to GPU device memory — explicit
  `ocl.buf`/`ocl.read_*` calls, matching the model of the language.
* No multi-GPU scheduling; a single chosen device gets a single queue, as in
  the API sketch above.

## Progress

* [x] Floating-point core, conversion builtins, list buffers
* [x] JIT direct-call mechanism (address = the thing to call)
* [x] This design document + driver-entry decision (OpenCL)
* [ ] `src/dl.s`: ELF loader + relocations + `dlopen`/`dlsym` builtins
* [ ] `call_native` / pointer bridge builtins
* [ ] `lib/opencl.qf` OpenCL host API + `examples/mandelbrot.qf` or similar
* [ ] Optional: Vulkan compute, then GL compute fallback