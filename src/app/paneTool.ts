// ペインの隅に浮く小さな道具の器（見た目は style.css の `.pane-tool`）。
//
// **押しても下へ抜けない。** 道具はペインの上に乗っているだけで、下の
// キャンバスとは別のものだから。マップは背景を押されると矩形選択を始めて
// ポインタを捕まえるので、抜けると pointerup がペインへ行き、**ボタンの
// click がそもそも起きない**（マップ側のボタンが押せなかったのはこれ）。

export function paneTool(id: string): HTMLDivElement {
  const box = document.createElement("div");
  box.id = id;
  box.className = "pane-tool";
  box.addEventListener("pointerdown", (e) => e.stopPropagation());
  return box;
}
