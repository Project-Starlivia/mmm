// 記法構造の網。**敷き詰めが本体** — 覆えていない字が出れば、どこかの裁定が
// 自分の記法を取りこぼしている。骨格の裁定と木を突き合わせるほうは、組み立て
// （`assemble`）を通した後の木と比べるので、裁定と組み立ての往復が閉じていることを言う。

///|
/// **原文を隙間なく覆う。** 前の to が次の from、頭は frontmatter の尻、尻は原文の尻。
/// 指紋と違って `moon test -u` で書き換わらないよう `fail` で言う。
test "見本 — ひと切れは原文を隙間なく覆う" {
  for md in read_corpus {
    let n = notation(md)
    let mut at = match n.frontmatter {
      Some(f) => f.span.to
      None => 0
    }
    for p in n.pieces {
      guard p.at.from == at else {
        fail("\{md.escape()}: \{at} の次が \{p.at.from}")
      }
      guard p.at.to > p.at.from else {
        fail("\{md.escape()}: [\{p.at.from},\{p.at.to}] が空か裏返る")
      }
      at = p.at.to
    }
    guard at == md.length() else {
      fail("\{md.escape()}: 尻が \{at}（原文は \{md.length()}）")
    }
  }
}

///|
/// **骨格の裁定は、いまの木と同じことを言う。** 深さ・ラベルの頭・綴りを文書順に
/// 並べて突き合わせる。飛び（Implicit）は原文に行を持たないのでひと切れにならず、
/// 木の側でも飛ばす。**ひと切れの列から組み直した木が裁定と食い違えば、ここが鳴る。**
test "見本 — 骨格の裁定は、いまの木と同じ" {
  for md in read_corpus {
    let (doc, spans) = build(md)
    let want = StringBuilder()
    fn walk(n : Node, depth : Int) {
      if n.mark is Some(_) {
        let label = match spans.get(n.id) {
          Some({ label: Some(l), .. }) => l.to_string()
          _ => "-"
        }
        want.write_string("\{depth} \{label} \{mark_sig(n.mark)}\n")
      }
      for k in n.children {
        walk(k, depth + 1)
      }
    }

    for r in doc.roots {
      walk(r.node, 1)
    }
    let got = StringBuilder()
    for p in notation(md).pieces {
      guard p.verdict is Some(Line(depth~, label~, mark~, ..)) else { continue }
      got.write_string("\{depth} \{label} \{mark_sig(mark)}\n")
    }
    guard got.to_string() == want.to_string() else {
      fail("\{md.escape()}\n--- 木\n\{want}--- 記法\n\{got}")
    }
  }
}

