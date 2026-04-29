# nvim-min-pi-agent

A tiny Neovim plugin that asks the local `pi` CLI to rewrite the current
visual selection.

The goal is small, localized edits with little context and easy-to-read code.
The plugin sends Pi only:

- your instruction;
- the selected text;
- the buffer file name;
- the filetype;
- the selected line range.

It also runs Pi with no tools, no session, and no context files.

## Requirements

- Neovim 0.9 or newer.
- The Pi coding agent CLI available as `pi`.

Install Pi and authenticate it first:

```sh
npm install -g @mariozechner/pi-coding-agent
pi
```

Inside Pi, run:

```text
/login
```

Choose your provider. OpenAI ChatGPT or an OpenAI API key both work through
Pi. If you prefer an API key, set it before starting Neovim:

```sh
export OPENAI_API_KEY=sk-...
```

## Install with LazyVim

Create a plugin spec such as
`~/.config/nvim/lua/plugins/min-pi-agent.lua`:

```lua
return {
  {
    "surfdude75/nvim-min-pi-agent",
    main = "min_pi_agent",
    opts = {
      default_model = "openai-codex/gpt-5.5",
      default_thinking = "medium",
    },
    keys = {
      {
        "<leader>as",
        ":<C-u>MinPiAgentEditSelection<CR>",
        mode = "x",
        desc = "Pi edit selection",
      },
    },
  },
}
```

## Usage

1. Select text in visual mode.
2. Press `<leader>as`.
3. In the popup, describe the edit.
4. Press `<C-s>` to submit.

In the popup:

- type the requested change in the body;
- press `<C-l>` to select a model from `pi --list-models gpt`;
- press `<C-t>` to select the thinking level;
- press normal mode `<CR>` to submit;
- press normal mode `q` or `<Esc>` to cancel.

If `<C-s>` is captured by your terminal, use normal mode `<CR>` instead.
The success or failure notification includes the elapsed Pi request time.

The plugin remembers the last model and thinking value only in the current
Neovim process. Restarting Neovim resets them to the configured defaults.

If the original buffer changes while Pi is working, the replacement is
cancelled. This avoids applying stale output over text that you already edited.

## Commands

- `:MinPiAgentEditSelection` edits the current visual selection.
- `:MinPiAgentCheck` checks that the `pi` command is available.
- `:MinPiAgentLogin` opens Pi in a terminal split so you can run `/login`.
- `:MinPiAgentLogCommand on` logs the exact Pi command before each request.
- `:MinPiAgentShowLastCommand` prints the last Pi command again.

## Configuration

Default options:

```lua
require("min_pi_agent").setup({
  default_model = "openai-codex/gpt-5.5",
  default_thinking = "medium",
  pi_cmd = "pi",
  extra_args = {},
  keymap = nil,
  model_list_search = "gpt",
  strip_trailing_newline = true,
  log_cmd = false,
})
```

Set `model_list_search = ""` if you want `<C-l>` to list all Pi models.

Optional prompt customization: `agent_prompt` replaces the default instruction
lines sent before the request and selected text. Do not add it unless you want
to customize the agent behavior.

```lua
require("min_pi_agent").setup({
  agent_prompt = {
    "Rewrite only the selected text.",
    "Return replacement text only.",
    "Do not include Markdown fences or explanations.",
  },
})
```

The user request, file metadata, and selected text are still appended after
these lines.

The provider prefix matters. A bare model such as `gpt-5.5` can resolve to a
provider you have not authenticated, such as Azure OpenAI. If Pi lists your
desired model with a provider prefix, use that exact value. For example:

```lua
require("min_pi_agent").setup({
  default_model = "openai-codex/gpt-5.5",
})
```

You can also set the visual keymap from setup:

```lua
require("min_pi_agent").setup({
  keymap = "<leader>as",
})
```

LazyVim users usually prefer the `keys` section in the plugin spec.

## What gets sent to Pi

For every request, the plugin runs a command similar to:

```sh
pi \
  --print \
  --no-session \
  --no-tools \
  --no-context-files \
  --no-extensions \
  --no-skills \
  --no-prompt-templates \
  --model openai-codex/gpt-5.5 \
  --thinking medium
```

The prompt is passed on standard input. Pi then sends the prompt to the
selected model provider.

## Troubleshooting

To compare the command used by the default model and the model picker, run:

```vim
:MinPiAgentLogCommand on
```

Then try both flows and inspect `:messages`. You can also rerun:

```vim
:MinPiAgentShowLastCommand
```

## Current limits

- Visual block selections are not supported.
- There is no diff preview yet.
- The plugin expects Pi to return replacement text only.
- Authentication is handled by Pi, not by this plugin.
