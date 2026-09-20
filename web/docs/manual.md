# J-Machine workbench manual

Generated from `web/site/documentation/topics.js` by `npm run docs:render`. Edit the topics file, not this page.

- [J-Machine manual](#welcome): An index of the environment, language tools, and machine inspectors.
- [Quick start](#quick-start): Build, load, and run your first project target.
- [Project builds](#build): Select a graph and target, build dependencies, load an image, then run.
- [Windows and layouts](#workspace): Arrange independent tools without losing their state.
- [Files and drafts](#files): Browser-persistent paths, recoverable edits, versions, and exports.
- [Editing code](#editor): Buffers, compiler diagnostics, source navigation, and compilation.
- [The listener](#listener): A command prompt whose output contains selectable IDE objects.
- [The debugger](#debugger): Run, pause, step, inspect memory, and stop at source locations.
- [Routing geometry](#geometry): Physical coordinates, expected routes, observed hops, and blocked links.
- [Packet inspection](#packets): Filter messages and follow their payloads, routes, replies, and source.
- [Waiting and futures](#waiting): Queues, reservations, backpressure, and remote-result mailboxes.
- [Network breakpoints](#breakpoints): Stop on injection, delivery, link transfer, handler entry, or sustained stalls.
- [Causal history and archives](#history): Browse recorded events and save captures with their source snapshots.
- [Graphical display](#display): Render integer arrays as pixels, inspect them, and export PNG images.
- [Example programs](#examples): Programs that make remote execution, routing, and graphical output visible.
- [Keyboard reference](#keyboard): Global commands, window navigation, and tool-specific keys.
- [Tagged words](#words): 36-bit values, addresses, futures, and memory inspection.

<a id="welcome"></a>

## J-Machine manual

An index of the environment, language tools, and machine inspectors.
The workbench combines a tiled desktop, a persistent filesystem, a compiler, and a cycle-accurate RTL simulator. Documentation is another window: follow links with the mouse or Tab and Enter, and return with Back.


<a id="welcome-start-here"></a>

### Start here
- [Quick start](#quick-start): build an image and run it.
- [Project builds](#build): graphs, targets, incremental builds, and loading.
- [Example programs](#examples): remote calls, routing, and graphical output.
- [Keyboard control](#keyboard): operate the whole desktop from the keyboard.


<a id="welcome-the-environment"></a>

### The environment
- [Windows and layouts](#workspace), [files and drafts](#files), and [the editor](#editor).
- [The listener](#listener): commands and selectable objects.
- [The debugger](#debugger) and [tagged words](#words).


<a id="welcome-network-and-output"></a>

### Network and output
- [Routing geometry](#geometry) and [packet inspection](#packets).
- [Waiting and futures](#waiting), [breakpoints](#breakpoints), and [causal history](#history).
- [Graphical display](#display): turn program memory into pixels.


<a id="welcome-using-this-manual"></a>

### Using this manual
F1 opens help for the current control or window. Build and Load lead to the build guide; Buffer controls lead to the editor guide. In a chooser, F1 explains the selected action. Search matches titles and page contents. Alt+Left and Alt+Right traverse reading history; each page keeps its scroll position. Cmd/Ctrl+F focuses manual search. Home returns here.

Links to files open editor buffers. Links to tools open their windows. Listener examples offer Insert buttons that put a command at the prompt for you to review and execute. Reading a page never runs a program.

<a id="quick-start"></a>

## Quick start

Build, load, and run your first project target.

<a id="quick-start-a-project-in-four-steps"></a>

### A project in four steps
1. Open the Build window (IDE action `window-build`). Choose /home/user/build.jm and the /build/main.image target there; the window lists each target's inputs.
2. Choose Build, or press Cmd/Ctrl+B. The listener reports which targets were built or already up to date.
3. Choose Load. This installs the image into the RTL simulator.
4. Choose Run, or press F5. The same button becomes Pause while clocks are advancing.

The [debugger](#debugger) shows the loaded machine's node count, source, and stop reason. Edit main.c (`/home/user/main.c`) to change the program; build and load again to update its image.


<a id="quick-start-try-a-graphical-program"></a>

### Try a graphical program
Choose /home/user/build-graphics.jm in Project, select /build/mandelbrot.image, then Build and Load. Open the graphics layout (IDE action `layout-graphics`) and press F5. The four nodes compute tiles of the same picture.

[More examples](#examples) include cellular automata, a message hotspot, and a 512-node corner-coloring program. The full 512-node RTL model is much slower than the small meshes.


<a id="quick-start-compile-a-single-buffer"></a>

### Compile a single buffer
Open a C file, select the Buffer node count in the header, and choose the adjacent Compile & Load button or Cmd/Ctrl+Enter. This compiles and loads that buffer immediately. Run starts execution; Restart starts the loaded image again after it returns.

Project targets take their node counts from the build graph. The Buffer selector only controls single-buffer compilation. [Read about project builds](#build).

<a id="build"></a>

## Project builds

Select a graph and target, build dependencies, load an image, then run.
The Build window (IDE action `window-build`) selects the active graph and target and shows every output with its inputs, definition, build reason, and Load action. The header's Build and Load buttons act on that selection; their tooltips name it.

Opening a .jm file visits its buffer. Choose Use graph beside the editor pathname to make it the active project, or select it in the Build window. The graph and selected target survive reloads. Edit graph always visits the active project graph.


<a id="build-build-load-run"></a>

### Build, load, run
1. Choose a graph in the Build window. Edit graph visits its source.
2. Choose a target, or Defaults to use the graph's default statement.
3. Build (Cmd/Ctrl+B) produces files and reports progress in the Build window and listener.
4. Load installs a built image. If a group contains several images, choose one from the list.
5. Run (F5) executes the loaded image. F5 also pauses.

Building keeps the currently loaded machine in place. Source edits mark that machine stale; rebuild and load it before running again. Loading an image keeps the active editor buffer. Project Load accepts images from the selected graph and verifies their recipe, inputs, and output contents. Rebuild if these have changed.

Compile & Load stores single-buffer images under /build/buffers, using the complete source pathname and node count. That directory is reserved; project targets use other output paths. Buffers with the same filename cannot overwrite each other's images or a project output.

The starter build.jm (`/home/user/build.jm`) builds main.c and the 512-node example. build-graphics.jm (`/home/user/build-graphics.jm`) supplies the graphical targets. Each C input is one complete program.


<a id="build-graph-syntax"></a>

### Graph syntax
Paths are relative to the build file. Quote paths containing spaces. Comments occupy their own line.
```text
build staged.c: copy main.c
build out/main.image: jmc staged.c
  nodes = 2
build all: phony out/main.image
default all
```
- jmc compiles one C file to an image. The indented nodes option accepts 2, 4, 16, or 512; omitted means 2.
- copy produces one file from another.
- phony groups dependencies. It produces no file to load.
- default names the initial targets; without it, the first target is the default.

Dependencies build before their consumers. This language has built-in rules; arbitrary shell recipes and multi-file C linking are not implemented.


<a id="build-incremental-builds"></a>

### Incremental builds
Input contents, rule options, output contents, and compiler identity determine whether a target rebuilds. Current editor drafts count as inputs. Build records persist with generated files, so unchanged targets can skip after a reload.

A missing input, duplicate output, cycle, or output that would overwrite a user file is an error. A failed compile retains the last successful image. If an input or the graph changes during compilation, the stale result is rejected.


<a id="build-from-the-listener"></a>

### From the listener
Insert these one at a time. Selecting a target in the Build window also selects what an argument-free build command builds.
```listener
use-build /home/user/build.jm
build /build/main.image
load /build/main.image
run
```
[Listener presentations](#listener-selectable-objects) let you click a reported target or error location. [Files and drafts](#files) explains where outputs are stored.

<a id="workspace"></a>

## Windows and layouts

Arrange independent tools without losing their state.

<a id="workspace-arrange-the-desktop"></a>

### Arrange the desktop
Windows reopens or focuses tools, grouped into editing and building, debugging, output, and documentation. Layout contains presets and commands to split, move, zoom, close, focus, and resize windows. Its presets are development, editing, building, debugging, network, graphics, and documentation. Open the documentation layout (IDE action `layout-documentation`) to read beside the editor.

Drag a title bar onto an edge of another window to move it. Drag a divider to resize. The title-bar arrows split beside or below a window. Double-click its title, or use the square button, to zoom and restore.

Closing a window retains its state. Closing the editor window also retains its open buffers. The layout and focus survive reloads.


<a id="workspace-keyboard"></a>

### Keyboard
Ctrl+Alt+Arrows focuses neighbors. Ctrl+Alt+N and Ctrl+Alt+P cycle tools. Ctrl+Alt+Shift+Arrows resizes the focused tile. Ctrl+Alt+Enter zooms; Ctrl+Alt+Backspace closes.

Focused dividers accept arrows; Home resets an even split. M-x searches split and move commands. [Full keyboard reference](#keyboard).

<a id="files"></a>

## Files and drafts

Browser-persistent paths, recoverable edits, versions, and exports.
Open Files (IDE action `window-files`) or use Open (Cmd/Ctrl+O) to visit a pathname.


<a id="files-filesystem-roots"></a>

### Filesystem roots
- /home/user contains writable source files and build graphs.
- /examples contains bundled, read-only programs. Copy or Save as creates an editable version.
- /build contains generated images and source maps.

This filesystem lives in browser storage for this site. It is separate from the host checkout. A different port or browser profile has a separate workspace.


<a id="files-save-and-recover"></a>

### Save and recover
Edits keep a recoverable draft. Save (Cmd/Ctrl+S) commits it and retains the previous five saved versions. Versions recovers a saved version into a new file. Save as (Cmd/Ctrl+Shift+S) writes another pathname.

Move, Copy, and Trash apply to files or directories. Trash is recoverable; Restore refuses to overwrite an existing path. The [editor](#editor) retains open-buffer cursor positions and undo history.


<a id="files-import-and-export"></a>

### Import and export
Import reads local files into the selected directory. Export downloads the selected file; for a directory it exports a filesystem snapshot including drafts, versions, and trash. Export the filesystem (IDE action `export-files`) to keep a separate copy.

An outdated tab refuses to replace changes written by another tab. Export also includes pending edits if storage is full.

[Listener filesystem commands](#listener-files) accept relative paths and quoted names.

<a id="editor"></a>

## Editing code

Buffers, compiler diagnostics, source navigation, and compilation.
Open Editor (IDE action `window-editor`). Tabs represent files; switching them leaves the loaded machine in place. The modeline shows the buffer's current path and state.


<a id="editor-language-tools"></a>

### Language tools
The language server provides compiler diagnostics, completion, hover, definition, references, and document symbols. Diagnostics use the Lean compiler. Navigation uses a lexical scope index and does not implement full C type analysis.

Editor commands (IDE action `editor-commands`) opens Monaco's command list. F1 opens this manual. Problems (IDE action `window-problems`) links diagnostics to their source locations.


<a id="editor-compile-and-debug"></a>

### Compile and debug
Buffer Compile & Load (Cmd/Ctrl+Enter) compiles and loads the active C file with the Buffer node count. For dependency graphs and generated artifacts, use [Project builds](#build).

If Compile & Load fails, the previous machine remains available for inspection, and execution is disabled. Compile successfully or explicitly load a built image (IDE action `load-built-image`) to choose what will run.

Click the gutter or press F9 to toggle a source breakpoint. F10 steps an instruction on the selected node; F11 steps to another source line. A stop visits the loaded program's source, even if a different buffer was active.

Editing the loaded source makes the machine stale. Compile again, or rebuild and load the project image, to execute your changes.

<a id="listener"></a>

## The listener

A command prompt whose output contains selectable IDE objects.
Open Listener (IDE action `window-listener`). Enter executes the prompt; Up and Down recall commands. Relative paths use the prompt's current directory. Quote paths containing spaces. The listener operates on this environment, not a host shell.


<a id="listener-selectable-objects"></a>

### Selectable objects
A pathname, source location, node, packet, build target, or documentation topic in output is a typed object. Click or press Enter to visit it. Shift-click or Shift+Enter inserts its value into the prompt. Clicking an old command recalls it without executing it.

Alt+Up from the prompt selects the latest object. Arrows, Home, and End move through objects. Escape returns to the prompt.


<a id="listener-files"></a>

### Files
```text
ls [path]           cd path             pwd
edit path          new path            mkdir path
save               cp from to          mv from to
trash path         restore [id]        cat path
```


<a id="listener-build-and-machine"></a>

### Build and machine
```text
use-build path     build [target]      load output.image
compile [path]     nodes 2|4|16|512     inspect node
run                continue            pause
restart            reset
step source|instruction|cycle
```
See [build graphs](#build) and [debugger behavior](#debugger).


<a id="listener-network-and-desktop"></a>

### Network and desktop
```text
packets [filter]   packet id           break-network type conditions
delete-network-breakpoint id          trace-cycle n
trace-live         save-trace [path]   open-trace path
window id          tile layout         clear
commands           command id          keymap-reload
help [topic]       doc [topic or search words]
```
[Packet filters](#packets), [network breakpoints](#breakpoints), and [trace archives](#history) explain those arguments. M-x searches registered actions by name or ID.

<a id="debugger"></a>

## The debugger

Run, pause, step, inspect memory, and stop at source locations.
Open Debugger (IDE action `window-debugger`). The loaded source and node count identify which program you are inspecting. The execution toggle shows Run at cycle zero, Continue after a pause or step, and Pause while clocks advance. Its tooltip identifies the loaded image and source.


<a id="debugger-execution"></a>

### Execution
F5 runs or pauses the whole mesh. F10 advances until an instruction retires on the selected node. F11 advances to another source line. Cycle and +100 advance the requested number of clocks unless a stop condition occurs.

The cycle budget defaults to 10,000,000 and can be changed in the debugger. Continue resumes after a breakpoint or budget stop. After main returns, Continue is disabled. Restart (Shift+F5) resets and runs the loaded image from cycle zero; Reset reloads it without running. Explicit stepping remains available after main returns for hardware inspection. Reading state never advances clocks.

The main-result mailbox is at hexadecimal address 00300 on node 0. The debugger shows four data registers, four address registers, the tagged instruction pointer, and node state. [Tagged words](#words) explains the values.


<a id="debugger-stops"></a>

### Stops
F9 or a gutter click toggles a source breakpoint. An instruction breakpoint takes a hexadecimal word address. Read inspects a memory word; Watch stops when it changes.

Source and instruction breakpoints use RTL fetch boundaries. Handled faults are optional stops because futures use them during ordinary execution. Catastrophes always stop.

[Network breakpoints](#breakpoints) stop on accepted transfers, handler entry, or stalls. [Waiting](#waiting) explains blocked links and outstanding futures.

<a id="geometry"></a>

## Routing geometry

Physical coordinates, expected routes, observed hops, and blocked links.
Open Routing Geometry (IDE action `window-geometry`) or the network layout (IDE action `layout-network`).


<a id="geometry-coordinates"></a>

### Coordinates
Flat node IDs use x + X * (y + Y * z). In an 8×8×8 mesh, node 511 is (7,7,7). The expected route follows X, then Y, then Z.

Choose XY, XZ, YZ, or a 3D overview. Plane views show all slices or the selected slice. Resizing preserves node coordinates and adjacency.


<a id="geometry-read-a-route"></a>

### Read a route
Amber links show observed packet hops; dashed links show the expected path. Red links indicate current stalls. Select a link to filter its packets, or choose its direction and Inspect link. Priority filtering restricts traffic.

Arrows move within a plane; Page Up and Page Down change the slice. Enter opens the selected node's [Waiting inspector](#waiting). Ctrl+Alt+G jumps to a flat node ID or x,y,z.

[Packets](#packets) shows payloads and per-hop timing. [Causal history](#history) selects earlier observations without rewinding the machine.

<a id="packets"></a>

## Packet inspection

Filter messages and follow their payloads, routes, replies, and source.
Open Packets (IDE action `window-packets`). Select an entry to inspect injection flits, decoded 36-bit words, dimension headers, route, and timestamps.


<a id="packets-filters"></a>

### Filters
Structured filters include src:0, dst:511, priority:0, id:1, and handler:0x12c1. Free text also matches delivered, in flight, or a handler name such as __mdc_set.
```listener
packets src:0 dst:511
```
Up, Down, Home, and End move through packet entries. [Routing geometry](#geometry) shares the selection.


<a id="packets-follow-a-message"></a>

### Follow a message
Compiler annotations identify MDC handlers. Spawn requests retain the return node and mailbox; SET replies and mailbox writes link the request to its reply and future resolution. A message sent inside a hardware handler also retains that handler's packet identity.

Send source visits the captured instruction. Runtime handlers without a C location open the compiled listing. Raw assembly messages remain inspectable without MDC decoding.

FUT(0) alone cannot identify a future. Correlations use recorded requests, reply mailboxes, and observations. Lost events mark correlations incomplete.

Stall counts sum waiting cycles across routers and can exceed packet latency. [Waiting and futures](#waiting) and [network breakpoints](#breakpoints) help explain delays.

<a id="waiting"></a>

## Waiting and futures

Queues, reservations, backpressure, and remote-result mailboxes.
Open Waiting (IDE action `window-waiting`) to inspect the selected node.


<a id="waiting-follow-backpressure"></a>

### Follow backpressure
Both priorities show queue head, occupancy, and capacity. Output reservations, downstream backpressure, arbitration, priority selection, and reservations waiting for their producer explain where progress is blocked.

Follow moves to the next blocked link. The [geometry](#geometry) and [packet inspector](#packets) retain the selected node and message.


<a id="waiting-remote-results"></a>

### Remote results
Outstanding result mailboxes link to their requests. Observed SET replies and mailbox writes connect requests to completion. Future faults retain the operand and instruction address.

A recorded future fault does not establish that the processor is still blocked. Inspect current state and later observations. [History](#history) can distinguish an earlier wait from the live machine.

<a id="breakpoints"></a>

## Network breakpoints

Stop on injection, delivery, link transfer, handler entry, or sustained stalls.
Open network breakpoint controls (IDE action `network-breakpoint`) in Packets. The listener uses the same predicates.


<a id="breakpoints-examples"></a>

### Examples
```listener
break-network inject src=0 dst=511
break-network deliver dst=511 priority=0
break-network link node=0 port=2
break-network handler node=511 handler=0x1020
break-network stall node=7 cycles=20
delete-network-breakpoint 1
```
Ports are LOCAL=0, −X=1, +X=2, −Y=3, +Y=4, −Z=5, +Z=6. Use a handler address from the loaded image; the address above is an example.


<a id="breakpoints-timing"></a>

### Timing
Transfer breakpoints stop immediately after the accepting clock edge. Reading inspectors does not advance clocks. Source and instruction breakpoints retain their fetch-boundary behavior.

A stall predicate counts consecutive qualifying cycles. [Packets](#packets) provides the matched message and source, while [Waiting](#waiting) explains link reservations.

<a id="history"></a>

## Causal history and archives

Browse recorded events and save captures with their source snapshots.
Open Causal History (IDE action `window-history`).


<a id="history-navigate-observations"></a>

### Navigate observations
Select an event or cycle to inspect earlier observations. This does not rewind or modify the live machine. Live returns to the current capture; Run also returns to live execution.

Up, Down, Home, and End navigate the event list. Alt+Left and Alt+Right select the previous and next event when History has focus.


<a id="history-save-and-reopen"></a>

### Save and reopen
Save creates a .jmtrace archive containing topology, packets, events, source, and the compiled image. Compiler identity and an image SHA-256 are included when available. Open reads an archive for inspection.

The listener can store captures in the [virtual filesystem](#files):
```listener
save-trace /home/user/capture.jmtrace
open-trace /home/user/capture.jmtrace
trace-live
```


<a id="history-capture-limits"></a>

### Capture limits
The native stream holds 131,072 events between drains. The UI retains 50,000 events and 2,048 packet summaries. Payload storage is also bounded.

Drops and expired history are reported. Missing events leave correlations and historical queue state incomplete; the inspector does not invent missing headers or tails. [Graphical Display](#display) always reads live memory.

<a id="display"></a>

## Graphical display

Render integer arrays as pixels, inspect them, and export PNG images.
Open Graphical Display (IDE action `window-display`) or the graphics layout (IDE action `layout-graphics`).


<a id="display-program-convention"></a>

### Program convention
Declare these integer globals:
```c
int display_width = 8;
int display_height = 8;
int display_frame;
int display_pixels[64]; /* row-major 0xRRGGBB */
```
The display reads program memory without clocking the machine. Dimensions must fit the allocated array. The compiler's per-object ADDR length limit is 1,023 words.

RGB uses 0xRRGGBB. Grayscale uses the low byte of each integer. Non-integer pixels appear magenta. The optional frame counter is a program-defined progress marker; partial writes are visible while running.


<a id="display-inspect-output"></a>

### Inspect output
The Auto arrangement shows a mosaic when several nodes draw and a single node otherwise. Node mosaics show up to 16 nodes in increasing flat-ID order. Select a pixel to see its node, address, and value. Watch pixel adds a memory watchpoint. Save PNG downloads the displayed canvas.

Arrows inspect pixels; plus and minus change zoom. The display always shows live memory, including when [History](#history) is inspecting an earlier event.

[Graphical examples](#examples-graphical-programs) provide Mandelbrot tiles, Rule 110, a message hotspot, and mesh corners.

<a id="examples"></a>

## Example programs

Programs that make remote execution, routing, and graphical output visible.
Browse all examples (IDE action `examples`). Bundled files are read-only; Save as creates an editable copy.


<a id="examples-first-programs"></a>

### First programs
- factorial.c (`/examples/factorial.c`): a small two-node starting point for source stepping.
- remote_call.c (`/examples/remote_call.c`): follow a remote call and its result through [Packets](#packets).
- mesh512.c (`/examples/mesh512.c`): a remote array sum on node 511 returns 539 across the full 8×8×8 mesh.


<a id="examples-graphical-programs"></a>

### Graphical programs
Choose build-graphics.jm (`/home/user/build-graphics.jm`) in Project, select an image target, Build, Load, and Run. Open the graphics layout (IDE action `layout-graphics`).

- distributed_mandelbrot.c (`/examples/distributed_mandelbrot.c`): four 16×16 tiles form a 32×32 Mandelbrot picture. Target /build/mandelbrot.image uses four nodes and returns 1024; the display shows all four tiles.
- rule110.c (`/examples/rule110.c`): node 0 draws a 32×24 cellular-automaton diagram. Target /build/rule110.image uses two nodes and returns 24.
- message_hotspot.c (`/examples/message_hotspot.c`): four senders paint progress columns at node 5. Target /build/hotspot.image uses 16 nodes and returns 32.
- mesh_rainbow.c (`/examples/mesh_rainbow.c`): nodes 7, 56, 448, and 511 draw colored corner tiles. Target /build/rainbow.image uses 512 nodes and returns 256.

The full 512-node RTL model is substantially slower. Start with the four-node Mandelbrot program for a quicker graphical demonstration. Long programs can reach the [debugger's cycle budget](#debugger-execution); Continue resumes them.

[Display conventions](#display) explain how to write your own output program.

<a id="keyboard"></a>

## Keyboard reference

Global commands, window navigation, and tool-specific keys.

<a id="keyboard-everyday-actions"></a>

### Everyday actions
- M-x: Alt+X or Cmd/Ctrl+Shift+P searches commands and paths.
- F1: documentation for the current control, tool, or chooser selection.
- Cmd/Ctrl+O: find a file. Cmd/Ctrl+S: save. Cmd/Ctrl+Shift+S: save as.
- Cmd/Ctrl+B: build the selected project target or defaults.
- Cmd/Ctrl+Enter: compile and load the current C buffer.
- F5: run, continue, or pause. Shift+F5: restart the loaded image. F9: source breakpoint. F10: instruction. F11: source step.
- Ctrl+Alt+K: commands for the focused window.
- Ctrl+Alt+H: show active keyboard bindings.

M-x shows every registered action, including unavailable commands and the reason they are disabled. The same rules apply to header buttons and keyboard shortcuts. Choosers use Up/Down or Page Up/Down to select, Return to perform the displayed action, and Escape to cancel.


<a id="keyboard-window-navigation"></a>

### Window navigation
- Ctrl+Alt+Arrows: focus a neighbor. Ctrl+Alt+N / P: next / previous tool.
- Ctrl+Alt+Shift+Arrows: resize. Ctrl+Alt+Enter: zoom or restore.
- Ctrl+Alt+Backspace: close. M-x: search split and move commands.
- Tab / Shift+Tab: move among controls. Enter or Space: activate a button.


<a id="keyboard-tool-keys"></a>

### Tool keys
- [Listener](#listener): Up / Down recalls commands; Alt+Up selects an output object; Shift+Enter inserts it; Escape returns to the prompt.
- [Geometry](#geometry): Arrows move within a plane; Page Up / Down changes slice; Enter inspects waits. Ctrl+Alt+G jumps to a node.
- [Packets](#packets) and [History](#history): Up / Down / Home / End selects entries. History also uses Alt+Left / Right.
- [Display](#display): Arrows inspect pixels; plus / minus changes zoom.
- Documentation: Cmd/Ctrl+F searches; Alt+Left / Right navigates reading history; Tab / Enter follows links. Escape in search returns to the page.


<a id="keyboard-customize-bindings"></a>

### Customize bindings
Edit keymap.json (IDE action `keymap-edit`), save, then reload keyboard bindings (IDE action `keymap-reload`). Mod means Cmd on macOS or Ctrl elsewhere. An empty list unbinds a command. Invalid or duplicate keys leave the current map intact.

Use default keyboard bindings (IDE action `keymap-reset`) recovers the defaults. Monaco text-editing shortcuts remain available through Editor commands (IDE action `editor-commands`).

<a id="words"></a>

## Tagged words

36-bit values, addresses, futures, and memory inspection.
J-Machine memory words carry both a tag and a 32-bit payload. Inspectors show raw hexadecimal words beside decoded values.


<a id="words-inspect-a-word"></a>

### Inspect a word
Debugger (IDE action `window-debugger`) Read takes a hexadecimal word address on the selected node. Watch stops when that word changes. Registers, packet payloads, and display pixels use the same decoded presentation.

Integer values carry the INT tag. Addresses identify memory objects and include bounds information. Future values can trigger handled faults while awaiting a result. A FUT(0) value alone is not a unique message identity.

Use [Waiting](#waiting) to follow outstanding result mailboxes and [Packets](#packets) to connect requests, SET replies, and writes. The main-result mailbox is at address 00300 on node 0.


<a id="words-source-and-image"></a>

### Source and image
The compiled image (IDE action `window-image`) contains tagged words and compiler source-map annotations. The debugger's loaded source link identifies the program that produced the machine state.
