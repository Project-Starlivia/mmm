// 読みを **md の字だけで**固定する。木の形（`json_inspect(parse(md))`）で言っている
// 試験は Doc の型にぶら下がっているが、ここは md → md しか見ないので、内側の作りが
// 変わっても生き残る。**型を壊しても、ここが通れば同じ mmm。**
//
// 見本は木の形の試験が読ませている md を全部集めたもの（188 通り）。#88 で負荷の
// 見本にしか無かった記法（~~~ / フェンスの中の見出し / タブ / 末尾空白 / 表 /
// 素の URL / 脚注）もここへ吸わせた。**記法の変化はここが言い、大きさは
// test/fixtures が言う。**
// 押さえるのは 4 つ:
//
//   正規形     読んで書き戻した字。**読み方の答えがそのまま出る**
//   冪等       もう一度書いても同じ字
//   往復       書いた字を読み直せば同じ木
//   破れ       parse の出力は check を通る
//
// 見本を足すときは、木の形の試験に md を足すのと同じ気持ちで足す。

///|
/// 木の形の試験が読ませている md、全部。
let read_corpus : Array[String] = [
  // #206 — 字下げコード。記法の 4 桁、越えた分の中身、タブ、項目の中
  "    code\n", "      code\n", "\tcode\n", "# a\n\n    a\n      b\n", "- x\n\n      code\n",
  "- a\n  - b\n\n        code\n", "# \n", "# a\n", "* a\n", "+ a\n", "# a\n\n", "# a\r\n",
  "# a#\n", "## a\n", "# a #b\n", "- root\n", "# a ###\n", "- - - a\n", "# a\n\n# b\n",
  "# a\n\n***\n", "# r\n\n- a\n", "- # node\n", "- a\n\n# x\n", "- a\n  # x\n", "- a **b**\n",
  // #203 — 桁 0 に並ぶ項目の列。読んだ詰めのまま書き戻る
   "- a\n- b\n", "* a\n* b\n", "- a\n\n- b\n", "- a\n- b\n- c\n", "1. a\n2. b\n",
  "# a\n\nhello\n", "# r\n\n### x\n", "- a\n\n### x\n", "intro\n\n# a\n", "# a\n\n> quote\n",
  "# a\r\n\r\n## b\r\n", "- a\n\n  hello\n", "- root\n  - a\n", "# a\n\n    code\n",
  "# a **b** `c`\n", "# r\n\n---\n\n# s\n", "- aaa\r\n  bbb\r\n", "# r\n\n## a\n\n- b\n",
  "# r\n\n## a\n\n---\n", "# r\n\n***\n\n## a\n", "# r\n\n- b\n\n## a\n", "# r\n\n---\n\n## a\n",
  "# r\n\n___\n\n## a\n", "* \n  * \n    * \n", "- \n  - \n    - \n", "- item\n\n  ## h\n",
  "aaa\r\nbbb\r\n===\r\n", "body\n\n---\n\n# a\n", "# a\n\nx\n\n## b\n\ny\n", "# r\n\n## a\n\n## b\n",
  "# r\n\n- b\n\n### x\n", "# r\n\n</details>\n", "- [q]: /r\n  ZZZ\n", "- a\n\n  ---\n\n# h\n",
  "[q]: /r\nZZZ\n---\n", "# r\n\n## a\n\n### x\n", "- x\n  # n\n  ## s\n", "---\nk: v\n---\n# a\n",
  "# a\n\nhello\n\nworld\n", "# r\n\n## h\n\n[a]: b\n", "- [ ] a\n  - [x] b\n", "- a\n\n  ***\n\n  - b\n",
  "- aaa\n  bbb\n  ccc\n", "---\nk: v\n---\n\n# a\n", "# a\n\n![alt](x.png)\n", "- root\n  - a\n  - b\n",
  "# a\r\n\r\n```\r\nx\r\n```\r\n", "# r\n\n## a\n\n---\n\n- b\n", ":::a\n:::b\nx\n:::\n:::\n",
  "# a\n\nbody\n\n---\n\n## b\n", "# r\n\n## a\n\n---\n\n## b\n", "# r\n\n## s\n\n- a\n  - b\n",
  "# r\n\n<details>\n\n## h\n", "# r\n\n## a\n\n---\n\n### x\n", "# r\n\n[a]: b \"c\"\n\n## h\n",
  "- a\n\n  <!-- x\n  y -->\n", "# a\n\nsee ![alt](x.png)\n", "# r\n\n## a\n\n### x\n\n## b\n",
  "# r\n\n- b\n\n  - c\n\n### x\n", "- a\n  - b\n\n    [q]: /r\n", "# a\n\n<svg><rect/></svg>\n",
  "- \n  - \n    - \n      - \n", "- ```\n  code\n  ```\n\n  x\n", "# a\n\n```js\nlet x = 1\n```\n",
  "# r\n\n## a\n\n---\n\n- b\n\n- c\n", "# r\n\n## a\n\n---\n\n---\n\n## b\n", "# r\n\n## h\n\n---\n\n- a\n  - b\n",
  "- a\n\n  - b\n\n  text\n\n  - c\n", "# a\n\n[text](https://e.com)\n", "# a\n\nbody\n\n---\n\nbody\n\n## b\n",
  "# r\n\n:::note\n- a\n  ***\n:::\n", "# r\n\n## a\n\n---\n\nZZZ\nWWW\n---\n", "# r\n\n$$\nx\n$$\n\n:::note\ny\n:::\n",
  "# r\n\n## a\n\n### x\n\n---\n\n### y\n", "# r\n\n## a\n\n---\n\n[q]: /r\n\n## b\n",
  "# r\n\n<details>\n## h\n</details>\n", "# r\n\n<details>\n\n## h\n\n</details>\n",
  "# r\n\n![a](b.png \"t1\")\n\n[c](d \"t2\")\n", "# r\n\n<details-x>\n\n## a\n\n</details>\n",
  "# a\n\n<details>\n\nx\n\n</details>\n\n## b\n", "# r\n\n<details>\n### x\n\n## y\n</details>\n",
  "# r\n\n## a\n\n***\n\n## b\n\n***\n\n```\n***\n```\n", "# r\n\n## h\n\n<details>\n\nbody\n\n</details>\n",
  "# r\n\n<details>\n\n### x\n\n## y\n</details>\n", "- a\n\n  <details>\n\n  ## h\n\n  </details>\n",
  "# r\n\n## h\n\n### x\n\n---\n\n- a\n  - b\n\n### t\n", "# r\n\n<details>\n\n## h\n\n## h2\n\n</details>\n",
  "# r\n\n<details>\n\n[q]: /r\n\n## a\n\n</details>\n", "# r\n\n<details>\n\nbodya\n\n# head\n\n</details>\n",
  "# root\n\n---\n\n## h1\n\n---\n\n* i1\n\n---\n\n## h2\n", "# r\n\n## h\n\n<svg><details>a</details></svg>\n",
  "# r\n\n<details>\n\n## a\n\n---\n\n</details>\n\n## b\n", "# r\n\n<details>\njunk\n\n[q]: /r\n\n## a\n\n</details>\n",
  "# r\r\n\r\n<details class=\"x\">\r\n\r\n## h\r\n\r\n</details>\r\n", "- a\n  - b\n\n    <details>\n\n    ## h\n\n    </details>\n",
  "# r\n\n<details>\n<summary>a</summary>\n\n- a\n\n</details>\n", "# r\n\n<details><summary>a</summary>\n\n## a\n\n</details>\n",
  "# r\n\n## h\n\n---\n\n<details>\n\n- a\n  - b\n\n</details>\n\n- c\n", "# r\n\n<details>\t<summary>s</summary>\n\n## a\n\n</details>\n",
  "# r\n\n<details>\n<summary>x</summary>\n\n## h\n\n</details>\n", "- <details>\n  <summary>a</summary>\n\n  x\n\n  </details>\n",
  "# r\n\n<details>\n<summary>a</summary>\n\n- a\n\n</details>\n\nx\n", "# r\n\n<details \"x>\n<summary>h</summary>\n\n## h\n\n</details>\n",
  "# r\n\n<details open>\n<summary>a</summary>\n\n- a\n\n</details>\n", "# r\n\n<details>\n<summary>h</summary>\n\n## **h**\n\n</details>\n",
  "# a\n\n<details>\n<summary>b</summary>\n\n## b\n\n</details>\n\n---\n", "# r\n\n<details open>\n<summary>h</summary>\n\n## h\n\n</details>\n",
  "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\ntail\n", "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\n\n## b\n",
  "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\nbody\n\n</details>\n", "# r\n\n<details>\n<summary>**h**</summary>\n\n## **h**\n\n</details>\n",
  "# r\n\n<details class=\"x\">\n<summary>h</summary>\n\n## h\n\n</details>\n", "# r\n\n<details>\n<summary>y</summary>\n\n## y\n</details>\n</details>\n",
  "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n#### deep\n\n</details>\n",
  "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n</details>\n\n---\n\n## b\n",
  "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\nbody\n\n---\n\n</details>\n",
  "- item\n\n  <details>\n  <summary>h</summary>\n\n  ## h\n\n  </details>\n", "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n---\n\n### x\n\n</details>\n",
  "- a\n\n  <details>\n  <summary>b</summary>\n\n  - b\n\n  </details>\n\n  - c\n",
  "# r\n\n## a\n\n---\n\n<details>\n<summary>c</summary>\n\n- c\n\n</details>\n\n- e\n",
  "# root\n\n<details>\n<summary>head</summary>\n\n## head\n\n</details>\n\ntext\n",
  "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n</details>\n\n---\n\n---\n\n## b\n",
  "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n</details>\n\n---\n\nsome text\n",
  "# root\n\n<details>\n<summary>head</summary>\n\n## head\n\n</details>\n\n### z\n",
  "# a\n\n<details>\n<summary>b</summary>\n\n## b\n\n</details>\n\n<details>\n\n## c\n",
  "# r\n\n## h\n\n<details open>\n<summary>s</summary>\n\nbody\n\nmore\n\n</details>\n",
  "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n<?x </details> ?>\n\n</details>\n",
  "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n<!-- </details> -->\n\n</details>\n",
  "# r\n\n<details>\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\n\n</details>\n",
  "# root\n\n- head\n\n<details>\n<summary>head</summary>\n\n## head\n\n</details>\n\n- y\n",
  "# r\n\n<details>\n<summary>h</summary>\n<summary>ZZZ</summary>\n\n## h\n\n</details>\n",
  "# r\n\n<details>\n\n## s\n\n---\n\n<summary>z</summary>\n\n</details>\n\n### a\n\n### b\n\n## t\n",
  "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n<pre><details></pre>\n\n</details>\n\n## h2\n",
  "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n<script>\nvar x = \"</details>\";\n</script>\n\n</details>\n",
  "# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n</details></details>\n",
  "# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n</details>\n</details>\n",
  "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n</details>\n\n<details>\n<summary>b</summary>\n\n## b\n\n</details>\n",
  "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n<details>\n<summary>a1</summary>\n\n### a1\n\n</details>\n\n</details>\n",
  "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n<details open>\n<summary>a1</summary>\n\n### a1\n\n</details>\n\n</details>\n",
  "# a\n\n<details>\n<summary>b</summary>\n\n## b\n\n</details>\n\n<details class=\"z\">\n<summary>c</summary>\n\n## c\n\n</details>\n",
  "# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n\n<details>\n<summary>z</summary>\n\n#### z\n</details>\n</details>\n</details>\n",
  // 破れの見本（check_wbtest.mbt から）— 深さの飛び・空の文書・7 本目の `#`・info 付きのフェンス
   "# a\n\n## b\n\n### c\n", "# r\n\n#### z\n", "- a\n  - b\n", "# r\n\n---\n\n### x\n",
  "# r\n\n<details>\n\n## h\n\nbody\n\n</details>\n", "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\n",
  "# r\n\n<!-- x -->\n", "text\n\n![a](b.png)\n\n# a\n", "# a\n\n```js\nx\n```\n",
  "###### f\n\n####### g\n", "",
  // 境界の綴り（`___`）と、列のマーカー・番号（#84。飛んだ番号も読んだまま）
   "# a\n\n## b\n\n___\n\n## c\n", "# a\n\n* b\n* c\n", "# a\n\n1. b\n2. c\n", "# a\n\n1. b\n3. c\n",
  // #88 — 負荷見本にしか無かった記法。**大きさではなく記法の変化**はここで言う。
  // チルダのフェンス / フェンスの中の見出しと水平線 / タブ区切りの見出し /
  // 末尾空白付きの見出し / 表 / 素の URL の行 / 脚注（読み解かないので Raw に落ちる）
   "# a\n\n~~~\n## not a heading\n~~~\n", "# a\n\n```md\n# not a heading\n---\n```\n",
  "##\ta\n", "## a  \n", "# a\n\n| x | y |\n|---|---|\n| 1 | 2 |\n", "# a\n\nhttps://x.example/\n",
  "# a\n\ntext[^1]\n\n[^1]: note\n",
]

