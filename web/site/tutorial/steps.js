// The guided tour. Each step names what to look at, performs its own action,
// reports when the machine reached the expected state, and arranges only the
// windows it talks about, so the desktop reveals itself one tool at a time.
import { leaf, split } from '../shell/layout.js';

const editing = () => split('y', .68, leaf('editor'), leaf('listener'));
const stage = (main, side, ratio = .6) => split('x', ratio, main, split('y', .5, leaf('tutorial'), side));

const settled = ide => new Promise(resolve => {
  if (!ide.debug?.running) return resolve();
  const off = ide.on('state', () => { if (!ide.debug?.running) { off(); resolve(); } });
});
// Opens a buffer and runs it: compiles when it is not the loaded program,
// restarts a finished image, and otherwise continues. Execution is not
// awaited; the step's done check follows the machine instead.
async function runFile(ide, path, nodes) {
  if (ide.debug?.running) { ide.pause(); await settled(ide); }
  ide.openFile(path, { focus: false });
  if (nodes) ide.setNodes(nodes);
  if (ide.compiledPath !== path || ide.stale) { await ide.compile(path); if (ide.loadFailure) return; }
  else if (ide.debug?.completed) ide.reset();
  ide.perform(() => ide.execute());
}
const resultIs = (ide, path, value) => ide.compiledPath === path && !!ide.debug?.completed && (ide.simulator.peek(0, 0x300) & 0xffffffffn) === value;
const finished = (ide, path) => ide.compiledPath === path && !!ide.debug?.completed;
// A cycle-accurate model of sixteen nodes advances a few generations a
// minute in a browser, so a step is done once the picture has visibly
// evolved; the program keeps running until the next step pauses it.
const evolved = (ide, path, cycles) => ide.compiledPath === path && (!!ide.debug?.completed || (ide.debug?.snapshot?.cycle ?? 0n) > cycles);

