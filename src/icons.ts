// ボタンの絵の唯一の源。
//
// **字形に頼らない。** ⤓ や ⧉ は環境によって在ったり無かったり、太さも
// 大きさも揃わない（同じ帯の中で 1 つだけ細く見える）。線で引けば、どこでも
// 同じものが同じ太さで出る。
//
// 色は `currentColor` — ボタンの文字色をそのまま継ぐので、hover も
// disabled もテーマも、CSS 側だけで面倒を見られる。

/** 16 の升目で引く。ボタンの字（13px）の隣に置いて釣り合う大きさ */
const BOX = 16;

const PATHS = {
  /** 書類の入れ物。File のメニューに付く */
  folder: "M2 4.5h4l1.4 1.6H14v7.4H2z",
  /** 下向きの矢印と、受け止める床。ディスクへ落とす */
  download: "M8 2.5v7.5M4.8 7.2 8 10.4l3.2-3.2M3 13h10",
  /** 重なった 2 枚。貼れるようにする */
  copy: "M5.5 2.5h8v8M2.5 5.5h8v8h-8z",
  /** 開く印 */
  chevron: "m3.5 6 4.5 4.5L12.5 6",
  /** 十字とその中心の輪。視点を寄せる先を示す */
  target:
    "M8 2v2.5M8 11.5v2M2 8h2.5M11.5 8h2M6 8a2 2 0 1 0 4 0a2 2 0 1 0 -4 0",
} as const;

export type IconName = keyof typeof PATHS;

/**
 * その名前の絵。**塗りではなく線**で引く（細い線 1 本ぶんの太さで揃う）。
 * `folder` だけは面で塗ったほうが小さくても形が残るので、そこだけ塗る。
 */
export function icon(name: IconName): SVGSVGElement {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("class", "icon");
  svg.setAttribute("viewBox", `0 0 ${BOX} ${BOX}`);
  svg.setAttribute("aria-hidden", "true");
  const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
  path.setAttribute("d", PATHS[name]);
  path.setAttribute("fill", "none");
  path.setAttribute("stroke", "currentColor");
  path.setAttribute("stroke-width", "1.4");
  path.setAttribute("stroke-linecap", "round");
  path.setAttribute("stroke-linejoin", "round");
  svg.append(path);
  return svg;
}

/** 絵と文字を並べたボタンの中身にする（絵が先か後かは呼ぶ側が決める） */
export function label(text: string, name: IconName, after = false): Node[] {
  const span = document.createElement("span");
  span.textContent = text;
  return after ? [span, icon(name)] : [icon(name), span];
}
