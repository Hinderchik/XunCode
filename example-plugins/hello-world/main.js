// Minimal VScode Mobile plugin.
// The runtime calls `exports.activate(vscode)` once the host is ready.
// See /assets/plugin-docs.html or the in-app docs for the full API.

exports.activate = (vscode) => {
  vscode.commands.registerCommand('hello.say', () => {
    vscode.ui.showMessage('Hello from plugin!');
  });

  vscode.hooks.onSave((path) => {
    vscode.ui.showMessage('Saved: ' + path);
  });
};
