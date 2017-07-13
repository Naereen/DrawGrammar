open General.Abbr

module Lexing = OCamlStandard.Lexing
let sprintf = OCamlStandard.Printf.sprintf

let set_file_name lexbuf = Lexing.(function
  | None -> ()
  | Some file_name ->
    lexbuf.lex_start_p <- {lexbuf.lex_start_p with pos_fname=file_name};
    lexbuf.lex_curr_p <- {lexbuf.lex_curr_p with pos_fname=file_name};
)

module Make(Parser: sig
  type token
  val syntax: (Lexing.lexbuf -> token) -> Lexing.lexbuf -> Grammar.t
end)(Lexer: sig
  val token: Lexing.lexbuf -> Parser.token
end) = struct
  let parse_lexbuf ?file_name lexbuf =
    set_file_name lexbuf file_name;
    lexbuf
    |> Parser.syntax Lexer.token

  let parse_chan ?file_name chan =
    chan
    |> Lexing.from_channel
    |> parse_lexbuf ?file_name

  let parse_file file_name =
    (* @todo Add In_channel.with_file in General *)
    let chan = open_in file_name in
    let g = parse_chan ~file_name chan in
    close_in chan;
    g

  let parse_string ?file_name code =
    code
    |> Lexing.from_string
    |> parse_lexbuf ?file_name
end

(* @todo Rename Iso14977Ebnf *)
module Ebnf = Make(EbnfParser)(EbnfLexer)

(* @todo Rename PythonEbnf *)
module Python = Make(PythonParser)(PythonLexer)

module Syntax = struct
  type t =
    | Ebnf
    | Python

  let of_string = function
    | "ebnf" -> Ebnf
    | "python" -> Python
    | syntax -> failwith (sprintf "Unknown grammar syntax %s" syntax)
end

let parse_string ~syntax s =
  match syntax with
    | Syntax.Ebnf -> Ebnf.parse_string s
    | Syntax.Python -> Python.parse_string s

let parse_file name =
  let syntax =
    name
    |> Str.split ~sep:"."
    |> Li.reverse
    |> Li.head
    |> Syntax.of_string
  in
  match syntax with
    | Syntax.Ebnf -> Ebnf.parse_file name
    | Syntax.Python -> Python.parse_file name

module EbnfUnitTests = struct
  open Tst

  let make s expected =
    s >:: (fun _ ->
      check_poly ~to_string:Grammar.to_string Grammar.(grammar [rule "r" expected]) (parse_string ~syntax:Syntax.Ebnf (sprintf "r = %s;" s))
    )

  let t = Grammar.terminal "t"
  let v1 = Grammar.non_terminal "v1"
  let v2 = Grammar.non_terminal "v2"
  let v3 = Grammar.non_terminal "v3"
  let v4 = Grammar.non_terminal "v4"
  let s = Grammar.sequence
  let a = Grammar.alternative
  let r = Grammar.repetition
  let n = Grammar.null
  let sp = Grammar.special
  let ex = Grammar.except

  let test = "Ebnf" >::: [
    make "'t'" t;
    make "'t' (* foobar *)" t;
    make "\"t\"" t;
    make "v1" v1;
    make "v1, v2, v3, v4" (s [v1; v2; v3; v4]);
    make "v1, (v2, v3), v4" (s [v1; v2; v3; v4]);
    make "v1 | v2 ! v3 / v4" (a [v1; v2; v3; v4]);
    make "v1 | (v2 | v3) | v4" (a [v1; v2; v3; v4]);
    make "{v1}" (r n v1);
    make "(:v1:)" (r n v1);
    make "5 * v1" (r v1 n);
    make "[v1]" (a [n; v1]);
    make "(/v1/)" (a [n; v1]);
    make "" n;
    make "v1 - v2" (ex v1 v2);
    make "? foo bar baz ?" (sp "foo bar baz");
  ]
end

module PythonUnitTests = struct
  open Tst

  let make s expected =
    s >:: (fun _ ->
      check_poly ~to_string:Grammar.to_string Grammar.(grammar [rule "r" expected]) (parse_string ~syntax:Syntax.Python (sprintf "r: %s" s))
    )

  let g = Grammar.grammar
  let nt = Grammar.non_terminal
  let t = Grammar.terminal
  let s = Grammar.sequence
  let a = Grammar.alternative
  let r = Grammar.repetition
  let ru = Grammar.rule
  let n = Grammar.null
  let sp = Grammar.special
  let ex = Grammar.except

  let test = "Python" >::: [
    make "FOO" (t "FOO");
    make "FOO # bar baz\n" (t "FOO");
    make "foo" (nt "foo");
    make "FOO | BAR" (a [t "FOO"; t "BAR"]);
    make "FOO BAR" (s [t "FOO"; t "BAR"]);
    make "FOO BAR | BAZ BIM" (a [s [t "FOO"; t "BAR"]; s [t "BAZ"; t "BIM"]]);
    make "FOO (BAR | BAZ) BIM" (s [t "FOO"; a [t "BAR"; t "BAZ"]; t "BIM"]);
    make "[FOO]" (a [n; t "FOO"]);
    make "FOO*" (r n (t "FOO"));
    make "FOO+" (r (t "FOO") n);
    "several rules" >:: (fun _ ->
      check_poly ~to_string:Grammar.to_string
        (g [ru "a" (t "FOO"); ru "b"(t "BAR")])
        (parse_string ~syntax:Syntax.Python "a: FOO\nb: BAR\n")
    )
  ]
end

module UnitTests = struct
  open Tst

  let test = "Parse" >::: [
    EbnfUnitTests.test;
    PythonUnitTests.test;
  ]
end