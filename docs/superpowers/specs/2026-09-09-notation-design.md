# notation — 記法を木から追い出し、ライブラリの塊に mmm の裁定を足す（設計）

#205。木が md の書き方を覚えるための欄を足し続けていて、記法を 1 つ覆うたびに太る。
**記法はライブラリの塊が既に持っている。** mmm はそこに裁定を足すだけにして、木は構造と
機能だけを持つ使い捨てにする。

範囲は `core/tree` と `core/op` の境界、`core/view` の存在意義まで。map/ と app/ は
`View` を見ているだけなので触らない。#188 より大きい。

## 事実

### 木が綴りの欄を抱えている

```
Doc   { frontmatter, body : [Block], roots : [Root] }
Root  { node, sides : [Side], rules : [String] }
Node  { id, label, fold, body : [Block], children : [Node], mark : Mark? }
Block { id, content : Content?, source : String? }
Mark  = Heading { setext, closing } | Item { marker, offset, loose }
```

綴りだけの欄が 7 つ — `Mark` の 5 つ、`Block.source`、`Root.rules`。`rules` は型の doc で
自分を「**書き戻すためだけの欄**」と呼んでいる。

### ライブラリはそれを全部持っている

`mizchi/markdown` の `Block` は 16 種で、綴りの欄が揃っている。

```moonbit
ThematicBreak(marker~ : Char, count~ : Int, span~, leading_trivia~, trailing_trivia~)
Heading(level~, style~ : HeadingStyle, children~, closing_hashes~, span~, ...)
FencedCode(fence_marker~, fence_length~, info~, code~, indent~, span~, ...)
IndentedCode(code~, span~, ...)
MathBlock(value~, fence_length~, span~, ...)
Directive(name~, meta~, children~, fence_length~, span~, ...)
BulletList(marker~ : BulletMarker, tight~, items~, span~, ...)
OrderedList(start~, delimiter~, tight~, items~, span~, ...)
Blockquote / Alert(kind~) / Table / HtmlBlock / DefinitionList / Attributed
FootnoteDefinition(label~) / BlankLines(count~) / Paragraph
```

**全部の塊が `leading_trivia` / `trailing_trivia : Trivia` を持つ。** 中身は `String` 1 つで、
塊の前後の意味を持たない字の置き場。mmm は空を渡していて、代わりに `Root.rules` と
`Block.source` で同じことをしている。

`ListItem` は `checked : Bool?` を持つ（GFM のタスクリスト）。#180 で「ラベルに `[ ]` が
入っていない」と言っていたのは、ライブラリが分けて持っていたから。

mmm が `Mark` に潰していたものも、元は分かれている。`style`（ATX / setext）、
`start` と `delimiter`（`1.` / `1)`）、`fence_marker` と `fence_length` と `indent`。

### 閉じ込めは既に半分しか効いていない

`md.mbt` は「ライブラリに触るのはこのファイルだけ — 差し替えがここに閉じる」と書くが、
実測では科の中で 5 ファイル・98 か所が触っている。

```
core/tree/md.mbt        29 か所   方言
core/tree/build.mbt     24 か所   積む
core/tree/unbuild.mbt   20 か所   書く
core/tree/fold.mbt      17 か所   畳みの裁定
core/tree/content.mbt    8 か所   意味の読み取り
```

守れているのは**科の境界**のほうで、`core/op` も `core/map` も `core/view` も `@markdown` を
1 度も見ない。`moon.pkg` で import しているのも `core/tree` だけ。

書く側は最初から依存している。`unbuild` は `@markdown.Block` を組んで `serialize` に渡す —
**型を通貨として使わないと書けない**。

### 記法の在り処を、段ごとに数え直している

方言（`md.mbt`）の span 直しは 5 つ。**うち 2 つは 2026-09-09 に足した。**

```
closed          フェンス付きの塊の尻を閉じの行の改行まで（ライブラリは手前で止める）
unswallowed     伸ばした span に飲まれた塊を落とす
after_newline   定義行の span を改行込みに
measured        空の span を原文から測り直す              #46
undent          字下げコードの span に記法の 4 桁を戻す    #206
```

読み（`build.mbt`）にも同じ仕事が 6 つ。`head_start` / `head_label` / `item_start` /
`marker_end` / `skip_blank` / `carve` の `column`。どれも「記法を読み飛ばして中身の頭を
見つける」。`fold.mbt` は 800 行の前半が丸ごとそれで、`<details>` の字句解析を自分で書いている。

