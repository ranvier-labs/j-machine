# J-Machine development environment

The static workbench combines a tiling window manager, a browser-persistent
filesystem, a Monaco editor, a Message-Driven C language server, and a debugger
for the Verilated RTL. The monochrome desktop, editor modelines, command
listener, and pathname-based workflow take inspiration from early Lisp
machines. Amber identifies focus, breakpoints, and changed state.

`compiler.wasm` runs the Lean compiler. The simulator variants run the sparse
SystemVerilog targets for 2, 4, 16, and 512 physical nodes. The 512-node example
uses the full `8x8x8` mesh and returns 539 from a remote array sum on node 511.
Image transfer uses `*` broadcast records for common code, keeping the text
compact while loading the same 1,097,216 machine words on the 512-node example.

## Build and preview

Prerequisites: Verilator 5, Emscripten, Node.js 20 or newer and npm, Python 3,
WABT, wasi-sdk, and a built Lean checkout with the experimental Wasm backend.
The browser must support WebAssembly exception tags and tail calls.

From the repository root:

```sh
export WASI_SDK_PATH=/path/to/wasi-sdk
bazel run //web:build
bazel run //web:serve
```

Open <http://localhost:8000>, or load the large example directly at
<http://localhost:8000/?example=mesh512.c>. The build writes `web/dist/`, which any static
host can serve with `.wasm` files typed as `application/wasm`. Refresh an
existing browser tab after rebuilding to load its new language worker and
compiler. `?file=/home/user/main.c` visits a filesystem path. The earlier
`?example=mesh512.c` URLs still work. `?help=build` opens the integrated
manual at Project builds; section links such as `?help=build%23graph-syntax`
open an individual heading.

The build installs pinned frontend dependencies with `npm ci`. For frontend
iteration after the engines are built, use `npm --prefix web run build`.
`NODE=/path/to/node` selects the Node executable for the shell scripts; they
fall back to `/opt/homebrew/bin/node` if the default is too old.

## Lean toolchain repair

`LEAN_WASM_ROOT` defaults to `web/build/lean4-wasm`. The working toolchain is
based on `feat/wasm-backend` commit `d4b9e8f6b3b2005159e2af26c4e957cf16aab151`.
`compiler/lean-wasm-backend.patch` preserves the backend fixes required by
this workbench: erased closure argument slots, persistent closed constants,
and correct sharing checks for those constants. Apply it once when preparing
that toolchain revision, then rebuild stage 1:

```sh
git -C web/build/lean4-wasm apply "$PWD/web/compiler/lean-wasm-backend.patch"
CCACHE_READONLY=true make -j8 -C web/build/lean4-wasm/build/release/stage1
```

The patch is already applied in the current local worktree. It changes the
Lean backend itself; the C example needs no workaround. `EmitBrowser.lean`
enables whole-program emission and Wasm tail calls. The compiler build
validates and compiles all bundled examples before replacing the preview's
compiler, so a failed rebuild retains the previous artifact.

## Network debugging and graphical output

The Routing Geometry, Packets, Waiting, Causal History, and Graphical Display
windows share the debugger's live observations. Use **M-x → Layout: network**
or **Layout: graphics**. [Network debugging and graphical output](docs/network-debugging.md)
documents packet filters, network breakpoints, trace archives, complete keyboard
navigation, keymaps, the framebuffer convention, and four graphical examples.
`/home/user/build-graphics.jm` builds the examples without changing the existing
project graph. Example updates preserve editable workspace copies.

## Desktop and filesystem

The header is one compact toolbar with all controls visible. **Buffer →
Compile** compiles and loads the current C file with the adjacent node count.
**Project**, target, **Build**, **Load**, **Edit graph**, and **Targets** expose
project builds. File actions, **Run**, Windows, Layout, Help, and M-x remain
directly accessible. Run/Pause is one toggle in each execution toolbar.
Controls wrap together on narrower screens. The Build and Debugger windows
show project and machine status.

Each tool is an independent window. Drag its title bar onto the edge of
another window to move it. Drag the dividers to resize; focused dividers also
accept arrow keys, with Home restoring an even split. The title-bar arrows
choose a tool to split beside or below the current window. Double-click a
title or use its square button to zoom and restore. Closing a window retains
its buffers and machine state; **Windows** reopens it. **Layout** supplies
development, editing, debugging, building, network, graphics, and documentation arrangements. A new development layout includes the Build window. Split positions and visible
windows survive reloads.

**M-x** (Alt+X or Cmd/Ctrl+Shift+P) searches commands and pathnames.
Unavailable actions show the same reason as their toolbar buttons. **Windows**
groups tools by purpose; **Layout** contains presets and window arrangement,
focus, and resize actions. Choosers identify their action as Open, Load, Read,
or Apply, with F1 help for the selection.
Ctrl+Alt+Arrows focus neighboring windows; Ctrl+Alt+N/P cycles windows; Ctrl+Alt+Enter zooms the focused window.
The Files window, editor tabs, and **Open** (Cmd/Ctrl+O) visit buffers.
Each buffer retains its own undo history and cursor position while open.

