# core — 文書モデルの内部

md が何を意味するか（方言の裁定）は [spec.md](spec.md) の「md の裁定」。
ここはその意味を **core がどう持ち、どう回すか**だけを書く。

**いま作り直している最中。** ここは今のコードの説明ではなく、これから作る形。

## 型

```
Doc  { frontmatter: String?, eol: Eol, body: [Block], roots: [Root] }
Root { node: Node, sides: [Side] }          // 側を持つ唯一の型。根の子と並走

Node = HeadingNode | ListNode | ImplicitNode   // 構築子は型名と同じ。タグに意味は無い

HeadingNode  { id, label, fold: Fold?, body: [Block], children: [Node] }
Fold         { open, summary: String? }        // 在ること自体が「畳まれている」
ListNode     { id, label, fold: Fold?, body: [Block], children: [ListNode] }
ImplicitNode { id, children: [Node] }       // 記法を持たない

Side  = Right | Left
Eol   = Lf | Crlf
Block   { id, content: Content }            // 中身 1 枚。id はノードと同じ列
Content = Image | Link | Code | Svg         // 解釈の包みは無い
        | ThematicBreak                     // 境界にならなかった水平線
        | Details(text)                     // <details>。領域の原文
        | Opaque(text)                      // 読み解かない原文
```

**id はノードにも中身にも、1 つの列で振る。** 中身がノードと同じ番号を
持つので、引き当てる・選ぶ・動かすが型の上で割れない。「解釈できた /
できなかった」を Result で包むことはせず、Opaque という名前が担う。

**型が言うのは「あり得ない形」だけ**で、仕様を満たすのは実装の仕事。
型の上で作れるものは何でも許容し、細かい充足はテストが受け持つ。

型で殺しているのは 3 つ:

- **項目の子孫は項目**（`ListNode.children : [ListNode]`）。項目の根に見出しが
  生えないことも同時に決まる。項目は相対記法で飛べないので Implicit も無い
- **Implicit は記法を持たない**（`ImplicitNode` に label / body / fold が無い）。
  包む見出し・項目の行が無いので**畳めないことも同時に決まる**（`fold` が無い）
- **側は根の子だけ**（`sides` は `Root` にしか無い）。深いノードは側を持てない

`children` を全部の深さで `[Node]` に保つため、側は組にせず並走させる
（深さで型が変わると走査も操作も割れる）。長さが揃うことは型では言えない。

check が見るもの — id 一意（ノードも中身も） / Implicit は子を持つ / `sides` と根の子の長さが揃う /
畳みの名前が `<summary>` に書ける。**`open` と名前が畳みのときだけ在ることは
型が殺す**（`fold : Fold?` に括ってあるので、畳みでなければ持ちようがない）。

### View — map が見る木

`project(Doc)`（`view/`）が Doc から**削るだけ**で作り、JSON で ts へ渡す。
足すものは無い。

```
Tree { node: Node, sides: [Side] }          // 側は Root と同じ。根の子と並走
Node { id, label: String?, fold: Fold?, blocks: [Block], children: [Node] }
```

- **ノードの種類は無い。** Doc が 3 種に分けている理由は全部 md の書き方の
  制約で、描く側には 1 つも要らない
- **Implicit は `label` が無い。** 空の見出し（`## `）は `Some("")` なので
  型で区別が付く。旗も種類も要らない
- **`blocks` は body から Opaque を落としたもの。** core が「読み解かない」と
  裁定したものだけが map に届かない。何がカードかは描く側の分類のまま
- 書き戻すためだけの欄（frontmatter・eol・散文の body）は無い
- **id は Doc のまま。** 読みが文書順に振った通し番号で、Opaque にも振ってある
  ので、落としても残りの番号は動かない（View の添字を body の添字へ読み替える
  段は要らない）。順序を id に読ませない

## パイプライン