**同じ問い（どこまでが記法か）を、記法ごとに数え直している。**

### 壊れてはいない

`test/fixtures` の 7 本 361 KB と、木の形の試験が読ませている md 162 通り
（`corpus_wbtest.mbt`）を通した。

```
fixtures  7 本 361 KB   木として安定・字まで一致しないのは 2 本（見出しの末尾空白とタブ）
見本      162 通り      正規形が同じ 139 / 冪等 162 / 往復 159 / check 空 159
```

往復で崩れる 3 つは #203（根の詰まった列）#207（CRLF が混ざる）と畳みの角で、
どれも今の 2 層が原因ではない。**返すのは設計の借金で、バグではない。**

## 決め

### 2 つ持つ

```
md ↔ mdAst        ライブラリ。読みも書きもここが正義
mdAst → 記法構造   ライブラリの塊に mmm の裁定を足す。並びは md のまま
記法構造 → 木構造  構造と機能だけ取り出す。今の View にほぼ等しい
```

木への変更を記法構造へ当て、記法構造の塊を `serialize` に渡して md を書く。

### 記法構造はライブラリの塊に裁定を足したもの

```moonbit
/// 記法構造 — md の並びそのもの。塊はライブラリのものをそのまま持つ
struct Ast {
  frontmatter : @markdown.Frontmatter?
  pieces : Array[Piece]        // 文書順。原文を隙間なく敷き詰める
}

/// 塊 1 枚と、mmm がそれをどう読んだか
struct Piece {
  block : @markdown.Block      // 記法・綴り・span・trivia はここが持つ
  verdict : Verdict?           // 無ければ読み解いていない
}

/// mmm がその塊に見た意味。**構造はここが持つ**
enum Verdict {
  /// 骨格の行。深さは解決済み（`#` の本数でも入れ子の段数でもなく、積まれた深さ）。
  /// `label` は原文の範囲で持つ — 字は span 1 か所
  Node(id~ : Int, depth~ : Int, label~ : @markdown.Span)
  Border                                          // 側の変わり目
  FoldOpen(id~ : Int, open~ : Bool, summary~ : @markdown.Span?)
  FoldClose
  Card(id~ : Int, content~ : Content?)            // 中身。持ち主は直前の Node
}
```

同じ `ThematicBreak` が `Border` にも `Card` にもなり、同じ `HtmlBlock` が `FoldOpen` にも
`Card` にもなる。**どちらに読んだかを裁定が言う。**

**`Mark` も `Kind` も要らない。** ライブラリの塊が綴りを持っている。
**`Block.source` も `Root.rules` も要らない。** `span` が原文を指し、`Trivia` が前後の字を持つ。
**`Doc.body` の非対称も消える。** 文書はただの並び。

**記法が増えても mmm の語彙が動かない。** ライブラリが `Block` に 1 種足すだけで、
`Verdict` は 5 つのまま。今は md の記法を覆うたびに `Mark` が太る。

### 守る線は科の境界

「ライブラリに触るのは 1 ファイル」はもう嘘なので捨てる。代わりに

> **ライブラリの型が出るのは記法構造の科まで。木構造から先には出ない。**

今の実態（`core/tree` の中だけ・科の境界は守られている）を、名前と型で正直に書き直す。
差し替えの代償は変わらない — 今も 5 ファイル 98 か所が同時に動く。変わるのは、
依存を隠すのをやめることだけ。

### 記法構造は平ら

**並びが真実。親子は持たない。** 親子を id で持つと真実が 2 つになり、ノードを動かすたび
両方を整合させる仕事が生まれる。型は整合を保証しない（孤児も循環も作れる）。

```
部分木   その Node から、深さがそれ以下の次の Node の手前まで
子       その範囲の中で、深さがちょうど +1 の Node
中身     直前の Node が持つ Card
側       根の子の列を Right から歩き、Border ごとに裏返す
畳み     FoldOpen と FoldClose で挟まれた範囲
```

`BlankLines` も塊なので、隙間も piece。**敷き詰めるなら「塊の外」は存在しない。**

### 入れ子をどこまで平らにするか

md の入れ子と mmm が読む入れ子は一致していない。**mmm が読み解く所だけ平らに開き、
読み解かない所は塊 1 枚で持つ。** 今の `sift` の再帰と同じ線。

```
項目の中     読み解く（項目の中は文書）  →  中の塊も piece
畳みの中     読み解く                    →  中の塊も piece。FoldOpen / FoldClose が挟む
引用の中     読み解かない                →  1 枚の piece
:::  の中    読み解かない                →  1 枚の piece
```

### 木は導く。使い捨て

```moonbit
struct Node {
  id : Int
  label : String?              // Implicit だけ None
  fold : Fold?
  blocks : Array[Block]
  children : Array[Node]
}
```

綴りを 1 つも持たない。今の `View` とほぼ同じ形なので、`core/view/project` の存在意義も
無くなる。木は入れ子のまま — `walk` / `splice` / 配置が入れ子を好むので、平らにする理由が
無い（`docs/core.md` の「Doc を id キーの平らな store にするか」は、**記法構造が平らに
なることで用が済む**）。

### 反映は「触った塊を差し替える」

記法構造が原文を持つので `ours` と `base` が同じものになり、**3 つの点が 2 つに潰れる**。

```
消す     その piece を列から抜く
書き換え その piece の block を差し替える
差す     隙間を決めて、塊を組んで列に差す
```

md は `serialize` に列を渡すだけ。**`unbuild`（木 → mdAst）が要らなくなる。** 今は全文を
綴り直してから差分を取っているが、それは木が原文を表せないからやっている回り道。

`merge.mbt` の `plan` / `canon_gaps` / `gaps` / `sided` / `plain` / `elements` / `aligned` /
`shape` / `faceless` の群が要らなくなる。`canon_gaps` は正規形で隙間を作り直す関数、
`gaps` は原文で隙間を測り直す関数で、**同じことを 2 通りで求めて突き合わせている**のは
正規形が隙間を知らないから。

引き継ぐのは 2 つ。**差すときの隙間を決める規則**（挿入だけが新しい字を要る）と、
**木の差分を記法構造の操作へ翻訳する層**（今は差分が翻訳を代行しているので存在しない）。

### 検証と安全網は残す

読み直して形を比べる検証も、合わなければ全文を正規形に落とす安全網も、そのまま残す。
md の字の上でやっているので、中の作りが変わっても効く（下の「移行の測り方」）。

### core は状態を持たない

「操作 1 回ごとに md を読み直す」は変えない。記法構造を持ち回れば読み直しが消えるが、
`docs/core.md` の決めを崩す。速さ（#64）は別の軸として測る。

## 段の割り方

**順番を決めているのは 1 つ — 木から綴りを落とすと、木から md が書けなくなる。**
`unbuild`（木 → mdAst）と、合流の安全網（全文を正規形に落とす）はそれに乗っている。
だから**書きを記法構造へ移すのが、木を痩せさせるより先**。

```
1  記法構造の型と読み      mdAst → Ast。誰も使わない            piece の列の指紋
2  木を記法構造から導く    Ast → 今の Doc（綴り込み）            既存の試験が全部の網
3  書きを記法構造から      Ast → md。unbuild は残すが使わない    corpus_wbtest の正規形
4  反映を記法構造の上で    木の差分 → piece の差し替え           古い道の裏で割合を数える
5  木から綴りを落とす      unbuild と古い merge を消す           木の形の試験を書き直す
```

**段 1 は足すだけ。** 何も壊れない。中身は今の `sift`（畳みの裁定）と `build`（深さの
解決・境界の判定）の判断を Ast の裁定に移す作業で、**そこがこの仕事の山**。
単体は piece の列の指紋（塊の種類と裁定と範囲を並べたもの）で固定する。

**段 2 で切り替える。** `Ast → Doc` を書き、`build` を差し替える。今の `Doc` は綴りを
持つので、`Mark` を `block` から、`source` を `span` から、`rules` を `Border` の piece から
組み直すことになる — **捨てる予定のコードを書く**。それでも書くのは、この段だけ既存の
試験 8,997 行が丸ごと網になるから。**網が要るのはまさにここ**で、読みの裁定を丸ごと
移し替えた直後に、木の形が 1 つも変わっていないことを言える。

**段 3 で書きを移す。** `serialize` が piece の `block` を `@markdown.serialize` に渡すだけに
なる。`unbuild` はまだ消さない — 段 4 の安全網が「全文を正規形に落とす」で使う。
網は `corpus_wbtest` の正規形の表で、**162 通りの答えが 1 つも動かないこと**を見る。

**段 4 で反映を移す。** ここだけ古い道と新しい道が並走する。詳しくは下の「移行の測り方」。

**段 5 で痩せさせる。** `Mark` / `Block.source` / `Root.rules` / `Doc.body` の非対称を外し、
`Doc` を今の `View` の形にする。`core/view/project` も、段 2 で書いた `Ast → Doc` の
綴りを組み直す部分も、`unbuild` も、`merge.mbt` の正規形との照合の群もここで消える。
**木の形で言っている試験 84 か所を書き直すのもここ。**

`2026-09-08-layers-design.md` の二段（段は 1 語の動詞、語彙は 1 文で言い切れる）はそのまま効く。

## 移行の測り方

**古い検証はどの段でも動く。** md の字の上でやっているので、中の作りが変わっても効く。

```moonbit
fn verified(md, edits, after) -> Bool {
  shape(parse(patched(md, edits))) == shape(after)
}
```

段 4 だけ、新しい道を**この検証の裏で走らせる**。

```
op → 記法構造の編集 → md → 読み直す → 木を比べる
                                        合えば採用
                                        合わなければ今の全文正規形へ落とす
