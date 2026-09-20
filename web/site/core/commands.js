// Listener commands are application operations, never operating-system commands.
export function parseCommand(text) {
  const words = []; let word = '', quote = null, escaped = false, started = false;
  for (const char of text.trim()) {
    if (escaped) { word += char; escaped = false; started = true; continue; }
    if (char === '\\' && quote !== "'") { escaped = true; started = true; continue; }
    if (quote) { if (char === quote) quote = null; else word += char; continue; }
    if (char === '"' || char === "'") { quote = char; started = true; continue; }
    if (/\s/.test(char)) { if (started) { words.push(word); word = ''; started = false; } }
    else { word += char; started = true; }
  }
  if (quote || escaped) throw new Error('Unfinished quote or escape in command.');
  if (started) words.push(word);
  return words;
}
