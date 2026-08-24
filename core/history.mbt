// 1 本の undo スタック。エントリは Edit 集合の列と、その逆。
// id は「エントリ適用の前後で、どの見出しがどの id だったか」の対応表で
// undo / redo をまたいで生き残る。
// begin_tx / commit_tx は複数コマンドを 1 つの undo にまとめるための括弧。

///|
priv struct Entry {
  steps : Array[Array[Edit]] // applied in order for redo
  inv : Array[Array[Edit]] // inv[i] undoes steps[i]; undo applies in reverse
  tag : String
  before : Array[(Int, Int)] // (from, id) per node before the entry applied
  mut after : Array[(Int, Int)] // same, after — ids survive undo/redo
}

///|
/// (heading start, id) per node, in document order. Stored on undo entries
/// so ids survive undo/redo of any command.
fn id_pairs() -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  for nd in st.nodes {
    out.push((nd.from, nd.id))
  }
  out
}

///|
fn pairs_map(pairs : Array[(Int, Int)]) -> Map[Int, Int] {
  let m : Map[Int, Int] = Map([])
  for p in pairs {
    let (from, id) = p
    m[from] = id
  }
  m
}

///|
/// Commands that patch node ids AFTER apply_sets (move_block) call this so
/// the undo entry's `after` snapshot reflects the patched ids.
fn refresh_entry_after() -> Unit {
  match st.tx {
    Some(_) => () // commit_tx captures the final state
    None =>
      if st.undo.length() > 0 {
        st.undo[st.undo.length() - 1].after = id_pairs()
      }
  }
}

///|
/// Apply edit sets to the document: update text, reparse, remap node ids
/// (headings whose start position survives keep their id), and record the
/// entry on the undo stack (merged into an open tx or a same-tag top entry).
fn apply_sets(sets : Array[Array[Edit]], tag : String) -> Unit {
  let before = id_pairs()
  // carry old ids through the edits by position
  let mapped : Array[Int] = [] // mapped from per old node, -1 if destroyed
  for nd in st.nodes {
    mapped.push(nd.from)
  }
  let inv_sets : Array[Array[Edit]] = []
  for s in sets {
    for k = 0; k < mapped.length(); k = k + 1 {
      if mapped[k] >= 0 {
        mapped[k] = map_offset(mapped[k], s)
      }
    }
    inv_sets.push(invert_edit_set(s))
    st.text = apply_edit_set(st.text, s)
  }
  let id_at : Map[Int, Int] = Map([]) // surviving offset -> old id
  for k = 0; k < mapped.length(); k = k + 1 {
    if mapped[k] >= 0 {
      id_at[mapped[k]] = st.nodes[k].id
    }
  }
  rebuild_nodes(id_at)
  st.rev = st.rev + 1
  for s in sets {
    st.last_sets.push(s)
  }
  let after = id_pairs()
  match st.tx {
    Some(tx) => {
      for i = 0; i < sets.length(); i = i + 1 {
        tx.steps.push(sets[i])
        tx.inv.push(inv_sets[i])
      }
    }
    None => {
      st.redo.clear()
      let merged = if tag != "" && st.undo.length() > 0 {
        let top = st.undo[st.undo.length() - 1]
        if top.tag == tag {
          for i = 0; i < sets.length(); i = i + 1 {
            top.steps.push(sets[i])
            top.inv.push(inv_sets[i])
          }
          top.after = after
          true
        } else {
          false
        }
      } else {
        false
      }
      if !merged {
        st.undo.push(Entry::{ steps: sets, inv: inv_sets, tag, before, after })
      }
    }
  }
}

///|
fn begin_tx(tag : String) -> Unit {
  st.tx = Some(Entry::{ steps: [], inv: [], tag, before: id_pairs(), after: [] })
}

///|
fn commit_tx() -> Unit {
  match st.tx {
    Some(tx) => {
      st.tx = None
      if tx.steps.length() > 0 {
        tx.after = id_pairs()
        st.redo.clear()
        st.undo.push(tx)
      }
    }
    None => ()
  }
}

///|
/// Replay an entry's edit sets on the text, then restore the recorded node
/// ids by position — one rebuild total, and ids survive perfectly.
fn replay_entry(
  sets : Array[Array[Edit]],
  reversed : Bool,
  pairs : Array[(Int, Int)],
) -> Unit {
  if reversed {
    for i = sets.length() - 1; i >= 0; i = i - 1 {
      st.text = apply_edit_set(st.text, sets[i])
      st.last_sets.push(sets[i])
    }
  } else {
    for i = 0; i < sets.length(); i = i + 1 {
      st.text = apply_edit_set(st.text, sets[i])
      st.last_sets.push(sets[i])
    }
  }
  rebuild_nodes(pairs_map(pairs))
  st.rev = st.rev + 1
}

///|
fn do_undo() -> Unit {
  if st.undo.length() == 0 {
    return
  }
  let entry = st.undo.unsafe_pop()
  replay_entry(entry.inv, true, entry.before)
  st.redo.push(entry)
}

///|
fn do_redo() -> Unit {
  if st.redo.length() == 0 {
    return
  }
  let entry = st.redo.unsafe_pop()
  replay_entry(entry.steps, false, entry.after)
  st.undo.push(entry)
}
