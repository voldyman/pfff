(* Yoann Padioleau
 *
 * Copyright (C) 2020 r2c
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 * 
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* Abstract Syntax Tree for Go.
 *
 * This file tries to keep the convention used in the official ast.go
 * implementation (e.g., it uses FuncLit instead of the more common Lambda).
 *
 * reference: https://golang.org/src/go/ast/ast.go
 *)

(*****************************************************************************)
(* Names *)
(*****************************************************************************)

(* ------------------------------------------------------------------------- *)
(* Token/info *)
(* ------------------------------------------------------------------------- *)
(* Contains among other things the position of the token through
 * the Parse_info.token_location embedded inside it, as well as the
 * transformation field that makes possible spatch on the code.
 *)
type tok = Parse_info.t
 (* with tarzan *)

(* a shortcut to annotate some information with token/position information *)
type 'a wrap = 'a * tok
 (* with tarzan *)

(* ------------------------------------------------------------------------- *)
(* Ident, qualifier *)
(* ------------------------------------------------------------------------- *)
(* for ?/?/? *)
type ident = string wrap
 (* with tarzan *)

(* for ?/?/?  (called names in ast.go) *)
type qualified_ident = ident list (* 1 or 2 elements *)
 (* with tarzan *)

(*****************************************************************************)
(* Type *)
(*****************************************************************************)
type type_ =
 | TName of qualified_ident (* included the basic types: bool/int/... *)
 | TPtr of type_

 | TArray of expr * type_
 | TSlice of type_
  (* only in CompositeLit (could be rewritten as TArray with static length) *)
 | TArrayEllipsis of tok (* ... *) * type_ 

 | TFunc of func_type
 | TMap of type_ * type_
 | TChan of chan_dir * type_

 | TStruct    of struct_field list
 | TInterface of interface_field list

  and chan_dir = TSend | TRecv | TBidirectional
  and func_type =  { 
    fparams: parameter list; 
    fresults: parameter list;
  }
    and parameter = {
      pname: ident option;
      ptype: type_;
      (* only at last element position *)
      pdots: tok option;
    }

  and struct_field = struct_field_kind * tag option
    and struct_field_kind = 
    | Field of ident * type_ (* could factorize with entity *)
    | EmbeddedField of tok option (* * *) * qualified_ident
   and tag = string wrap
    
  and interface_field = 
    | Method of ident * func_type
    | EmbeddedInterface of qualified_ident

and expr_or_type = (expr, type_) Common.either

(*****************************************************************************)
(* Expression *)
(*****************************************************************************)
and expr = 
 | BasicLit of literal
 (* less: the type of TarrayEllipsis ( [...]{...}) in a CompositeLit
  *  could be transformed in TArray (length {...}) *)
 | CompositeLit of type_ * init list

  (* This Id can actually denotes sometimes a type (e.g., in Arg), or 
   * a package (e.g., in Selector). 
   * To disambiguate requires semantic information.
   * Selector (Name,'.', ident) can be many things.
   *)
 | Id of ident 

 (* A Selector can be a 
  *  - a field access of a struct
  *  - a top decl access of a package
  *  - a method access when expr denotes actually a type 
  *  - a method value
  * We need more semantic information on expr to know what it is.
  *)
 | Selector of expr * tok * ident

 (* valid for TArray, TMap, Tptr, TName ("string") *)
 | Index of expr * index
  (* low, high, max *)
 | Slice of expr * (expr option * expr option * expr option) 

 | Call of call_expr
 (* note that some Call are really Cast, e.g., uint(1), but we need
  * semantic information to know that
  *)
 | Cast of type_ * expr

 (* special cases of Unary *)
 | Deref of tok (* * *) * expr
 (* less: some &T{...} should be transformed in call to new? *)
 | Ref   of tok (* & *) * expr
 | Receive of tok * expr (* denote a channel *)

 | Unary of         Ast_generic.arithmetic_operator (* +/-/~/! *) wrap * expr
 | Binary of expr * Ast_generic.arithmetic_operator wrap * expr

 (* x.(<type>) *)
 | TypeAssert of expr * type_
 (* x.(type)
  * less: can appear only in a TypeSwitch, so could be moved there *)
 | TypeSwitchExpr of expr * tok (* 'type' *)

 (* ?? sgrep *)
 | EllipsisTODO of tok

 | FuncLit of func_type * stmt

 (* only used as an intermediate during parsing, should be converted *)
 | ParenType of type_

 (* TODO: move in stmt, but need better comm_clause *)
 (* Send as opposed to Receive is a statement, not an expr *)
 | Send of expr (* denote a channel *) * tok (* <- *) * expr

  (* old: was just a string in ast.go *)
  and literal = 
  (* less: Bool of bool wrap | Nil of tok? *)
  | Int of string wrap
  | Float of string wrap
  | Imag of string wrap
  | Rune of string wrap
  | String of string wrap

  and index = expr
  and arguments = argument list
  and argument = 
    (* less: could also use Arg of expr_or_type *)
    | Arg of expr
    (* for new, make, ?? *)
    | ArgType of type_

    | ArgDots of tok (* should be the last argument *)

 (* could be merged with expr *)
 and init = 
  | InitExpr of expr (* can be Id, which have special meaning for Key *)
  | InitKeyValue of init * tok (* : *) * init
  | InitBraces of init list

