open General.Abbr

module Lexing = OCamlStandard.Lexing

let set_file_name lexbuf = Lexing.(function
  | None -> ()
  | Some file_name ->
    lexbuf.lex_start_p <- {lexbuf.lex_start_p with pos_fname=file_name};
    lexbuf.lex_curr_p <- {lexbuf.lex_curr_p with pos_fname=file_name};
)

module Errors = struct
  exception Lexing of string
  exception Parsing of string

  let position_to_string {Lexing.pos_fname; pos_lnum; pos_bol; pos_cnum; _} =
    let file = match pos_fname with
      | "" -> ""
      | _ -> Frmt.apply "file %S, " pos_fname
    in
    Frmt.apply "%sline %n, character %n" file pos_lnum (pos_cnum - pos_bol + 1)

  let lexing position message =
    Exn.raise (Lexing (Frmt.apply "%s: lexing error: %s" (position_to_string position) message))

  let parsing position message =
    Exn.raise (Parsing (Frmt.apply "%s: parsing error: %s" (position_to_string position) message))
end

module Make(Parser: sig
  module MenhirInterpreter: sig
    include MenhirLib.IncrementalEngine.INCREMENTAL_ENGINE
  end

  module Incremental: sig
    val grammar: Lexing.position -> Grammar.t MenhirInterpreter.checkpoint
  end
end)(Messages: sig
  val message: int -> string
end)(Lexer: sig
  val token: Lexing.lexbuf -> Parser.MenhirInterpreter.token
  exception Error of string
end) = struct
  let parse_lexbuf ?file_name lexbuf =
    set_file_name lexbuf file_name;
    try
      Parser.MenhirInterpreter.loop_handle
        identity
        (function
          | Parser.MenhirInterpreter.HandlingError env ->
            env
            |> Parser.MenhirInterpreter.current_state_number
            |> Messages.message
            |> Str.drop_suffix ~suf:"\n"
            |> Errors.parsing (Lexing.lexeme_start_p lexbuf)
          | _ -> Errors.parsing (Lexing.lexeme_start_p lexbuf) "unknown"
        )
        (Parser.MenhirInterpreter.lexer_lexbuf_to_supplier Lexer.token lexbuf)
        (Parser.Incremental.grammar lexbuf.Lexing.lex_curr_p)
    with
      | Lexer.Error message -> Errors.lexing (Lexing.lexeme_start_p lexbuf) message

  let parse_chan ?file_name chan =
    chan
    |> Lexing.from_channel
    |> parse_lexbuf ?file_name

  let parse_file file_name =
    InFile.with_channel file_name ~f:(parse_chan ~file_name)

  let parse_string ?file_name code =
    code
    |> Lexing.from_string
    |> parse_lexbuf ?file_name
end

module IsoEbnf = Make(IsoEbnf_Parser)(IsoEbnf_Messages)(IsoEbnf_Lexer)

module PythonEbnf = Make(PythonEbnf_Parser)(PythonEbnf_Messages)(PythonEbnf_Lexer)

module OCamlETexEbnf = Make(OCamlETexEbnf_Parser)(OCamlETexEbnf_Messages)(OCamlETexEbnf_Lexer)