The filesystem provides three locations:

| Path | Contents |
| --- | --- |
| `/home/user` | Writable files and project directories |
| `/examples` | Bundled, read-only programs; Copy or Save as creates an editable file |
| `/build` | Generated images with tagged words and source maps |

Edits retain a recoverable draft in browser storage. **Save** (Cmd/Ctrl+S)
commits that draft and retains the previous five saved versions. **Versions**
recovers a saved version into a new file. **Save as** (Cmd/Ctrl+Shift+S) writes
to a new pathname. Files and directories can be copied, moved, or renamed;
Trash is recoverable and Restore refuses to overwrite existing paths.
Buffers from the earlier console migrate into `/home/user` on first use.

**Import** reads local files into the selected directory. **Export** downloads
the selected file; with a directory selected, it downloads a JSON snapshot of
the filesystem, including drafts, versions, and trash. These files live in
this browser's storage for this site, rather than the host repository. Export
provides a separate copy before clearing site data or changing browser profiles.
An outdated tab refuses to overwrite filesystem changes committed by another
tab. The earlier filesystem and layout stores are imported into separate,
versioned stores so tabs running older code cannot replace the new workspace.
Export includes pending edits even if browser storage is full.

The Listener accepts filesystem and machine commands. It has command history
on Up/Down, resolves relative pathnames against its current directory, and
supports quoted names. For example:

```text
mkdir project
cp /examples/remote_call.c project/main.c
cd project
edit main.c
compile
run
inspect 1
window trace
tile debugging
```

`help` lists commands with selectable manual topics. `help topic` or `doc topic`
opens a page; `doc search words` searches the manual. The listener operates on the virtual filesystem
and simulator; it does not execute host shell commands.

Listener output contains mouse-selectable presentations. Click a pathname to
visit it, a source location to jump to that line, a node to inspect it, or a
build target to open its Build window entry. Shift-click inserts the selected
value into the listener, quoting pathnames with spaces. Clicking an earlier
command recalls it for editing; Return executes it. Alt+Up selects the latest presented value from the prompt. Arrow keys navigate
presentations, Return visits, Shift+Return inserts, and Escape returns to the
prompt.

## Project builds

`build.jm` describes a small dependency graph with Ninja-style statements.
The starter file in `/home/user` defines the main and 512-node images and an
`all` group. The always-visible **Project** controls select the graph and target;
**Defaults** follows the graph's default statement. **Build** (Cmd/Ctrl+B)
opens the Build window and builds that selection. **Load** installs its image;
for a group containing several images, a chooser identifies which one to load.
**Run** (F5) executes the loaded image.

**Targets** opens the Build window's dependency inputs, definitions, per-target
actions, and build reasons. **Edit graph** visits the selected `.jm` file, and
**Guide** opens its manual page. `use-build path` selects a graph from the
listener; `build [target]` and `load path.image` operate on it. An argument-free
`build` uses the target selected in Project, or the graph defaults.
The selected graph and target persist across reloads. Opening a `.jm` buffer
visits it; **Use graph** beside its pathname activates it as the project.

```text
# Paths are relative to this build file. Quote pathnames containing spaces.
build staged.c: copy main.c
build out/main.image: jmc staged.c
  nodes = 2
build all: phony out/main.image
default all
```

The built-in rules are `jmc` (one complete C program to an image), `copy` (one
file to another), and `phony` (a group of dependencies). The `nodes` option
accepts 2, 4, 16, or 512. Comments occupy their own line. There are no arbitrary
shell commands, user-defined rules, or multi-file linking in this first build
language.

Builds traverse dependencies before their targets and create output directories
as needed. Missing inputs, duplicate targets, cycles, and output paths that
would replace user files are errors. Inputs include current editor drafts.
Content hashes, rule options, output contents, and the compiler's SHA-256
identity determine whether an action can be skipped. Build records persist
with the generated files, so unchanged targets also skip after a reload.
Failures retain previously successful outputs; an input or graph edit during
compilation rejects the stale result. The listener shows each target's build
reason and provides a clickable source location on errors.

Building produces files. **Load** installs a built image into the simulator,
and **Run** executes it. Loading retains the active editor buffer and records
the artifact's source and upstream dependencies. Changes to those inputs mark
the loaded machine stale until it is rebuilt and loaded again.

## Editing and debugging

The language server supplies compiler diagnostics, completion, hover,
definition, references, and document symbols. Diagnostics come from the
actual Lean compiler. Navigation and completion use a lexical scope index;
they do not yet provide full C type analysis. The same LSP 3.17 server can
run over stdio with `npm --prefix web run lsp`, using Content-Length framing.

