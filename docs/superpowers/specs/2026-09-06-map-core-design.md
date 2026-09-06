# map-core — map を core で置き、描く（設計）

`src/map` のうち **DOM を知らない半分**（geometry / cards / metrics / layout / edge）と
**SVG を組む半分**（svg / drawCard / render）を MoonBit の core へ移す。
入力（select / drop / keys / label / card / menu / gesture / pick / indicator / context）と
視点（camera）、書き出し（toSvg）、コードの色分け（highlight — CodeMirror の言語表）は TS のまま。

Issue: #137。先に #135（MoonBit 0.10.11）。

## なぜ

- 「core が意味・TS が見せ方」の線は、CodeMirror が DOM とトランザクションを持つ md 側には残る。
  map 側は SVG を全部自作していて、CM に相当するものが無い
- `layout.ts` は自分で「DOM を知らない純粋なレイアウト層。core の木をそのまま歩き、構造は
  core の語のまま読み、寸法は外から受ける」と言っている。**もう core の形で、置き場が TS なだけ**
- `mizchi/js_browser` に Document / Element / SVG*Element / MouseEvent … の型が揃っている。
  型は名目（`#external`）で、境界の cast だけが無検査 — TS の `as` と同じ強さ。中に入れば検査が効く
- 得るもの: 境界 1 つ（View の JSON → TS の layout → TS の render、が core の中で閉じる）、
  layout の試験が `moon test` に揃うこと、寸法の唯一の定義が core に 1 つになること。
  失うもの: `svgEl<K extends keyof SVGElementTagNameMap>` の tag → 型の対応（今の map で
  個別の型に頼っているのは render の `Map<number, SVGGElement>` と mindmap の `world` /
  `caretLayer` / `caretRings` だけ。薄い）

## 決めたこと

### 層

```
md ──parse──> Doc ──project──> View                       core/tree, core/view（今のまま）
                                 │
                       map.layout(roots, size)            core/map: View + 寸法 → Layout。畳みの埋没・sides の zip・付け根のずらし
                                 │                        寸法は metric.node_size(measure) — 字の実測は外から
                     render.draw(layout, scene)           core/render: Layout → <g> の中の SVG を差分で更新。js だけ
                                 │
   coreApi ── JSON ──> TS の入力側（select / drop / keys …）  境界: 形を確かめるだけ。語彙は core のまま
```

**core が持つ**: 座標系（側 → 符号）、Block → Card の分類、寸法（字の大きさ・余白・行の高さ・
隙間 — **唯一の定義**）、配置、線の形、SVG の組み立てと差分更新。

**TS が持つ**: 字の実測（canvas `measureText` と CSS の `--font` / `--mono`）、画像の URL、
コードの色分け、入力とその値、視点、書き出し、当たりの広げ幅（`HIT_PAD` / `HIT_EDGE` — 描画の
寸法ではなく入力の決め）。

### 境界

- **データは JSON のまま。** `coreApi.ts` が形を確かめて整える（信頼境界はここ 1 か所、という今の決め）。
  Layout も同じ道で TS へ渡る — TS の入力側（select / drop / keys / label / card / mindmap）は
  Layout の数を読むだけで、数えない
- **MoonBit の値は不透明な持ち手で往復する。** `survey` が View を、`layout` が Layout を
  持ち手として返し、TS はそれを `layout` / `draw` にそのまま渡す。**JSON を 2 度組まない、
  2 度 parse しない**。js backend では MoonBit の値がそのまま JS の値なので、持ち手は cast 1 回
- **外から受けるものは閉包。** js backend では JS の関数を MoonBit の関数型の引数にそのまま渡せる
  （確かめた）。`measure` / `image_url` / `tokens` の 3 つ
- **DOM の契約は変えない。** `.node[data-id]` / `.edge` / `[data-card="id,i"]` / `.link-open[data-url]` /
  `[data-connect]` / `.selected` / `.dragging` / `.drop-parent` と、各要素の class。style.css も
  TS のハンドラも、そのまま効く

### 語彙と名前

- core の語（View / Node / Root / Side / Fold / Block）は読むだけ。`Box.node` は参照
- `core/map` — **map の語**: `Pt` / `Rect` / `Card` / `Edge` / `Box` / `Layout` / `Size` / `Font`。
  TS の `CardRow` は `Card` に、`rows` は `cards` に（行であることは型が言う）
- `core/render` — `Renderer` / `Scene`。TS の `MapRenderer` と同じ役
- ファイルは TS と同じ切り方: `map/` に geometry / card / metric / layout / edge、
  `render/` に svg / card / render
- 出口は今までどおり `tree/js/exports.mbt` 1 つ（`mmmMetrics` / `mmmSurvey` / `mmmLayout` /
  `mmmRenderer` / `mmmDraw` / `mmmPaint` / `mmmNodeEl` / `mmmEdgeEl`）。出口の置き場の名が
  `tree/js` なのは core の科の名付け直し（別件）に委ねる

### 型（MoonBit）

