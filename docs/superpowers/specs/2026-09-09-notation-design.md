# notation — 記法を木から追い出し、md の並びそのものに持たせる（設計）

#205。木が md の書き方を覚えるための欄を足し続けていて、md の記法を 1 つ覆うたびに
太る形になっている。**記法は木ではなく、md の並びそのものが持つ。** 木は構造と機能だけを
持ち、記法構造から導く使い捨てにする。

範囲は `core/tree` と `core/op` の境界、`core/view` の存在意義まで。map/ と app/ は
`View` を見ているだけなので触らない。#188 より大きい。

## いま何が起きているか

**木が綴りの欄を抱えている。** `Node` は 6 欄のうち `mark` が丸ごと綴りで、`Block` は
「読み解いた意味」と「読んだ原文」を同居させている。

```
Doc   { frontmatter, body : [Block], roots : [Root] }
Root  { node, sides : [Side], rules : [String] }
Node  { id, label, fold, body : [Block], children : [Node], mark : Mark? }
Block { id, content : Content?, source : String? }
Mark  = Heading { setext, closing } | Item { marker, offset, loose }
```

綴りだけの欄は 7 つ — `Mark` の 5 つ、`Block.source`、`Root.rules`。`rules` は型の doc で
自分を「**書き戻すためだけの欄**」と呼んでいる。

**位置は木の外に置いてある。** `build(md, ast)` の返りは `(Doc, Map[Int, Spot])`。木には
載せていない（載せると Doc が特定の原文に縛られるため）。合流はこの横持ちで突き合わせる。

**書き戻しは、全文を綴り直してから差分を取っている。** `merge.mbt`（802 行）は正規形を
base にした 3-way merge。

```
ours   = 原文（地番と原文の字）
base   = 前の木の正規形
theirs = 後の木の正規形
```

`base` と `theirs` が正規形なのは、木が原文を表せないから。**回り道の全部がここから出ている。**

**木は位置を表せない。** ノードの中身は「行の後ろ・子の前」にしか置けず、`Doc.body` は
「最初の骨格より前」だけ。子と子の間、根と根の間に場所が無い。

### 測ったこと（2026-09-09）

**壊れてはいない。** `test/fixtures` の 7 本 361 KB と、木の形の試験が読ませている md
156 通り（`corpus_wbtest.mbt`）を通した。

```
fixtures  7 本 361 KB   木として安定・字まで一致しないのは 2 本（見出しの末尾空白とタブ）
見本      156 通り      正規形が同じ 133 / 冪等 156 / 往復 153 / check 空 153
```

往復で崩れる 3 つは #203（根の詰まった列）#206（字下げコード）#207（CRLF）で、
どれも今の 2 層が原因ではない。**読んだ文書に対して今の形はほぼ正しい。**

歪みが出たのは「木が位置を表せない」ほうだけで、そこも #181 と #202 でほぼ塞いだ。
**急ぐ理由は無い。** 返すのは設計の借金で、バグではない。

## 決め

### 2 つ持つ

```
md ↔ mdAst        ライブラリ（mizchi/markdown）。触るのは md.mbt だけ（今と同じ）
mdAst → 記法構造   解釈を乗せた md の並びそのもの。原文・範囲・裁定を持つ
記法構造 → 木構造  構造と機能だけ取り出す。今の View にほぼ等しい
```

木への変更を記法構造へ当て、記法構造から md を書く。

**mdAst は段に出さない。** ライブラリの型を段の境界に置くと「差し替えがここに閉じる」
（`md.mbt`）が壊れる。記法構造は mmm 自身の型で、md の語彙に従うが `@markdown.Block` を
参照しない。**md の語彙に従うことと、ライブラリの型に依存することは別。**

### 記法構造は平ら

**並びが真実。親子は持たない。**

```moonbit
/// 記法構造 — md の並びそのもの。原文を隙間なく敷き詰める
struct Ast {
  frontmatter : String?
  pieces : Array[Piece]        // 文書順。前の to = 次の from
}

/// 塊 1 枚と、mmm がそれをどう読んだか
struct Piece {
  id : Int                     // 木と同じ番号。読み直すたびに文書順で振り直す
  from : Int
  to : Int
  col : Int                    // 原文での桁（項目の中の字下げ）
  source : String              // 読んだ字（桁を剥いだもの）
  kind : Kind                  // md がこれを何と言ったか
  verdict : Verdict?           // mmm がこれをどう読んだか。無ければ読み解いていない
}
```

親子を id で持つと、**並びと親子で真実が 2 つ**になる。ノードを動かすたび両方を整合させる
仕事が生まれ、型は整合を保証しない（孤児も循環も作れる）。並びだけを真実にすれば消える。

親子は並びと深さから出る。

