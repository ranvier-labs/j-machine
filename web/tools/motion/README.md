# Lookbook: a produced motion piece about the J-Machine

A short film in the style of a fashion lookbook: a title, eight numbered
"looks", an end card. Every look is one subject drawn from real machine data,
with a monospace HUD layer (tracking brackets, labels, a split-flap board, a
stats ticker, timecode, a waveform of the soundtrack), lyric-style captions
that appear word by word, and bold display type. Film grain, a vignette and a
one-pixel chroma shift are added when the frames are encoded.

## Pipeline

    node tools/motion/capture.mjs            # runs the example programs headlessly → out/motion/data/*.json
    python3 tools/motion/music.py 104 128    # placeholder 128 BPM track → out/motion/music.wav + music.json
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

- Cuts sit on bars of the 128 BPM grid (`BAR` in `piece.js`); every look has a
  `dur` in bars, an `art(u, dur)` drawing the imagery on the canvas and a
  `hud(u, t, dur)` returning the overlay for local time `u`.
- To use photographs or generated stills instead of drawn imagery, load them
  like the workbench still (`data.workbench`) and draw them in a look's `art`
  with the same slow camera push; the HUD layer needs no change.
- The soundtrack is a placeholder. The captions in `piece.js` double as a
  lyric sheet: generate a track from them (any music model), save it as
  `out/motion/music.wav`, write an RMS envelope to `music.json` at 30 Hz (the
  end of `music.py` shows the format), and re-render.

## Lyric sheet

    J-Machine. Fall Winter ninety-one. Collection of one.
    Look 01. Thirty-six bits to a word. Four of them say what it is.
    Look 02. Five hundred twelve nodes in a cube. Eight by eight by eight. Two cycles a hop.
    Look 03. Four senders, thirty-two messages, one address. Everybody waits their turn.
    Look 04. Sixteen tiles trade their edges. Sixteen generations of life. Fourteen survive.
    Look 05. Heat leaves the hot corner. One sweep at a time. Residual one ninety-six.
    Look 06. Four nodes split the Mandelbrot set. Nobody shares a byte.
    Look 07. The whole machine, gate for gate, inside a browser tab.
    Look 08. Message-driven C. Call a function at a node. That is the whole language.
    End of show.
