# Historical compiler and program evidence

The original software distribution has not yet been located. This directory records
the primary artifacts that were found, without presenting reconstructed material as
original source code.

## Message-Driven C

Daniel Maskit's Caltech master's thesis, *A Message-Driven Programming System for
Fine-Grain Multicomputers* (1994), current archive DOI `10.7907/Z9J38QKJ`
(legacy CaltechTHESIS DOI `10.7907/z35v-1x17`), documents a GNU C
retarget plus a linker, archiver, loader, and approximately 200-word microkernel.
The open-access CaltechAUTHORS record and its archived PDF are:

<https://authors.library.caltech.edu/records/c9tkh-yvy68>

<https://authors.library.caltech.edu/records/c9tkh-yvy68/files/postscript.pdf>

The older CaltechTHESIS path resolves to the same document:

<https://thesis.caltech.edu/6912/01/Maskit_d_1994.pdf>

SHA-256 of the repository PDF independently retrieved from the current archive
on 2026-08-17 (and of the older repository copy retrieved on 2026-08-16):

`216537b63e215fe06491dec72720898646ae263c8c8ee81b03b8e46ce8b8f3a4`

Relevant original examples:

- Figure 2.1: recursive factorial in Message-Driven C, whose recursive call is
  mapped to the next computer with the `@next` extension.
- Figure 3.3: a `Hop` program that traverses every computer repeatedly.
- Figures 4.1-4.3: C producer code and 108 instructions of generated MDP
  assembly, including heap frames, tagged message headers, and direct sends.
- Figures 5.1-5.2: one-way and two-way producer-consumer benchmarks.
- Figures 5.3-5.5: a parallel Dirichlet/Laplace application and its message
  handlers.

Figure 6.1 is deliberately not included in that list. It illustrates a proposed
higher-level stream language with `in stream`, `out stream`, parallel blocks,
and list-pattern notation. Section 6.4 presents this as language-design work on
top of the systems-programming layer, not as a compilable program in the GNU-C
retarget documented in Chapters 3-5. It is therefore evidence for a possible
future frontend rather than a missing Message-Driven C regression.

Section 6.3.1 states that the MDP is addressable in 32-bit words and that the
compiler represents each character with one full word, with a separate packed
string library for four 8-bit codes per word. The clean-room compiler therefore
uses the target-consistent word-scalar ABI: all `char`, `short`, `int`, and
`long` objects occupy one 32-bit payload word while preserving their distinct C
ranks and signedness. This is not presented as byte-addressable storage that the
hardware does not provide.

The new `compiler/examples/factorial.c` deliberately removes the remote mapping
annotation and is labeled as a single-node adaptation. It is not claimed to be the
historical source file.

`compiler/examples/historical_factorial.c` transcribes Figure 2.1's function
body and `factorial(n-1)@next` placement. The executable harness adds the
definition `next = (computer()+1)%computers()` and a `main` that evaluates
`factorial(6)`; those additions are clean-room test scaffolding, not words
printed in the figure. `compiler/examples/historical_hop.c` preserves Figure
3.3's four-tour control and remote `Hop(sizeof(int),rep)@next` communication.
Because the new bare-metal targets have no host `printf`, its printed value is
recorded in node-local `hop_visits`/`hop_last` globals and completion in
`hop_done`. The comments in both files state these adaptations explicitly.

`compiler/examples/historical_producer_one_way.c` is an executable clean-room
transcription of Figure 5.1's producer, eight-word bulk argument, void remote
consumer, and receive counter. The printed benchmark sends 1,000,000 messages
to computer 8; the bounded regression sends 40 to logical rank 1. It replaces
`exit` with an observable completion word, adds a payload checksum so the test
proves all eight words were read, and relies on the MDC runtime's automatic
bulk-block reclamation instead of the original explicit `msgFree` call.

`compiler/examples/historical_producer_two_way.c` preserves Figure 5.2's two
distinct loops: the first issues every remote call into an array of deferred
return values and the second reads that array to force completion. The printed
benchmark uses 2,500 sets of 40 calls to computer 8; the exact regression uses
two sets of eight calls to rank 1. The original consumer returns its local
zero-valued `j`; the added receive count and payload checksum are observable
bare-metal instrumentation. Both simulators require all 16 arrivals, a zero
return sum, 14 process-level FUT faults, and reclaimed process/bulk blocks.

Figures 5.3-5.5 provide the parallel Dirichlet decomposition and message-handler
pseudocode rather than a complete compilable source file.
`compiler/examples/historical_dirichlet.c` is therefore labeled a clean-room
executable realization, not a transcription. It retains distributed node
initialization, the initial global-norm barrier, neighbor-face sends, receive
counting, a norm barrier after every timestep, and the published
terminate-or-restart control path. A four-node ring replaces the unavailable
file-loaded graph, and deterministic integer smoothing replaces the unavailable
numerical library. The regression terminates only after all four nodes converge
to value 5 at step 5 and the coordinator receives final value/step checksums of
20. `bazel test //compiler:historical_dirichlet_rtl_test` checks those exact words independently in
the golden C++ model and a four-node Verilator mesh.

The reduced iteration counts above bound regression time; they do not alter
message envelopes, future forcing, handler priority, routing, or reclamation.
The original constants and each adaptation remain explicit here and in the
source rather than being presented as recovered source code.

Figures 4.2-4.3 also establish the wire layout now used by the new compiler's
MDC runtime: a tagged message header, function identifier, receiver temporary,
return length/computer/address, logical argument count, then a length word and
payload for each logical argument. The figure's one eight-word array argument
therefore produces a sixteen-word message including the header. The new
implementation uses the same envelope for both length-one scalars and
length-delimited `(int length, int *data)` bulk arguments; its source and
generated images remain clean-room work.

The clean-room runtime also follows Figures 4.5-4.6 for futures: a FUT fault
links a saved process header into the unresolved word and executes `SUSPEND`;
the SET handler writes the result and sends wake messages that restore FIP and
the saved register state.

## Other original environments

The archived J-Machine project page states that Concurrent Smalltalk and
Message-Driven C were the two supported programming environments:

<https://web.mit.edu/sctv/old_sites/20011127005141/http%3A/cva.stanford.edu/j-machine/cva_j_machine.html>

Richard Lethin's 1997 MIT thesis, *Message-Driven Dynamics*, credits Waldemar
Horwat with the CST compiler, COSMOS, and an MDP simulator, and credits the
Caltech group with the GNU C port. The Bitsavers copy is:

<https://www.bitsavers.org/pdf/mit/lcs/tr/MIT-LCS-TR-0721.pdf>

## Recovery status

Searches covered the original MIT/Stanford project pages, CaltechTHESIS, MIT
DSpace/Bitsavers, the Internet Archive index, and public source-code search. The
papers, listings, and example descriptions survive; no buildable MDC/CST/COSMOS
source archive was found. Any later recovery should be stored verbatim under a
new `upstream/` directory with its URL, retrieval date, checksum, and license.
