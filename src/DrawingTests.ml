(* Copyright 2017 Vincent Jacques <vincent@vincent-jacques.net> *)

open General.Abbr

let single_rule_grammars =
  Grammar.[
    ("terminal", Definition.Terminal {Terminal.value="in a rounded rectangle"});
    ("non-terminal", Definition.NonTerminal {NonTerminal.name="in a rectangle"});
    ("sequence", Definition.Sequence {Sequence.elements=[Definition.Terminal {Terminal.value="t1"}; Definition.Terminal {Terminal.value="t2"};]});
  ]
  |> Li.map ~f:(fun (name, definition) ->
    (name, {Grammar.rules=[{Grammar.Rule.name; definition}]})
  )

let tests =
  single_rule_grammars