(* @todo Parse Menhir/ocamlyacc's .mly files *)

module Syntax = struct
  type t =
    | IsoEbnf
    | PythonEbnf
    | OCamlETexEbnf

  let all = [
    IsoEbnf;
    PythonEbnf;
    OCamlETexEbnf;
  ]

  let to_string = function
    | IsoEbnf -> "iso-ebnf"
    | PythonEbnf -> "python-ebnf"
    | OCamlETexEbnf -> "ocaml-etex-ebnf"

  let description = function
    | IsoEbnf -> "ISO-14977 EBNF"
    | PythonEbnf -> "syntax used in Python grammar file"
    | OCamlETexEbnf -> "syntax used in OCaml manual .etex sources"

  let online_reference = function
    | IsoEbnf -> "http://www.cl.cam.ac.uk/~mgk25/iso-14977.pdf"
    | PythonEbnf -> "https://github.com/python/cpython/blob/master/Grammar/Grammar"
    | OCamlETexEbnf -> "https://github.com/ocaml/ocaml/tree/trunk/manual/manual/refman"

  let of_string = function
    | "iso-ebnf" -> IsoEbnf
    | "python-ebnf" -> PythonEbnf
    | "ocaml-etex-ebnf" -> OCamlETexEbnf
    | syntax -> Exn.failure "Unknown grammar syntax %s" syntax
end

let parse_string ~syntax s =
  match syntax with
    | Syntax.IsoEbnf -> IsoEbnf.parse_string s
    | Syntax.PythonEbnf -> PythonEbnf.parse_string s
    | Syntax.OCamlETexEbnf -> OCamlETexEbnf.parse_string s

let parse_file ?syntax name =
  let syntax =
    match syntax with
      | Some syntax -> syntax
      | None ->
        name
        |> Str.split ~sep:"."
        |> Li.reverse
        |> Li.head
        |> Syntax.of_string
  in
  match syntax with
    | Syntax.IsoEbnf -> IsoEbnf.parse_file name
    | Syntax.PythonEbnf -> PythonEbnf.parse_file name
    | Syntax.OCamlETexEbnf -> OCamlETexEbnf.parse_file name

let check_grammar =
  General.Testing.check_poly ~repr:Grammar.to_string

module IsoEbnfUnitTests = struct
  open Tst

  let success s expected =
    s >: (lazy (
      check_grammar
        ~expected:Grammar.(grammar [rule "r" expected])
        (parse_string ~syntax:Syntax.IsoEbnf (Frmt.apply "r = %s;" s))
    ))

  let fail_lexing s message =
    s >: (lazy (
      expect_exception
        ~expected:(Errors.Lexing message)
        (lazy (parse_string ~syntax:Syntax.IsoEbnf s))
    ))

  let fail_parsing s message =
    s >: (lazy (
      expect_exception
        ~expected:(Errors.Parsing message)
        (lazy (parse_string ~syntax:Syntax.IsoEbnf s))
    ))

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

  let test = "IsoEbnf" >:: [
    success "'t'" t;
    success "'t' (* foobar *)" t;
    success "\"t\"" t;
    success "v1" v1;
    success "v1, v2, v3, v4" (s [v1; v2; v3; v4]);
    success "v1, (v2, v3), v4" (s [v1; v2; v3; v4]);
    success "v1 | v2 ! v3 / v4" (a [v1; v2; v3; v4]);
    success "v1 | (v2 | v3) | v4" (a [v1; v2; v3; v4]);
    success "{v1}" (r n v1);
    success "(:v1:)" (r n v1);
    success "5 * v1" (r v1 n);
    success "[v1]" (a [n; v1]);
    success "(/v1/)" (a [n; v1]);
    success "" n;
    success "v1 - v2" (ex v1 v2);
    success "? foo bar baz ?" (sp "foo bar baz");

    fail_lexing "#" "line 1, character 1: lexing error: unexpected character '#'";
    fail_lexing "(*" "line 1, character 3: lexing error: unexpected end of file in comment";
    fail_lexing "'" "line 1, character 1: lexing error: unexpected end of file in string";
    fail_lexing "\"" "line 1, character 1: lexing error: unexpected end of file in string";
    fail_lexing "?" "line 1, character 1: lexing error: unexpected end of file in special sequence";

    fail_parsing "a = (;" "line 1, character 6: parsing error: We are working on better error messages. (iso-ebnf 9)";
  ]
end

module PythonEbnfUnitTests = struct
  open Tst

  let success s expected =
    s >: (lazy (
      check_grammar
        ~expected:Grammar.(grammar [rule "r" expected])
        (parse_string ~syntax:Syntax.PythonEbnf (Frmt.apply "r: %s" s))
    ))

  let fail_lexing s message =
    s >: (lazy (
      expect_exception
        ~expected:(Errors.Lexing message)
        (lazy (parse_string ~syntax:Syntax.PythonEbnf s))
    ))

  let fail_parsing s message =
    s >: (lazy (
      expect_exception
        ~expected:(Errors.Parsing message)
        (lazy (parse_string ~syntax:Syntax.PythonEbnf s))
    ))

  let g = Grammar.grammar
  let nt = Grammar.non_terminal
  let t = Grammar.token
  let s = Grammar.sequence
  let a = Grammar.alternative
  let r = Grammar.repetition
  let ru = Grammar.rule
  let n = Grammar.null
  let sp = Grammar.special
  let ex = Grammar.except

  let test = "PythonEbnf" >:: [
    success "FOO" (t "FOO");
    success "FOO # bar baz\n" (t "FOO");
    success "foo" (nt "foo");
    success "FOO | BAR" (a [t "FOO"; t "BAR"]);
    success "FOO BAR" (s [t "FOO"; t "BAR"]);
    success "FOO BAR | BAZ BIM" (a [s [t "FOO"; t "BAR"]; s [t "BAZ"; t "BIM"]]);
    success "FOO (BAR | BAZ) BIM" (s [t "FOO"; a [t "BAR"; t "BAZ"]; t "BIM"]);
    success "[FOO]" (a [n; t "FOO"]);
    success "FOO*" (r n (t "FOO"));
    success "FOO+" (r (t "FOO") n);
    "several rules" >: (lazy (
      check_grammar
        ~expected:(g [ru "a" (t "FOO"); ru "b"(t "BAR")])
        (parse_string ~syntax:Syntax.PythonEbnf "a: FOO\nb: BAR\n")
    ));

    fail_lexing "{" "line 1, character 1: lexing error: unexpected character '{'";
    fail_lexing "'" "line 1, character 1: lexing error: unexpected end of file in literal terminal";

    fail_parsing "a: )" "line 1, character 4: parsing error: We are working on better error messages. (python-ebnf 1)";
  ]
end

module OCamlETexEbnfUnitTests = struct
  open Tst

  let success s expected =
    s >: (lazy (
      let s = Frmt.apply "{lkqjsd|\\begin{syntax}r: %s\\end{syntax}x{{xx\\begin{syntax}s: 't'\\end{syntax}flkdjf" s in
      check_grammar
        ~expected:Grammar.(grammar [rule "r" expected; rule "s" (terminal "t")])
        (parse_string ~syntax:Syntax.OCamlETexEbnf s)
    ))

  let fail_lexing s message =
    s >: (lazy (
      expect_exception
        ~expected:(Errors.Lexing message)
        (lazy (parse_string ~syntax:Syntax.OCamlETexEbnf s))
    ))

  let fail_parsing s message =
    s >: (lazy (
      expect_exception
        ~expected:(Errors.Parsing message)
        (lazy (parse_string ~syntax:Syntax.OCamlETexEbnf s))
    ))

  let g = Grammar.grammar
  let nt = Grammar.non_terminal
  let t = Grammar.terminal
  let s = Grammar.sequence
  let a = Grammar.alternative
  let r = Grammar.repetition
  let ra = Grammar.range
  let ru = Grammar.rule
  let n = Grammar.null
  let sp = Grammar.special
  let ex = Grammar.except

  let test = "OCamlETexEbnf" >:: [
    success "foo" (nt "foo");
    success "\"bar\"" (t "bar");
    success "foo | bar" (a [nt "foo"; nt "bar"]);
    success "foo || bar" (a [nt "foo"; nt "bar"]);
    success "foo \\ldots bar" (ra (nt "foo") (nt "bar"));
  ]
end

module UnitTests = struct
  open Tst

  let test = "Parse" >:: [
    IsoEbnfUnitTests.test;
    PythonEbnfUnitTests.test;
    OCamlETexEbnfUnitTests.test;
  ]
end
