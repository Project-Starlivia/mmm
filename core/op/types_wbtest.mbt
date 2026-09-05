// Op が値として JSON になることを固定する。境界（別 PR）がこの形を受ける。

///|
test "Op は JSON の値になる" {
  json_inspect(
    Op::MoveNode(ids=[3, 5], at=NodePlace::In(node=2, side=Some(Left))),
    content=[
      "MoveNode",
      { "ids": [3, 5], "at": ["In", { "node": 2, "side": "Left" }] },
    ],
  )
  json_inspect(Op::Delete(ids=[4]), content=["Delete", { "ids": [4] }])
  json_inspect(
    Op::AddBlock(
      at=BlockPlace::Before(block=7),
      content=Code(info="js", text="x"),
    ),
    content=[
      "AddBlock",
      {
        "at": ["Before", { "block": 7 }],
        "content": ["Code", { "info": "js", "text": "x" }],
      },
    ],
  )
}
