# MmdToImg

Render Mermaid diagrams on save and preview the correct theme in Neovim.
Each `.mmd` file generates an adaptive `.svg`, a `.light.png`, and a `.dark.png` beside the source.
Use a normal Markdown image link to the SVG.
Browsers select its theme with `prefers-color-scheme`.
The optional Snacks integration displays the PNG that matches `vim.o.background`.

![Mermaid diagram preview in Neovim](assets/neovim-preview.png)

## Prerequisites

- Neovim 0.10 or later.
- Mermaid CLI (`mmdc`) on your PATH: `npm install -g @mermaid-js/mermaid-cli`.
- Optional image previews: Snacks, a Markdown Treesitter parser, and a supported terminal such as Ghostty or Kitty.

## Installation

### lazy.nvim

The plugin lives in `libs/MmdToImg`.
Add that directory to Neovim’s runtime path before you call `setup()`.
The runtime path is the list of directories that Neovim searches for plugins.

Add this plugin specification:

```lua
{
  "skapoor8/MmdToImg",
  version = "*",
  lazy = false,
  opts = {},
  config = function(plugin, opts)
    vim.opt.runtimepath:append(plugin.dir .. "/libs/MmdToImg")
    require("mmdtoimg").setup(opts)
  end,
}
```

### vim-plug

Add the plugin to your vim-plug block and run `:PlugInstall`:

```vim
call plug#begin(stdpath('data') . '/plugged')
Plug 'skapoor8/MmdToImg', { 'tag': '*' }
call plug#end()
```

After `plug#end()`, configure the plugin:

```lua
local root = vim.fn.stdpath("data") .. "/plugged/MmdToImg"
vim.opt.runtimepath:append(root .. "/libs/MmdToImg")
require("mmdtoimg").setup()
```

If you use a different vim-plug installation directory, change `root` to match it.

### Native Git packages

Clone the plugin into Neovim's package directory:

```sh
git clone --depth 1 https://github.com/skapoor8/MmdToImg.git \
  ~/.local/share/nvim/site/pack/plugins/start/MmdToImg
```

Add this to your Neovim configuration:

```lua
local root = vim.fn.stdpath("data") .. "/site/pack/plugins/start/MmdToImg"
vim.opt.runtimepath:append(root .. "/libs/MmdToImg")
require("mmdtoimg").setup()
```

If you use a custom package directory, change `root` to match it.

## Usage

Save a `.mmd` file to generate its three image files.
For example, `docs/diagrams/architecture.mmd` produces `architecture.svg`, `architecture.light.png`, and `architecture.dark.png` in the same directory.
Reference the SVG in Markdown:

```markdown
![Architecture](diagrams/architecture.svg)
```

Commit all three images with their source.
Readers can view the diagrams without installing Neovim or MmdToImg.

The plugin provides these commands:

- `:MmdToImg` renders the current `.mmd` file.
- `:MmdToImg path/to/diagram.mmd` renders another file.
- `:MmdToImgAll` renders Mermaid files beneath the Git root or current directory.
- `:MmdToImgAll path/to/diagrams` renders files beneath a selected directory.

The directory scan skips Git metadata, `node_modules`, `target`, and `.cache`.
Rendering runs in the background, one diagram at a time.
Saving a file again queues a fresh render.
Failed Mermaid commands leave the existing images in place.

## Inline Mermaid blocks

MmdToImg detects top-level fenced `mermaid` blocks and renders them with the same pipeline as `.mmd` files.
Snacks is used only to display the finished PNG.
The image visually replaces the block while the Markdown source stays intact.
By default, previews appear automatically in normal mode, including when the cursor is inside a block.
Enter Insert mode inside the block to edit its source; return to normal mode to restore the preview.
Opening Markdown, editing a block, and changing the colorscheme refresh previews without a command.
MmdToImg renders into its own cache; no `.mmd` files or image links are added to your document.
This also works for Markdown outside a repository, such as Difflab plans.