```
部分木   その Line から、深さがそれ以下の次の Line の手前まで
子       その範囲の中で、深さがちょうど +1 の Line
中身     直前の Line が持つ Card
側       根の子の列を Right から歩き、Border ごとに裏返す
畳み     FoldOpen と FoldClose で挟まれた範囲
```

**深さは解決済みの値を持つ。** `#` の本数でも入れ子の段数でもなく、積まれた深さ。
境界が部分木を深さ 2 へ引き出す規則も、項目の相対記法も、読むときに 1 度だけ効かせる。
生の本数を持つと、並びだけでは部分木が切れない。

### 隙間も piece

敷き詰めるなら「塊の外」は存在しない。空行も `Piece` にして `Blank` と言う。
差し込みが「列に piece を 1 枚差す」で一様になる。

### kind は md の語彙、verdict は mmm の裁定

```moonbit
/// md のブロックの種類。**綴りはここが持つ**
enum Kind {
  Heading(level~ : Int, setext~ : Bool, closing~ : Int)
  ListItem(marker~ : String, offset~ : Int, loose~ : Bool)
  Paragraph
  FencedCode(info~ : String, fence~ : String, length~ : Int)
  IndentedCode
  HtmlBlock
  ThematicBreak(marker~ : String, count~ : Int)
  Table
  Blockquote
  MathBlock
  Directive(name~ : String)
  Alert(kind~ : String)
  FootnoteDefinition
  DefinitionList
  Definition                   // リンクの定義行。mdAst はブロックにしない
  Blank(count~ : Int)
}

/// mmm がその塊に見た意味。**構造はここが持つ**
enum Verdict {
  Node(depth~ : Int, label~ : String)      // 骨格の行になった。深さは解決済み
  Border                                    // 側の変わり目になった
  FoldOpen(open~ : Bool, summary~ : String?)
  FoldClose
  Card(content~ : Content?)                 // 中身になった。持ち主は直前の Node
}
```

同じ `ThematicBreak` が `Border` にも `Card` にもなり、同じ `HtmlBlock` が `FoldOpen` にも
`Card` にもなる。**どちらに読んだかを裁定が言う。**

**記法が増えても mmm の語彙が動かない。** 今は md の記法を覆うたびに `Mark` が太る。
新しい形では `Kind` に 1 つ足すだけで、`Verdict` は 5 つのまま。

名前は既にある言葉から取る。`verdict` は docs/spec.md の節「md の裁定」と同じ語。
`Piece` は `fold.mbt` の `priv enum Piece`（「積む前のひと切れ」）と同じ語で、
**`sift` の仕事を新しい層が吸収する**ので衝突ではなく合流。造語は増やさない。

### 木は導く。使い捨て

```moonbit
/// 木構造 — 綴りを 1 つも持たない
struct Node {
  id : Int
  label : String?              // Implicit だけ None
  fold : Fold?
  blocks : Array[Block]
  children : Array[Node]
}
```

`Mark` も `Root` も `sides` も `rules` も `Block.source` も `Doc.body` も消える。
今の `View` とほぼ同じ形なので、`core/view/project` の存在意義も無くなる。

木は入れ子のまま。`walk` / `splice` / 配置が入れ子を好むので、平らにする理由が無い
（`docs/core.md` の「Doc を id キーの平らな store にするか」は、**記法構造が平らになる
ことで用が済む**）。

### 入れ子をどこまで平らにするか

md の入れ子と mmm が読む入れ子は一致していない。**mmm が読み解く所だけ平らに開き、
読み解かない所は 1 枚で持つ。** 今の `sift` の再帰と同じ線。

```
項目の中     読み解く（項目の中は文書）  →  中の塊も piece。col が桁を言う
畳みの中     読み解く                    →  中の塊も piece。FoldOpen / FoldClose が挟む
引用の中     読み解かない                →  1 枚の piece
:::  の中    読み解かない                →  1 枚の piece
```

### 反映は「触った piece を差し替える」

記法構造が原文を持つので `ours` と `base` が同じものになり、**3 つの点が 2 つに潰れる**。

```
消す     その piece を列から抜く
書き換え その piece の source を差し替える
差す     隙間を決めて、字を組んで列に差す
```

md の編集列は、差し替えた piece の範囲から出る。触っていない piece は範囲がそのままなので、
**何もしないのが既定**になる。今は「触っていない所を触らない」ことを頑張って保証している。

`merge.mbt` の機能で言うと、`plan` / `canon_gaps` / `gaps` / `sided` / `plain` / `elements` /
`aligned` / `shape` / `faceless` の群が要らなくなる。`canon_gaps` は正規形で隙間を作り直す
関数、`gaps` は原文で隙間を測り直す関数で、**同じことを 2 通りで求めて突き合わせている**のは
正規形が隙間を知らないから。

引き継ぐのは 2 つ。**差すときの隙間を決める規則**（挿入だけが新しい字を要る）と、
**木の差分を記法構造の操作へ翻訳する層**（今は `unbuild` が全文を綴って差分が翻訳を
代行しているので存在しない）。字組み自体は `unbuild_node`（部分木 → md）をそのまま呼ぶ。