```
読み   md ──mizchi/markdown──> mdAst ──build──> Doc
書き   Doc ──unbuild──> mdAst ──mizchi/markdown──> 正規形の md
反映   操作 ──触った範囲だけ正規形に置換──> 編集リスト ──> CodeMirror
```

**サイクルは 1 本**。md が変わったら必ず 読み → project → 描画。無限ループしないのは
「**書くのは操作だけ。読みのサイクルは決して書かない**」から。

**id は読みのサイクルを越えて持たない。** 読みが文書順に振る通し番号で、
位置そのもの。上に 1 つ足せば以降が全部ずれるので、render も選択も id を
抱え込まず、サイクルごとにいまの木から引き直す（md を打っている間は caret が
span から、操作の後は操作の結果から）。UUID にしても読み直せば別の値になるだけで、
同一性は形式では買えない。木をまたいで引き当てる reconcile は、枝の移動を
アニメーションで見せたくなるまで要らない。

反映の手順:

1. 操作が「自分はここを触った」と**申告する**(木を比較しない)
2. 触ったノードは、**span の範囲**をそのノードの正規形で置き換える
3. どのノードにも属さないもの(水平線の空行・frontmatter)は
   **隣の span から範囲が出る** — `from = 前の span.to` / `to = 次の span.from`
4. 入れ子は**一番上だけ**書き換える(範囲が重ならないように)
5. 出来た文章を**読み直して木と一致するか検証**。違えば全文正規形へ落ちる
6. 編集リストを 1 トランザクションで渡す。カーソルと undo は CodeMirror の仕事

正しさは 5 の検証が持つ。だから 1〜4 がどれだけ雑でも壊れない。

## パスの積み方

**結合テストは単体テストが終わってから。** 最後まで作ってから回すと、落ちた
ときに何が壊れたか割り出せない。パスは少しずつ作り、各パスに自分のテストを
付けてから次へ行く。

- `md_wbtest.mbt` がライブラリ(mdAst)の読みを指紋で固定し、その先が我々の読みを固定する
- `lab/` が mdAst と mmmTree を並べて出すのも、どの段で壊れたかを切り分けるため
- **serialize のテストは木を手で組む。`parse` で作らない** — `serialize(parse(md))`
  と書くと、書きのテスト全部が読みに依存する
- **書きで我々が持つのは骨格だけ**（深さ → `#`、側の変わり目 → 水平線、畳み → `<details>`）。
  中身とラベルは md として読み直して mdAst に戻す。字下げ・フェンス長・空行・
  エスケープ・定義行の置き場はライブラリの serializer の仕事で、その正規化
  （`_em_` → `*em*`、水平線は `***`、定義行は末尾へ、setext → ATX）は
  **この段では素直に受ける**。補正するなら反映の段
- 往復(法則 1)・冪等(法則 2)・総当たりは、両側の単体が揃ってからの別パス

## 操作

`op/` が `apply(doc, op) -> Done?` で Doc を Doc にする。md も CodeMirror も知らない
純粋な関数で、`None` は「できない操作」。表に出るのはこれと型だけ。

```
NodePlace  = Before(node~)  | After(node~)  | In(node~, side: Side?)   // ノードの席。子の列
BlockPlace = Before(block~) | After(block~) | In(node~)                 // 中身の席。body の列

Op = Add(at: NodePlace, labels)   | AddBlock(at: BlockPlace, content)
   | Rename(id, label)            | SetBlock(id, content)
   | Move(ids, at: NodePlace)     | MoveBlock(ids, at: BlockPlace)
   | Delete(ids)                  // ノードも中身も
   | Wrap(id, label) | FlipSide(id) | Fold(id, open) | Unfold(id)
   | Graft(at: NodePlace, md)

Done = { doc, focus: Int? }       // 操作後の木と、そこで選ぶべき id
```

**席は隣の id で言う。添字は持たない。** `In` は列の末尾で、隣が無い（空の親・
空の body）ときの唯一の入口。`In(doc_id)` が新しい根、`BlockPlace::In(doc_id)` が
文書の散文。側は `NodePlace::In` だけが持つ。

