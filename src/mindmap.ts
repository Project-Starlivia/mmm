// マップのペインの配線。置く・描く・入力を判断して答えを出すのは core
// （core/render/mindmap.mbt）。ここが持つのは、ブラウザでなければできないことだけ —
// ペインの HTML の部品（白紙の言い出し・寄せるボタン）、右クリックの器（menu.ts）、
// クリップボード、しらせ、字の実測と色分け。

import * as core from "./coreApi.ts";
import { measure } from "./map/measure.ts";
import { languageEpoch, tokenize, tokenizeBlock } from "./map/highlight.ts";
import { ContextMenu, type MenuEntry } from "./map/menu.ts";
import { mapToSvg } from "./map/toSvg.ts";
import { icon, isIconName } from "./icons.ts";
import { paneTool } from "./app/paneTool.ts";
import { paneHint } from "./app/hint.ts";
import { FAILED, type Failed, failed } from "./app/notice.ts";

export interface MapHost {
  /** いまの文書（core の読みの持ち手。置くのに要る） */
  survey(): core.Survey;
  /** ローカル画像の objectURL。読めていない / 握っていないあいだは null */
  imageUrl(path: string): string | null;
  /** 読めていない場所取りに添える字。握っていないときだけ（他は null） */
  imageHint(): string | null;
  /** その字が押された。画像フォルダを繋ぎ直す */
  connectAssets(): void;
  /** 選択を持っている側。md なら輪（内側）、map なら枠（selected）で塗る */
  holder(): core.Holder;
  /** いま選んでいるもの */
  selection(): core.Selection;
  /** 地図で選び直した。reveal は md 側をその頭へスクロールするか */
  setSelection(sel: core.Selection, reveal: boolean): void;
  /** 選んでいるカードの中身の id */
  picked(): number | null;
  /** カードを選び直した（null で外す） */
  setPicked(id: number | null): void;
  /** その中身の原文。地番で md から切り出す（無ければ空） */
  blockText(id: number): string;
  /** 操作を md に映す。edit なら、映した後の focus をそのまま編集開始
   *  （ノードのときだけ — 中身の focus はカードとして選ぶ）。返り値は映した focus */
  apply(op: core.Op, edit: boolean): number | null;
  /** クリップボードを貼る（Mod+V）。宛先は選択の anchor、無ければ文書 */
  paste(): void;
  /** 選んでいるもの（カードならその原文、でなければ選択の部分木）をクリップボードへ
   *  写す（Mod+C / Mod+X）。写せたか — 写せなければ Cut は消さない */
  copy(): Promise<boolean>;
  /** そのノードへ描いて貼る（Shift+D）。窓を開いて、確定した絵を保存する */
  draw(id: number): void;
}

/**
 * core の右クリックの行を、menu.ts が描ける形に写す。押せば `act` へ渡すだけで、
 * 意味はここに増やさない。沈む行は `why` を押せない理由として持ち、無ければただ沈む
 */
export function menuOf(es: core.Entry[], act: (intent: core.Intent) => void): MenuEntry[] {
  const one = (it: core.Item): MenuEntry => {
    const disabled = it.intent === null ? (it.why ?? true) : false;
    const run = (): void => {
      if (it.intent) act(it.intent);
    };
    const mark = it.mark !== null && isIconName(it.mark) ? it.mark : undefined;
    const key = it.key ?? undefined;
    const items = it.items?.map(one);
    return items
      ? { label: it.label, key, mark, disabled, items, run }
      : { label: it.label, key, mark, disabled, run };
  };
  return es.map((e) => (e === "sep" ? "sep" : one(e)));
}

/** core の言葉をしらせの表と突き合わせる。知らない言葉は綴りの食い違い — 壊れている */
function asFailed(msg: string): Failed {
  const hit = FAILED.find((f) => f === msg);
  if (hit === undefined) throw new Error(`知らないしらせ: ${msg}`);
  return hit;
}

export class Mindmap {
  private readonly pane: HTMLElement;
  private readonly handle: core.MapHandle;
  /** 右クリック（と長押し）のメニュー */
  private readonly menu = new ContextMenu();

  constructor(pane: HTMLElement, host: MapHost) {
    this.pane = pane;
    // md からの始め方は md ペイン自身が同じ器で言う（app/hint.ts）
    const hint = paneHint("map");
    const tool = paneTool("map-center");
    const center = document.createElement("button");
    center.type = "button";
    center.title = "Center the view — Home";
    center.setAttribute("aria-label", "Center the view");
    center.append(icon("crosshair"));
    center.addEventListener("click", () => core.mapCenter(this.handle));
    tool.append(center);
    this.handle = core.map(
      pane,
      {
        survey: host.survey,
        measure,
        imageUrl: host.imageUrl,
        imageHint: host.imageHint,
        connectAssets: host.connectAssets,
        holder: host.holder,
        selection: host.selection,
        setSelection: host.setSelection,
        picked: host.picked,
        setPicked: host.setPicked,
        blockText: host.blockText,
        apply: (op, edit) => host.apply({ kind: "raw", json: JSON.parse(op) }, edit),
        paste: host.paste,
        copy: host.copy,
        draw: host.draw,
        readClipboard: () => navigator.clipboard.readText().catch(() => ""),
        tokens: tokenize,
        tokensBlock: tokenizeBlock,
        epoch: languageEpoch,
        menu: (x, y, entries) => {
          const es = core.entries(entries);
          // 行が無い（箱の外）なら閉じるだけ
          if (es.length === 0) this.menu.hide();
          else this.menu.show(x, y, menuOf(es, (i) => core.mapAct(this.handle, i)));
        },
        failed: (msg) => failed(asFailed(msg)),
      },
      hint,
      tool,
    );
  }

  /** 置き直して描く（文書が変わった） */
  render(): void {
    core.mapRender(this.handle);
  }

  fitView(): void {
    core.mapFit(this.handle);
  }

  /** 選択（無ければ根）を画面の中心へ。拡大率は変えない */
  centerOnTarget(): void {
    core.mapCenter(this.handle);
  }

  /** 選択の塗り直し。レイアウトは見直さない */
  refreshSelection(): void {
    core.mapRefresh(this.handle);
  }

  /** その場編集に入る。seed は最初の字。箱が無い（畳まれて埋もれた）ノードは開けない */
  beginEdit(id: number, seed: string | null): boolean {
    return core.mapBeginEdit(this.handle, id, seed);
  }

  /** カードをその場で開く。畳まれて埋もれている（箱が無い）ときは断る */
  editCard(id: number): void {
    core.mapEditCard(this.handle, id);
  }

  /** 掴みやすさ（⋯ の Easy grab）。見た目は変えず、叩ける範囲だけ広げる */
  setGrab(on: boolean): void {
    core.mapSetGrab(this.handle, on);
  }

  /** ファイルのドラッグ中、その画面の点に落ちる先を予告する（app/dnd.ts）。
   *  `null` は予告を消す合図。当たった先のノードの id（無ければ null）を返す */
  markFileDrop(at: { x: number; y: number } | null): number | null {
    return core.mapFileDrop(this.handle, at);
  }

  /** 書き出し用の SVG。全体。空なら null */
  exportSvg(): Promise<SVGSVGElement | null> {
    const p = core.mapSvgParts(this.handle);
    return mapToSvg({ boxes: p.rects, edges: p.edges, nodes: p.nodes, pane: this.pane });
  }
}
