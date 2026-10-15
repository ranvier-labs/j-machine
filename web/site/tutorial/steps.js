// Lessons arrange tools and source; the reader operates the machine.
import { leaf, split } from '../shell/layout.js';
import { describeWord } from '../runtime.js';

export const CHAPTERS = [
  { id: 'intro', title: 'Introduction' },
  { id: 'hardware', title: 'Hardware and ISA' },
  { id: 'language', title: 'Message-Driven C' },
  { id: 'inspect', title: 'Run, edit, and inspect' },
  { id: 'routing', title: 'Routing and communication' },
  { id: 'examples', title: 'Distributed examples' },
  { id: 'workspace', title: 'Working on your own' },
];

const stage = context => split('x', .213, leaf('tutorial'),
  split('y', .574, leaf('editor'), split('x', .602,
    context ? split('x', .55, leaf('listener'), context) : leaf('listener'), leaf('machine'))));

const settled = ide => new Promise(resolve => {
  if (!ide.debug?.running) return resolve();
  const off = ide.on('state', () => { if (!ide.debug?.running) { off(); resolve(); } });
});
export async function openLessonWorkspace(ide, step) {
  if (ide.debug?.running) { const stopped = settled(ide); ide.pause(); await stopped; }
  const workspace = step.workspace;
  if (workspace?.file) ide.openFile(workspace.file, { focus: false });
  if (workspace?.nodes) ide.setNodes(workspace.nodes);
  if (workspace?.project) { ide.selectBuildFile(workspace.project); ide.selectBuildTarget(workspace.target); }
  if (ide.debug) ide.selectNode(0);
  ide.services.applyLayout(step.layout());
  ide.services.selectTool(workspace?.tab ?? 'instructions');
  ide.services.openWindow('tutorial');
}
const stoppedAt = (ide, path, node) => ide.compiledPath === path && ide.debug?.stopReason.type === 'breakpoint' && ide.debug.stopReason.node === node;
const memoryObservation = (ide, path) => {
  if (ide.compiledPath !== path) return '';
  const global = ide.debug.info.globals.find(entry => entry.name === 'observed[0]');
  if (!global) return '';
  return `Word 0x${global.address.toString(16).padStart(5, '0')} · node 0 observed: ${describeWord(ide.simulator.peek(0, global.address))} · node 1 observed: ${describeWord(ide.simulator.peek(1, global.address))}`;
};
const resultIs = (ide, path, value) => ide.compiledPath === path && !!ide.debug?.completed && (ide.simulator.peek(0, 0x300) & 0xffffffffn) === value;
const finished = (ide, path) => ide.compiledPath === path && !!ide.debug?.completed;
// A cycle-accurate model of sixteen nodes advances a few generations a
// minute in a browser, so a step is done once the picture has visibly
// evolved; the program keeps running until the next lesson pauses it.
const evolved = (ide, path, cycles) => ide.compiledPath === path && (!!ide.debug?.completed || (ide.debug?.snapshot?.cycle ?? 0n) > cycles);

