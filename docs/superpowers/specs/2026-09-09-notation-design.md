# notation — 記法を木から追い出し、md の並びに持たせる（設計）

#205。木が md の書き方を覚えるための欄を足し続けていて、記法を 1 つ覆うたびに太る。
**読んだ md の並びそのものを型にして、記法をそこに置く。** 木はそこから導く使い捨てにし、
構造と機能だけを持つ。

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

綴りの欄が 7 つ — `Mark` の 5 つ、`Block.source`、`Root.rules`。`rules` は型の doc で
自分を「**書き戻すためだけの欄**」と呼んでいる。

**ただし `Mark` は綴りだけではない。** 型の doc が「**種類はこれが持つ唯一の在り処**」と
書いていて、`sign_of` を `check` / `op` / `merge` の 13 か所が読む。落とすなら種類の
行き先を別に決める必要がある。

### ライブラリはその大半を持っている

`mizchi/markdown` の `Block` は 16 種で、綴りの欄が揃っている。

```moonbit
ThematicBreak(marker~ : Char, count~ : Int, span~, leading_trivia~, trailing_trivia~)
Heading(level~, style~ : HeadingStyle, children~, closing_hashes~, span~, ...)
FencedCode(fence_marker~, fence_length~, info~, code~, indent~, span~, ...)
BulletList(marker~ : BulletMarker, tight~, items~, span~, ...)
OrderedList(start~, delimiter~, tight~, items~, span~, ...)
IndentedCode / MathBlock / Directive / Blockquote / Alert / Table / HtmlBlock
DefinitionList / Attributed / FootnoteDefinition / BlankLines / Paragraph
```

**全部の塊が `leading_trivia` / `trailing_trivia : Trivia` を持つ。** 塊の前後の意味を
持たない字の置き場が型として在り、mmm は空を渡している。`ListItem` は `checked : Bool?`
（GFM のタスクリスト）も持つ。

**持っていないものが 2 つある。** どちらも mmm が原文から測り直している。

```
項目の marker   ライブラリは列の先頭から番号を振り直すので、飛んだ数字（`1.` の次が `5.`）が
                取れない。build.mbt:754 が原文を切る
項目の loose    CommonMark の tight は列のどこかに空行があれば偽。項目ごとには測れない。
                build.mbt:732 が原文の空行を項目ごとに測る
```

だから「記法はライブラリが全部持っている」は言い過ぎで、**正しくは「大半を持ち、2 つは
原文からしか取れない」**。この 2 つは記法構造が自分で測って持つ。

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
`marker_end` / `skip_blank` / `carve` の `column`。`fold.mbt` は 800 行の前半が丸ごと
`<details>` の字句解析。**同じ問い（どこまでが記法か）を、記法ごとに数え直している。**

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

### 段を足さない。`read` を伸ばす

新しい動詞は要らない。**`read` が md から記法構造まで読む。**

```
            read              build              project
md ───────> 記法構造 ───────> Doc + 地番 ──────> View
            write             unbuild
md <─────── 記法構造 <─────── Doc
```

`read` の中身は「ライブラリ + 方言 + 裁定」。畳みが立つかと深さの相互再帰
（`standing` ↔ `depths`）は段の中に閉じるので、`docs/core.md` の「段は一方向で、
相互再帰は段の中に閉じる」はそのまま守れる。今その再帰が `build` の中にあるのを、
`read` の中へ移すだけ。

**`unbuild` の行き先が mdAst から記法構造に変わる。** `serialize(doc) = write(unbuild(doc))`
は形のまま残り、読んだ文書を書き戻す道は `write(記法構造)` になる。

### 記法構造は、読んだ塊に裁定を足した平らな列

