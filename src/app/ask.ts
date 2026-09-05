// たずね。**答えを待つ** — 塞いで、返ってくるまで進まない。
//
// 器は `<dialog>` 1 つ。焦点を閉じ込める・Escape で閉じる・後ろを暗くする
// (`::backdrop`) はブラウザが持っているので、こちらは書かない。
//
// **中身は「字」と「欄」を並べただけ**（`Part`）。聞き方が増えても器は 1 つ
// で、増えるのは並べ方だけ — はい/いいえ は欄ゼロ、名前は欄 1 つ、
// 画像の行き先は `![](` 字 + 欄 + `.webp)` 字、というように。
// **分かっているところは字、分からないところだけ欄**を、この形が守る。
//
// ここに来ないもの: ファイルを開く・保存する・フォルダを選ぶ・権限を聞く。
// あれはこちらが持っていない持ち場なので、ブラウザのピッカーのまま。

/** 打てる欄。並びの中で値を 1 つ受け持つ */
export interface Field {
  value: string;
  /**
   * その値では進めない理由。進めるなら null。
   *
   * **打つそばから効く。** だめな値のまま押させて後から失敗を言うのは、
   * 打った本人が既に知っていることを後出しするのと同じ。
   */
  check?: (value: string) => string | null;
}

/** 並べるもの。ただの字か、打てる欄か */
export type Part = string | Field;

const isField = (p: Part): p is Field => typeof p !== "string";

export interface Ask {
  /** 何を聞いているか。1 行で言い切る */
  title: string;
  /** 補足。**要るときだけ** — 題で足りるなら書かない */
  note?: string;
  /** 進む側のボタンの名前（`OK` / `Discard` など） */
  ok: string;
  /** 断る側の名前。既定は `Cancel`（`Keep as is` のように意味を持つことがある） */
  cancel?: string;
  /** 字と欄の並び。空なら はい/いいえ */
  parts?: Part[];
  /** 何の話をしているかを見せる絵（画像の名前を聞くときの、その画像） */
  preview?: string;
}

/** 組んだ form と、欄の値を並び順で読む口 */
export interface AskForm {
  form: HTMLFormElement;
  values: () => string[];
}

/**
 * たずねの中身（form）を組む。**器に載せるのは呼ぶ側** — `ask` は `<dialog>` に
 * 載せて `showModal` し、並べて見る道具は開いたまま置く。
 *
 * `cancel` は断る側のボタンが押されたときに呼ぶ（器を閉じる係は器が持つ）。
 * 進む側は `method="dialog"` の送信そのもので、押したボタンの value（`"ok"`）が
 * `returnValue` になる。
 */
export function askForm(a: Ask, cancel: () => void): AskForm {
  const form = document.createElement("form");
  form.method = "dialog"; // 送ると dialog が閉じ、押したボタンの value が returnValue

  const title = document.createElement("p");
  title.className = "title";
  title.textContent = a.title;
  form.append(title);

  if (a.note !== undefined) {
    const note = document.createElement("p");
    note.className = "note";
    note.textContent = a.note;
    form.append(note);
  }

  // 何の話かを見せる絵。字より先に置く — 名前を聞かれている相手が、
  // 読む前に分かる
  if (a.preview !== undefined) {
    const img = document.createElement("img");
    img.className = "shot";
    img.src = a.preview;
    img.alt = "";
    form.append(img);
  }

  // 字と欄の並び。**欄は並びの中に居る** — 別行に切り出すと、その値が
  // 何の一部なのかが読めなくなる
  const inputs: { el: HTMLInputElement; check?: (v: string) => string | null }[] = [];
  if (a.parts && a.parts.length > 0) {
    const row = document.createElement("div");
    row.className = "parts";
    for (const part of a.parts) {
      if (isField(part)) {
        const input = document.createElement("input");
        input.type = "text";
        input.value = part.value;
        // 中身なりの幅。短い値の欄が横いっぱいに伸びると、並びが読めない
        input.size = Math.max(part.value.length, 6);
        row.append(input);
        inputs.push({ el: input, check: part.check });
      } else {
        const text = document.createElement("span");
        text.textContent = part;
        row.append(text);
      }
    }
    form.append(row);
  }

  // だめな理由の置き場。**並びのすぐ下** — 直したい字と、直せと言う言葉が
  // 離れていると目が往復する。要らないうちは場所も取らない。
  // `aria-live` は要る側だけに付ける — 何も言わない要素を読み上げの
  // 監視対象に加えても、黙って何も起きないだけ
  const checked = inputs.some((i) => i.check);
  const bad = document.createElement("p");
  bad.className = "bad";
  bad.hidden = true;
  if (checked) {
    bad.setAttribute("aria-live", "polite");
    form.append(bad);
  }

  const row = document.createElement("div");
  row.className = "row";
  const no = document.createElement("button");
  no.type = "button"; // 送らない。閉じるだけ（returnValue は空のまま）
  no.textContent = a.cancel ?? "Cancel";
  no.addEventListener("click", cancel);
  const go = document.createElement("button");
  go.className = "go";
  go.value = "ok";
  go.textContent = a.ok;
  row.append(no, go);
  form.append(row);

  // 打つそばから見直す。**進めない理由がある間は、進む道そのものを閉じる** —
  // ボタンが沈めば Enter でも送られない（送信は無効なボタンからは起きない）。
  // 欄が 2 つ以上あるときは、**先に見つかった 1 つだけ**を言う（並べると、
  // どれを直せば進めるのかが読めなくなる）
  if (checked) {
    const review = (): void => {
      let why: string | null = null;
      for (const i of inputs) {
        why = i.check?.(i.el.value) ?? null;
        if (why !== null) break;
      }
      go.disabled = why !== null;
      bad.textContent = why ?? "";
      bad.hidden = why === null;
    };
    for (const i of inputs) i.el.addEventListener("input", review);
    review();
  }

  return { form, values: () => inputs.map((i) => i.el.value) };
}

/**
 * 器を組んで開き、**欄の値を並び順で**返す。断られたら null。
 * 開くたびに作る — 聞くのは操作のたびに 1 回きりで、使い回す得が無い。
 *
 * 返るのは `<dialog>` の `returnValue` 由来: 進んだときだけ `"ok"`。
 * Escape・背景・Cancel はすべて空文字（＝ 断り）に落ちる。
 */
export function ask(a: Ask): Promise<string[] | null> {
  const dlg = document.createElement("dialog");
  dlg.className = "ask";
  const { form, values } = askForm(a, () => dlg.close());
  dlg.append(form);
  document.body.append(dlg);
  dlg.showModal();
  // 最初の欄を選んだ状態で開く（打ち直しがすぐ始められる）
  form.querySelector("input")?.select();

  return new Promise((resolve) => {
    dlg.addEventListener("close", () => {
      const ok = dlg.returnValue === "ok";
      const out = values();
      dlg.remove();
      resolve(ok ? out : null);
    });
  });
}