const LESSONS = [
  { id: 'welcome', chapter: 'intro', title: 'A message-driven machine', text: `
The J-Machine was built at MIT between 1988 and 1993 in William Dally's group: up to 1,024 Message-Driven Processors in a three-dimensional mesh, each with its own memory, exchanging short messages that start a handler on arrival. The processor is described in [Architecture of a Message-Driven Processor](https://people.eecs.berkeley.edu/~kubitron/courses/cs258-S02/handouts/papers/dally-architecture.pdf) (ISCA 1987) and specified in [MDP Architecture Version 11, MIT AI Memo 1069](https://www.bitsavers.org/pdf/mit/ai/aim/AIM-1069.pdf); the router in [The J-Machine Network](https://doi.org/10.1109/ICCD.1992.276305) (ICCD 1992); the system in [The J-Machine Multicomputer: An Architectural Evaluation](https://people.eecs.berkeley.edu/~kubitron/courses/cs258-S08/handouts/papers/p224-noakes.pdf) (ISCA 1993). The language here, Message-Driven C, follows Daniel Maskit's [Caltech thesis](https://doi.org/10.7907/Z9J38QKJ) (1994).

The goal was to make short messages and small parallel tasks practical by putting communication, dispatch, and synchronization support close to the processor. This tour first explains that hardware and its language, then follows messages and explores distributed pictures and simulations.

This tab runs a clean-room SystemVerilog model through Verilator and WebAssembly. Its cycle count measures this RTL implementation, rather than proving identical timing to the historical chips. The Lean 4 compiler also runs in the browser. The project is [open source](https://github.com/ranvier-labs/j-machine).

The desktop borrows several ideas from [Lisp-machine environments](https://www.bitsavers.org/pdf/symbolics/software/genera_8/Program_Development_Tutorial.pdf): an integrated editor and debugger, named commands, a Listener, and [typed, clickable output](https://mcclim.common-lisp.dev/static/manual/mcclim.html). These are interface influences; this simulator runs MDP instructions compiled from Message-Driven C. It does not emulate a Lisp machine.

Read each lesson, then open its workspace to try it yourself. Opening a workspace selects the source and tools; you compile, run, and step. Next explicitly advances to the next lesson. The Lesson menu in the top bar lets you revisit any chapter or lesson.
`, layout: () => stage() },
  { id: 'environment', chapter: 'intro', title: 'Look around the desktop', text: `
EDITOR holds the C source. Below it, a shared tool panel has Listener, Instructions, and Debugger tabs. Instructions shows machine code; Debugger shows registers, breakpoints, and memory. MACHINE shows each node's instruction activity, the cycle count, and the main result. This Tutorial stays beside the tools you need.

Start the guided tour to see each area highlighted. Use Next area to move between explanations. When the tour ends, try help in Listener, then switch to Instructions.

Why Listener? Lisp machines used a Lisp Listener for a read–evaluate–print conversation with the system. Here the name carries that interactive tradition, but the language is the IDE's command language: help, edit, run, inspect, and other commands. It is not a Lisp evaluator or a host shell. Editable files live in this browser's storage; /examples is read-only.
`, workspace: { tab: 'listener' },
    done: ide => ide.fs.data.session.inspectionTab === 'listener', layout: () => stage() },
  { id: 'inspection', chapter: 'intro', title: 'Choose what to inspect', text: `
Open the workspace to select Instructions and node 0. Click a node in MACHINE to change whose instructions and state you inspect; selecting a node does not pause the machine or give it exclusive execution.

The arrow marks the next fetch in that node's memory. Word : slot is a hexadecimal word address followed by :0 for its first instruction or :1 for its second. Hover or focus a row to learn what it does; ? explains the columns. The selected node's next position may change while an instruction is in progress.

Next: Instruction, Clock cycle, and Source line advance the whole mesh. The next chapter explains why those are different amounts of work.
`, workspace: { tab: 'instructions' },
    done: ide => ide.selectedNode === 0 && ide.fs.data.session.inspectionTab === 'instructions', layout: () => stage() },
  { id: 'cores', chapter: 'hardware', title: 'Independent cores, private memory', text: `
Each node has an MDP processor, local memory, message queues, and a router. Nodes run independently; the mesh carries messages between them. They do not share a coherent memory where an ordinary store on one node automatically changes another node's variable.

Open the workspace, click Compile & Load, then Run. observed starts at 7 on both nodes. A message asks node 1 to set its copy to 41; a reply lets node 0 read that value. Node 0's own observed stays 7, so main returns 7 × 100 + 41 = 741. The same address below belongs to two separate memories.

Click the two nodes to compare their instruction positions. The @1 notation sends a call to node 1; the language chapter will unpack it.
`, workspace: { file: '/examples/tutorial_memory.c', nodes: 2 },
    done: ide => resultIs(ide, '/examples/tutorial_memory.c', 741n), observe: ide => memoryObservation(ide, '/examples/tutorial_memory.c'),
    layout: () => stage() },
  { id: 'isa', chapter: 'hardware', title: 'A custom instruction set', text: `
The MDP has its own instruction set, specified by Architecture Version 11. It is not ARM, x86, or MIPS. Every core executes this same ISA: ordinary arithmetic, memory accesses, and branches, plus instructions for sending messages, checking tags, associative lookup, and ending a handler with SUSPEND.

Data words have 32 data bits and a 4-bit tag, distinguishing integers, addresses, futures, and other values. An instruction word instead packs two 17-bit instructions; constants encountered in the instruction stream load R0. Four data registers (R0–R3) and four address registers (A0–A3) keep contexts small. Bounds and tag checks can raise faults.

Open the workspace and click Compile & Load for the plain C addition. Click Next: Source line to reach source code, then Next: Instruction. Compare Next: Clock cycle and Instruction. An instruction retires when it completes; memory or network waits can cost several clocks. A C expression can compile to many instructions. Background loops also retire instructions, so a lit node is not necessarily doing useful application work.
`, workspace: { file: '/examples/tutorial_local.c', nodes: 2 },
    done: ide => ide.compiledPath === '/examples/tutorial_local.c' && ide.debug?.stopReason.type === 'instruction', layout: () => stage() },
  { id: 'dispatch', chapter: 'hardware', title: 'Messages start handlers', text: `
Incoming messages are queued by hardware. Their header identifies a handler, and dispatch sets the core's instruction pointer so that handler runs using the same ISA as any other code. Routers forward traffic without making each intermediate core execute forwarding software.

There are two message priorities and a background context. Higher-priority messages can interrupt lower-priority work; separate register contexts reduce switching overhead. A handler ends with SUSPEND, which removes its message and allows another handler or interrupted work to proceed. This instruction is different from the debugger's Pause, which freezes the whole mesh.

Open the workspace and compile. Click the editor gutter on observed = value to set a breakpoint. This line is executed by the handler on node 1. Click Run to stop before the store. The application handler is C compiled into MDP instructions, entered through runtime dispatch. Node 0 sent the request; node 1 is now executing it. Continue to finish with 142.
`, workspace: { file: '/examples/remote_call.c', nodes: 2 },
    done: ide => stoppedAt(ide, '/examples/remote_call.c', 1), observe: ide => memoryObservation(ide, '/examples/remote_call.c'),
    layout: () => stage() },
  { id: 'local', chapter: 'language', title: 'Start with an ordinary C call', text: `
Message-Driven C retains familiar C expressions, variables, functions, and control flow. The basic difference appears when a call is placed on another node. Start with a call that has no placement suffix: add(20, 22).

Open the workspace, click Compile & Load, then Run to execute this plain C program. main and add both execute on node 0 and return 42. Calling add transfers control within that node and returns to the caller; it does not send a network request. Node 1 has no application task and runs background code.

This compiler supports a documented C subset with extensions; hardware mechanisms and the compiler/runtime together implement the language. The core does not execute C directly.
`, workspace: { file: '/examples/tutorial_local.c', nodes: 2 },
    done: ide => resultIs(ide, '/examples/tutorial_local.c', 42n), layout: () => stage() },
  { id: 'placement', chapter: 'language', title: 'Place a call on another node', text: `
A call suffixed with @node sends work to that node: record(41)@1 runs record on node 1. computer() returns the current node number. The remote handler accesses the destination's local variables, not the caller's copies. Ordinary C pointers do not become shared-memory references across the mesh.

Open the workspace, compile, and run to replay the private-memory example. The void record call sends a one-way message; the value-returning read_observed call supplies a remote result. Node 0 combines its local 7 with node 1's 41 and returns 741. A bare record(41) would change node 0's observed instead.

The compiler turns placement into runtime messages and MDP SEND instructions. The next two lessons separate sending a call from waiting for its result.
`, workspace: { file: '/examples/tutorial_memory.c', nodes: 2 },
    done: ide => resultIs(ide, '/examples/tutorial_memory.c', 741n), observe: ide => memoryObservation(ide, '/examples/tutorial_memory.c'),
    layout: () => stage() },
  { id: 'oneway', chapter: 'language', title: 'Sending does not mean finished', text: `
A remote void call is one-way: it sends a request and lets the caller continue without waiting for the handler to finish. The send itself can stall under backpressure, but completing the send is not an acknowledgement that the destination's work is done.

Open the workspace and compile. Set a gutter breakpoint on int independent = 7. Run to send record(41) to node 1 and stop before that statement. The handler deliberately does a small loop first: node 1's observed is still 0. The caller has reached more local work while the remote handler has yet to perform its store.

Continue to finish. The later read_observed()@1 is a value-returning call; consuming its result supplies synchronization. After record finishes, the result is 7 + 41 = 48. The deliberately delayed handler makes this observation repeatable, rather than relying on a race.
`, workspace: { file: '/examples/tutorial_oneway.c', nodes: 2 },
    done: ide => stoppedAt(ide, '/examples/tutorial_oneway.c', 0), observe: ide => memoryObservation(ide, '/examples/tutorial_oneway.c'),
    layout: () => stage() },
  { id: 'futures', chapter: 'language', title: 'Wait when you need a future', text: `
A value-returning remote call yields a future: a placeholder for a reply that may not have arrived. Assigning the future lets the caller continue; using its value in arithmetic can require waiting. This is different from an ordinary local C call, which finishes before the caller receives its return value.

Open the workspace and compile. Set a gutter breakpoint on return first + second + independent, then Run. Two calls go to node 1 and independent = 7 is computed locally before this statement consumes the results. Continue: the delayed replies supply 11 and 21, and main returns 39. The two requests were issued before either result was needed.

MDP FUT and CFUT tags let hardware detect an unresolved value and fault. Runtime software saves the task, arranges a wake-up, and can let other work run until a reply resolves it. A waiting task does not freeze the mesh; the debugger's Pause does. In WAITING and packet history later, requests, future faults, and replies are separate events.
`, workspace: { file: '/examples/tutorial_futures.c', nodes: 2 },
    done: ide => stoppedAt(ide, '/examples/tutorial_futures.c', 0), layout: () => stage() },
  { id: 'run', chapter: 'inspect', title: 'Run a program', text: `
Now put the pieces together with the original factorial example. Open the workspace, click Compile & Load, then Run on two nodes; the starter program computes factorial(6) and returns 720. Node 1 runs its background loop while node 0 does the application work.

MACHINE reports the result from node 0's word 0x00300. Its cells measure instruction retirement, not useful work or message completion. INSTRUCTIONS shows the selected node's own next position; Listener records compilation, execution, and stop reasons.

You can use Next: Source line to follow C, Instruction to examine its lowering, or Clock cycle to follow the hardware. Run executes the program until a result or a breakpoint.
`,
    workspace: { file: '/home/user/main.c', nodes: 2 },
    done: ide => resultIs(ide, '/home/user/main.c', 720n),
    layout: () => stage() },
  { id: 'edit', chapter: 'inspect', title: 'Change the program', text: `
Edit the source in EDITOR and the machine becomes stale: the loaded image no longer matches the text. Run then reads Compile & Run and does both. Cmd/Ctrl+Enter compiles and loads without running; Cmd/Ctrl+S saves and keeps the previous five versions.

Open the workspace and edit factorial(6) to factorial(5), then click Compile & Load and Run; the main result becomes 120. Compiler errors appear under the text and in the modeline below the editor.
`,
    workspace: { file: '/home/user/main.c', nodes: 2 },
    done: ide => resultIs(ide, '/home/user/main.c', 120n),
    layout: () => stage() },
  { id: 'debug', chapter: 'inspect', title: 'Stop and step', text: `
A source breakpoint stops the machine before the first instruction of that line. Click the editor gutter or press F9 on a line to set one. The DEBUGGER shows the stop reason, the instruction pointer, the four data and four address registers, and memory of the selected node; amber marks values that changed.

Open the workspace, compile, and set a gutter breakpoint on line 6. Click Run to stop at the recursive call. If the program has already finished, use Reset in Debugger first. INSTRUCTIONS highlights the next MDP instruction; hover it to learn what it does. Use Next: Instruction (F10), Clock cycle, or Source line (F11) to compare those three kinds of progress. F5 continues or pauses. Memory watches stop when a word changes.
`,
    workspace: { file: '/home/user/main.c', nodes: 2, tab: 'debugger' },
    done: ide => ide.compiledPath === '/home/user/main.c' && ide.debug?.stopReason.type === 'breakpoint',
    layout: () => stage() },
  { id: 'remote', chapter: 'routing', title: 'Request, handler, and reply', text: `
Sending a call, routing its packet, admitting it to a queue, running its handler, and returning its result are distinct stages. A packet arriving at a node does not imply the handler has finished. A reply that resolves a future is another message in the opposite direction.

Open the workspace, click Compile & Load, remove any breakpoint left from the handler lesson, then Run on two nodes. Node 0 sends record(40) to node 1 and then calls remote_add there; the main result is 142. ROUTING GEOMETRY draws the mesh; select a node to inspect it.

The value-returning request is complete when its reply resolves the result consumed by main. Next, inspect the recorded packets to separate these events from core instruction activity.
`,
    workspace: { file: '/examples/remote_call.c', nodes: 2 },
    done: ide => resultIs(ide, '/examples/remote_call.c', 142n),
    layout: () => stage(leaf('geometry')) },
  { id: 'packets', chapter: 'routing', title: 'Follow the messages', text: `
Every message is captured as a packet: the send instruction, the injection and delivery cycles, the route through the mesh, the handler that ran at the destination, and the reply that resolved a future. PACKETS lists them; a filter such as dst=1 narrows the list.

Open the workspace, compile and run remote_call.c, remove any earlier source breakpoint, then click a packet in PACKETS to inspect it. You can do this even if you jump here directly. ROUTING GEOMETRY draws its observed route in amber and the expected route dashed. Send source and Handler visit the code. WAITING shows queues and outstanding futures for the selected node; CAUSAL HISTORY replays events cycle by cycle and saves traces. Runtime code-fetch messages may appear alongside application requests and replies.
`,
    workspace: { file: '/examples/remote_call.c', nodes: 2 },
    done: ide => ide.compiledPath === '/examples/remote_call.c' && ide.network?.selectedPacket != null,
    layout: () => stage(split('y', .5, leaf('packets'), leaf('geometry'))) },
  { id: 'contention', chapter: 'routing', title: 'Contention on sixteen nodes', text: `
message_hotspot.c runs on a 4 × 4 mesh. Four senders converge on node 5, so its input queue fills and routers upstream block. In ROUTING GEOMETRY link width grows with traffic and red marks a blocked input; WAITING explains each stall for the selected node.

Open the workspace, click Compile & Load, then Run on sixteen nodes. Pause with F5 while it runs to inspect a moment; Continue resumes. Network breakpoints in PACKETS stop on injection, delivery, link transfer, handler entry, or a sustained stall.

Finite queues connect computation to communication: if a destination cannot accept more data, backpressure propagates upstream and a sender can stall. Other nodes may still make progress. This is different from a task waiting for a future, although both can leave a core without useful application work.
`,
    workspace: { file: '/examples/message_hotspot.c', nodes: 16 },
    done: ide => finished(ide, '/examples/message_hotspot.c'),
    layout: () => stage(split('y', .5, leaf('geometry'), leaf('waiting'))) },
  { id: 'project', chapter: 'workspace', title: 'Projects', text: `
A build graph (build.jm) describes outputs and their inputs with Ninja-style statements: jmc compiles one C program to an image, copy produces a file, phony groups targets. BUILD lists every target with its inputs, definition, state, and build reason.

Open the workspace to select /home/user/build.jm and /build/main.image. Click Build, then Load, then Run. Remove any factorial source breakpoint if you want to run to completion. Unchanged targets are skipped by content hash. Edit graph opens the file; Guide opens its manual page.
`,
    workspace: { file: '/home/user/main.c', nodes: 2, tab: 'listener', project: '/home/user/build.jm', target: '/build/main.image' },
    done: ide => ide.imagePath === '/build/main.image' && !!ide.debug?.completed,
    layout: () => stage(leaf('build')) },
  { id: 'graphics', chapter: 'examples', title: 'Pictures from memory', text: `
A program that defines display_width, display_height, and display_pixels turns part of its memory into a picture. GRAPHICAL DISPLAY reads those words while the machine runs, shows a mosaic when several nodes draw, and saves a PNG.

Open the workspace to select the target from build-graphics.jm. Click Build, then Load, then Run on four nodes. Each node renders one 16 × 16 tile; the picture fills in while the machine runs. Click a pixel to see its address and value.

The tiles need little communication once work has been placed. Contrast that with the neighboring-tile exchanges in the next examples. Loading the image prepares the machine; the result of 1,024 pixels marks this demonstration's computation complete.
`,
    workspace: { file: '/examples/distributed_mandelbrot.c', nodes: 4, project: '/home/user/build-graphics.jm', target: '/build/mandelbrot.image' },
    done: ide => ide.imagePath === '/build/mandelbrot.image' && !!ide.debug?.completed,
    layout: () => stage(split('y', .5, leaf('build'), leaf('display'))) },
  { id: 'life', chapter: 'examples', title: 'Life across sixteen nodes', text: `
life16.c runs Conway's Game of Life on a 16 × 16 torus split into sixteen 4 × 4 tiles, one per node of the 4 × 4 mesh. Node 15 runs the game as one long call from main: each generation it collects every tile's four edges, packed into one word, with a value-returning call, assembles each tile's halo from its neighbours' edges, and delivers it with a one-way message. Receiving that halo is what makes a tile compute and draw its next generation; a tile never sends on its own, so no node is ever flooded.

Open the workspace, compile, and run on sixteen nodes to start the game. GRAPHICAL DISPLAY shows the whole board as a mosaic of the sixteen tiles; ROUTING GEOMETRY shows the traffic to and from node 15. The lesson counts as done after the first generations; the game keeps running until the next lesson pauses it. The result is the number of live cells after 16 generations, which a plain single-machine simulation of the same rules reproduces exactly. Every C statement costs hundreds of cycles on this machine, so a generation takes a few seconds.

Each tile needs its neighbors' boundary values from the same generation. The coordinator's edge collection and halo messages provide that coordination; independently running a core faster cannot replace it. The lesson's Done marker means the demonstration has started evolving, not that all 16 generations have finished.
`,
    workspace: { file: '/examples/life16.c', nodes: 16 },
    done: ide => evolved(ide, '/examples/life16.c', 900000n),
    layout: () => stage(leaf('display')) },
  { id: 'heat', chapter: 'examples', title: 'A heat equation on the mesh', text: `
heat16.c solves the steady heat equation on a 16 × 16 plate by Jacobi relaxation, the computation the original J-Machine programmers benchmarked. Two spots are held hot and two cold; every sweep replaces each other cell with the mean of its four neighbours. Tiles hand node 15 their edge temperatures, four 8-bit values per word, as in the last lesson, and node 15 delivers each tile the temperatures around it. The result is the total change of the last of 24 sweeps summed over the plate, so it reports how far the plate is from steady state.

Open the workspace, compile, and run on sixteen nodes to start the solver. The display maps temperature from black through red to amber; watch the heat spread from the sources and the residual fall. Pause with F5 to inspect a sweep in PACKETS and WAITING, then Continue.

As in Life, each sweep requires coordinated boundary data. Its final result measures the last sweep's change, rather than a count of packets or retired instructions. You can choose Next at any time; main returns only after all 24 sweeps.
`,
    workspace: { file: '/examples/heat16.c', nodes: 16 },
    done: ide => evolved(ide, '/examples/heat16.c', 900000n),
    layout: () => stage(leaf('display')) },
  { id: 'mesh', chapter: 'examples', title: 'The full mesh', text: `
The largest configuration is 8 × 8 × 8 = 512 nodes. Its simulator is a 40 MB WebAssembly module; the status line reports the download and the load. mesh512.c sums an array on node 511, the far corner, and returns 539.

Open the workspace, compile, and run on 512 nodes to start the full-mesh example. ROUTING GEOMETRY switches to the 3D overview when its window is too narrow for eight slices; Go to node jumps to a number or x,y,z coordinate. The full model is much slower than the small meshes.
`,
    workspace: { file: '/examples/mesh512.c', nodes: 512 },
    done: ide => resultIs(ide, '/examples/mesh512.c', 539n),
    layout: () => stage(leaf('geometry')) },
  { id: 'files', chapter: 'workspace', title: 'Your files', text: `
Everything lives in this browser's storage for this site. /home/user holds your files and projects; /examples is read-only; /build holds generated images. Save keeps the previous five versions, Trash is recoverable, and Export downloads a file or a snapshot of the whole filesystem.

Open the workspace. In Listener enter cp /examples/remote_call.c /home/user/my_remote_call.c, then edit /home/user/my_remote_call.c to open your editable copy. FILES lists the tree; Listener accepts ls, cd, cp, mv, edit, and trash with the same pathnames.

Listener output can carry typed objects, called presentations in Lisp-machine interfaces: a pathname, node, or source location keeps its meaning when displayed. Click one to visit it; Shift-click inserts its representation into the command line. This connects browsing output to the next command without copying plain text.
`,
    workspace: { file: '/examples/remote_call.c', nodes: 2, tab: 'listener' },
    done: ide => ide.fs.files().some(path => /^\/home\/user\/my_remote_call.*\.c$/.test(path)),
    layout: () => stage(leaf('files')) },
  { id: 'desktop', chapter: 'workspace', title: 'The whole desktop', text: `
Windows lists every tool; Layout has presets for development, editing, debugging, building, network, graphics, and documentation. Drag a title bar onto the edge of another window to move it, drag dividers to resize, double-click a title to zoom.

The editor buffer and modeline, named commands, and context-sensitive help follow the integrated environment tradition associated with Lisp machines and Emacs. M-x (Alt+X or Cmd/Ctrl+Shift+P) searches every command and pathname and says why an action is unavailable. F1 opens the manual for whatever has focus. Type help in the listener for its commands. Choose Next lesson to finish the tutorial and arrange the tools for your own work; reopen this tour any time with Tutorial in the header or the tutorial command.
`,

    layout: () => stage() },
];

export const STEPS = CHAPTERS.flatMap(chapter => LESSONS.filter(step => step.chapter === chapter.id));