```moonbit
/// 読んだ md そのもの。**原文を隙間なく覆う**（前の to = 次の from）
struct Notation {
  frontmatter : @markdown.Frontmatter?
  pieces : Array[Piece]
}

/// 塊 1 枚と、mmm がそれをどう読んだか
struct Piece {
  block : @markdown.Block      // 記法・綴り・span・trivia はここが持つ
  verdict : Verdict?           // 無ければ読み解いていない
}

/// mmm がその塊に見た意味
enum Verdict {
  /// 骨格の行。深さは解決済み（`#` の本数でも入れ子の段数でもなく、積まれた深さ）。
  /// `marker` と `loose` はライブラリから取れないので、ここが原文から測って持つ
  Line(depth~ : Int, label~ : @markdown.Span, sign~ : Sign, marker~ : String, loose~ : Bool)
  Border                                          // 側の変わり目
  FoldOpen(open~ : Bool, summary~ : @markdown.Span?)
  FoldClose
  Card(content~ : Content?)                       // 中身。持ち主は直前の Line
}
```

同じ `ThematicBreak` が `Border` にも `Card` にもなり、同じ `HtmlBlock` が `FoldOpen` にも
`Card` にもなる。**どちらに読んだかを裁定が言う。**

`BlankLines` も塊なので、隙間も piece。**敷き詰めるなら「塊の外」は存在しない。**

**並びが真実。親子は持たない。** 親子を id で持つと真実が 2 つになり、動かすたび両方を
整合させる仕事が生まれる。親子は並びと深さから出る。

```
部分木   その Line から、深さがそれ以下の次の Line の手前まで
子       その範囲の中で、深さがちょうど +1 の Line
中身     直前の Line が持つ Card
側       根の子の列を Right から歩き、Border ごとに裏返す
畳み     FoldOpen と FoldClose で挟まれた範囲
```

**mmm が読み解く所だけ平らに開き、読み解かない所は塊 1 枚で持つ。** 今の `sift` の再帰と
同じ線 — 項目の中と畳みの中は開き、引用と `:::` の中は 1 枚。

### 木から消えるもの、残るもの

```
消える   Mark の綴り 5 欄 / Block.source / Root.rules / Doc.body
残る     id / label / fold / children / blocks / side / 種類（Sign）
```

**種類は残す。** `Mark` は綴りと種類を兼ねていて、種類のほうは `op` が席の綴りを決めるのに
読む（`sign_at` / `respell`）。`mark : Mark?` を `sign : Sign?` に痩せさせる — 綴りは落ちるが、
「見出しか項目か飛びか」は残る。

**`Doc.body` の行き先は未決。** 最初の骨格より前の散文は、新しい木にも `View` にも置き場が
無い（`project` が落としている）。記法構造の列が引き取るのが筋だが、`op` の
`BlockPlace::In(doc_id)` が今そこへ書いている。

### 反映は「触った piece を差し替える」

記法構造が原文を持つので `ours` と `base` が同じものになり、**3 つの点が 2 つに潰れる**。

```
消す     その piece を列から抜く
書き換え その piece の block を差し替える
差す     隙間を決めて、piece を組んで列に差す
```

置き換わるのは `merge.mbt` の**隙間の 3-way 本体**。`canon_gaps`（正規形で隙間を作り直す）
と `gaps`（原文で隙間を測り直す）が**同じことを 2 通りで求めて突き合わせている**のが
回り道の本体で、その答えを読む `gapped` / `headless` と、それを通る `merge_seq` /
`dropped` / `filled` / `grown` / `gap_text` / `merge_node` / `merge_children` / `merge_body` /
`loosened` が一緒に置き換わる。`elements` / `head_element` は `canon_gaps` 専用なので同時に消え、
`sided` / `plain` は `Root` と `sides` が消えることで用が無くなる。

**`shape` と `faceless` は残る。** 形の比較器で、`merge` の外の試験 6 ファイルが呼ぶ。

### `unbuild` は残る。木から綴り直す道は要る

**設計の前の版で「`unbuild` が要らなくなる」と書いたが、これは間違い。** 3 か所が要求している。

```
安全網          merge.mbt:73  操作後の木を全文 md に落とす。入力は木で、記法構造ではない
検証の 2 枝目    merge.mbt:90  木を正規形に書いて読み直した形と比べる（BorderBreak を通す枝）
新しく生えたもの  貼った行・AddBlock の中身・Adopt の子は piece を持たない。字は綴るしかない
```

安全網が特に効く。発火するのは「記法構造から書いた md を読み直したら形が違った」ときで、
**その列をもう一度書けば、さっき失敗した同じ字が出る**。落とし先になるには「意味から
綴り直す」別の道が要り、それが `unbuild`。

項目の列も同じ。`md.mbt` が自分で書いている — 「マーカー・ラベルの桁・詰めをライブラリの
書き手が読まないので、そこだけ mmm が組んだ字を生の塊で渡す」。項目を 1 つ差すだけでも
ライブラリの `serialize` では字が出ない。

**痩せるのは `unbuild` の前半。** 型の doc が既に「読んだ原文はそのまま返す。綴るのは
mmm が新しく作ったものだけ」と書いていて、記法構造ができれば前半（原文を返す道）が
piece に移り、後半（新しいものを綴る道）だけが残る。

### core は状態を持たない

「操作 1 回ごとに md を読み直す」は変えない。記法構造を持ち回れば読み直しが消えるが、
`docs/core.md` の決めを崩す。速さ（#64）は別の軸として測る。

## 段の割り方

**順番を決めているのは 1 つ — 綴りを落とした木は、もう全文 md を綴れない。**
だから**安全網の落とし先を先に付け替え**、そのうえで木を痩せさせる。

### 段 1 — `read` を記法構造まで伸ばす。誰も呼ばない

`read` の返りを `Notation` にする。今 `fold.mbt` が下している畳みの裁定と、`build` が
積みながら出している深さ・境界・ラベルの判断を、piece の裁定へ移す。互いに呼び合う
`standing` と `depths` は一緒に移す — 片方を `build` に残すと段をまたぐ再帰になる。

**この段がこの仕事の山。** 呼ぶ者がまだ居ないので、木も md も 1 つも変わらない。

網 — piece の列の指紋（塊の種類・裁定・範囲）を見本 162 通りで新しく置き、
**前の to と次の from が必ず合う**（原文を隙間なく覆う）ことを見る。

### 段 2 — `build` の入口を記法構造にする。木は今のまま

`build` が mdAst でなく `Notation` を読む。出す `Doc` は 1 欄も変えない — piece の字から
`Mark` の 5 欄・`Block.source`・`Root.rules` を埋め直す。**段 5 で捨てる道を書くことになる。**

それでも書くのは、**この段だけ既存の試験がまるごと網になる**から。読みの判断を全部
移し替えた直後に「木が 1 つも変わっていない」と言えるのは、ここしかない。

網 — 木の形で言う試験 84 か所と地番の指紋（`spans_wbtest`）が、1 字も書き換わらずに通る。

### 段 3 — 記法構造から md を書く道を足す

`write` が piece の列を受けて md を書く。読んだ文書の書き戻しをそちらへ載せ替える。

**`unbuild` は残す。** 安全網も検証の 2 枝目も、新しく生えたものを綴る道も、まだ木から
書いている。ここで消せると思って進めると、段 5 で落とし先を失う。

網 — 見本 162 通りの正規形・冪等・往復と fixtures 7 本が、1 字も動かない。

### 段 4 — 反映を記法構造の上でやる。古い道の裏で走らせる

木の差分を「piece を抜く」「piece を差し替える」「隙間を決めて差す」に訳す層を書き、
古い 3-way の**裏で**走らせて字を突き合わせる。差す piece の隙間を誰が決めるかは、ここで決める。

返す答えは古い道のままなので、出る md は 1 字も変わらない。**一致した割合がそのまま
進み具合になる。**

網 — `law_wbtest` の総当たり 1,700 通りと `merge_law_wbtest` が今のまま通る。

### 段 5 — 落とし先を付け替えてから、木を痩せさせる

**順番がある。**

```
5a  安全網と検証の入力を、木から記法構造へ付け替える
5b  木から綴りの欄を落とす（Mark の 5 欄 / Block.source / Root.rules / Doc.body）
5c  古い 3-way の群と core/view/project、段 2 で書いた埋め直しを消す
```

5a を飛ばすと、綴りを落とした木で全文 md を綴ろうとして詰む。`Mark` は種類も持つので、
種類は `Sign` として木に残す。`Doc.body` の行き先はここで決める。

網 — 木の形で言う 84 か所は書き直すが、**md の字で言う分は 1 つも落とさない**。
見本 162 通り・fixtures 7 本・総当たり 1,700 通りがそのまま通る。

### 止めどき

段 1 は足すだけ。段 2 と段 3 は既存の試験が網。段 4 は古い道が残っている。
**段 5 に入るまで、どこで止めても壊れない。**

## 移行の測り方

**古い検証はどの段でも動く。** md の字の上でやっているので、中の作りが変わっても効く。
ただし今の検証は 2 枝あり、2 枝目が木の全文 md を要求している（上の「`unbuild` は残る」）。

段 4 だけ、新しい道をこの検証の裏で走らせる。

```
op → 記法構造の編集 → md → 読み直す → 木を比べる
                                        合えば採用
                                        合わなければ古い道の答えを使う
