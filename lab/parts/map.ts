// ノード・カード・印・その場編集。**本物の Mindmap をそのまま動かす** —
// 見本の md を core に読ませ、選択と picked だけ持つ代役の host を渡す。
// 手で Box を組まないのは、それが嘘の置き方になるから。

import { type Node, type View, survey } from "../../src/coreApi.ts";
import { type MapHost, Mindmap } from "../../src/mindmap.ts";
import { NONE, type Selection } from "../../src/map/select.ts";
import type { Part } from "./kind.ts";

const MD = `# mmm

## Left

### one

### two

## Right

\`\`\`ts
const x = 1;
\`\`\`

## Kinds

[mmm](https://example.com)

---

<details>
<summary>note</summary>

folded text

</details>

![](shot.webp)

<details>

### hidden

</details>
`;

interface Stand {
  el: HTMLDivElement;
  map: Mindmap;
  host: MapHost;
  view: View;
}

/**
 * 見本の md を読んで、`.map-pane` の div に本物の Mindmap を立てる。
 * 寄せ（fitView）はペインに大きさが付いてから走る（返した要素が枠に置かれた
 * 後、Mindmap 自身の ResizeObserver が拾う）ので、`after` はその次の描画で呼ぶ —
 * 先に呼ぶと、視点を動かす状態（indicator）が寄せに上書きされる
 */
function stand(md = MD, after: (s: Stand) => void = () => {}): HTMLDivElement {
  const el = document.createElement("div");
  el.style.height = "100%"; // 枠いっぱいに（アプリでは #map-pane の flex が決める）
  const s = survey(md, [], []);
  let selection: Selection = NONE;
  let picked: number | null = null;
  const host: MapHost = {
    doc: () => s.view,
    imageUrl: () => null,
    imageHint: () => "click to connect",
    connectAssets: () => {},
    selection: () => selection,
    setSelection: (sel) => {
      selection = sel;
      map.refreshSelection();
    },
    picked: () => picked,
    setPicked: (id) => {
      picked = id;
      map.refreshSelection();
    },
    blockText: (id) => {
      const sp = s.spots.get(id);
      return sp ? md.slice(sp.from, sp.to) : "";
    },
    apply: () => null,
    paste: () => {},
    copy: () => Promise.resolve(true),
    draw: () => {},
  };
  const map = new Mindmap(el, host);
  map.render();
  map.fitView();
  const grown = new ResizeObserver(([e]) => {
    if (!e || e.contentRect.width === 0) return;
    grown.disconnect();
    requestAnimationFrame(() => after({ el, map, host, view: s.view }));
  });
  grown.observe(el);
  return el;
}

/** その名前のノード。無ければ例外（見本の md と食い違っている） */
function named(view: View, label: string): Node {
  const find = (n: Node): Node | null =>
    n.label === label ? n : (n.children.map(find).find((x) => x !== null) ?? null);
  const hit = view.roots.map((r) => find(r.node)).find((x) => x !== null);
  if (!hit) throw new Error(`ノード "${label}" が見本に無い`);
  return hit;
}

/** そのノードの最初の中身の id */
function firstBlock(view: View, label: string): number {
  const b = named(view, label).blocks[0];
  if (!b) throw new Error(`ノード "${label}" に中身が無い`);
  return b.id;
}

const select = (host: MapHost, ids: number[]): void => host.setSelection({ ids, anchor: ids[0] ?? null }, false);

export const MAP: Part = {
  name: "map",
  height: 420,
  states: {
    plain: () => stand(),
    empty: () => stand(""),
    selected: () => stand(MD, ({ view, host }) => select(host, [named(view, "Left").id])),
    "selected-many": () =>
      stand(MD, ({ view, host }) => select(host, ["Left", "one", "two"].map((l) => named(view, l).id))),
    "label-editor": () => stand(MD, ({ view, map }) => map.beginEdit(named(view, "Left").id, null)),
    "card-editor": () => stand(MD, ({ view, map }) => map.editCard(firstBlock(view, "Right"))),
    "card-pick": () => stand(MD, ({ view, host }) => host.setPicked(firstBlock(view, "Right"))),
    indicator: () =>
      stand(MD, ({ el }) =>
        // 根が画面の外へ出るまでホイールで押しやる（本物と同じ入力）
        el.dispatchEvent(new WheelEvent("wheel", { deltaY: 4000, bubbles: true, cancelable: true })),
      ),
  },
};
