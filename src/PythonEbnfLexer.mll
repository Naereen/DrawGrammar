{
  open General.Abbr
  module Array = OCamlStandard.Array
  module Lexing = OCamlStandard.Lexing
  module Printf = OCamlStandard.Printf

  open PythonEbnfParser

  exception Error of string

  let error format =
    Printf.ksprintf (fun message -> raise (Error message)) format
}

let identifier = ['a'-'z'] ['a'-'z' '_' '0'-'9']*

rule token = parse
  | ['\n']  { Lexing.new_line lexbuf; token lexbuf }
  | [' ' '\r']+  { token lexbuf }
  | '#' [^'\n']* '\n' { Lexing.new_line lexbuf; token lexbuf }
  | '#' [^'\n']* eof { EOF }
  | eof { EOF }

  | (identifier as name) ':' { RULE name }
  | identifier as name { IDENTIFIER name }
  | '\'' ([^'\'']+ as value) '\'' { TERMINAL value }
  | (['A'-'Z']+ as value) { TOKEN value }

  | '|' { ALTERNATIVE }
  | '(' { START_GROUP }
  | ')' { END_GROUP }
  | '[' { START_OPTION }
  | ']' { END_OPTION }
  | '*' { REPEAT_ZERO }
  | '+' { REPEAT_ONE }
  | _ as c { error "unexpected character %C." c }