**Buffer → Compile & Load** (`Cmd/Ctrl+Enter`) compiles the active C buffer and resets
the image. Each example is a complete program; project directories organize
files, but compilation does not yet link several source files together.
Switching buffers leaves the loaded program intact. The debugger identifies
its source pathname and node count, and a source stop visits the corresponding
buffer. Editing that program makes its image stale and disables execution
until it is compiled again, or rebuilt and loaded. The Buffer node selector sets
the next single-file compilation's topology. Project targets use their graph's
`nodes` settings; the Debugger shows the loaded topology.

Buffer images use `/build/buffers/<full source pathname>.<nodes>.image`,
separate from project targets. Project Load verifies the graph, recipe,
input contents, and output hash. A failed Compile & Load retains the old machine
for inspection and disables execution until a successful compile or explicit load.

F5 continues, Pause stops
clocking the whole mesh, F10 waits for an instruction to retire on the
selected node, and F11 advances to a different source line on that node.
Cycle and +100 clock the requested number of cycles unless a stop condition
occurs. Each run defaults to a 10,000,000-cycle budget, adjustable in the debugger;
Continue resumes longer programs.
Pause remains available during long runs.
The toggle reads Run at cycle zero, Continue after stopping, and Pause while
running. Continue is disabled when main returns. **Restart** (Shift+F5) resets
and runs the loaded image; **Reset** reloads it without advancing clocks.
Explicit stepping remains available for hardware inspection after main returns.

Click the editor gutter or press F9 for a source breakpoint. Address
breakpoints use a hexadecimal instruction word address. Memory watches stop
when a word changes. The inspector shows all four data and four address
registers, the tagged IP, node state, and the main-result mailbox at `0x300`.
Handled faults are optional stops because futures use them during normal
execution. Catastrophes always stop execution.

Source maps are image comments enabled by `CompilerOptions.sourceMap`; they
do not change executable words. Snapshot ABI 2 exposes registers and the
RTL fetch boundary. A breakpoint stops before instruction issue: the core's
IP alone advances before retirement and cannot establish that boundary.
Pausing stops simulation clocks; it does not gate only processor execution
while allowing routers or memory to continue. Reading state never clocks
the machine. These facilities are simulator observations, not a hardware
JTAG or scan interface.

## Integrated documentation

**Help** or **F1** opens documentation for the current control or tool. **Windows →
DOCUMENTATION** reopens the reader, and **Layout → documentation** places it
beside the editor and listener. The bundled manual covers builds, files, the
listener, keyboard control, debugging, routing, packets, futures, archives,
graphical output, and example programs.

Topics link to other pages and headings, source files, and registered IDE
actions. Listener command examples have Insert buttons that recall a command
at the prompt without executing it. Back/Forward preserve reading positions;
Home returns to the index. Search matches page titles and contents.

Tab and Enter follow links; Up/Down navigates the topic list. With Documentation
focused, Cmd/Ctrl+F searches and Alt+Left/Right traverses history. Escape from
search returns to the page. M-x offers documentation topics and Monaco's
**Editor commands**, whose usual F1 shortcut now opens contextual help.

## Verification

After building the engines:

```sh
bazel run //web:test
bazel test //compiler:jmc_test //sim:rtl_conformance_test --test_output=errors
```

The web checks cover the minimal array-initializer regression, compiler
memory use, LSP framing and recovery, source and instruction stepping,
breakpoints, watches, pause, topology validation, all four simulator variants,
and execution of every bundled example. To select an example for the last
execution check, pass `-- mesh512.c` to `bazel run //web:test`.

The filesystem and tiling checks cover drafts, saved revisions, migration,
rename, trash recovery, storage failure, and layout restoration. IDE controller
tests use the real compiler and RTL simulator to check buffer switching,
source breakpoint ownership, stale compilation, and listener file operations.

Build checks cover dependency ordering, incremental and persistent caching,
compiler changes, stale inputs, failed compilation, and runnable artifacts.
Presentation checks cover exact path and node values, command recall, and
insertion without execution.

`npm --prefix web test` runs compiler/LSP/debugger/workspace/build, network,
keyboard, and graphical-output checks.
`npm --prefix web run test:examples -- mesh512.c` runs just the full 512-node
compile-and-execute regression. These engine tests run under Node; they do
not substitute for checking browser interaction and layout.

## UI modules

`site/shell/layout.js` models binary splits, and `window-manager.js` owns
window frames, docking, resizing, focus, zoom, and layout persistence. A window
registers an `id`, `title`, DOM `element`, and optional `onFocus`, `onResize`,
and `onHide` hooks. The shell imports no editor, filesystem, or simulator code.

`site/core/filesystem.js` owns filesystem transactions and persistence.
`site/core/build.js` parses build files, orders targets, and caches built-in
actions; its compiler is an injected function. `site/core/presentations.js`
retains typed values for listener selections. `site/core/ide.js` coordinates
buffers, compilation, builds, and debugger sessions;
it has no dependency on the window manager or Monaco. The tools under
`site/windows/` render that state. `site/app.js` registers the tools and supplies
desktop commands and layout presets. The standalone debugger controller and
Wasm runtime remain below those layers.
