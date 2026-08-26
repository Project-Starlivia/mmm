// Thin JS export layer over mmm-app/core. Kept separate so the library
// package stays testable with `moon test`.

///|
#export_name("initDoc")
pub fn init_doc(text : String) -> String {
  @core.init_doc(text)
}

///|
#export_name("setListFrom")
pub fn set_list_from(b : Int) -> String {
  @core.set_list_from(b)
}

///|
#export_name("reformat")
pub fn reformat(tag : String) -> String {
  @core.reformat(tag)
}

///|
#export_name("getText")
pub fn get_text() -> String {
  @core.get_text()
}

///|
#export_name("replaceText")
pub fn replace_text(from : Int, to : Int, insert : String, tag : String) -> String {
  @core.replace_text(from, to, insert, tag)
}

///|
#export_name("addChild")
pub fn add_child(id : Int, tag : String) -> String {
  @core.add_child(id, tag)
}

///|
#export_name("addSibling")
pub fn add_sibling(id : Int, tag : String) -> String {
  @core.add_sibling(id, tag)
}

///|
#export_name("addSiblingBefore")
pub fn add_sibling_before(id : Int, tag : String) -> String {
  @core.add_sibling_before(id, tag)
}

///|
#export_name("addParent")
pub fn add_parent(id : Int, tag : String) -> String {
  @core.add_parent(id, tag)
}

///|
#export_name("addRoot")
pub fn add_root(tag : String) -> String {
  @core.add_root(tag)
}

///|
#export_name("renameNode")
pub fn rename_node(id : Int, label : String, tag : String) -> String {
  @core.rename_node(id, label, tag)
}

///|
#export_name("deleteNodes")
pub fn delete_nodes(ids : Array[Int]) -> String {
  @core.delete_nodes(ids)
}

///|
#export_name("indentNodes")
pub fn indent_nodes(ids : Array[Int]) -> String {
  @core.indent_nodes(ids)
}

///|
#export_name("outdentNodes")
pub fn outdent_nodes(ids : Array[Int]) -> String {
  @core.outdent_nodes(ids)
}

///|
#export_name("moveNodes")
pub fn move_nodes(ids : Array[Int], target : Int, pos : Int) -> String {
  @core.move_nodes(ids, target, pos)
}

///|
#export_name("moveAsParent")
pub fn move_as_parent(ids : Array[Int], target : Int) -> String {
  @core.move_as_parent(ids, target)
}

///|
#export_name("reorderNode")
pub fn reorder_node(id : Int, dir : Int) -> String {
  @core.reorder_node(id, dir)
}

///|
#export_name("toggleHidden")
pub fn toggle_hidden(id : Int) -> String {
  @core.toggle_hidden(id)
}

///|
#export_name("undo")
pub fn undo() -> String {
  @core.undo()
}

///|
#export_name("redo")
pub fn redo() -> String {
  @core.redo()
}

///|
#export_name("selectionText")
pub fn selection_text(ids : Array[Int]) -> String {
  @core.selection_text(ids)
}

///|
#export_name("hasHeadings")
pub fn has_headings(text : String) -> Bool {
  @core.has_headings(text)
}

///|
#export_name("relevelText")
pub fn relevel_text(text : String, target_depth : Int) -> String {
  @core.relevel_text(text, target_depth)
}
