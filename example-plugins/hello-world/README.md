# Hello World Plugin

A minimal VScode Mobile plugin you can clone and modify.

## Try it

1. Push this folder to a public GitHub repo (or fork the parent repo and point at this directory).
2. In the app: **Marketplace → Submit** (or use the in-app installer once it's published).
3. After install, run the **`hello.say`** command from the plugin runtime — you should see a snackbar.

## What it does

- Registers one command (`hello.say`) that pops a message.
- Subscribes to `onSave` and shows the saved file path.

That's the whole API in 10 lines. See [`assets/plugin-docs.html`](../../assets/plugin-docs.html) for everything else.
