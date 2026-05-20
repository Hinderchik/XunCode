// Minimal plugin example. The runtime calls `exports.activate(vscode)` once
// the host is ready. The `vscode` object is the API surface — see the bundled
// docs (Settings → Plugins → Документация по плагинам) for the full reference.

exports.activate = (vscode) => {
  vscode.commands.registerCommand('hello.say', () => {
    vscode.ui.showMessage('Hello from plugin!');
  });

  vscode.hooks.onSave((path) => {
    vscode.ui.showMessage('Saved: ' + path);
  });
};