///|
/// **正規形は読み方の答え。** 同じ字に戻るなら「読んで書いても変わらない」で、
/// 戻らないなら何がどう正規化されるかがそのまま表になる。
test "見本 — 読んで書き戻した字" {
  let out = StringBuilder()
  for md in read_corpus {
    let once = serialize(parse(md))
    if once == md {
      continue
    }
    out.write_string("\{md.escape()}\n  → \{once.escape()}\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|"# \n"
      #|  → "#\n"
      #|"# a\n\n"
      #|  → "# a\n"
      #|"# a\r\n"
      #|  → "# a\n"
      #|"# a\r\n\r\n## b\r\n"
      #|  → "# a\n\n## b\n"
      #|"- aaa\r\n  bbb\r\n"
      #|  → "- aaa\n  bbb\n"
      #|"* \n  * \n    * \n"
      #|  → "*\n  * *\n"
      #|"- \n  - \n    - \n"
      #|  → "-\n  - -\n"
      #|"aaa\r\nbbb\r\n===\r\n"
      #|  → "aaa\nbbb\n===\n"
      #|"- x\n  # n\n  ## s\n"
      #|  → "- x\n  # n\n\n  ## s\n"
      #|"---\nk: v\n---\n# a\n"
      #|  → "---\nk: v\n---\n\n# a\n"
      #|"# a\r\n\r\n```\r\nx\r\n```\r\n"
      #|  → "# a\n\n```\nx\n```\n"
      #|"# r\n\n- b\n\n  - c\n\n### x\n"
      #|  → "# r\n\n- b\n  - c\n\n### x\n"
      #|"- \n  - \n    - \n      - \n"
      #|  → "- -\n    - -\n"
      #|"- a\n\n  - b\n\n  text\n\n  - c\n"
      #|  → "- a\n  - b\n\n    text\n  - c\n"
      #|"# r\r\n\r\n<details class=\"x\">\r\n\r\n## h\r\n\r\n</details>\r\n"
      #|  → "# r\n\n<details class=\"x\">\n\n## h\n\n</details>\n"
      #|"# r\n\n<details><summary>a</summary>\n\n## a\n\n</details>\n"
      #|  → "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n</details>\n"
      #|"# r\n\n<details>\t<summary>s</summary>\n\n## a\n\n</details>\n"
      #|  → "# r\n\n<details>\n<summary>s</summary>\n\n## a\n\n</details>\n"
      #|"# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n</details></details>\n"
      #|  → "# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n\n</details>\n\n</details>\n"
      #|"# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n</details>\n</details>\n"
      #|  → "# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n\n</details>\n\n</details>\n"
      #|"# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n\n<details>\n<summary>z</summary>\n\n#### z\n</details>\n</details>\n</details>\n"
      #|  → "# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n\n<details>\n<summary>z</summary>\n\n#### z\n\n</details>\n\n</details>\n\n</details>\n"
      #|"##\ta\n"
      #|  → "## a\n"
      #|"## a  \n"
      #|  → "## a\n"
      #|
    ),
  )
}

