// 分割線の居場所。狭いときに「両方」を残すと、CSS が片方を隠して
// **状態が 2 つになり食い違う**（矢印は行けない場所を指す）。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { type Vis, project, spotsFor, toggled } from "../src/app/panes.ts";

const MD_ONLY: Vis = { md: true, map: false };
const BOTH: Vis = { md: true, map: true };
const MAP_ONLY: Vis = { md: false, map: true };

test("広いときは 3 つ、狭いときは 2 つ", () => {
  assert.deepEqual(spotsFor(false), [MAP_ONLY, BOTH, MD_ONLY]);
  assert.deepEqual(spotsFor(true), [MAP_ONLY, MD_ONLY]);
});

test("左から右へ並ぶ順は、狭くても変わらない", () => {
  // `‹` はいつでも「分割線を左へ 1 つ」。行き先が減るだけ
  for (const narrow of [false, true]) {
    const list = spotsFor(narrow);
    assert.deepEqual(list[0], MAP_ONLY);
    assert.deepEqual(list[list.length - 1], MD_ONLY);
  }
});

test("居場所にある形は、そのまま", () => {
  assert.deepEqual(project(BOTH, spotsFor(false)), BOTH);
  assert.deepEqual(project(MD_ONLY, spotsFor(true)), MD_ONLY);
});

test("狭いところへ「両方」が来たら、マップを残す", () => {
  assert.deepEqual(project(BOTH, spotsFor(true)), MAP_ONLY);
});

// **この一手だけの注意:** `project` のフォールバックは「行き先を言っていない
// 要求」（境目をまたいだ・両方消えた）専用。「md を出したい」という名指しの
// 要求を、いま片方（map）が出ている状態から素朴に「もう片方も true にする」
// と組み立てると、狭いときは居場所の無い `BOTH` になり、`project` はそれを
// マップへ丸めてしまう — **要求した md ではなく map が残る。** だから
// `project` へ投げる前に、行き先を知っている呼び出し側が先に決める
// （`app/panes.ts` の `toggled`）。ここでその「名指しの要求を BOTH のまま
// 渡すと壊れる」こと自体を固定する: `toggled` を `project` の中へ
// 「簡略化」して戻すと、この形が再びテストを割らずに通ってしまわないように
test("名指しで md を出したくても、BOTH のまま渡すと map に丸められる（だから toggled が先に行き先を決める）", () => {
  const wantMd = { ...MAP_ONLY, md: true }; // 「md も出したい」を素朴に組んだ形 = BOTH
  assert.deepEqual(wantMd, BOTH);
  assert.notDeepEqual(project(wantMd, spotsFor(true)), MD_ONLY);
  assert.deepEqual(project(wantMd, spotsFor(true)), MAP_ONLY);
});

test("「両方消えた」は作らない", () => {
  const none: Vis = { md: false, map: false };
  // これは `project` 自身の契約（行き先を言っていない要求への既定）であって、
  // 今の呼び出し側が実際にこう振る舞うという意味ではない —
  // `togglePaneVis` / `togglePane` はどちらも `toggled` が先に行き先を
  // 決めるので、この形（両方 false）を `project` へ渡すことはもう無い
  assert.deepEqual(project(none, spotsFor(false)), BOTH);
  assert.deepEqual(project(none, spotsFor(true)), MAP_ONLY);
});

// ---- toggled ----
// `which` を出す/引っ込める一手そのものの行き先。`project` は「行き先を
// 言っていない要求」の後始末はするが、「md を出したい」のような名指しの
// 要求そのものを解決してはくれない（真上のテストの通り）。だから
// `togglePaneVis` / `togglePane` はここを通す

test("toggled: 隠れているペインを出す", () => {
  // 広いとき: 相方はそのまま、その 1 枚が増える
  assert.deepEqual(toggled(MAP_ONLY, "md", spotsFor(false)), BOTH);
  assert.deepEqual(toggled(MD_ONLY, "map", spotsFor(false)), BOTH);
  // 狭いとき: 「両方」という置き場が無いので、そのペイン 1 枚だけになる
  assert.deepEqual(toggled(MAP_ONLY, "md", spotsFor(true)), MD_ONLY);
  assert.deepEqual(toggled(MD_ONLY, "map", spotsFor(true)), MAP_ONLY);
});

test("toggled: もう片方も出ていれば、指名した 1 枚だけ消える（広いときにしか起こらない）", () => {
  assert.deepEqual(toggled(BOTH, "md", spotsFor(false)), MAP_ONLY);
  assert.deepEqual(toggled(BOTH, "map", spotsFor(false)), MD_ONLY);
});

test("toggled: 最後の 1 枚は消せず、もう片方が出る — 幅を問わない（狭いときだけ運良く正しかった回帰の直し）", () => {
  // 広いとき: 以前はここで「両方」に戻ってしまっていた
  // （`{md:false,map:false}` を `project` の「行き先を言っていない要求」用
  // フォールバックに渡すと `{md:true,map:true}` に丸められてしまうため）
  assert.deepEqual(toggled(MD_ONLY, "md", spotsFor(false)), MAP_ONLY);
  assert.deepEqual(toggled(MAP_ONLY, "map", spotsFor(false)), MD_ONLY);
  // 狭いとき
  assert.deepEqual(toggled(MD_ONLY, "md", spotsFor(true)), MAP_ONLY);
  assert.deepEqual(toggled(MAP_ONLY, "map", spotsFor(true)), MD_ONLY);
});

test("toggled: 狭いときは、出す/引っ込めるをどう繰り返しても「両方」にならない", () => {
  const list = spotsFor(true);
  const seq: Array<"md" | "map"> = ["md", "md", "map", "map", "md", "map"];
  let v: Vis = MAP_ONLY;
  for (const which of seq) {
    v = toggled(v, which, list);
    assert.ok(!(v.md && v.map), `両方になってはいけない: ${JSON.stringify(v)} (toggled ${which})`);
  }
});