### 検証と安全網は残す

```moonbit
fn verified(md, edits, after) -> Bool {
  shape(parse(patched(md, edits))) == shape(after)
}
```

md の字の上でやっているので、中の作りが変わっても効く。落とし先の「全文を正規形に落とす」
も `unbuild` が全文を綴れる限り成立する。

**守るべき不変条件が 1 つ増える — 記法構造を捨てても木から全部綴り直せること。**

### core は状態を持たない

「操作 1 回ごとに md を読み直す」は変えない。記法構造を持ち回れば読み直しが消えるが、
`docs/core.md` の決めを崩す。速さ（#64）は別の軸として測る。

## 段の割り方

**読みを先に作り、木は今のまま。** 記法構造を作って `Doc` を導けるようにするまでが 1 段目で、
そこまでは既存の試験が全部の網になる。反映はその後。

```
1  記法構造の型と、mdAst → 記法構造            単体は piece の列の指紋
2  記法構造 → 木（今の Doc を導く）             既存の木の形の試験が全部通る
3  記法構造 → md（書き）                        corpus_wbtest の正規形が全部通る
4  木の差分 → 記法構造の編集（反映）             古い道の裏で走らせ、合った割合を数える
5  古い merge を外し、Doc から綴りの欄を落とす   木の形の試験を書き直すのはここ
```

`docs/superpowers/specs/2026-09-08-layers-design.md` の二段（段は 1 語の動詞、語彙は
1 文で言い切れる）はそのまま効く。

## 移行の測り方

**新しい道を古い検証の裏で走らせる。**

```
op → 記法構造の編集 → md → 読み直す → 木を比べる
                                        合えば採用
                                        合わなければ今の全文正規形へ落とす
```

最初は合わない場面が多くても壊れない。**合った割合を数えれば、どこまで出来ているかが
測れる。** 物差しは既にある。

```
core/tree/corpus_wbtest.mbt   読みの見本 156 通り（正規形・冪等・往復・破れ）
test/fixtures                 7 本 361 KB
core/op/law_wbtest.mbt        corpus × 全 id × 全 op の総当たり 1,700 通り
```

**捨てるのは実装、残すのは試験と決め。** `core/tree` の試験 8,997 行のうち、木の形で
言っている 84 か所は書き直しになるが、md の字で言っている分は生き残る。数か月かけて
詰めた md の裁定は実装ではなくそこに書いてある。

## 型が手放すもの

`core/tree/types.mbt` はこう書いている。

> **型が払うのは、走査から分岐が消えるときだけ。** 殺しているのは側が根の子にしか
> 無いことの 1 つで、それ以外は check とテストが受け持つ。

`Border` を piece にすると、それがどの深さにも書けるようになる。**型が殺していた唯一の
ことが check へ降りる**（今の `ListSide` の隣に「根の子以外の `Border`」が並ぶ）。
その代わり `Root` と `sides` と `rules` の 3 つが消え、側は導出になる。

## 却下した案

- **`Doc` に `tail`（子の後ろの中身）を足す。** 「全部の子の後ろ」しか言えず、子と子の
  間は表せない。`Doc.body` の非対称も残る
- **中身と子を 1 本の `limbs` にして、`sides` を Kid の部分列と並走させる。**
  添字が 2 種類になり、1 本にした利点をそこだけ捨てる
- **`limbs` にして side を `Kid` に載せる。** 深さ 3 以上の Kid で意味を持たない。
  型が大半の位置で嘘をつく
- **順序を id に持たせる（型は変えない）。** 読んだ順は id に入っているが、新しく足した
  中身の id は max+1 なので部分木の後ろに落ち、「子の前に足す」が言えなくなる
- **記法構造が `@markdown.Block` を包む。** ライブラリの型が段をまたいで漏れる
- **記法構造を持ち回って読み直しを省く。** 「core は状態を持たない」を崩す。速さは別軸

## 決まっていないこと

- **差すときの隙間を誰が決めるか。** 「隣の piece の隙間を真似る」で足りるか、
  今の「theirs の隙間を連れてくる、ただし項目の列は原文の兄弟の流儀が先」が要るか
- **合わなかったときの落とし先を狭められるか。** 今は全文正規形。記法構造なら
  「その piece だけ書き直す」まで狭められるかもしれない
- **`Definition`（リンクの定義行）を並びに入れるか。** mdAst はブロックとして返さず
  `Document.definitions` に分けて持つ。今は `restore` が原文の位置へ戻している
- **`Kind` をどこまで細かく持つか。** ライブラリの分類をそのまま写すか、mmm が
  読み解かないものをまとめるか
- **段 5 で木の形の試験をどうするか。** 新しい木の形に書き直すか、md の字の試験に
  寄せ切って捨てるか
