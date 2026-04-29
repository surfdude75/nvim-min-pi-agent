# Agent instructions

This repository contains a minimal Neovim plugin for localized edits through
Pi. Keep the code small, readable, and easy to audit.

## Goals

- Use the local `pi` CLI rather than embedding provider SDKs.
- Send only the selected text and the user's instruction.
- Keep Pi in print mode with no tools, no session, and no context files.
- Avoid heavy UI dependencies. Prefer built-in Neovim Lua APIs.
- Add comments only when the code is not obvious.

## Code style

- Write Lua for the plugin.
- Keep public functions in `lua/min_pi_agent/init.lua` simple.
- Avoid background state unless it is necessary for an active request.
- Preserve the default model and thinking options unless asked to change them.
- Do not add network code outside calls to the `pi` executable.

## Validation

After changing Lua files, run:

```sh
nvim --headless -u NONE \
  -c 'set rtp+=.' \
  -c 'runtime plugin/min_pi_agent.lua' \
  -c 'lua require("min_pi_agent")' \
  -c 'qa'
```

After changing Markdown files, run a Markdown linter when available.
