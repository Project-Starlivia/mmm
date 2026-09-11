// 帯の並び（Files / ⋯）。行の形と、沈む理由・切り替えた先の言葉を固定する

///|
fn row_of(e : @parts.Entry) -> String {
  match e {
    Run(r, _) | Done(r, _) | Flip(r, _) | Sub(r, _, _) =>
      r.label +
      (match r.disabled {
        No => ""
        Yes => " (off)"
        Why(why) => " (off: " + why + ")"
      })
    Caption(t, _) => "# " + t
    Sep => "---"
  }
}

///|
/// 並びの中の絵の名の全部（行の頭と見出し、入れ子の中も）
fn marks_of(es : Array[@parts.Entry]) -> Array[String] {
  let out = []
  for e in es {
    let (mark, inner) = match e {
      Run(r, _) | Done(r, _) | Flip(r, _) => (r.mark, [])
      Sub(r, items, _) => (r.mark, items)
      Caption(_, m) => (m, [])
      Sep => (None, [])
    }
    match mark {
      Some(m) => out.push(m)
      None => ()
    }
    out.append(marks_of(inner))
  }
  out
}

///|
let nop : () -> Unit = () => ()

///|
let file_acts : FileActs = {
  new_file: nop,
  open: nop,
  open_recent: _ => (),
  save: nop,
  save_as: nop,
  toggle_autosave: nop,
  rename: nop,
  choose_folder: nop,
}

///|
let saved : Files = {
  saved_name: Some("notes.md"),
  recent: ["ideas.md", "todo.md"],
  autosave: false,
  can_open: true,
  can_save: true,
  can_rename: true,
  can_choose_folder: true,
  folder: "pics",
}

///|
test "files_menu: 見出しが状態を言い、続く行ができること。Recent は入れ子で、押せば番号" {
  let mut opened = -1
  let rows = files_menu(saved, { ..file_acts, open_recent: i => opened = i, })
  assert_eq(rows.map(row_of), [
    "# notes.md", "New", "Open", "Recent", "Save", "Save as", "Autosave", "Rename",
    "# pics", "Choose folder",
  ])
  // **行は切り替えた先を名乗る。** 入っていれば手で書く側が次
  assert_eq(
    files_menu({ ..saved, autosave: true, }, file_acts).map(row_of)[6],
    "Save by hand",
  )
  guard rows[3] is Sub(_, items, None) else {
    fail("Recent が入れ子でない")
  }
  assert_eq(items.map(row_of), ["ideas.md", "todo.md"])
  guard items[1] is Run(_, go) else { fail("行でない") }
  go()
  assert_eq(opened, 1)
}

///|
test "files_menu: 保存していなければ見出しは not saved yet、Recent が無ければ沈み、Rename は理由を言う" {
  let rows = files_menu(
    { ..saved, saved_name: None, recent: [], folder: "no folder", },
    file_acts,
  )
  assert_eq(rows[0] |> row_of, "# not saved yet")
  assert_eq(rows[3] |> row_of, "Recent (off: Nothing opened yet)")
  assert_eq(rows[7] |> row_of, "Rename (off: " + nothing_to_rename + ")")
  assert_eq(rows[8] |> row_of, "# no folder")
}

///|
test "files_menu: ファイルを扱えない環境では、改名もふくめて全部が同じ 1 つの理由で沈む" {
  let rows = files_menu(
    {
      ..saved,
      can_open: false,
      can_save: false,
      can_rename: false,
      can_choose_folder: false,
    },
    file_acts,
  )
  let why = " (off: " + @parts.no_file_access + ")"
  assert_eq(rows[2] |> row_of, "Open" + why)
  assert_eq(rows[4] |> row_of, "Save" + why)
  assert_eq(rows[5] |> row_of, "Save as" + why)
  // **改名も同じ理由。** ファイルを持てないのだから、改名できないのは
  // 「この環境が改名を持たない」より前の話（docs/browsers.md の (b′)）
  // **自動保存も同じ理由。** 置き場が無いのだから、いつ書くかより前の話
  assert_eq(rows[6] |> row_of, "Autosave" + why)
  assert_eq(rows[7] |> row_of, "Rename" + why)
  assert_eq(rows[9] |> row_of, "Choose folder" + why)
}

///|
/// 改名できない理由は**根の深い順**に出る。持てない → 改名を持たない → まだ無い
test "rename_problem: 深い理由が浅い理由を隠す" {
  assert_eq(rename_problem(false, false, false), Some(@parts.no_file_access))
  assert_eq(rename_problem(false, true, true), Some(@parts.no_file_access))
  assert_eq(rename_problem(true, false, true), Some(no_rename_here))
  assert_eq(rename_problem(true, true, false), Some(nothing_to_rename))
  assert_eq(rename_problem(true, true, true), None)
}

///|
test "more_menu: 3 つの塊。テーマと掴みやすさの行は切り替えた先を言い、Copy link は閉じずに答える" {
  let mut copied = 0
  let acts : MoreActs = {
    undo: nop,
    redo: nop,
    pick_color: nop,
    toggle_theme: nop,
    toggle_grab: nop,
    copy_link: k => {
      copied += 1
      k(true)
    },
    visit: _ => (),
  }
  let dark = more_menu(
    { light: false, grab: false, link_caveat: k => k([]), },
    acts,
  )
  assert_eq(dark.map(row_of), [
    "Undo", "Redo", "---", "Accent color", "Light theme", "Easy grab", "---", "Copy link",
    "---", "Shortcuts", "GitHub",
  ])
  let light = more_menu(
    { light: true, grab: true, link_caveat: k => k(["Images won't travel"]), },
    acts,
  )
  assert_eq(light[4] |> row_of, "Dark theme")
  assert_eq(light[5] |> row_of, "Exact hit")
  guard light[7] is Done(r, go) else { fail("Copy link が Done でない") }
  assert_eq(r.mark, Some("link"))
  let notes = []
  r.caveat.unwrap()(n => notes.push(n))
  assert_eq(notes, [["Images won't travel"]])
  let mut ok = false
  go(v => ok = v)
  assert_eq((copied, ok), (1, true))
}

///|
/// 帯の表が言う絵の名は、どれも parts/icons.mbt の表に在る（綴りの食い違いは開いた瞬間に落ちる）
test "帯の並びの絵は全部 icons の表に在る" {
  let more : MoreActs = {
    undo: nop,
    redo: nop,
    pick_color: nop,
    toggle_theme: nop,
    toggle_grab: nop,
    copy_link: _ => (),
    visit: _ => (),
  }
  let all = marks_of(files_menu(saved, file_acts)) +
    marks_of(
      more_menu({ light: false, grab: false, link_caveat: _ => (), }, more),
    ) +
    marks_of(
      more_menu({ light: true, grab: true, link_caveat: _ => (), }, more),
    ) +
    marks_of(export_ways(host(false), None))
  assert_true(all.length() > 0)
  for m in all {
    assert_true(@parts.is_icon(m), msg="知らない絵: " + m)
  }
}