```

**捨てるのは実装、残すのは試験と決め。** 数か月かけて詰めた md の裁定は、実装ではなく
試験に書いてある。

```
core/tree/corpus_wbtest.mbt     読みの見本 162 通り                段 1〜3
test/fixtures                   7 本 361 KB                       段 1〜3
core/op/law_wbtest.mbt          見本 × 全 id × 全 op 1,700 通り    段 4
core/tree/merge_law_wbtest.mbt  見本 × 全ノード × 変え方           段 4
```

## 型が手放すもの

`core/tree/types.mbt` は「型が払うのは走査から分岐が消えるときだけ。殺しているのは
側が根の子にしか無いことの 1 つ」と書く。`Border` を piece にすると、それがどの深さにも
書けるようになる。**その 1 つが check へ降りる**（`ListSide` の隣に「根の子以外の
`Border`」が並ぶ）。代わりに `Root` と `sides` と `rules` が消え、側は導出になる。

## 却下した案

- **段を足す（`sift` / `mark` / `tile` などの新しい動詞）。** `read` を伸ばせば足りる。
  特に `sift` は「綴りを落とす」が定義（型が `gone` を持つ）で、1 枚も落とさず敷き詰める
  新しい層とは逆を言う
- **`Kind` を自前で写す。** ライブラリの `Block` 16 種と綴りの欄を書き写すことになる。
  写した先が古びるし、`Trivia` のように既に在るものを作り直す
- **`Doc` に `tail`（子の後ろの中身）を足す。** 「全部の子の後ろ」しか言えず、子と子の
  間は表せない
- **中身と子を 1 本の `limbs` にする。** `sides` が Kid の部分列と並走して添字が 2 種類に
  なるか、side を `Kid` に載せて深さ 3 以上で意味を持たない欄になる
- **順序を id に持たせる（型は変えない）。** 新しく足した中身の id は max+1 なので
  部分木の後ろに落ち、「子の前に足す」が言えなくなる
- **記法構造を持ち回って読み直しを省く。** 「core は状態を持たない」を崩す

## 決まっていないこと

- **型の名。** `Ast` は `ast_sig`（mdAst の指紋）と紛れるので落とした。`Notation` は
  正確だが長い。`Sheet` / `Script` も候補
- **`Verdict` の名前衝突。** `fold.mbt` の `priv struct Verdict`（消える）と `merge.mbt` の
  `fn verdict`（残る）が同じ語。片方を改名する
- **id の対応。** 木の id は走査で振る通し番号で、Implicit は piece を持たないのに id を
  持つ。並びの id と木の id は 1 対 1 にならない
- **`Doc.body` の行き先。** 木にも `View` にも置き場が無い。`op` の `BlockPlace::In(doc_id)` が
  今そこへ書いている
- **ラベルを字で持つか、範囲で持つか。** 上の型は範囲にした。「読んだ字は 1 か所」に
  揃うが、木を組むたびに切り出す
- **`Trivia` を使うか、`BlankLines` の塊で足りるか。** 隙間が両方に書ける
- **差すときの隙間を誰が決めるか。** 「隣の piece の隙間を真似る」で足りるか
- **安全網の落とし先を狭められるか。** 「全文を正規形に」から「合わなかった piece だけ」へ
- **`Attributed` と `DefinitionList` をどう扱うか。** mmm は今どちらも読んでいない

## この設計で消える暫定の直し

- **#206（字下げコードの span に 4 桁を戻す）** — 読みと書きが同じ塊を見るなら、
  ライブラリが自分の解釈で 4 桁を書き戻す
- **方言の span 直し 5 つのいくつか** — 往復が閉じるなら、span がずれていても困らない。
  残るのは「読み落とした塊」（`measured`）だけかもしれない