```moonbit
// core/map
pub struct Pt { x : Double; y : Double }
pub struct Rect { x : Double; y : Double; w : Double; h : Double }   // 左上と大きさ
pub struct Size { w : Double; h : Double }

pub enum Card {                                   // ラベルの下に積む 1 行
  Link(title~ : String, url~ : String)
  Image(path~ : String, name~ : String)
  Svg(markup~ : String)
  Code(lang~ : String, lines~ : Array[String])
  Break
  Details(open~ : Bool, summary~ : String?, lines~ : Array[String])
}

pub struct Edge { id : Int; side : @tree.Side }   // 親との繋がり。側は繋がりの性質
pub struct Box {
  node : @view.Node
  parent : Edge?
  buried : Int                                    // 畳んで埋もれた子孫の数
  mut fan : Double                                // 親の辺の上での付け根のずらし
  x : Double; mut y : Double; w : Double; h : Double
  cards : Array[Card]
}
pub struct Layout { order : Array[Int]; boxes : Map[Int, Box] }

pub struct Font { px : Int; mono : Bool }         // 字の大きさは core、字の綴り（family）は TS
pub typealias (Font, String) -> Double as Measure // 幅を測る。実体は TS の canvas
pub typealias (@view.Node, Array[Card], Int) -> Size as SizeOf

pub fn layout(roots : Array[@view.Root], size : SizeOf) -> Layout
pub fn node_size(measure : Measure) -> SizeOf     // metric。layout の試験は size を数で渡す
pub fn card_rect(b : Box, i : Int) -> Rect?        // 箱の左上から見た i 枚目の中身の矩形
pub fn edge_ends(l : Layout, id : Int) -> (Pt, Pt)?
pub fn edge_path(a : Pt, z : Pt) -> String        // d 属性

// core/render（supported_targets = "js"）
pub struct Scene {
  layout : @map.Layout
  image_url : (String) -> String?                 // path → objectURL。読めていなければ None
  image_hint : String?                            // 場所取りに添える字。握っていないときだけ
  tokens : (String, String) -> Array[Array[Token]] // (lang, 改行で繋いだ行) → 行ごとの塊
  epoch : Int                                     // 言語の読み込みの世代。変われば描き直す
}
pub struct Renderer { ... }                       // edge_layer / node_layer と id → 要素の Map
pub fn Renderer::new(doc : @dom.Document) -> Renderer
pub fn Renderer::draw(self, scene : Scene) -> Unit
pub fn Renderer::paint(self, selected : Array[Int]) -> Unit
pub fn Renderer::node_el(self, id : Int) -> @dom.Element?
pub fn Renderer::edge_el(self, id : Int) -> @dom.Element?
```

**Layout の JSON**（TS の入力側が読む形。`coreApi.ts` が `core.Layout` に整える）

```
{ order: [id], boxes: [{ id, parent: {id, side} | null, buried, x, y, w, h, cards: [Rect] }] }
```

`cards` は `card_rect` を全部の行ぶん先に数えたもの — TS は矩形を読むだけで、積み方を知らない。
`node` は JSON に無い。`coreApi` が View の id から引いて `core.Box.node` に付ける（参照）。

**metrics の JSON**（起動時に 1 度）: `{ gap: {x, y, root}, row: { normal: {px, padX, h}, hidden: {…} } }`。
TS の drop（帯の高さ）と label / card（欄の重ね）がこれを読む。数字を TS に書かない。

### 外から受けるもの

| 何 | 型 | 出所 |
|---|---|---|
| 字の実測 | `(Font, String) -> Double` | `metrics.ts` の `measure`（canvas。キャッシュ込み）。`Font` は `{px, mono}` の素の object で届く |
| 画像の URL | `(String) -> String?` | `MapHost.imageUrl` |
| 場所取りの字 | `String?` | `MapHost.imageHint` |
| コードの色分け | `(String, String) -> Array[Array[Token]]` | `highlight.ts` の `tokenize`。`Token = {text, cls}` |
| 言語の世代 | `Int` | `highlight.ts` の `languageEpoch` |

`String?` は JS の `null` を `None` に読む（`@js.nullable` / `identity_option`）。

## 段（feat/map-core に積む）

| 段 | 何 | 試験 |
|---|---|---|
| 1 | docs（この設計と計画） | — |
| 2 | `core/map` geometry / card / metric | wbtest（TS の geometry / cards / metrics の試験を移す） |
| 3 | `core/map` layout / edge | wbtest（layout.test.ts を移す。size は数で渡す） |
| 4 | `core/render` | happy-dom（`js_browser` の試験と同じ手口。root の devDependency） |
| 5 | 配線 — exit・coreApi・mindmap.ts。TS の 8 ファイルと 4 試験を消す。docs（spec / design / core / look） | `pnpm test` / ブラウザ |

段 2〜4 は main では使われないので feat/map-core に積み、段 5 で切り替わったら main へ squash。

## 却下した案

- **layout だけ core へ（render は TS のまま）** — 境界が「View の JSON」から「Layout の JSON」へ
  動くだけで往復は残る。効くのは render まで行ったとき
- **Layout を JSON にせず、MoonBit の struct をそのまま TS に読ませる** — js backend では struct が
  素の object になる（確かめた）が、enum（Side）と Option の表現は内部のもの。「型は名乗らせず
  確かめる」の境界を保つため、データは JSON のまま
- **入力側（select / drop …）も core へ** — DOM のイベントの塊で、動かす必然が無い。試験も
  TS で足りている
- **survey に layout を含める** — survey は state.ts の field（DOM を知らない）で回る。
  measure を field に注ぐことになるので、layout は今までどおり mindmap の draw で組む

## 測った（段 5）

- 5000 ノードの文書で末尾に 1 字打つ 1 打鍵（dispatch の同期時間、5 回）: main 50〜67 ms、
  この枝 68〜85 ms。差の 15〜20 ms は Layout の JSON（5000 箱）の stringify と parse と
  形の確かめ。許容の内だが、詰めるなら boxes を平らな数の列にする（別 issue）
- `core/render` の happy-dom は `moon test` から `require("happy-dom")` で引けた
  （core/_build の下から node が親の node_modules を辿る）

## 未決

- Layout の JSON を平らにするか（上）
- 出口の置き場 `tree/js` の名（core の科の名付け直しと一緒に）