```

最初は合わない場面が多くても壊れない。**合った割合を数えれば、どこまで出来ているかが
測れる。** 100% になったら古い `merge` を外す（段 5）。

物差しは既にある。

```
core/tree/corpus_wbtest.mbt   読みの見本 162 通り（正規形・冪等・往復・破れ）  段 1〜3
test/fixtures                 7 本 361 KB                                    段 1〜3
core/op/law_wbtest.mbt        corpus × 全 id × 全 op の総当たり 1,700 通り    段 4
core/tree/merge_law_wbtest.mbt  見本 × 全ノード × 変え方                      段 4
```

**捨てるのは実装、残すのは試験と決め。** `core/tree` の試験のうち木の形で言っている
84 か所は段 5 で書き直しになるが、md の字で言っている分は生き残る。数か月かけて詰めた
md の裁定は、実装ではなくそこに書いてある。

**各段は独立に測れて、途中で止めても壊れない。** 段 1 は足すだけ、段 2 と段 3 は既存の
試験が網、段 4 は古い道が残っている。止めどきを選べる形にしてある。

## 型が手放すもの

`core/tree/types.mbt` は「型が払うのは走査から分岐が消えるときだけ。殺しているのは
側が根の子にしか無いことの 1 つ」と書く。`Border` を piece にすると、それがどの深さにも
書けるようになる。**その 1 つが check へ降りる**（`ListSide` の隣に「根の子以外の
`Border`」が並ぶ）。代わりに `Root` と `sides` と `rules` が消え、側は導出になる。

## 却下した案

- **`Kind` を自前で写す。** ライブラリの `Block` 16 種と綴りの欄を全部書き写すことになる。
  写した先が古びるし、`Trivia` のように既に在るものを作り直す
- **`Doc` に `tail`（子の後ろの中身）を足す。** 「全部の子の後ろ」しか言えず、子と子の
  間は表せない
- **中身と子を 1 本の `limbs` にする。** `sides` が Kid の部分列と並走して添字が 2 種類に
  なるか、side を `Kid` に載せて深さ 3 以上で意味を持たない欄になる
- **順序を id に持たせる（型は変えない）。** 新しく足した中身の id は max+1 なので
  部分木の後ろに落ち、「子の前に足す」が言えなくなる
- **記法構造を持ち回って読み直しを省く。** 「core は状態を持たない」を崩す

## 決まっていないこと

- **ラベルを字で持つか、範囲で持つか。** 上の型は範囲（`@markdown.Span`）にした。
  「読んだ字は 1 か所」に揃うが、木を組むたびに切り出す
- **`Trivia` を使うか、`BlankLines` の塊で足りるか。** 隙間が両方に書ける
- **差すときの隙間を誰が決めるか。** 「隣の塊の隙間を真似る」で足りるか
- **合わなかったときの落とし先を狭められるか。** 今は全文正規形。記法構造なら
  「その塊だけ書き直す」まで狭められるかもしれない
- **`Attributed` と `DefinitionList` をどう扱うか。** mmm は今どちらも読んでいない
- **段 5 で木の形の試験をどうするか。** 新しい木の形に書き直すか、md の字の試験に
  寄せ切って捨てるか

## この設計で消える暫定の直し

- **#206（字下げコードの span に 4 桁を戻す）** — 書く側が塊を `serialize` に渡すなら、
  ライブラリが自分の解釈で 4 桁を書き戻すので、戻す必要が無くなる
- **方言の span 直し 5 つ** — 読みと書きが同じ塊を見るなら、span がずれていても
  往復は閉じる。残るのは「読み落とした塊」（`measured`）だけかもしれない
