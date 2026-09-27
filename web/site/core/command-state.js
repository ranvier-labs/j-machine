import { projectSelection } from './project.js';

// Shared by buttons, M-x, keyboard dispatch, and window toolbars. A reason
// describes the same unavailable action wherever it is presented.
export function commandState(ide, id) {
  const running = !!ide.debug?.running, ready = ide.ready ? '' : 'Wait for the environment to finish starting.';
  const idle = ide.busy ? 'Wait for the current operation to finish.' : running ? 'Pause the machine first.' : '';
  const machine = ide.machineReason();
  let label, detail = '', reason = '';
  switch (id) {
    case 'new-file': case 'new-directory': case 'find-file': case 'examples': reason = ready; break;
    case 'save': case 'save-as': reason = !ide.activePath ? 'Select a buffer first.' : ''; break;
    case 'compile':
      label = 'Compile & Load'; reason = ready || idle || (!/\.c$/.test(ide.activePath ?? '') ? 'Select a C source buffer.' : '');
      detail = `Compile and load ${ide.activePath ?? 'the active C buffer'} for ${ide.nodes} nodes`; break;
    case 'build': case 'load-project':
      reason = !ide.builder ? 'Wait for the build system to finish starting.' : idle;
      if (!reason) {
        try {
          const selection = projectSelection(ide);
          detail = `${id === 'build' ? 'Build' : 'Load'} ${selection.selected.join(', ')} from ${ide.buildFile}`;
          if (id === 'load-project' && !selection.images.length) reason = 'Build the selected target before loading its image.';
        } catch (error) { reason = error.message; }
      }
      break;
    case 'build-graph': reason = ready || (!ide.fs.exists(ide.buildFile) ? 'The active build graph is missing.' : ''); break;
    case 'use-buffer-build':
      reason = !ide.builder ? 'Wait for the build system to finish starting.' : ide.busy ? idle : !/\.jm$/.test(ide.activePath ?? '') ? 'Open a build graph buffer.' : '';
      if (!reason) { try { ide.builder.graph(ide.activePath); } catch (error) { reason = error.message; } }
      if (!reason && ide.activePath === ide.buildFile) reason = 'This is already the active project graph.';
      break;
    case 'load-built-image': reason = ready || idle || (!ide.fs.files().some(path => ide.fs.stat(path).metadata?.artifact) ? 'Compile or build an image first.' : ''); break;
    case 'continue': {
      // Run compiles the active C buffer when it is not the loaded program.
      // A C buffer opened after the last load compiles on Run, unless a paused
      // program is mid-execution; a stale loaded buffer recompiles. Explicit
      // loads after a buffer switch keep Run on the loaded image.
      const path = ide.activePath ?? '', isC = /\.c$/.test(path), midRun = !!ide.debug?.image && !ide.debug.completed && ide.debug.snapshot?.cycle > 0n;
      const recompile = isC && (path !== ide.compiledPath ? ide.activatedAt > ide.installedAt && !midRun : ide.stale && !!ide.debug?.image);
      if (running) { label = 'Pause'; detail = 'Pause execution'; }
      else if (recompile) { label = 'Compile & Run'; reason = ready || idle; detail = `Compile ${path} for ${ide.nodes} nodes, load it, and run`; }
      else {
        label = ide.debug?.snapshot?.cycle > 0n ? 'Continue' : 'Run';
        reason = machine || (ide.debug?.completed ? 'Main has returned. Use Restart to run this image from the beginning.' : '');
        detail = `${label} ${ide.imagePath ?? 'the loaded image'}${ide.compiledPath ? ` (${ide.compiledPath})` : ''}`;
      }
      break; }
    case 'pause': reason = running ? '' : 'The machine is already paused.'; break;
    case 'step-source': case 'step-instruction': case 'step-cycle': case 'step-100': case 'reset': case 'restart':
      reason = machine || (running ? 'Pause the machine first.' : '');
      detail = `${({'restart':'Reset and run','reset':'Reset without running','step-source':'Step to the next source line in','step-instruction':'Step one instruction in','step-cycle':'Step one cycle in','step-100':'Step 100 cycles in'})[id]} ${ide.imagePath ?? 'the loaded image'}${ide.compiledPath ? ` (${ide.compiledPath})` : ''}`;
      break;
    case 'breakpoint': reason = ready || (!/\.c$/.test(ide.activePath ?? '') ? 'Select a C source buffer.' : ''); break;
    case 'editor-commands': reason = ready; break;
    case 'jump-node': case 'packet-filter': case 'trace-save': case 'trace-previous': case 'trace-next':
      reason = !ide.network ? 'Load a machine or open a trace first.' : ''; break;
    case 'network-breakpoint': reason = !ide.debug || ide.archiveTrace ? 'Load a live machine first.' : ''; break;
    case 'trace-open': reason = idle; break;
    case 'trace-live': reason = !ide.debug ? 'Load a live machine first.' : ''; break;
    case 'display-save': reason = !ide.debug || ide.busy || running ? 'Load and pause a machine first.' : ''; break;
  }
  return { ...(label ? { label } : {}), enabled: !reason, reason, ...(detail ? { detail } : {}) };
}