export const STEPS = [
  { id: 'run', title: 'Run a program', text: `
The J-Machine was built at MIT between 1988 and 1993 in William Dally's group: up to 1,024 Message-Driven Processors in a three-dimensional mesh, each with its own memory, exchanging short messages that start a handler on arrival. The processor is described in [Architecture of a Message-Driven Processor](https://people.eecs.berkeley.edu/~kubitron/courses/cs258-S02/handouts/papers/dally-architecture.pdf) (ISCA 1987) and specified in [MDP Architecture Version 11, MIT AI Memo 1069](https://www.bitsavers.org/pdf/mit/ai/aim/AIM-1069.pdf); the router in [The J-Machine Network](https://doi.org/10.1109/ICCD.1992.276305) (ICCD 1992); the system in [The J-Machine Multicomputer: An Architectural Evaluation](https://people.eecs.berkeley.edu/~kubitron/courses/cs258-S08/handouts/papers/p224-noakes.pdf) (ISCA 1993). The language here, Message-Driven C, follows Daniel Maskit's [Caltech thesis](https://doi.org/10.7907/Z9J38QKJ) (1994).

This tab runs a SystemVerilog implementation of that hardware: the MDP core, its message unit and queues, and the mesh router, assembled into 2-, 4-, 16- and 512-node meshes. Verilator turns the RTL into C++ and Emscripten turns that into WebAssembly, so every cycle counted here is a cycle of the register-transfer-level model, not an estimate. The C compiler is written in Lean 4 and also runs as WebAssembly; the desktop is plain JavaScript around the Monaco editor. Everything is open source under the Apache 2.0 license at [github.com/ranvier-labs/j-machine](https://github.com/ranvier-labs/j-machine).

main.c is compiled and loaded on a two-node machine. Run executes it. Watch MACHINE: node 0 runs the program, node 1 has no work and only runs its background loop, and the value main returns appears as the main result. The LISTENER below the editor logs what happened; it is also a command line.
`,
    action: { label: 'Run main.c', run: ide => runFile(ide, '/home/user/main.c') },
    done: ide => resultIs(ide, '/home/user/main.c', 720n),
    layout: () => stage(editing(), leaf('machine')) },
  { id: 'edit', title: 'Change the program', text: `
Edit the source in EDITOR and the machine becomes stale: the loaded image no longer matches the text. Run then reads Compile & Run and does both. Cmd/Ctrl+Enter compiles and loads without running; Cmd/Ctrl+S saves and keeps the previous five versions.

Do it changes factorial(6) to factorial(5) and runs; the main result becomes 120. Compiler errors appear under the text and in the modeline below the editor.
`,
    action: { label: 'Change 6 to 5 and run', run: ide => {
      const path = '/home/user/main.c'; ide.openFile(path, { focus: false });
      const text = ide.text(path).replace('factorial(6)', 'factorial(5)');
      if (text !== ide.text(path)) { ide.editor.syncSource(path, text); ide.edited(path, text); }
      return runFile(ide, path);
    } },
    done: ide => resultIs(ide, '/home/user/main.c', 120n),
    layout: () => stage(editing(), leaf('machine')) },
  { id: 'debug', title: 'Stop and step', text: `
A source breakpoint stops the machine before the first instruction of that line. Click the editor gutter or press F9 on a line to set one. The DEBUGGER shows the stop reason, the instruction pointer, the four data and four address registers, and memory of the selected node; amber marks values that changed.

Do it sets a breakpoint on line 6, the recursive call, and runs from the start. Then press F10 to step one instruction, F11 to reach the next source line, and F5 to continue. Memory watches stop when a word changes.
`,
    action: { label: 'Break on line 6 and run', run: async ide => {
      const path = '/home/user/main.c'; if (ide.debug?.running) { ide.pause(); await settled(ide); }
      ide.openFile(path, { focus: false });
      if (!ide.breakpoints(path).some(bp => bp.line === 6)) ide.toggleBreakpoint(6);
      if (ide.compiledPath !== path || ide.stale) { await ide.compile(path); if (ide.loadFailure) return; } else ide.reset();
      ide.perform(() => ide.execute());
    } },
    done: ide => ide.compiledPath === '/home/user/main.c' && ide.debug?.stopReason.type === 'breakpoint',
    layout: () => split('x', .6, editing(), split('y', .4, leaf('tutorial'), leaf('debugger'))) },
  { id: 'remote', title: 'Two nodes', text: `
Message-Driven C adds one operator to C: a call suffixed with @node runs on that node. A void call is a one-way message. A value-returning call yields a future; reading it blocks until the reply arrives. computer() names the node the code runs on.

Do it loads remote_call.c on two nodes and runs it. Node 0 sends record(40) to node 1 and then calls remote_add there; the main result is 142. ROUTING GEOMETRY draws the mesh; select a node to inspect it.
`,
    action: { label: 'Run remote_call.c', run: ide => runFile(ide, '/examples/remote_call.c') },
    done: ide => resultIs(ide, '/examples/remote_call.c', 142n),
    layout: () => stage(editing(), split('y', .5, leaf('machine'), leaf('geometry'))) },
  { id: 'packets', title: 'Follow the messages', text: `
Every message is captured as a packet: the send instruction, the injection and delivery cycles, the route through the mesh, the handler that ran at the destination, and the reply that resolved a future. PACKETS lists them; a filter such as dst=1 narrows the list.

Do it selects the first packet. ROUTING GEOMETRY draws its observed route in amber and the expected route dashed. Send source and Handler visit the code. WAITING shows queues and outstanding futures for the selected node; CAUSAL HISTORY replays events cycle by cycle and saves traces.
`,
    action: { label: 'Select the first packet', run: ide => {
      const trace = ide.network; if (!trace?.packets.size) throw new Error('Run remote_call.c first: go back one step.');
      trace.selectedPacket = [...trace.packets.keys()][0]; ide.emit('network');
    } },
    done: ide => ide.compiledPath === '/examples/remote_call.c' && ide.network?.selectedPacket != null,
    layout: () => split('x', .5, split('y', .6, leaf('packets'), leaf('listener')), split('y', .45, leaf('tutorial'), leaf('geometry'))) },
  { id: 'contention', title: 'Contention on sixteen nodes', text: `
message_hotspot.c runs on a 4 × 4 mesh. Four senders converge on node 5, so its input queue fills and routers upstream block. In ROUTING GEOMETRY link width grows with traffic and red marks a blocked input; WAITING explains each stall for the selected node.

Do it compiles and runs it on sixteen nodes. Pause with F5 while it runs to inspect a moment; Continue resumes. Network breakpoints in PACKETS stop on injection, delivery, link transfer, handler entry, or a sustained stall.
`,
    action: { label: 'Run message_hotspot.c', run: ide => runFile(ide, '/examples/message_hotspot.c', 16) },
    done: ide => finished(ide, '/examples/message_hotspot.c'),
    layout: () => split('x', .55, split('y', .6, leaf('geometry'), leaf('waiting')), split('y', .45, leaf('tutorial'), leaf('machine'))) },
  { id: 'project', title: 'Projects', text: `
A build graph (build.jm) describes outputs and their inputs with Ninja-style statements: jmc compiles one C program to an image, copy produces a file, phony groups targets. BUILD lists every target with its inputs, definition, state, and build reason.

Do it selects /home/user/build.jm, builds /build/main.image, loads it, and runs; it also removes the breakpoint from step 3 so the program completes. Unchanged targets are skipped by content hash. Edit graph opens the file; Guide opens its manual page.
`,
    action: { label: 'Build, load, and run /build/main.image', run: async ide => {
      if (ide.debug?.running) { ide.pause(); await settled(ide); }
      ide.openFile('/home/user/main.c', { focus: false }); for (const bp of ide.breakpoints('/home/user/main.c')) ide.toggleBreakpoint(bp.line);
      ide.selectBuildFile('/home/user/build.jm'); ide.selectBuildTarget('/build/main.image');
      await ide.build('/build/main.image'); await ide.loadArtifact('/build/main.image', { project: '/home/user/build.jm' });
      ide.perform(() => ide.execute());
    } },
    done: ide => ide.imagePath === '/build/main.image' && !!ide.debug?.completed,
    layout: () => split('x', .55, split('y', .6, leaf('build'), leaf('listener')), split('y', .45, leaf('tutorial'), leaf('machine'))) },
  { id: 'graphics', title: 'Pictures from memory', text: `
A program that defines display_width, display_height, and display_pixels turns part of its memory into a picture. GRAPHICAL DISPLAY reads those words while the machine runs, shows a mosaic when several nodes draw, and saves a PNG.

Do it builds the Mandelbrot target from build-graphics.jm, loads it on four nodes, and runs. Each node renders one 16 × 16 tile; the picture fills in while the machine runs. Click a pixel to see its address and value.
`,
    action: { label: 'Build and run the Mandelbrot image', run: async ide => {
      if (ide.debug?.running) { ide.pause(); await settled(ide); }
      ide.selectBuildFile('/home/user/build-graphics.jm'); ide.selectBuildTarget('/build/mandelbrot.image');
      await ide.build('/build/mandelbrot.image'); await ide.loadArtifact('/build/mandelbrot.image', { project: '/home/user/build-graphics.jm' });
      ide.perform(() => ide.execute());
    } },
    done: ide => ide.imagePath === '/build/mandelbrot.image',
    layout: () => split('x', .55, split('y', .65, leaf('display'), leaf('listener')), split('y', .45, leaf('tutorial'), leaf('machine'))) },
  { id: 'life', title: 'Life across sixteen nodes', text: `
life16.c runs Conway's Game of Life on a 16 × 16 torus split into sixteen 4 × 4 tiles, one per node of the 4 × 4 mesh. Node 15 runs the game as one long call from main: each generation it collects every tile's four edges, packed into one word, with a value-returning call, assembles each tile's halo from its neighbours' edges, and delivers it with a one-way message. Receiving that halo is what makes a tile compute and draw its next generation; a tile never sends on its own, so no node is ever flooded.

Do it compiles and runs it. GRAPHICAL DISPLAY shows the whole board as a mosaic of the sixteen tiles; ROUTING GEOMETRY shows the traffic to and from node 15. The step counts as done after the first generations; the game keeps running until the next step pauses it. The result is the number of live cells after 16 generations, which a plain single-machine simulation of the same rules reproduces exactly. Every C statement costs hundreds of cycles on this machine, so a generation takes a few seconds.
`,
    action: { label: 'Run life16.c on 16 nodes', run: ide => runFile(ide, '/examples/life16.c', 16) },
    done: ide => evolved(ide, '/examples/life16.c', 900000n),
    layout: () => split('x', .55, split('y', .65, leaf('display'), leaf('listener')), split('y', .45, leaf('tutorial'), leaf('geometry'))) },
  { id: 'heat', title: 'A heat equation on the mesh', text: `
heat16.c solves the steady heat equation on a 16 × 16 plate by Jacobi relaxation, the computation the original J-Machine programmers benchmarked. Two spots are held hot and two cold; every sweep replaces each other cell with the mean of its four neighbours. Tiles hand node 15 their edge temperatures, four 8-bit values per word, as in the last step, and node 15 delivers each tile the temperatures around it. The result is the total change of the last of 24 sweeps summed over the plate, so it reports how far the plate is from steady state.

Do it compiles and runs it. The display maps temperature from black through red to amber; watch the heat spread from the sources and the residual fall. Pause with F5 to inspect a sweep in PACKETS and WAITING, then Continue.
`,
    action: { label: 'Run heat16.c on 16 nodes', run: ide => runFile(ide, '/examples/heat16.c', 16) },
    done: ide => evolved(ide, '/examples/heat16.c', 900000n),
    layout: () => split('x', .55, split('y', .65, leaf('display'), leaf('listener')), split('y', .45, leaf('tutorial'), leaf('geometry'))) },
  { id: 'mesh', title: 'The full mesh', text: `
The largest configuration is 8 × 8 × 8 = 512 nodes. Its simulator is a 40 MB WebAssembly module; the status line reports the download and the load. mesh512.c sums an array on node 511, the far corner, and returns 539.

Do it loads and runs it. ROUTING GEOMETRY switches to the 3D overview when its window is too narrow for eight slices; Go to node jumps to a number or x,y,z coordinate. The full model is much slower than the small meshes.
`,
    action: { label: 'Run mesh512.c on 512 nodes', run: ide => runFile(ide, '/examples/mesh512.c', 512) },
    done: ide => resultIs(ide, '/examples/mesh512.c', 539n),
    layout: () => split('x', .55, split('y', .6, leaf('geometry'), leaf('listener')), split('y', .45, leaf('tutorial'), leaf('machine'))) },
  { id: 'files', title: 'Your files', text: `
Everything lives in this browser's storage for this site. /home/user holds your files and projects; /examples is read-only; /build holds generated images. Save keeps the previous five versions, Trash is recoverable, and Export downloads a file or a snapshot of the whole filesystem.

Do it copies remote_call.c into /home/user as an editable file and opens it. FILES lists the tree; the listener accepts ls, cd, cp, mv, edit, and trash with the same pathnames.
`,
    action: { label: 'Copy remote_call.c into /home/user', run: ide => {
      const target = ide.uniquePath('/home/user/my_remote_call.c'); ide.fs.copy('/examples/remote_call.c', target); ide.openFile(target, { focus: false });
    } },
    done: ide => ide.fs.files().some(path => /^\/home\/user\/my_remote_call.*\.c$/.test(path)),
    layout: () => stage(editing(), leaf('files')) },
  { id: 'desktop', title: 'The whole desktop', text: `
Windows lists every tool; Layout has presets for development, editing, debugging, building, network, graphics, and documentation. Drag a title bar onto the edge of another window to move it, drag dividers to resize, double-click a title to zoom.

M-x (Alt+X or Cmd/Ctrl+Shift+P) searches every command and pathname and says why an action is unavailable. F1 opens the manual for whatever has focus. Type help in the listener for its commands. Do it applies the development layout; reopen this tour any time with Tutorial in the header or the tutorial command.
`,
    action: { label: 'Show the development layout', run: ide => ide.services.layout('development') },
    layout: () => stage(editing(), leaf('machine')) },
];
