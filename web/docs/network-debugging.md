# Network observation and graphical output

Use **M-x → Layout: network** for Routing Geometry, Packets, Waiting, and
Causal History. **Layout: graphics** combines the editor, listener, display,
and mesh. Windows remain independent tools registered with the tiling shell.

Press **F1** in any inspector for its linked manual page. **Help** opens the
same reader, with search, Back/Forward, links to related tools and examples,
and listener commands you can insert at the prompt. The always-visible
**Project** controls expose graph selection and **Build → Load**; F5 runs the
loaded image and toggles to Pause.

## Keyboard workflow

Every desktop command is searchable by its name or stable command ID in M-x
(Alt+X or Cmd/Ctrl+Shift+P). `commands` lists IDs in the listener;
`command window-packets` invokes the same registered action. **Commands for
focused window** (Ctrl+Alt+K) exposes that tool's buttons and inputs. Tab and
Shift+Tab move among controls; native buttons activate with Return or Space.

| Action | Keys |
| --- | --- |
| Documentation for the focused tool | F1 |
| Documentation: search / back / forward | Cmd/Ctrl+F / Alt+Left / Alt+Right |
| Focus a neighboring tile | Ctrl+Alt+Arrow |
| Cycle through tiles | Ctrl+Alt+N / P |
| Resize the focused tile | Ctrl+Alt+Shift+Arrow |
| Zoom / restore | Ctrl+Alt+Return |
| Close the focused tile | Ctrl+Alt+Backspace |
| Split, move, or reopen a tile | M-x, search the action or window name |
| Jump to node number or x,y,z | Ctrl+Alt+G |
| Contextual key list | Ctrl+Alt+H |
| Listener: select latest presented object | Alt+Up from the prompt |
| Listener: navigate presented objects | Arrows / Home / End |
| Listener: visit / insert / return to prompt | Return / Shift+Return / Escape |
| Geometry: move within plane / change slice | Arrows / Page Up / Page Down |
| Geometry: inspect selected node's waits | Return |
| Packets and history: select entries | Up / Down / Home / End |
| History: previous / next event | Alt+Left / Alt+Right |
| Display: inspect pixels / zoom | Arrows / + / − |

Edit `/home/user/keymap.json`, save, then run `keymap-reload` or M-x → Reload
keyboard bindings. An empty binding list unbinds a command. Invalid or duplicate
bindings are rejected without replacing the working keymap. `Mod` means Cmd on
macOS or Ctrl elsewhere. Standard editor text-editing keys remain available.
Use **Use default keyboard bindings** to recover from an inconvenient keymap.

For the large mesh, enter these listener commands one at a time:

```text
use-build /home/user/build.jm
build /build/mesh512.image
load /build/mesh512.image
break-network deliver dst=511
run
tile network
packet 1
```

Select **Send source** to visit the captured sending instruction. Runtime
handlers without a C source location open the compiled listing at the exact
instruction address. The image's source snapshot is used if the workspace
buffer has changed.

## Geometry and packets

Flat IDs use `x + X * (y + Y * z)`. Thus node 511 is `(7,7,7)` in the 8×8×8
mesh. XY, XZ, and YZ views display all slices or just the selected slice; a 3D
overview is also available. Window resizing scales the drawing while keeping
coordinates and adjacency fixed. The expected path follows X, then Y, then Z.
Amber links show observed packet hops, dashed links show the expected route,
and red links show current stalls. Select a link to filter its packets, or
choose a link direction and use **Inspect link**. Traffic can be filtered by
priority.

Packets retain their source, destination, priority, raw injection flits,
decoded 36-bit payload words, consumed dimension headers, route, and cycle
timestamps. Filters accept `src:0 dst:511 priority:0 id:1 handler:0x12c1`, as
well as free text such as `delivered`, `in flight`, or `__mdc_set`.

The observer recognizes MDC handlers from compiler image annotations. Spawn
messages identify a return node and mailbox; SET replies and writes to that
mailbox connect a request to its reply and future resolution. Messages sent
while a hardware handler is active also retain that handler's packet identity.
Raw assembly messages remain inspectable even when no MDC decoding applies.
FUT(0) values are not unique identities and are never used alone to attribute
a reply or resolution.

Waiting shows queue head, occupancy and capacity for both priorities, output
reservations, downstream backpressure, arbitration, priority selection, and
reservations waiting for their producer. **Follow** moves inspection along a
blocked link. Outstanding remote-result mailboxes link back to their request.
Future faults retain the observed operand and instruction address. A recorded
future fault does not by itself prove that the processor remains blocked.

