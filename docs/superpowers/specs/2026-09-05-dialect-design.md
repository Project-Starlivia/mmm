# 方言 — mizchi の mdAst を mmm の読み方に直す場所を 1 つにする

## 問題

`core/tree/md.mbt` は「ライブラリに触るのはこのファイルだけ」と言うが、ライブラリ（mizchi/markdown）の癖の補正が読みの各所に散っている。

| 癖 | 補正の場所 |
|---|---|
| コード・`$$`・`:::` の span が閉じの行を含まない | `content.mbt` の `closing()`（`build.mbt` と `verbatim` が呼ぶ） |
| 定義行（`[q]: /r`）の span が改行を含まない | `fold.mbt` の `eol_after` |
| frontmatter の後ろの空行を読みが捨て、書き手も置かない | `md.mbt` の `serialize`（書く側で足す） |
| 書き手が区切り線を marker に関わらず `***` で書く | 補正なし（mmm は `---` で書きたい） |
| 入れ子の項目の周りの `Blank` の範囲が壊れている | 反映が `Blank` を使わず原文の字で測る |
| インラインの span が段落の中身に対する相対 | `content.mbt` の `inline_text` が足す |

ライブラリの版が上がって癖が変われば、直す場所を探し回ることになる。

## 決め

**読みも書きも `md.mbt` の 2 本に閉じる。** 中は「ライブラリ」と「方言」の直列。

```
read(md)   = @markdown.parse(md) |> mend(md)        mdAst → mmm の方言の mdAst
write(ast) = @markdown.serialize(ast) |> spell       字 → mmm の綴り
```

`build` / `content` / `fold` / `reflect` は方言の mdAst だけを見る。ライブラリの癖を知るのは `md.mbt` だけ。

### 読みの方言 `mend(md, ast) -> ast`

mdAst を歩き、span を mmm の決めに揃えた mdAst を返す（純粋。容器は中まで歩く: 項目・引用・Alert・Directive・Attributed・脚注）。

- **フェンス付きの塊（コード・`$$`・`:::`）の span は閉じの行の改行まで。** 他の塊（段落・見出し）と同じく「行末の改行込み」。閉じが無ければそのまま
- **定義行の span は改行込み。**
- それ以外の span は触らない。**段落の span が中身の頭から始まる**（項目のマーカーの後ろ）、**インラインの span が段落の中身に対する相対**は、ライブラリの決めとしてそのまま使う（`inline_text` は残す。書き換えるにはインラインを全部組み直すことになる）
- **`Blank` は使わない。** 入れ子の項目の周りで範囲が壊れているので、隙間は原文の字で測る（反映の決め）。`mend` は `Blank` を触らない

これで `closing()` と `eol_after` は消える。`verbatim` は span を切るだけ、`fill` は `s.to` をそのまま使う。

### 書きの綴り `spell(text) -> text`

ライブラリが書いた字を、mmm の綴りに直す。**書いた字を読み直して当てる**（span で当てるので、コードの中の同じ字は触らない）。

- **区切り線は `---`。** ライブラリは marker に関わらず `***` と書く。読み直した mdAst の `ThematicBreak` の span を `---` に置き換える（同じ長さなので span はずれない）。側の変わり目も飾りの水平線も同じ
- **frontmatter と本文の間は空行 1 つ。** 今 `serialize` にある補正をここへ

`fragment` / `prose` / `serialize` は全部 `write` を通るので、断片も正規形も同じ綴り。

### 試験

`md_wbtest.mbt` に、癖ごとに「ライブラリの生の指紋 → 方言の指紋」を並べる。ライブラリの版が上がって生の指紋が変われば、ここで気付く。

- `mend`: コード・`$$`・`:::` の span（LF / CRLF / 閉じ無し / 項目の中）、定義行の span
- `spell`: `***` → `---`（見出しの間、項目の中、コードの中の `***` は触らない）、frontmatter の後ろの空行

既存の試験で `***` を期待しているもの（content / fragment / md / reflect / side / unbuild、edit の見本）は `---` に書き換える。法則（読み × 書き、op × 反映、反映の隙間）はそのまま安全網。

## 構成

```
core/tree/md.mbt          read = parse |> mend、write = serialize |> spell、mend、spell
core/tree/content.mbt     closing() を消す。verbatim は span を切るだけ
core/tree/build.mbt       fill の to は s.to
core/tree/fold.mbt        eol_after を消す
core/tree/md_wbtest.mbt   生の指紋 → 方言の指紋
docs/core.md              読み書きの節に「方言」を書く
```

## やらないこと

- インラインの span を絶対にする（インラインの組み直しになる。相対のまま `inline_text` で足す）
- `Blank` を直す（使わない）
- ライブラリの差し替え
