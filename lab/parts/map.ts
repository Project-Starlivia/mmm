// ノード・カード・印・その場編集。**本物の Mindmap をそのまま動かす** —
// 見本の md を core に読ませ、選択と picked だけ持つ代役の host を渡す。
// 手で Box を組まないのは、それが嘘の置き方になるから。

import * as core from "../../src/app.ts";
import { languageEpoch, tokenize, tokenizeBlock } from "../../src/highlight.ts";
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
  map: core.MapHandle;
  host: core.MapHost;
  s: core.Survey;
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
  const s = core.survey(md);
  let selection: core.Selection = core.NONE;
  let picked: number | null = null;
  const host: core.MapHost = {
    survey: () => s,
    imageUrl: () => null,
    imageHint: () => "click to connect",
    connectAssets: () => {},
    holder: () => "map", // 見本は地図の枠（selected）で塗る
    selection: () => selection,
    setSelection: (sel) => {
      selection = sel;
      core.mapRefresh(map);
    },
    picked: () => picked,
    setPicked: (id) => {
      picked = id;
      core.mapRefresh(map);
    },
    blockText: (id) => {
      const sp = core.spot(s, id);
      return sp ? md.slice(sp.from, sp.to) : "";
    },
    tokens: tokenize,
    tokensBlock: tokenizeBlock,
    epoch: languageEpoch,
  };
  const map = core.map(el, host);
  core.mapRender(map);
  core.mapFit(map);
  const grown = new ResizeObserver(([e]) => {
    if (!e || e.contentRect.width === 0) return;
    grown.disconnect();
    requestAnimationFrame(() => after({ el, map, host, s }));
  });
  grown.observe(el);
  return el;
}

/** 見本の木と、その配置。右クリックメニューの見本が選択を渡すのに使う */
export function sample(): { s: core.Survey; L: core.Layout } {
  const s = core.survey(MD);
  return { s, L: core.layout(s) };
}

/** その名前のノードの id。無ければ例外（見本の md と食い違っている） */
export function named(s: core.Survey, label: string): number {
  const id = core.find(s, label);
  if (id === null) throw new Error(`ノード "${label}" が見本に無い`);
  return id;
}

/** そのノードの最初の中身の id */
function firstBlock(s: core.Survey, label: string): number {
  const b = core.blocks(s, named(s, label))[0];
  if (b === undefined) throw new Error(`ノード "${label}" に中身が無い`);
  return b;
}

const select = (host: core.MapHost, ids: number[]): void => host.setSelection({ ids, anchor: ids[0] ?? null }, false);

export const MAP: Part = {
  name: "map",
  height: 420,
  states: {
    plain: () => stand(),
    empty: () => stand(""),
    selected: () => stand(MD, ({ s, host }) => select(host, [named(s, "Left")])),
    "selected-many": () => stand(MD, ({ s, host }) => select(host, ["Left", "one", "two"].map((l) => named(s, l)))),
    "label-editor": () => stand(MD, ({ s, map }) => core.mapBeginEdit(map, named(s, "Left"), null)),
    "card-editor": () => stand(MD, ({ s, map }) => core.mapEditCard(map, firstBlock(s, "Right"))),
    "card-pick": () => stand(MD, ({ s, host }) => host.setPicked(firstBlock(s, "Right"))),
    indicator: () =>
      stand(MD, ({ el }) =>
        // 根が画面の外へ出るまでホイールで押しやる（本物と同じ入力）
        el.dispatchEvent(new WheelEvent("wheel", { deltaY: 4000, bubbles: true, cancelable: true })),
      ),
  },
};
