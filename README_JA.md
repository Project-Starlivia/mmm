# mmm

**markdown / mindmap / mirror** — 双方向に編集できる Markdown ⇄ Mindmap
エディタ。

実体はただの `.md` ファイル。Mindmap は、その md を空間的に見るための
もう一つの窓でしかない。

詳しい仕様は [docs/spec.md](docs/spec.md)。

([English README](README.md))

## 実行方法

必要: Node.js、pnpm、[MoonBit toolchain](https://www.moonbitlang.com/download)
(`moon` が PATH にあること)

    pnpm install
    pnpm run dev        # コアをビルドしてから vite（http://localhost:13131）

本番ビルド: `pnpm run build` → `pnpm run preview` で確認。

## ライセンス

mmm 自体は MIT([LICENSE](LICENSE))。

成果物 — あなたが書いた Markdown ファイルと、書き出した SVG / WebP / PNG —
に mmm は権利を持たない。権利が生じる場合はこれを放棄する。用途の制限・
表示義務・報告義務は無い。

mmm 自体も成果物も無保証で、動作や内容の正しさを保証しない。それによって
生じたいかなるトラブル・損失・損害についても、誰も責任を負わない。

## クレジット

メニューや帯の絵は [Lucide](https://lucide.dev)（ISC License）からいただきました。
