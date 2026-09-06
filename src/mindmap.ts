// マップのペインの配線。置く・描く・入力を判断して答えを出すのは core
// （core/render/mindmap.mbt）。ここが持つのは、ブラウザでなければできないことだけ —
// クリップボード、字の実測と色分け、書き出し。

import * as core from "./coreApi.ts";
import { measure } from "./map/measure.ts";
import { languageEpoch, tokenize, tokenizeBlock } from "./map/highlight.ts";

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

export class Mindmap {
  /** core の地図そのもの。書き出し・ドロップはこれを渡す */
  readonly handle: core.MapHandle;

  constructor(pane: HTMLElement, host: MapHost) {
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
        failed: core.failed,
      },
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
}