and constant_expr = expr

(*****************************************************************************)
(* Statement *)
(*****************************************************************************)
and stmt = 
 | DeclStmts of decl list (* inside a Block *)

 | Block of stmt list
 (* less: could be rewritten as Block [] *)
 | Empty

 | ExprStmt of expr

 (* good boy! not an expression but a statement! better! *) 
 (* note: lhs and rhs do not always have the same length as in
  *  a,b = foo()
  *)
 | Assign of expr list (* lhs, pattern *) * tok * expr list (* rhs *)
 (* declare or reassign, and special semantic when Receive operation *)
 | DShortVars of expr list * tok (* := *) * expr list
 | AssignOp of expr * Ast_generic.arithmetic_operator wrap * expr
 | IncDec of expr * Ast_generic.incr_decr wrap * Ast_generic.prefix_postfix

 | If     of stmt option (* init *) * expr * stmt * stmt option
 (* todo: cond should be an expr, except for TypeSwitch where it can also
  * be x := expr
  *)
 | Switch of stmt option (* init *) * stmt option * case_clause list
 (* todo: expr should always be a TypeSwitchExpr *)
 (* | TypeSwitch of stmt option * expr (* Assign *) * case_clause list *)
 | Select of tok * comm_clause list

 (* note: no While or DoWhile, just For and Foreach (Range) *)
 | For of (stmt option * expr option * stmt option) * stmt
 (* todo: should impose (expr * tok * expr option) for key/value *)
 | Range of (expr list * tok (* = or := *)) option (* key/value pattern *) * 
            tok (* 'range' *) * expr * stmt 

 | Return of tok * expr list option
 (* was put together in a Branch in ast.go, but better to split *)
 | Break of tok * ident option
 | Continue of tok * ident option
 | Goto of tok * ident 
 | Fallthrough of tok

 | Label of ident * stmt

 | Go    of tok * call_expr
 | Defer of tok * call_expr

 (* todo: split in case_clause_expr and case_clause_type *)
 and case_clause = case_kind * stmt (* can be Empty*)
   and case_kind =
    | CaseExprs of expr_or_type list
    | CaseAssign of expr_or_type list * tok (* = or := *) * expr
    | CaseDefault of tok
 (* TODO: stmt (* Send or Receive *) * stmt (* can be empty *) *)
 and comm_clause = case_clause
    
 and call_expr = expr * arguments

(*****************************************************************************)
(* Declarations *)
(*****************************************************************************)

and decl = 
 (* consts can have neither a type nor an expr but the expr is usually
  * a copy of the expr of the previous const in a list of consts (e.g., iota),
  * and the grammar imposes that the first const at least has an expr.
  * less: could do this transformation during parsing.
  *)
 | DConst of ident * type_ option * constant_expr option 
 (* vars have at least a type or an expr ((None,None) is impossible) *)
 | DVar   of ident * type_ option * (* = *) expr option (* value *)

 (* type can be a TStruct to define and name a structure *)
 | DTypeAlias of ident * tok (* = *) * type_
 (* this introduces a distinct type, with different method set *)
 | DTypeDef of ident * type_
 (* with tarzan *)

(* only at the toplevel *)
type top_decl =
 | DFunc   of ident *                            func_type * stmt
 | DMethod of ident * parameter (* receiver *) * func_type * stmt
 | D of decl

 (* with tarzan *)

(*****************************************************************************)
(* Import *)
(*****************************************************************************)
type import = {
 i_path: string wrap;
 i_kind: import_kind;
}
  and import_kind =
  (* basename of i_path is usually the package name *)
  | ImportOrig
  | ImportNamed of ident
  (* inline in current file scope all the entities of the imported module *)
  | ImportDot of tok
 (* with tarzan *)

(*****************************************************************************)
(* Toplevel *)
(*****************************************************************************)

type program = {
  package: ident;
  imports: import list;
  decls: top_decl list;
}
 (* with tarzan *)

(*****************************************************************************)
(* Any *)
(*****************************************************************************)

type any = 
 | E of expr
 | S of stmt
 | T of type_
 | Decl of decl
 | I of import
 | P of program

 | Ident of ident
 | Ss of stmt list
 (* with tarzan *)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)
let stmt1 xs =
  match xs with
  | [] -> Empty
  | [st] -> st
  | xs -> Block xs
