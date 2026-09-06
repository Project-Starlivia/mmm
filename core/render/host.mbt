// 地図が外に頼るもの。文書と選択の値は EditorState（ts の state.ts）に居るので、
// 読む・書くは閉包で受ける。ブラウザの API（クリップボード・メニューの器・しらせ）も同じ。

///|
pub(all) struct Host {
  /// いまの文書（core の読み）。置くのに要る
  survey : () -> @read.Survey
  /// 字の実測（canvas）
  measure : @map.Measure
  /// ローカル画像の objectURL。読めていない / 握っていないあいだは None
  image_url : (String) -> String?
  /// 読めていない場所取りに添える字。握っていないときだけ（他は None）
  image_hint : () -> String?
  /// その字が押された。画像フォルダを繋ぎ直す
  connect_assets : () -> Unit
  /// 選択を持っている側。md なら輪（内側）、map なら枠（selected）で塗る
  holder : () -> @read.Holder
  /// いま選んでいるもの
  selection : () -> @map.Selection
  /// 地図で選び直した。reveal は md 側をその頭へスクロールするか
  set_selection : (@map.Selection, Bool) -> Unit
  /// 選んでいるカードの中身の id
  picked : () -> Int?
  /// カードを選び直した（None で外す）
  set_picked : (Int?) -> Unit
  /// その中身の原文。地番で md から切り出す（無ければ空）
  block_text : (Int) -> String
  /// 操作を md に映す。edit なら、映した後の focus をそのまま編集開始
  /// （ノードのときだけ — 中身の focus はカードとして選ぶ）。返り値は映した focus
  apply : (@op.Op, Bool) -> Int?
  /// クリップボードを貼る（Mod+V）。宛先は選択の anchor、無ければ文書
  paste : () -> Unit
  /// 選んでいるものをクリップボードへ写す（Mod+C / Mod+X）。写せたかを続きに渡す —
  /// 写せなければ Cut は消さない
  copy : ((Bool) -> Unit) -> Unit
  /// そのノードへ描いて貼る（Shift+D）
  draw : (Int) -> Unit
  /// クリップボードの字を続きに渡す（読めなければ ""）
  read_clipboard : ((String) -> Unit) -> Unit
  /// コードの色分け。(行, 言語) → 行ごとの塊
  tokens : (Array[String], String) -> Array[Array[Token]]
  /// カードの欄の色分け。原文 → 行ごとの塊
  tokens_block : (String) -> Array[Array[Token]]
  /// 言語の読み込みの世代。変われば描き直す
  epoch : () -> Int
  /// しらせ（app/notice.ts の言葉）
  failed : (String) -> Unit
}
