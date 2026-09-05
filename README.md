# mmm

**markdown / mindmap / mirror** — a Markdown ⇄ Mindmap editor you can edit
from either side.

The file itself is just a `.md`. The Mindmap is only another window onto it.

For the full spec, see [docs/spec.md](docs/spec.md). For the shape of the design — which known patterns each part follows and the laws between stages — see [docs/design.md](docs/design.md).

([日本語版はこちら](README_JA.md))

## Run it

Requires Node.js, pnpm, and the [MoonBit toolchain](https://www.moonbitlang.com/download)
(`moon` on PATH).

    pnpm install
    pnpm run lab        # builds the core, then opens the lab (http://localhost:13132)

**The editor itself does not run right now.** The document model is being
rebuilt (`core/tree`, see [docs/core.md](docs/core.md)) and `src/` still talks
to the old one, which is gone. What runs today is the lab: type Markdown and
it shows the mdAst and the mmm tree side by side, so you can tell which stage
broke.

    pnpm run test:core   # the reading rules
    pnpm run check:core

## License

mmm itself is MIT ([LICENSE](LICENSE)).

mmm claims no rights over what you create — the Markdown files you write, or
the SVG / WebP / PNG you export. Any right that might arise is waived. There's
no restriction on use, no attribution requirement, no obligation to notify.

Neither mmm nor what it produces comes with a warranty of correctness. Neither
mmm nor anyone behind it is liable for any trouble, loss, or damage that
results.

## Credits

Menu and toolbar icons are from [Lucide](https://lucide.dev) (ISC License).
