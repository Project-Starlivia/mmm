// 唯一の源（src/app/logo.ts）から exe アイコン一式を作り直す。
// ロゴを変えたらこれを実行し、生成された src-tauri/icons/ をコミットする。
// app-icon.svg は中間生成物（.gitignore 済み）。

import { execSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { LOGO_COLOR, logoSvg } from "../src/app/logo.ts";

const SRC = "src-tauri/app-icon.svg";
writeFileSync(SRC, `${logoSvg(LOGO_COLOR)}\n`);
execSync(`pnpm tauri icon ${SRC}`, { stdio: "inherit" });