### 決め

- **側は根のもの。** 枝を動かしても側は運ばれず、行き先が決め直す。`Before` /
  `After` は隣の側、`In(根, side)` は `Some` ならそれ、`None` なら末尾の子の側、
  子が無ければ Right
- **新しいノードの綴りは隣に従う。** 兄弟がいればその sign、いなければ親が項目なら
  項目、それ以外は見出し。モードは Reform と一緒に来る
- **動かすノードは綴りを保つ。** 綴りの変換（見出し ⇄ 項目）は正規形の仕事で、
  操作には無い。見出しを項目の下へ落とすのは型が許さないので `None`
- **flipSide は 3 段。** 根は `sides` を一括反転(鏡像)、根の子はその 1 つを反転、
  深いノードは反対側の末尾へ引き出す(深さは保つので、間を Implicit が埋める)
- **選んだ祖先の中の子孫は無視する。** `Delete` / `Move` の ids に親と子が両方
  あれば、子は親と一緒に動く。基準の id が動かすものの中なら `None`
- **Implicit は子が尽きたら消える。** 根まで登れば Root ごと
- **Implicit に名を付ければ見出しになる。** 畳みの名前はラベル（`<summary>` に
  書けなければ名無しで畳む）。Implicit は畳めない
- **比例性** — 操作の影響は、選んだ部分木とその親の中に収まる
- **文字列は常に md として解釈される。** ラベル専用のエスケープや拒否は作らない
- **apply の結果は check を通る。** 通らなければ操作のバグ
- 新しい id は文書に無い番号（最大 + 1）。既存の id は振り直さない（反映が前後を
  id の等しさで突き合わせる）。undo は core に無い — 反映が純粋関数なので
  CodeMirror のもの

### 道具

型の異種性(3 種のノード、根だけが持つ側、Implicit の存在条件)は道具に幽閉し、
操作に腕を生やさない。`splice(doc, id, f)` が「id の席を f の返した列に置き換えて
根までの道を組み直す」1 本の歩きで、**check の書き込み版** — 読む側で check が
見張る約束を、書く側で破らないように組む唯一の場所。`append`（隣の無い席）と
`body`（中身の列）がその上に乗る。席を「親と添字」に読み替えるのはこの中だけで、
Op も ts も数えない。行き先は 4 つ(roots / 見出しの子 / 項目の子 / 中身)で、
**これより増え始めたら設計を疑う。**

## 決まっていないこと

- **`Doc` が span をどう持つか。** 反映が要るが、型に載せると `Doc` が特定の原文に縛られる
- **「消す」(`<!-- -->`)の入口。** `Shift+H` は畳みに割り当てたので、
  コメントアウトを呼ぶ手が無い(右クリックメニューか、別のキーか)
- **ライブラリの正規化をどこまで受けるか。** 今は全部受ける。改行を含む見出しの
  ラベルは spec が setext と言うが、ライブラリは ATX しか書かないので 2 行目が
  段落に落ちる。補正は反映の段か、上流
- **改行。** spec の「文字コードと改行」は LF だけと言い、`Doc.eol` は書き戻すと言う。
  今の serialize は `Doc.eol` に従う
- **旧方言で書かれた既存文書の移行。** コメント畳み・`---` トグル・本数の意味は
  もう読まれない。開いたときにどう案内するか
- **Reform（モード）と綴りの変換。** 開いたときの自動判定も core の読み関数として
  一緒に足す。変換が入ったら `Move` の「見出しを項目の下へ」の `None` を開ける
- **境界。** `edit(md, op) -> { edits, focus }` は反映が入ってから。
  `survey → apply → reflect` を繋ぎ、focus は後の Doc を文書順に振り直して読み替える
- **fold の `open` の見せ方**と、`Shift+H` が 2 状態を巡回するか 3 状態か
