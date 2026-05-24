// XunCode Plugin API Demo — v2.0
// Shows the full ctx (vscode / xuncode) API surface

exports.activate = (vscode) => {
  const { editor, ui, fs, terminal, process, http, storage, settings, workspace, commands, hooks } = vscode;

  // ── Commands ──────────────────────────────────────────────────────
  commands.registerCommand('demo.greet', () => {
    const lang = editor.getLanguage();
    ui.showMessage(`Hello! Current language: ${lang}`);
  });

  commands.registerCommand('demo.insertDate', async () => {
    const now = new Date().toLocaleString();
    editor.insertText(`// ${now}\n`);
  });

  // ── File System ───────────────────────────────────────────────────
  commands.registerCommand('demo.fsDemo', async () => {
    const root = fs.getRoot();
    const readmePath = root + '/Projects/HELLO.md';

    try {
      // write
      await fs.writeFile(readmePath, '# Hello from XunCode plugin!\n');
      // read
      const content = await fs.readFile(readmePath);
      // stat
      const stat = await fs.stat(readmePath);
      // list
      const listing = await fs.listDir(root + '/Projects');

      ui.showMessage(`FS demo OK — wrote ${stat.size} bytes, ${listing.length} files in Projects/`);
    } catch (e) {
      ui.showError('FS demo: ' + e.message);
    }
  });

  // ── Terminal ──────────────────────────────────────────────────────
  commands.registerCommand('demo.terminalDemo', async () => {
    const result = await terminal.run('uname -a && echo "Hello from proot!"', fs.getRoot());
    ui.showMessage(`Terminal [exit=${result.exitCode}]: ${result.stdout.trim()}`);
  });

  // ── Process ───────────────────────────────────────────────────────
  commands.registerCommand('demo.processDemo', async () => {
    const result = await process.exec('ls -la /data/data/', { cwd: '/' });
    ui.showMessage(`Process output lines: ${result.stdout.split('\n').length}`);
  });

  // ── HTTP ──────────────────────────────────────────────────────────
  commands.registerCommand('demo.httpDemo', async () => {
    try {
      const res = await http.get('https://httpbin.org/get');
      ui.showMessage(`HTTP ${res.status}: ${res.body.substring(0, 100)}…`);
    } catch (e) {
      ui.showError('HTTP demo: ' + e.message);
    }
  });

  // ── Settings ──────────────────────────────────────────────────────
  commands.registerCommand('demo.settingsDemo', async () => {
    const all = settings.getAll();
    ui.showMessage(`Current theme: ${all.theme}, fontSize: ${all.fontSize}`);
  });

  // ── Storage (text + binary) ───────────────────────────────────────
  commands.registerCommand('demo.storageDemo', async () => {
    await storage.set('counter', '42');
    const val = await storage.get('storage.get', 'counter');
    // binary
    const bytes = new Uint8Array([72, 101, 108, 108, 111]); // "Hello"
    await storage.setBinary('greeting', bytes);
    const restored = await storage.getBinary('greeting');
    ui.showMessage(`Storage: counter=${val}, greeting bytes=${restored ? restored.length : 0}`);
  });

  // ── Editor ────────────────────────────────────────────────────────
  commands.registerCommand('demo.editorDemo', async () => {
    const lines = editor.getLines();
    const cursor = editor.getCursorPosition();
    editor.formatDocument();
    ui.showMessage(`Lines: ${lines.length}, cursor: L${cursor.line}:C${cursor.column}`);
  });

  // ── Hooks ─────────────────────────────────────────────────────────
  hooks.onSave((path) => {
    ui.showMessage('📁 Saved: ' + path.split('/').pop());
  });

  hooks.onEditorChange((content) => {
    // Could update a status bar, lint, etc.
  });

  // ── Welcome message ───────────────────────────────────────────────
  ui.showMessage('XunCode Plugin API Demo loaded! Use Command Palette → search "demo."');
};
