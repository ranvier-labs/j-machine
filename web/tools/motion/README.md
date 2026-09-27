# Lookbook: a produced motion piece about the J-Machine

A short film in the style of a fashion lookbook: a title, eight numbered
"looks", an end card. Every look is one subject drawn from real machine data,
with a monospace HUD layer (tracking brackets, labels, a split-flap board, a
stats ticker, timecode, a waveform of the soundtrack), lyric-style captions
that appear word by word, and bold display type. Film grain, a vignette and a
one-pixel chroma shift are added when the frames are encoded.

## Pipeline

    node tools/motion/capture.mjs            # runs the example programs headlessly → out/motion/data/*.json
    python3 tools/motion/music.py 60 128     # 60-bar sectioned 128 BPM track → out/motion/music.wav + music.json
    node tools/motion/render.mjs --stills 3,22,45   # PNG frames at those seconds, for review
    node tools/motion/render.mjs             # every frame at 30 fps → out/lookbook.mp4

`capture.mjs` records, per program, retired instructions and message
traffic per node every few thousand cycles, and every change of a node's
framebuffer. `piece.js` turns that into the looks; `scene.html` is the stage
and the HUD styles; `render.mjs` screenshots each instant with Playwright
(Chrome, 1920×1080) and hands the frames to ffmpeg with the music.

Node 20 or newer from `/opt/homebrew/bin` (Playwright and the simulator need
it), Chrome, ffmpeg and numpy. Rendering the 104-second piece takes about
seven minutes; capturing the 512-node programs takes longer than the rest
combined and is bounded by the `budget` seconds in `capture.mjs`.

## Changing the piece

- Cuts sit on bars of the 128 BPM grid (`BAR` in `piece.js`); every look has
  `bars`, an `art(u, dur)` drawing the imagery on the canvas and a
  `hud(u, t, dur)` returning the overlay for local time `u`.
- To use photographs or generated stills instead of drawn imagery, load them
  like the workbench still (`data.workbench`) and draw them in a look's `art`
  with the same slow camera push; the HUD layer needs no change.
- The soundtrack is generated and sectioned but still a stand-in for a
  produced track. The lyric sheet below is the brief: generate a track from it (any music model), save it as
  `out/motion/music.wav`, write an RMS envelope to `music.json` at 30 Hz (the
  end of `music.py` shows the format), and re-render.

## Structure

Three acts on a 60-bar, 128 BPM grid (112.5 s). The soundtrack's sections
follow them: a quiet intro with clock ticks under Act I, a build and a drop
into Act II at bar 12, a break for the Life and heat looks at bar 28, a
second drop with a lead line for Act III at bar 36, and an outro from bar 52.

| Bars | Act | Look | Point |
|---|---|---|---|
| 0–4 | | Title | one idea: a message should cost almost nothing |
| 4–12 | I · The cost | 01 Waiting | in 1988 one send cost hundreds of instructions; the processor waited |
| 12–29 | II · The machine | 02 Word, 03 Mesh, 04 Dispatch, 05 Hotspot | tagged words, 512 nodes two cycles a hop, handler runs 5 cycles after the last word (measured), contention shown |
| 29–36 | II | 06 Life, 07 Heat | real programs on the real cycles |
| 36–53 | III · Yours | 08 In the tab, 09 The call, 10 Nothing hidden, 11 Free | gate for gate in a browser, Message-Driven C, every packet visible, Apache 2.0 |
| 53–60 | | End | start at j-machine.pages.dev |

## Lyric sheet

    A machine from 1991, built on one idea. A message should cost almost nothing.
    Act one. The cost.
    Look 01. On the machines of its day, sending one message cost hundreds of instructions. The processor waited.
    Act two. The machine.
    Look 02. Thirty-six bits to a word. Four of them say what it is. The hardware knows a message when it sees one.
    Look 03. Five hundred twelve nodes in a cube. Eight by eight by eight. Two cycles a hop.
    Look 04. The handler runs five cycles after the last word leaves the sender. Twenty-one hops away. Nobody polled. Nobody copied.
    Look 05. Four senders, thirty-two messages, one address. Contention is visible, not hidden.
    Look 06. Sixteen tiles trade their edges. Sixteen generations of life. Fourteen survive.
    Look 07. Heat leaves the hot corner, one sweep at a time. Real programs. Real cycles.
    Act three. Yours.
    Look 08. The whole machine, gate for gate, inside a browser tab. No hardware. No install.
    Look 09. Write Message-Driven C. Call a function at a node. That is the whole language.
    Look 10. Every packet, every cycle, every register. Nothing is hidden.
    Look 11. Open source. Apache 2.0. Free. The RTL, the compiler, the workbench.
    Start at j-machine.pages.dev. End of show.