///|
/// 記法構造の指紋。`裁定[from,to]` を原文の順に。**`Rest` は覆えていない字**で、
/// 増えたらどこかの裁定が自分の記法を取りこぼしている
test "見本 — 記法構造の指紋" {
  let out = StringBuilder()
  for md in read_corpus {
    out.write_string("\{md.escape()}\n  → \{notation_sig(md)}\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|"    code\n"
      #|  → Card[0,9]["Code",{"info":"","text":"code\n"}]
      #|"      code\n"
      #|  → Card[0,11]["Code",{"info":"","text":"  code\n"}]
      #|"\tcode\n"
      #|  → Card[0,6]["Code",{"info":"","text":"code\n"}]
      #|"# a\n\n    a\n      b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,19]["Code",{"info":"","text":"a\n  b\n"}]
      #|"- x\n\n      code\n"
      #|  → Line[0,4](1,2,-,2,tight) Blank[4,7] Card[7,16]["Code",{"info":"","text":"code\n"}]
      #|"- a\n  - b\n\n        code\n"
      #|  → Line[0,4](1,2,-,2,tight) Blank[4,6] Line[6,10](2,8,-,2,tight) Blank[10,15] Card[15,24]["Code",{"info":"","text":"code\n"}]
      #|"# \n"
      #|  → Line[0,3](1,2,#0)
      #|"# a\n"
      #|  → Line[0,4](1,2,#0)
      #|"* a\n"
      #|  → Line[0,4](1,2,*,2,tight)
      #|"+ a\n"
      #|  → Line[0,4](1,2,+,2,tight)
      #|"# a\n\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5]
      #|"# a\r\n"
      #|  → Line[0,5](1,2,#0)
      #|"# a#\n"
      #|  → Line[0,5](1,2,#0)
      #|"## a\n"
      #|  → Line[0,5](2,3,#0)
      #|"# a #b\n"
      #|  → Line[0,7](1,2,#0)
      #|"- root\n"
      #|  → Line[0,7](1,2,-,2,tight)
      #|"# a ###\n"
      #|  → Line[0,8](1,2,#3)
      #|"- - - a\n"
      #|  → Line[0,2](1,2,-,2,tight) Line[2,4](2,4,-,2,tight) Line[4,8](3,6,-,2,tight)
      #|"# a\n\n# b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,9](1,7,#0)
      #|"# a\n\n***\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,9]"ThematicBreak"
      #|"# r\n\n- a\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,9](2,7,-,2,tight)
      #|"- # node\n"
      #|  → Line[0,2](1,2,-,2,tight) Line[2,9](2,4,#0)
      #|"- a\n\n# x\n"
      #|  → Line[0,4](1,2,-,2,tight) Blank[4,5] Line[5,9](1,7,#0)
      #|"- a\n  # x\n"
      #|  → Line[0,4](1,2,-,2,tight) Blank[4,6] Line[6,10](2,8,#0)
      #|"- a **b**\n"
      #|  → Line[0,10](1,2,-,2,tight)
      #|"- a\n- b\n"
      #|  → Line[0,4](1,2,-,2,tight) Line[4,8](1,6,-,2,tight)
      #|"* a\n* b\n"
      #|  → Line[0,4](1,2,*,2,tight) Line[4,8](1,6,*,2,tight)
      #|"- a\n\n- b\n"
      #|  → Line[0,4](1,2,-,2,loose) Blank[4,5] Line[5,9](1,7,-,2,loose)
      #|"- a\n- b\n- c\n"
      #|  → Line[0,4](1,2,-,2,tight) Line[4,8](1,6,-,2,tight) Line[8,12](1,10,-,2,tight)
      #|"1. a\n2. b\n"
      #|  → Line[0,5](1,3,1.,3,tight) Line[5,10](1,8,2.,3,tight)
      #|"# a\n\nhello\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,11]
      #|"# r\n\n### x\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,11](3,9,#0)
      #|"- a\n\n### x\n"
      #|  → Line[0,4](1,2,-,2,tight) Blank[4,5] Line[5,11](3,9,#0)
      #|"intro\n\n# a\n"
      #|  → Card[0,6] Blank[6,7] Line[7,11](1,9,#0)
      #|"# a\n\n> quote\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,13]
      #|"# a\r\n\r\n## b\r\n"
      #|  → Line[0,5](1,2,#0) Blank[5,7] Line[7,13](2,10,#0)
      #|"- a\n\n  hello\n"
      #|  → Line[0,4](1,2,-,2,tight) Blank[4,7] Card[7,13]
      #|"- root\n  - a\n"
      #|  → Line[0,7](1,2,-,2,tight) Blank[7,9] Line[9,13](2,11,-,2,tight)
      #|"# a\n\n    code\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,14]["Code",{"info":"","text":"code\n"}]
      #|"# a **b** `c`\n"
      #|  → Line[0,14](1,2,#0)
      #|"# r\n\n---\n\n# s\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,9]"ThematicBreak" Blank[9,10] Line[10,14](1,12,#0)
      #|"- aaa\r\n  bbb\r\n"
      #|  → Line[0,14](1,2,-,2,tight)
      #|"# r\n\n## a\n\n- b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Line[11,15](3,13,-,2,tight)
      #|"# r\n\n## a\n\n---\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Card[11,15]"ThematicBreak"
      #|"# r\n\n***\n\n## a\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Border[5,9] Blank[9,10] Line[10,15](2,13,#0)
      #|"# r\n\n- b\n\n## a\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,9](2,7,-,2,tight) Blank[9,10] Line[10,15](2,13,#0)
      #|"# r\n\n---\n\n## a\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Border[5,9] Blank[9,10] Line[10,15](2,13,#0)
      #|"# r\n\n___\n\n## a\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Border[5,9] Blank[9,10] Line[10,15](2,13,#0)
      #|"* \n  * \n    * \n"
      #|  → Line[0,2](1,2,*,2,tight) Blank[2,5] Line[5,7](2,7,*,2,tight) Blank[7,12] Line[12,14](3,14,*,2,tight) Blank[14,15]
      #|"- \n  - \n    - \n"
      #|  → Line[0,2](1,2,-,2,tight) Blank[2,5] Line[5,7](2,7,-,2,tight) Blank[7,12] Line[12,14](3,14,-,2,tight) Blank[14,15]
      #|"- item\n\n  ## h\n"
      #|  → Line[0,7](1,2,-,2,tight) Blank[7,10] Line[10,15](3,13,#0)
      #|"aaa\r\nbbb\r\n===\r\n"
      #|  → Line[0,15](1,0,=)
      #|"body\n\n---\n\n# a\n"
      #|  → Card[0,5] Blank[5,6] Card[6,10]"ThematicBreak" Blank[10,11] Line[11,15](1,13,#0)
      #|"# a\n\nx\n\n## b\n\ny\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,7] Blank[7,8] Line[8,13](2,11,#0) Blank[13,14] Card[14,16]
      #|"# r\n\n## a\n\n## b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Line[11,16](2,14,#0)
      #|"# r\n\n- b\n\n### x\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,9](2,7,-,2,tight) Blank[9,10] Line[10,16](3,14,#0)
      #|"# r\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,16]
      #|"- [q]: /r\n  ZZZ\n"
      #|  → Line[0,16](1,2,-,2,tight)
      #|"- a\n\n  ---\n\n# h\n"
      #|  → Line[0,4](1,2,-,2,tight) Blank[4,7] Card[7,11]"ThematicBreak" Blank[11,12] Line[12,16](1,14,#0)
      #|"[q]: /r\nZZZ\n---\n"
      #|  → Line[0,16](2,0,=)
      #|"# r\n\n## a\n\n### x\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Line[11,17](3,15,#0)
      #|"- x\n  # n\n  ## s\n"
      #|  → Line[0,4](1,2,-,2,tight) Blank[4,6] Line[6,10](2,8,#0) Blank[10,12] Line[12,17](3,15,#0)
      #|"---\nk: v\n---\n# a\n"
      #|  → Front[0,13] Line[13,17](1,15,#0)
      #|"# a\n\nhello\n\nworld\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,11] Blank[11,12] Card[12,18]
      #|"# r\n\n## h\n\n[a]: b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Card[11,18]
      #|"- [ ] a\n  - [x] b\n"
      #|  → Line[0,8](1,2,-,2,tight) Blank[8,10] Line[10,18](2,12,-,2,tight)
      #|"- a\n\n  ***\n\n  - b\n"
      #|  → Line[0,4](1,2,-,2,tight) Blank[4,7] Card[7,11]"ThematicBreak" Blank[11,14] Line[14,18](2,16,-,2,tight)
      #|"- aaa\n  bbb\n  ccc\n"
      #|  → Line[0,18](1,2,-,2,tight)
      #|"---\nk: v\n---\n\n# a\n"
      #|  → Front[0,13] Blank[13,14] Line[14,18](1,16,#0)
      #|"# a\n\n![alt](x.png)\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,19]["Image",{"alt":"alt","src":"x.png","title":""}]
      #|"- root\n  - a\n  - b\n"
      #|  → Line[0,7](1,2,-,2,tight) Blank[7,9] Line[9,13](2,11,-,2,tight) Blank[13,15] Line[15,19](2,17,-,2,tight)
      #|"# a\r\n\r\n```\r\nx\r\n```\r\n"
      #|  → Line[0,5](1,2,#0) Blank[5,7] Card[7,20]["Code",{"info":"","text":"x\n"}]
      #|"# r\n\n## a\n\n---\n\n- b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Border[11,15] Blank[15,16] Line[16,20](2,18,-,2,tight)
      #|":::a\n:::b\nx\n:::\n:::\n"
      #|  → Card[0,20]
      #|"# a\n\nbody\n\n---\n\n## b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,10] Blank[10,11] Border[11,15] Blank[15,16] Line[16,21](2,19,#0)
      #|"# r\n\n## a\n\n---\n\n## b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Border[11,15] Blank[15,16] Line[16,21](2,19,#0)
      #|"# r\n\n## s\n\n- a\n  - b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Line[11,15](3,13,-,2,tight) Blank[15,17] Line[17,21](4,19,-,2,tight)
      #|"# r\n\n<details>\n\n## h\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,15] Blank[15,16] Line[16,21](2,19,#0)
      #|"# r\n\n## a\n\n---\n\n### x\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Border[11,15] Blank[15,16] Line[16,22](3,20,#0)
      #|"# r\n\n[a]: b \"c\"\n\n## h\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,16] Blank[16,17] Line[17,22](2,20,#0)
      #|"- a\n\n  <!-- x\n  y -->\n"
      #|  → Line[0,4](1,2,-,2,tight) Blank[4,7] Card[7,22]
      #|"# a\n\nsee ![alt](x.png)\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,23]
      #|"# r\n\n## a\n\n### x\n\n## b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Line[11,17](3,15,#0) Blank[17,18] Line[18,23](2,21,#0)
      #|"# r\n\n- b\n\n  - c\n\n### x\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,9](2,7,-,2,tight) Blank[9,12] Line[12,16](3,14,-,2,tight) Blank[16,17] Line[17,23](3,21,#0)
      #|"- a\n  - b\n\n    [q]: /r\n"
      #|  → Line[0,4](1,2,-,2,tight) Blank[4,6] Line[6,10](2,8,-,2,tight) Blank[10,15] Card[15,23]
      #|"# a\n\n<svg><rect/></svg>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,24]["Svg","<svg><rect/></svg>\n"]
      #|"- \n  - \n    - \n      - \n"
      #|  → Line[0,2](1,2,-,2,tight) Blank[2,5] Line[5,7](2,7,-,2,tight) Blank[7,12] Line[12,14](3,14,-,2,tight) Blank[14,21] Line[21,23](4,23,-,2,tight) Blank[23,24]
      #|"- ```\n  code\n  ```\n\n  x\n"
      #|  → Line[0,2](1,2,-,2,tight) Card[2,19]["Code",{"info":"","text":"code\n"}] Blank[19,22] Card[22,24]
      #|"# a\n\n```js\nlet x = 1\n```\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,25]["Code",{"info":"js","text":"let x = 1\n"}]
      #|"# r\n\n## a\n\n---\n\n- b\n\n- c\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Border[11,15] Blank[15,16] Line[16,20](2,18,-,2,loose) Blank[20,21] Line[21,25](2,23,-,2,loose)
      #|"# r\n\n## a\n\n---\n\n---\n\n## b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Card[11,15]"ThematicBreak" Blank[15,16] Border[16,20] Blank[20,21] Line[21,26](2,24,#0)
      #|"# r\n\n## h\n\n---\n\n- a\n  - b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Border[11,15] Blank[15,16] Line[16,20](2,18,-,2,tight) Blank[20,22] Line[22,26](3,24,-,2,tight)
      #|"- a\n\n  - b\n\n  text\n\n  - c\n"
      #|  → Line[0,4](1,2,-,2,tight) Blank[4,7] Line[7,11](2,9,-,2,tight) Blank[11,14] Card[14,19] Blank[19,22] Line[22,26](2,24,-,2,tight)
      #|"# a\n\n[text](https://e.com)\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,27]["Link",{"text":"text","href":"https://e.com","title":""}]
      #|"# a\n\nbody\n\n---\n\nbody\n\n## b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,10] Blank[10,11] Card[11,15]"ThematicBreak" Blank[15,16] Card[16,21] Blank[21,22] Line[22,27](2,25,#0)
      #|"# r\n\n:::note\n- a\n  ***\n:::\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,27]
      #|"# r\n\n## a\n\n---\n\nZZZ\nWWW\n---\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Border[11,15] Blank[15,16] Line[16,28](2,16,=)
      #|"# r\n\n$$\nx\n$$\n\n:::note\ny\n:::\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,13] Blank[13,14] Card[14,28]
      #|"# r\n\n## a\n\n### x\n\n---\n\n### y\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Line[11,17](3,15,#0) Blank[17,18] Border[18,22] Blank[22,23] Line[23,29](3,27,#0)
      #|"# r\n\n## a\n\n---\n\n[q]: /r\n\n## b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Card[11,15]"ThematicBreak" Blank[15,16] Card[16,24] Blank[24,25] Line[25,30](2,28,#0)
      #|"# r\n\n<details>\n## h\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,31]["Details",{"open":false,"body":"## h"}]
      #|"# r\n\n<details>\n\n## h\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,15](-) Blank[15,16] Line[16,21](2,19,#0) Blank[21,22] Shut[22,33]
      #|"# r\n\n![a](b.png \"t1\")\n\n[c](d \"t2\")\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,22]["Image",{"alt":"a","src":"b.png","title":"t1"}] Blank[22,23] Card[23,35]["Link",{"text":"c","href":"d","title":"t2"}]
      #|"# r\n\n<details-x>\n\n## a\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,17] Blank[17,18] Line[18,23](2,21,#0) Blank[23,24] Card[24,35]
      #|"# a\n\n<details>\n\nx\n\n</details>\n\n## b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,30]["Details",{"open":false,"body":"x"}] Blank[30,31] Line[31,36](2,34,#0)
      #|"# r\n\n<details>\n### x\n\n## y\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,38]["Details",{"open":false,"body":"### x\n\n## y"}]
      #|"# r\n\n## a\n\n***\n\n## b\n\n***\n\n```\n***\n```\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Border[11,15] Blank[15,16] Line[16,21](2,19,#0) Blank[21,22] Card[22,26]"ThematicBreak" Blank[26,27] Card[27,39]["Code",{"info":"","text":"***\n"}]
      #|"# r\n\n## h\n\n<details>\n\nbody\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Card[11,39]["Details",{"open":false,"body":"body"}]
      #|"# r\n\n<details>\n\n### x\n\n## y\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,39]["Details",{"open":false,"body":"### x\n\n## y"}]
      #|"- a\n\n  <details>\n\n  ## h\n\n  </details>\n"
      #|  → Line[0,4](1,2,-,2,tight) Blank[4,7] Fold[7,17](-) Blank[17,20] Line[20,25](3,23,#0) Blank[25,28] Shut[28,39]
      #|"# r\n\n## h\n\n### x\n\n---\n\n- a\n  - b\n\n### t\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Line[11,17](3,15,#0) Blank[17,18] Border[18,22] Blank[22,23] Line[23,27](2,25,-,2,tight) Blank[27,29] Line[29,33](3,31,-,2,tight) Blank[33,34] Line[34,40](3,38,#0)
      #|"# r\n\n<details>\n\n## h\n\n## h2\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,40]["Details",{"open":false,"body":"## h\n\n## h2"}]
      #|"# r\n\n<details>\n\n[q]: /r\n\n## a\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,42]["Details",{"open":false,"body":"[q]: /r\n\n## a"}]
      #|"# r\n\n<details>\n\nbodya\n\n# head\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,42]["Details",{"open":false,"body":"bodya\n\n# head"}]
      #|"# root\n\n---\n\n## h1\n\n---\n\n* i1\n\n---\n\n## h2\n"
      #|  → Line[0,7](1,2,#0) Blank[7,8] Border[8,12] Blank[12,13] Line[13,19](2,16,#0) Blank[19,20] Border[20,24] Blank[24,25] Line[25,30](2,27,*,2,tight) Blank[30,31] Border[31,35] Blank[35,36] Line[36,42](2,39,#0)
      #|"# r\n\n## h\n\n<svg><details>a</details></svg>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Card[11,43]["Svg","<svg><details>a</details></svg>\n"]
      #|"# r\n\n<details>\n\n## a\n\n---\n\n</details>\n\n## b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,38]["Details",{"open":false,"body":"## a\n\n---"}] Blank[38,39] Line[39,44](2,42,#0)
      #|"# r\n\n<details>\njunk\n\n[q]: /r\n\n## a\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,47]["Details",{"open":false,"body":"junk\n\n[q]: /r\n\n## a"}]
      #|"# r\r\n\r\n<details class=\"x\">\r\n\r\n## h\r\n\r\n</details>\r\n"
      #|  → Line[0,5](1,2,#0) Blank[5,7] Card[7,50]["Details",{"open":false,"body":"## h"}]
      #|"- a\n  - b\n\n    <details>\n\n    ## h\n\n    </details>\n"
      #|  → Line[0,4](1,2,-,2,tight) Blank[4,6] Line[6,10](2,8,-,2,tight) Blank[10,15] Fold[15,25](-) Blank[25,30] Line[30,35](4,33,#0) Blank[35,40] Shut[40,51]
      #|"# r\n\n<details>\n<summary>a</summary>\n\n- a\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"a") Blank[36,37] Line[37,41](2,39,-,2,tight) Blank[41,42] Shut[42,53]
      #|"# r\n\n<details><summary>a</summary>\n\n## a\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,35](-,"a") Blank[35,36] Line[36,41](2,39,#0) Blank[41,42] Shut[42,53]
      #|"# r\n\n## h\n\n---\n\n<details>\n\n- a\n  - b\n\n</details>\n\n- c\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Border[11,15] Blank[15,16] Fold[16,26](-) Blank[26,27] Line[27,31](2,29,-,2,tight) Blank[31,33] Line[33,37](3,35,-,2,tight) Blank[37,38] Shut[38,49] Blank[49,50] Line[50,54](2,52,-,2,tight)
      #|"# r\n\n<details>\t<summary>s</summary>\n\n## a\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"s") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Shut[43,54]
      #|"# r\n\n<details>\n<summary>x</summary>\n\n## h\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"x") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Shut[43,54]
      #|"- <details>\n  <summary>a</summary>\n\n  x\n\n  </details>\n"
      #|  → Line[0,2](1,2,-,2,tight) Card[2,54]["Details",{"open":false,"summary":"a","body":"x"}]
      #|"# r\n\n<details>\n<summary>a</summary>\n\n- a\n\n</details>\n\nx\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,53]["Details",{"open":false,"summary":"a","body":"- a"}] Blank[53,54] Card[54,56]
      #|"# r\n\n<details \"x>\n<summary>h</summary>\n\n## h\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,57]["Details",{"open":false,"summary":"h","body":"## h"}]
      #|"# r\n\n<details open>\n<summary>a</summary>\n\n- a\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,41](open,"a") Blank[41,42] Line[42,46](2,44,-,2,tight) Blank[46,47] Shut[47,58]
      #|"# r\n\n<details>\n<summary>h</summary>\n\n## **h**\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"h") Blank[36,37] Line[37,46](2,40,#0) Blank[46,47] Shut[47,58]
      #|"# a\n\n<details>\n<summary>b</summary>\n\n## b\n\n</details>\n\n---\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,54]["Details",{"open":false,"summary":"b","body":"## b"}] Blank[54,55] Card[55,59]"ThematicBreak"
      #|"# r\n\n<details open>\n<summary>h</summary>\n\n## h\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,41](open,"h") Blank[41,42] Line[42,47](2,45,#0) Blank[47,48] Shut[48,59]
      #|"# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\ntail\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,59]["Details",{"open":false,"summary":"h","body":"## h"}]
      #|"# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\n\n## b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"h") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Shut[43,54] Blank[54,55] Line[55,60](2,58,#0)
      #|"# r\n\n<details>\n<summary>h</summary>\n\n## h\n\nbody\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"h") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Card[43,48] Blank[48,49] Shut[49,60]
      #|"# r\n\n<details>\n<summary>**h**</summary>\n\n## **h**\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,40](-,"**h**") Blank[40,41] Line[41,50](2,44,#0) Blank[50,51] Shut[51,62]
      #|"# r\n\n<details class=\"x\">\n<summary>h</summary>\n\n## h\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,64]["Details",{"open":false,"summary":"h","body":"## h"}]
      #|"# r\n\n<details>\n<summary>y</summary>\n\n## y\n</details>\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,64]["Details",{"open":false,"summary":"y","body":"## y"}]
      #|"# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n#### deep\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"a") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Line[43,53](4,48,#0) Blank[53,54] Shut[54,65]
      #|"# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n</details>\n\n---\n\n## b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"a") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Shut[43,54] Blank[54,55] Border[55,59] Blank[59,60] Line[60,65](2,63,#0)
      #|"# r\n\n<details>\n<summary>a</summary>\n\n## a\n\nbody\n\n---\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"a") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Card[43,48] Blank[48,49] Card[49,53]"ThematicBreak" Blank[53,54] Shut[54,65]
      #|"- item\n\n  <details>\n  <summary>h</summary>\n\n  ## h\n\n  </details>\n"
      #|  → Line[0,7](1,2,-,2,tight) Blank[7,10] Fold[10,43](-,"h") Blank[43,46] Line[46,51](3,49,#0) Blank[51,54] Shut[54,65]
      #|"# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n---\n\n### x\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,66]["Details",{"open":false,"summary":"a","body":"## a\n\n---\n\n### x"}]
      #|"- a\n\n  <details>\n  <summary>b</summary>\n\n  - b\n\n  </details>\n\n  - c\n"
      #|  → Line[0,4](1,2,-,2,tight) Blank[4,7] Fold[7,40](-,"b") Blank[40,43] Line[43,47](2,45,-,2,tight) Blank[47,50] Shut[50,61] Blank[61,64] Line[64,68](2,66,-,2,tight)
      #|"# r\n\n## a\n\n---\n\n<details>\n<summary>c</summary>\n\n- c\n\n</details>\n\n- e\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Border[11,15] Blank[15,16] Fold[16,47](-,"c") Blank[47,48] Line[48,52](2,50,-,2,tight) Blank[52,53] Shut[53,64] Blank[64,65] Line[65,69](2,67,-,2,tight)
      #|"# root\n\n<details>\n<summary>head</summary>\n\n## head\n\n</details>\n\ntext\n"
      #|  → Line[0,7](1,2,#0) Blank[7,8] Card[8,63]["Details",{"open":false,"summary":"head","body":"## head"}] Blank[63,64] Card[64,69]
      #|"# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n</details>\n\n---\n\n---\n\n## b\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,54]["Details",{"open":false,"summary":"a","body":"## a"}] Blank[54,55] Card[55,59]"ThematicBreak" Blank[59,60] Border[60,64] Blank[64,65] Line[65,70](2,68,#0)
      #|"# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n</details>\n\n---\n\nsome text\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,54]["Details",{"open":false,"summary":"a","body":"## a"}] Blank[54,55] Card[55,59]"ThematicBreak" Blank[59,60] Card[60,70]
      #|"# root\n\n<details>\n<summary>head</summary>\n\n## head\n\n</details>\n\n### z\n"
      #|  → Line[0,7](1,2,#0) Blank[7,8] Fold[8,42](-,"head") Blank[42,43] Line[43,51](2,46,#0) Blank[51,52] Shut[52,63] Blank[63,64] Line[64,70](3,68,#0)
      #|"# a\n\n<details>\n<summary>b</summary>\n\n## b\n\n</details>\n\n<details>\n\n## c\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,54]["Details",{"open":false,"summary":"b","body":"## b"}] Blank[54,55] Card[55,65] Blank[65,66] Line[66,71](2,69,#0)
      #|"# r\n\n## h\n\n<details open>\n<summary>s</summary>\n\nbody\n\nmore\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Line[5,10](2,8,#0) Blank[10,11] Card[11,71]["Details",{"open":true,"summary":"s","body":"body\n\nmore"}]
      #|"# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n<?x </details> ?>\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"h") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Card[43,61] Blank[61,62] Shut[62,73]
      #|"# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n<!-- </details> -->\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"a") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Card[43,63] Blank[63,64] Shut[64,75]
      #|"# r\n\n<details>\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,76]["Details",{"open":false,"body":"<details>\n<summary>h</summary>\n\n## h\n\n</details>"}]
      #|"# root\n\n- head\n\n<details>\n<summary>head</summary>\n\n## head\n\n</details>\n\n- y\n"
      #|  → Line[0,7](1,2,#0) Blank[7,8] Line[8,15](2,10,-,2,tight) Blank[15,16] Fold[16,50](-,"head") Blank[50,51] Line[51,59](2,54,#0) Blank[59,60] Shut[60,71] Blank[71,72] Line[72,76](2,74,-,2,tight)
      #|"# r\n\n<details>\n<summary>h</summary>\n<summary>ZZZ</summary>\n\n## h\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,77]["Details",{"open":false,"summary":"h","body":"<summary>ZZZ</summary>\n\n## h"}]
      #|"# r\n\n<details>\n\n## s\n\n---\n\n<summary>z</summary>\n\n</details>\n\n### a\n\n### b\n\n## t\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,60]["Details",{"open":false,"summary":"z","body":""}] Blank[60,61] Line[61,67](3,65,#0) Blank[67,68] Line[68,74](3,72,#0) Blank[74,75] Line[75,80](2,78,#0)
      #|"# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n<pre><details></pre>\n\n</details>\n\n## h2\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,36] Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Card[43,76]["Details",{"open":false,"body":"</pre>"}] Blank[76,77] Line[77,83](2,80,#0)
      #|"# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n<script>\nvar x = \"</details>\";\n</script>\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"a") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Card[43,84] Blank[84,85] Shut[85,96]
      #|"# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n</details></details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"x") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Fold[43,74](-,"y") Blank[74,75] Line[75,81](3,79,#0) Shut[81,102]
      #|"# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n</details>\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"x") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Fold[43,74](-,"y") Blank[74,75] Line[75,81](3,79,#0) Shut[81,103]
      #|"# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n</details>\n\n<details>\n<summary>b</summary>\n\n## b\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"a") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Shut[43,54] Blank[54,55] Fold[55,86](-,"b") Blank[86,87] Line[87,92](2,90,#0) Blank[92,93] Shut[93,104]
      #|"# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n<details>\n<summary>a1</summary>\n\n### a1\n\n</details>\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"a") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Fold[43,75](-,"a1") Blank[75,76] Line[76,83](3,80,#0) Blank[83,84] Shut[84,95] Blank[95,96] Shut[96,107]
      #|"# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n<details open>\n<summary>a1</summary>\n\n### a1\n\n</details>\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"a") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Fold[43,80](open,"a1") Blank[80,81] Line[81,88](3,85,#0) Blank[88,89] Shut[89,100] Blank[100,101] Shut[101,112]
      #|"# a\n\n<details>\n<summary>b</summary>\n\n## b\n\n</details>\n\n<details class=\"z\">\n<summary>c</summary>\n\n## c\n\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Card[5,54]["Details",{"open":false,"summary":"b","body":"## b"}] Blank[54,55] Card[55,114]["Details",{"open":false,"summary":"c","body":"## c"}]
      #|"# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n\n<details>\n<summary>z</summary>\n\n#### z\n</details>\n</details>\n</details>\n"
      #|  → Line[0,4](1,2,#0) Blank[4,5] Fold[5,36](-,"x") Blank[36,37] Line[37,42](2,40,#0) Blank[42,43] Fold[43,74](-,"y") Blank[74,75] Line[75,81](3,79,#0) Blank[81,82] Fold[82,113](-,"z") Blank[113,114] Line[114,121](4,119,#0) Shut[121,154]
      #|
    ),
  )
}

///|
/// **畳みの中に書かれた `---` は、畳みの中に残る。** 前の読みは畳みの外へ出していた
/// （保留した水平線を吐き出すのが `</details>` で枠を降ろした後になるため）。
/// 記法構造は「中身は直前の `Line` が持つ」で位置のまま置くので、書き戻すと
/// **入力と 1 バイトも違わない**。corpus の往復で崩れていた最後の 1 通りがこれ。
test "畳みの中の水平線は、畳みの中に残る" {
  let md = "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\nbody\n\n---\n\n</details>\n"
  assert_eq(serialize(parse(md)), md)
  assert_eq(parse(serialize(parse(md))), parse(md))
}

///|
/// **記法構造は原文を 1 バイトも落とさない。** 触っていない列を書けば原文がそのまま返る。
/// 敷き詰めの法則を字の側から言い直したもので、範囲が 1 つでもずれていれば鳴る。
/// 木から綴り直す `serialize` とは別の道（あちらは正規形を出すので入力と違いうる）。
test "見本 — 触っていない記法構造を書けば、原文がそのまま返る" {
  for md in read_corpus {
    let back = write_pieces(notation(md))
    guard back == md else { fail("\{md.escape()}\n  → \{back.escape()}") }
  }
}