Stall counts sum buffer/reservation waiting cycles across routers. Several
routers can wait simultaneously, so this count can exceed packet latency.

## Breakpoints and history

The Packets window and listener share the same breakpoint implementation:

```text
break-network inject src=0 dst=511
break-network deliver dst=511 priority=0
break-network link node=0 port=2
break-network handler node=511 handler=0x1020
break-network stall node=7 cycles=20
delete-network-breakpoint 1
```

Ports are LOCAL=0, −X=1, +X=2, −Y=3, +Y=4, −Z=5, +Z=6. A transfer breakpoint
stops immediately after the accepting clock edge. Reads and inspection do not
advance clocks. The native loop stops at candidate event edges before the
JavaScript decoder evaluates the full packet predicate; source and instruction
breakpoints retain the existing fetch-boundary behavior.

History selects an event or cycle without rewinding or modifying the live
machine. **Live** returns to the current capture; Continue also returns to
live execution. A saved `.jmtrace` includes packets, events, topology, source,
the compiled image, compiler identity when available, and an image SHA-256.
Open it through the History window, or use `save-trace path` / `open-trace path`
for files in the virtual filesystem. Imported traces are inspection-only.

The native stream holds up to 131,072 events between drains; the UI retains
50,000 events and 2,048 packet summaries. Drops and expired history are shown
explicitly. After loss, correlations are marked incomplete; reconstruction
never silently treats a missing header or tail as a complete packet. Historical
queue and reservation state is incomplete when its prerequisite events have
expired. Per-packet payload and flit storage is also capped.

## Graphical programs

The display reads program memory without advancing the simulator. Programs
provide these integer globals:

```c
int display_width = 8;
int display_height = 8;
int display_frame;
int display_pixels[64]; /* row-major 0xRRGGBB */
```

The compiler's current per-object ADDR length limit is 1,023 words. The
display validates dimensions against the allocated array. A grayscale mode
uses each integer's low byte; non-integer pixels are shown in magenta. The
optional frame counter is a program-defined progress marker, and partial
frame writes are visible while running. Node mosaics show up to 16 nodes,
in increasing flat-ID order. Selecting a pixel shows its address and value;
**Watch pixel** adds a memory watchpoint, and **Save PNG** exports the canvas.

`/home/user/build-graphics.jm` supplies four targets:

| Program | Nodes | Display | Result |
| --- | ---: | --- | ---: |
| `distributed_mandelbrot.c` | 4 | 2×2 mosaic of 16×16 tiles | 1024 |
| `rule110.c` | 2 | Node 0, 32×24 space-time diagram | 24 |
| `message_hotspot.c` | 16 | Node 5, four senders paint progress columns | 32 |
| `mesh_rainbow.c` | 512 | Colored tiles at nodes 7, 56, 448, 511 | 256 |

These images were read from the RTL simulator's framebuffer memory:

| Four Mandelbrot tiles | Rule 110 | Message hotspot |
| --- | --- | --- |
| ![Mandelbrot output](images/distributed_mandelbrot.png) | ![Rule 110 output](images/rule110.png) | ![Hotspot output](images/message_hotspot.png) |

Regenerate them with `npm --prefix web run examples:render` after building the
compiler and simulator engines.

The renderers can take several million RTL cycles. The debugger defaults to
a 10,000,000-cycle run budget, adjustable in its controls; Pause remains
available during execution. The display always represents live memory, while
Causal History represents saved observations.

The full 512-node RTL model is substantially slower than the smaller meshes.
Its browser execution uses short batches so controls remain available between
batches. Use the four-node Mandelbrot example for a quicker graphical demo.

## Implementation and checks

`J_MACHINE_NETWORK_TRACE` enables passive DPI observations in the router,
endpoint, and core. Normal RTL targets do not define it. No observation signal
drives the design. Hooks sample pre-edge handshakes and emit fixed 12-word
records; JavaScript processes all departures before assigning incoming flit
identities for that edge. This preserves correlations across simultaneous hops.
Observer IDs are never inserted into the network protocol.

`npm --prefix web test` covers the ordinary workbench plus network predicates,
bounded capture, archive validation, keymaps, layout operations, exact pixels,
and observation-on/off architectural equivalence. `node
web/tests/network_mesh.mjs` checks the two 512-node programs, their 21-hop
routes to node 511, breakpoint stops, and corner pixels. Run it with Node 20
or newer. Native compiler and RTL gates remain:

```sh
bazel test //compiler:jmc_test //sim:rtl_conformance_test --test_output=errors
```