Inline rendering uses the same command, timeout, light/dark configurations, scale and Puppeteer configuration as standalone rendering.
The cache includes the source and renderer configuration, so theme changes produce fresh images.
Images fit the usable window area, allowing for number/sign columns and margins.
Keep using `:MmdToImgAll directory` for committed diagrams and image links.
Set `inline_mermaid = false` to use Snacks' original Mermaid rendering instead.
A supported terminal is required. Inline fence detection does not require Treesitter.
The plugin temporarily enables conceal in preview windows and restores the previous settings when editing or disabling previews.

An optional `inline_source_visible(buf, first, last)` callback controls visibility
for each block. The fence line numbers are one-based and inclusive. Return `true`
to show source, `false` to show the preview, or `nil` to use the default behavior.
This callback takes priority in every mode. An existing render-markdown bridge
can therefore keep its per-buffer `render_modes` and `anti_conceal` settings in
control, including normal-mode source visibility.

Unchanged refreshes preserve image placements and virtual rows. Neovim has a
[scrolling bug around concealed and virtual lines](https://github.com/neovim/neovim/issues/42317)
that can trap upward scrolling at one line. On Neovim 0.11.4 and later, buffers
showing inline diagrams use a local guard for `Ctrl-Y` and upward mouse scrolling.
It retries a stuck step with the cursor moved up so the viewport can advance.
Existing user mappings are preserved. Snacks scroll animations are paused only
in buffers with diagram previews because their native scroll replay bypasses
the guard. The previous buffer settings and mappings return when previews close.

## Snacks image previews

MmdToImg detects Snacks and configures image previews automatically.
No resolver configuration is needed.
It preserves an existing custom resolver and selects the matching PNG for Mermaid SVG links.
Markdown previews refresh after rendering and when the editor background changes.
Use `:set background=light` or `:set background=dark` to select a preview theme.
Set `snacks = false` in MmdToImg's configuration to disable automatic integration.

## Configuration

```lua
require("mmdtoimg").setup({
  command = "mmdc",
  auto_render = true,
  snacks = true,
  inline_mermaid = true,
  theme = "default", -- or "nvim" to use the current editor colors
  scale = 2,
  timeout = 120000,
  -- light_config = "/path/to/light.json",
  -- dark_config = "/path/to/dark.json",
  -- puppeteer_config = "/path/to/puppeteer.json",
})
```

`scale` sets the PNG resolution multiplier.
`timeout` limits each Mermaid command in milliseconds.
The bundled theme files define the layout and colors.
Custom theme files must produce the same layout in both themes.
`puppeteer_config` passes a Puppeteer configuration file to the Mermaid CLI.

Set `theme = "nvim"` to derive diagram colors from Neovim's `Normal`, `Function`,
`Comment`, `String`, `Type`, and `DiagnosticWarn` highlights. Linked highlights
are supported. Missing colors use bundled defaults; a transparent `Normal`
background uses an opaque bundled background. If `Normal` has no foreground
or background, the complete bundled palette is used.

Only the variant matching `vim.o.background` uses the active editor palette.
The opposite variant uses its bundled light or dark palette, so both outputs
remain readable without changing your editor's colorscheme. Custom `light_config`
and `dark_config` files take priority; their `themeVariables.background` also
sets the renderer's canvas color. Diagram frontmatter can override Mermaid colors.

Inline previews regenerate automatically after colorscheme or background changes.
Standalone images adopt the current colors the next time you save or render
those diagrams. The default `theme = "default"` keeps exported images consistent
across developers, independent of their editor configuration.

## Development

The implementation, themes, tests, documentation, and development tools live in `libs/MmdToImg`.
The root `doc` symlink exposes `libs/MmdToImg/docs` to Neovim’s help system.
Run `:helptags ALL` once after a manual installation, then open `:help mmdtoimg.txt`.
Install the tools and run the checks:

```sh
mise trust
mise -C libs/MmdToImg install
mise run //libs/MmdToImg:install
mise run //libs/MmdToImg:build
mise run //libs/MmdToImg:lint
mise run //libs/MmdToImg:test
```

The tests cover real flowchart and sequence rendering, theme fallbacks, directory exclusions, rendering on save, automatic inline previews, SVG references, source snapshots, and output rollback.
Premise runs the checks using the tool versions declared in `mise.toml`.
The plugin installs from Git and requires no uploaded release artifacts.

## License

[MIT](LICENSE).
