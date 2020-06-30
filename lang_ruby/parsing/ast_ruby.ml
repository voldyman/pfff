(* Mike Furr
 *
 * Copyright (C) 2010 Mike Furr
 * Copyright (C) 2020 r2c
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the <organization> nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *)

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* Abstract Syntax Tree for Ruby 1.9
 *
 * Most of the code in this file derives from code from 
 * Mike Furr in diamondback-ruby.
 *
 * less: 
 *  - [AST Format of the Whitequark parser](https://github.com/whitequark/parser/blob/master/doc/AST_FORMAT.md)
 *  - https://rubygems.org/gems/ast
 *  - new AST format in RubyVM in ruby 2.6 (see wikipedia page on Ruby)
 * 
 * history:
 *  - 2010 diamondback-ruby latest version
 *  - 2020 integrate in pfff diamondback-ruby parser, AST and IL (called cfg)
 *  - lots of small refactorings, see modif-orig.txt
 *)

(*****************************************************************************)
(* Names *)
(*****************************************************************************)
(* Below we derive also eq, and ord, which is unusual compared to our other
 * parsers because we use the GLR parser generator dypgen to parse Ruby
 * and in case of ambiguities dypgen needs to _compare_ resulting ASTs
 * and filter out equivalence trees.
 *)

(* ------------------------------------------------------------------------- *)
(* Token/info *)
(* ------------------------------------------------------------------------- *)
type tok = Parse_info.t
 [@@deriving show] (* with tarzan *)
