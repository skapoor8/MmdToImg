# MmdToImg

Render Mermaid diagrams on save and preview the correct theme in Neovim.
Each `.mmd` file generates an adaptive `.svg`, a `.light.png`, and a `.dark.png` beside the source.
Use a normal Markdown image link to the SVG.
Browsers select its theme with `prefers-color-scheme`.
The optional Snacks integration displays the PNG that matches `vim.o.background`.

## Requirements

MmdToImg requires Neovim 0.10 or later and the Mermaid CLI (`mmdc`) on your PATH.
Install the Mermaid CLI with npm:

```sh
npm install -g @mermaid-js/mermaid-cli
```

The CLI installs Puppeteer, which uses Chromium to render diagrams.
For terminal image previews, Snacks also needs a supported terminal such as Ghostty or Kitty.
Generation works without Snacks or terminal image support.

## Installation

### lazy.nvim

Add this plugin specification:

```lua
{
  "skapoor8/MmdToImg",
  version = "*",
  lazy = false,
  main = "mmdtoimg",
  opts = {},
}
```

### vim-plug

Add the plugin to your vim-plug block and run `:PlugInstall`:

```vim
Plug 'skapoor8/MmdToImg', { 'tag': 'v0.1.0' }
```

Then configure the plugin:

```lua
require("mmdtoimg").setup()
```

### Native Git packages

Clone the plugin into Neovim's package directory:

```sh
git clone --branch v0.1.0 --depth 1 https://github.com/skapoor8/MmdToImg.git \
  ~/.local/share/nvim/site/pack/plugins/start/MmdToImg
```

Then call `require("mmdtoimg").setup()` from your Neovim configuration.
Adjust the package directory if you use a custom Neovim data directory.

## Use

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

## Snacks image previews

Configure Snacks to use MmdToImg's resolver, which selects the matching PNG:

```lua
{
  "folke/snacks.nvim",
  dependencies = { "skapoor8/MmdToImg" },
  opts = {
    image = {
      enabled = true,
      doc = { enabled = true, inline = true },
      resolve = function(file, src)
        return require("mmdtoimg").resolve(file, src)
      end,
    },
  },
}
```

Markdown previews refresh after rendering and when the editor background changes.
Use `:set background=light` or `:set background=dark` to select a preview theme.
The SVG selects its browser theme independently of Neovim.

## Configuration

```lua
require("mmdtoimg").setup({
  command = "mmdc",
  auto_render = true,
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

## Development

Premise initializes this repository as a monorepo with one language-agnostic library.
The implementation and themes live in `libs/MmdToImg`.
The root `lua/mmdtoimg/init.lua` entry point lets Neovim find the library through its standard runtime directory.

Install the development tools and run the library tasks:

```sh
mise trust
mise install
pm run MmdToImg:build
pm run MmdToImg:lint
pm run MmdToImg:test
```

Without Premise, run the same tasks with Mise:

```sh
mise run //libs/MmdToImg:build
mise run //libs/MmdToImg:lint
mise run //libs/MmdToImg:test
```

The tests cover image generation, theme selection, directory exclusions, rendering on save, and failed commands.
CI runs the tests on Neovim 0.10.4 and 0.12.6.

## License

[MIT](LICENSE).
