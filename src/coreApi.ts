// core の出口。**JSON の形を整えるだけ** — 意味は 1 つも足さない。
//
// 使う側は `import * as core` で `core.View` / `core.view(md)` と書く。
// フロントでは view は画面を意味し、`Node` は DOM のグローバル型と衝突するので、
// 裸の名前を出さない（MoonBit 側の `@view.Tree` と同じ形）。
//
// MoonBit の ToJson は Option の None を鍵ごと落とし、enum を `["Image", {…}]` /
// `"ThematicBreak"` の形で出す。その形を整えるのはここ 1 か所。信頼境界も
// ここだけ — 型は名乗らせず確かめる。

import * as mbt from "../core/_build/js/release/build/tree/js/js.js";

export type Side = "Right" | "Left";

/** 畳み。在ること自体が「畳まれている」 */
export interface Fold {
  open: boolean;
  /** `<summary>` の中身。行が無ければ null */
  summary: string | null;
}

/** ノードにぶら下がる中身 1 枚。id はノードと同じ列（文書順の通し番号） */
export interface Block {
  id: number;
  content: Content;
}

/** 中身そのもの。カードかどうかは map/cards.ts の分類 */
export type Content =
  | { kind: "image"; alt: string; src: string; title: string }
  | { kind: "link"; text: string; href: string; title: string }
  | { kind: "code"; info: string; text: string }
  | { kind: "svg"; markup: string }
  | { kind: "thematicBreak" }
  | { kind: "details"; text: string };

export interface Node {
  id: number;
  /** Implicit（綴られなかった見出し）は null。空の見出しは "" */
  label: string | null;
  fold: Fold | null;
  /** 中身のうち、core が読み解いたもの。Opaque は来ない */
  blocks: Block[];
  children: Node[];
}

/** 木 1 本。側は根の子と並走する（`sides[i]` が `node.children[i]` の側） */
export interface Tree {
  node: Node;
  sides: Side[];
}

export interface View {
  frontmatter: string | null;
  trees: Tree[];
}

/** md を core に読ませ、map が見る木を受け取る。読みのサイクルの入口 */
export const view = (md: string): View => decode(JSON.parse(mbt.mmmViewJson(md)));

// ---- JSON の形を確かめながら整える ----

const bad = (what: string): never => {
  throw new Error(`core の JSON: ${what}`);
};

const isRecord = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

const record = (v: unknown): Record<string, unknown> => (isRecord(v) ? v : bad("構造体でない"));
const str = (v: unknown): string => (typeof v === "string" ? v : bad("文字列でない"));
const num = (v: unknown): number => (typeof v === "number" ? v : bad("数でない"));
const bool = (v: unknown): boolean => (typeof v === "boolean" ? v : bad("真偽でない"));
const list = <T>(v: unknown, read: (x: unknown) => T): T[] =>
  Array.isArray(v) ? v.map(read) : bad("配列でない");

/** 在るはずの鍵。無ければ壊れている */
const field = <T>(o: Record<string, unknown>, key: string, read: (v: unknown) => T): T =>
  key in o ? read(o[key]) : bad(`${key} が無い`);

/** Option の鍵。None は鍵ごと落ちている */
const option = <T>(o: Record<string, unknown>, key: string, read: (v: unknown) => T): T | null =>
  key in o ? read(o[key]) : null;

const side = (v: unknown): Side => (v === "Right" || v === "Left" ? v : bad("側でない"));

const fold = (v: unknown): Fold => {
  const o = record(v);
  return { open: field(o, "open", bool), summary: option(o, "summary", str) };
};

/** enum は `"Tag"`（中身なし）か `["Tag", 中身]` */
function content(v: unknown): Content {
  if (v === "ThematicBreak") return { kind: "thematicBreak" };
  if (!Array.isArray(v) || v.length !== 2) return bad("Content の形でない");
  const [tag, body] = v;
  switch (tag) {
    case "Image": {
      const o = record(body);
      return {
        kind: "image",
        alt: field(o, "alt", str),
        src: field(o, "src", str),
        title: field(o, "title", str),
      };
    }
    case "Link": {
      const o = record(body);
      return {
        kind: "link",
        text: field(o, "text", str),
        href: field(o, "href", str),
        title: field(o, "title", str),
      };
    }
    case "Code": {
      const o = record(body);
      return { kind: "code", info: field(o, "info", str), text: field(o, "text", str) };
    }
    case "Svg":
      return { kind: "svg", markup: str(body) };
    case "Details":
      return { kind: "details", text: str(body) };
    default:
      return bad(`知らない Content ${String(tag)}`);
  }
}

const block = (v: unknown): Block => {
  const o = record(v);
  return { id: field(o, "id", num), content: field(o, "content", content) };
};

function node(v: unknown): Node {
  const o = record(v);
  return {
    id: field(o, "id", num),
    label: option(o, "label", str),
    fold: option(o, "fold", fold),
    blocks: field(o, "blocks", (b) => list(b, block)),
    children: field(o, "children", (c) => list(c, node)),
  };
}

const tree = (v: unknown): Tree => {
  const o = record(v);
  return { node: field(o, "node", node), sides: field(o, "sides", (s) => list(s, side)) };
};

/** core の JSON（`mmmViewJson` の出力）を View にする。試験はここを直接叩く */
export function decode(json: unknown): View {
  const o = record(json);
  return {
    frontmatter: option(o, "frontmatter", str),
    trees: field(o, "trees", (t) => list(t, tree)),
  };
}