(* we don't care about difference in token positions *)
let compare_tok _a _b = 0
let equal_tok _a _b = true

(* a shortcut to annotate some information with token/position information *)
type 'a wrap = 'a * tok
 [@@deriving show, eq, ord]

(* round(), square[], curly{}, angle<>, and also pipes|| brackets  *)
type 'a bracket = tok * 'a * tok
 [@@deriving show, eq, ord]

(* ------------------------------------------------------------------------- *)
(* Ident/name *)
(* ------------------------------------------------------------------------- *)
type ident = string wrap
 [@@deriving show, eq, ord]

(* less: Self of tok | Id of ident | Cst of uident | ...  
type uident = string wrap (* Uppercase, a.k.a "constant" in Ruby *)
 [@@deriving show, eq, ord]
*)
type variable = ident * id_kind 
 and id_kind = 
  | ID_Self 
  (* treesitter: *)
  | ID_Super
  | ID_Lowercase (* prefixed by [a-z] or _ *)
  (* TODO: rename constant *)
  | ID_Uppercase (* prefixed by [A-Z] *)
  | ID_Instance  (* prefixed by @ *)
  | ID_Class     (* prefixed by @@ *)
  (* pattern: \\$-?(([!@&`'+~=/\\\\,;.<>*$?:\"])|([0-9]* )|([a-zA-Z_][a-zA-Z0-9_]* ))" *)
  | ID_Global    (* prefixed by $ *)
  (* TODO: can merge with Global *)
  | ID_Builtin   (* prefixed by $, followed by non-alpha *)
  (* TODO: move out in method_name instead *)
  | ID_Assign of id_kind (* postfixed by = *)
 [@@deriving show { with_path = false }, eq, ord]

(* 
type name = NameConstant of uident | NameScope of ...
*)

(* ------------------------------------------------------------------------- *)
(* Operators *)
(* ------------------------------------------------------------------------- *)
type unary_op = 
  (* unary and msg_id *)
  | Op_UMinus    (* -x, -@ when in msg_id *)  | Op_UPlus (* +x, +@ in msg_id *)
  | Op_UBang     (* !x *) | Op_UTilde    (* ~x *)
  (* not in msg_id *)
  | Op_UNot      (* not x *)
  (* only in argument: TODO move out? *)
  | Op_UAmper    (* & *) 
  (* in argument, pattern, exn, assignment lhs or rhs *)
  | Op_UStar     (* * *)
  (* tree-sitter: in argument and hash *)
  | Op_UStarStar (* ** *)

  | Op_DefinedQuestion (* defined? *)

  (* TODO: move out *)
  | Op_UScope    (* ::x *)
 [@@deriving show { with_path = false }, eq, ord]


type binary_op = 
  (* binary and msg_id and assign op *)
  | Op_PLUS     (* + *)  | Op_MINUS    (* - *)
  | Op_TIMES    (* * *)  | Op_REM      (* % *)  | Op_DIV      (* / *)

  | Op_LSHIFT   (* < < *)  | Op_RSHIFT   (* > > *)

  | Op_BAND     (* & *)  | Op_BOR      (* | *)
  | Op_XOR      (* ^ *)
  | Op_POW      (* ** *)

  (* binary and msg_id (but not in assign op) *)
  | Op_CMP      (* <=> *)
  | Op_EQ       (* == *)  | Op_EQQ      (* === *)
  | Op_NEQ      (* != *)
  | Op_GEQ      (* >= *)  | Op_LEQ      (* <= *)
  | Op_LT       (* < *)  | Op_GT       (* > *)

  | Op_MATCH    (* =~ *)
  | Op_NMATCH   (* !~ *)

  | Op_AREF     (* [] *)
  | Op_ASET     (* []= *)

  | Op_DOT2     (* .. *)

  (* tree-sitter: *)
  (* ` +@ -@ = unary + and - name
   *)

  (* not in msg_id *)
  | Op_kAND     (* and *)  | Op_kOR      (* or *)
  (* not in msg_id but in Op_OP_ASGN *)
  | Op_AND      (* && *)  | Op_OR   (* || *)

  | Op_ASSIGN   (* = *)
  | Op_OP_ASGN of binary_op  (* +=, -=, ... *)

  (* TODO: move out in scope_op *)
  | Op_DOT      (* . *)
  (* tree-sitter: *)
  | Op_AMPDOT (* &. *)  

  | Op_SCOPE    (* :: *)

  (* in hash or arguments *)
  | Op_ASSOC    (* => *)

  (* sugar for .. and = probably *)
  | Op_DOT3     (* ... *)

 [@@deriving show { with_path = false }, eq, ord]

(* ------------------------------------------------------------------------- *)
(* Method name *)
(* ------------------------------------------------------------------------- *)
(* later, mutually dependent on expr because of MethodSymbol *)

(*****************************************************************************)
(* Expression *)
(*****************************************************************************)

type expr = 
  | Literal of literal

  | Id of variable

  (* todo: delete *)
  | Operator of binary_op wrap
  | UOperator of unary_op wrap

  | Hash of bool * expr list bracket
  | Array of expr list bracket
  | Tuple of expr list

  | Unary of unary_op wrap * expr
  | Binop of expr * binary_op wrap * expr
  | Ternary of expr * tok (* ? *) * expr * tok (* : *) * expr

  | Call of expr * expr list * expr option
  (* TODO: ArrayAccess of expr * expr list bracket *)

  (* true = {}, false = do/end *)
  | CodeBlock of bool bracket * formal_param list option * stmts

  | S of stmt
  | D of definition

and literal = 
  | Bool of bool wrap
  (* pattern: 0[bB][01](_?[01])*|0[oO]?[0-7](_?[0-7])*|(0[dD])?\d(_?\d)*|0x[0-9a-fA-F](_?[0-9a-fA-F])* *)
  | Num of string wrap
  (* pattern: \d(_?\d)*(\.\d)?(_?\d)*([eE][\+-]?\d(_?\d)* )? *)
  | Float of string wrap
  (* treesitter: TODO add in dyp *)
  (* pattern: (\d+)?(\+|-)?(\d+)i *)
  | Complex of string wrap 
  | Rational of string wrap * tok (* r *) 
 
  | String of string_kind wrap
  | Regexp of (string_contents list * string) wrap
  (* treesitter: TODO add in dyp *)
  (* pattern: \?(\\\S({[0-9]*}|[0-9]*|-\S([MC]-\S)?)?|\S) *)
  | Char of string wrap 

  | Atom of atom

  | Nil of tok 

  and string_kind = 
    | Single of string
    | Double of string_contents list
    | Tick of string_contents list

    and string_contents = 
      | StrChars of string
      | StrExpr of expr

  and atom = string_contents list wrap

(* ------------------------------------------------------------------------- *)
(* Method name *)
(* ------------------------------------------------------------------------- *)

and method_name = 
  | MethodId of variable (* all except Self and Super *)
  | MethodIdAssign of ident * tok * id_kind (* = *)
  | MethodAtom of atom
  | MethodUOperator of unary_op wrap
  | MethodOperator of binary_op wrap

(*****************************************************************************)
(* pattern *)
(*****************************************************************************)
(* arg or splat_argument in case/when, but
 * also tuple in lhs of Assign.
 *)
and pattern = expr

(*****************************************************************************)
(* Statement *)
(*****************************************************************************)
(* Note that in Ruby everything is an expr, but I still like to split expr
 * with the different "subtypes" 'stmt' and 'definition'.
 * Note that ../analyze/il_ruby.ml has proper separate expr and stmt types.
 *)
and stmt =
  | Empty (* TODO: should remove! *)
  | Block of stmts (* TODO: bracket with begin/end or ( ) *)

  | If of tok * expr * stmts * stmts option2
  | While of tok * bool * expr * stmts
  | Until of tok * bool * expr * stmts
  | Unless of tok * expr * expr list * stmts
  | For of tok * formal_param list * expr * stmts
  | For2 of tok * pattern * tok * expr * stmts

  (* stmt and also as "command" *)
  | Return of tok * expr list (* bracket option *)
  | Yield of tok * expr list (* option *)
  (* treesitter: TSNOTDYP *)
  | Break of tok * expr list | Next of tok * expr list
  (* not as "command" *)
  | Redo of tok * expr list | Retry of tok * expr list

  | Case of tok * case_block

  | ExnBlock of body_exn

  and case_block = {
    case_guard : expr option;
    case_whens: (tok (* when *) * pattern list * stmts) list;
    case_else: stmts option2;
  }
  
  and body_exn = {
    body_exprs: stmts (* TODO bracket *);
    rescue_exprs: rescue_clause list;
    ensure_expr: stmts option2;
    else_expr: stmts option2;
  }
    (* TODO: (tok * (exception_name list * ident option) * stmts)*)
    and rescue_clause = (expr * expr)

and stmts = expr list

(* TODO: (tok * 'a) option *)
and 'a option2 = 'a

(*****************************************************************************)
(* Definitions *)
(*****************************************************************************)
and definition =
  | ModuleDef of tok * expr * body_exn
  | ClassDef of tok * class_kind * inheritance_kind option * body_exn
  | MethodDef of tok * method_kind * formal_param list * body_exn

  | BeginBlock of tok * stmts bracket
  | EndBlock of tok * stmts bracket

  | Alias of tok * method_name * method_name
  | Undef of tok * method_name list

  (* treesitter: TODO stuff with ; and identifier list? in block params? *)
  and formal_param = 
    | Formal_id of variable (* TODO: even just ident? *)
    | Formal_amp of tok * ident

    (* TODO: Formal_splat of tok * ident option *)
    | Formal_star of tok * ident (* as in *x *)
    | Formal_rest of tok (* just '*' *)

    | Formal_tuple of formal_param list bracket
    | Formal_default of ident * tok (* = *) * expr

    (* treesitter: TSNOTDYP *)
    | Formal_hash_splat of tok * ident option
    | Formal_kwd of ident * tok * expr option
  
  (* TODO: of tok (* < *) * ?? *)
  and inheritance_kind = 
    | Class_Inherit of expr
    | Inst_Inherit of expr

  (* TODO: *)
  and _name = expr

  and method_kind =
   | M of method_name
   | SingletonM of expr (* TODO (variable | expr) * scope_op * method_name *)

  (* TODO: C of name * inheritance option | SingletonC of inheritance? *)
  and class_kind = expr

 [@@deriving show { with_path = false }, eq, ord] (* with tarzan *)

(*****************************************************************************)
(* Type *)
(*****************************************************************************)
(* Was called Annotation in diamondback-ruby but was using its own specific
 * comment format. 
 * less: maybe leverage the new work on gradual typing of Ruby in
 * Sorbet and steep?
 *)

(*****************************************************************************)
(* Toplevel *)
(*****************************************************************************)

type program = stmts
 [@@deriving show, eq, ord] (* with tarzan *)

(*****************************************************************************)
(* Any *)
(*****************************************************************************)

type any = 
  | E of expr
  | Pr of program

 [@@deriving show { with_path = false}, eq] (* with tarzan *)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)
let empty_body_exn = {
    body_exprs = [];
    rescue_exprs = [];
    ensure_expr = [];
    else_expr = [];
}
