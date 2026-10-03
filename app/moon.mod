name = "mmm/app"

version = "0.1.0"

repository = "https://github.com/Project-Starlivia/mmm"

license = "MIT"

keywords = [ ]

preferred_target = "js"

description = ""

import {
  "mmm/core@0.1.0",
  "mizchi/js@0.12.2",
  "mizchi/js_browser@0.12.2",
  "moonbitlang/async@0.20.5",
}

// implicit_impl_as_method は derive の行ごとに出る。入れない理由は docs/spec.md「開発」

warnings = "-79"
