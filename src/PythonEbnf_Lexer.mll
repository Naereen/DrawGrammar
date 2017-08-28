{
  open General.Abbr
  module Array = OCamlStandard.Array
  module Lexing = OCamlStandard.Lexing

  open PythonEbnf_Parser

  exception Error of string

  let error format =
    Frmt.with_result ~f:(fun message -> Exn.raise (Error message)) format
}

let identifier = ['a'-'z' '_'] ['a'-'z' '0'-'9' '_' '-']*

rule token = parse
  | '\n' { Lexing.new_line lexbuf; token lexbuf }
  | [' ' '\r']+ { token lexbuf }
  | '#' [^'\n']* '\n' { Lexing.new_line lexbuf; token lexbuf }
  | '#' [^'\n']* eof { EOF }
  | eof { EOF }

  | (identifier as name) ':' { RULE name }
  | identifier as name { IDENTIFIER name }
  | '\'' ([^'\'']+ as value) '\'' { TERMINAL value }
  | '\'' [^'\'']* eof { error "unexpected end of file in literal terminal" }
  | (['A'-'Z']+ as value) { TOKEN value }

  | '|' { ALTERNATIVE }
  | '(' { START_GROUP }
  | ')' { END_GROUP }
  | '[' { START_OPTION }
  | ']' { END_OPTION }
  | '*' { REPEAT_ZERO }
  | '+' { REPEAT_ONE }
  | _ as c { error "unexpected character %C" c }