///|
/// **木が抱える字は LF だけ**（#207）。読んだ原文はそのまま持つのが原則だが、改行は
/// 例外 — 混ざったまま持つと、書き戻した md の中で改行が 2 通りになる。
///
/// 揃えるのは木へ渡す所だけ（`carve` / `strip` と、ライブラリから来る字）。**原文その
/// ものは 1 バイトも変えない** — 地番は原文の位置を指し、記法構造の書き戻しは
/// `slice` で切るので、どちらも CR をそのまま返す（`見本 — 触っていない記法構造を…`）。
/// 木を JSON に落として見るので、**字を持つ欄を 1 つも取りこぼさない**
/// （label / source / content / rules / frontmatter / summary）。
test "見本 — 木が抱える字に CR は無い" {
  let bad : Array[String] = []
  for md in read_corpus {
    // JSON は CR を 2 文字の `\r` に綴る
    if parse(md).to_json().stringify().contains("\\r") {
      bad.push(md.escape())
    }
  }
  json_inspect(bad, content=[])
}

///|
/// **もう一度書いても同じ字。** 正規形が落ち着いていることは、書き方が
/// 入力に依らないことを言う
test "見本 — 冪等" {
  let bad : Array[String] = []
  for md in read_corpus {
    let once = serialize(parse(md))
    if serialize(parse(once)) != once {
      bad.push(md.escape())
    }
  }
  json_inspect(bad, content=[])
}

///|
/// **往復。** 書いた字を読み直せば同じ木。合わないものは、字がどう動いたかを並べる
/// （木が変われば合流の安全網が毎回開く）
test "見本 — 往復" {
  let out = StringBuilder()
  for md in read_corpus {
    let once = serialize(parse(md))
    if parse(once) == parse(md) {
      continue
    }
    out.write_string("\{md.escape()}\n  → \{once.escape()}\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|
    ),
  )
}

///|
/// **parse の出力は check を通る。** 通らないのは、破れそのものを見本にした md だけ
test "見本 — 破れ" {
  let out = StringBuilder()
  for md in read_corpus {
    let flaws = check(parse(md))
    if flaws.is_empty() {
      continue
    }
    out.write_string("\{md.escape()}  \{flaws.to_json().stringify()}\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|"# r\n\n---\n\n# s\n"  [["BorderBreak",3]]
      #|"body\n\n---\n\n# a\n"  [["BorderBreak",3]]
      #|
    ),
  )
}
