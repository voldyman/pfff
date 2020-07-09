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
open Common

open Ast_ruby
module G = AST_generic
module PI = Parse_info
(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* Ast_ruby to AST_generic.
 *
 * See AST_generic.ml for more information.
 *
 * alternatives:
 *  - starting from il_ruby.ml, which is good to get real stmts instead
 *    of stmt_as_expr, but expr may be too far from original expr
 *  - start from an ast_ruby_stmt.ml which is half between ast_ruby.ml and
 *    il_ruby.ml
 *)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)
let id = fun x -> x
let option = Common.map_opt
let list = List.map

let bool = id
let string = id

let _error = AST_generic.error
let fake s = Parse_info.fake_info s
let fb = G.fake_bracket

(* TODO *)
let combine_tok t _tafter =
  t

(*****************************************************************************)
(* Entry point *)
(*****************************************************************************)

let info x = x
let tok v = info v

let wrap = fun _of_a (v1, v2) ->
  let v1 = _of_a v1 and v2 = info v2 in 
  (v1, v2)

let bracket of_a (t1, x, t2) = (info t1, of_a x, info t2)

let ident x = wrap string x

let rec expr = function
  | Literal x -> literal x
  | Id (id, kind) -> 
      (match kind with
      | ID_Self -> G.IdSpecial (G.Self, (snd id))
      | ID_Super -> G.IdSpecial (G.Super, (snd id))
      | _ -> G.Id (ident id, G.empty_id_info())
      )
  | ScopedId x -> scope_resolution x
  | Hash (_bool, xs) -> G.Container (G.Dict, bracket (list expr) xs)
  | Array (xs) -> G.Container (G.Array, bracket (list expr) xs)      
  | Tuple xs -> G.Tuple (list expr xs)
  | Unary (op, e) -> 
    let e = expr e in
    unary op e
  | Binop (e1, op, e2) -> 
      let e1 = expr e1 in
      let e2 = expr e2 in
      binary op e1 e2
  | Ternary (e1, _t1, e2, _t2, e3) ->
      let e1 = expr e1 in
      let e2 = expr e2 in
      let e3 = expr e3 in
      G.Conditional (e1, e2, e3)
  | Call (e, xs, bopt) ->
      let e = expr e in
      let xs = list expr xs in
      let last = option expr bopt |> Common.opt_to_list in
      G.Call (e, fb ((xs @ last) |> List.map G.expr_to_arg))
  | DotAccess (e, t, m) ->
      let e = expr e in
      let fld = 
        match method_name m with
        | Left id -> G.FId id
        | Right e -> G.FDynamic e
      in
      G.DotAccess (e, t, fld)
  | Splat (t, eopt) ->
      let xs = 
        option expr eopt |> Common.opt_to_list |> List.map G.expr_to_arg in
      let special = G.IdSpecial (G.Spread, t) in
      G.Call (special, fb xs)
  | CodeBlock ((t1,_,t2), params_opt, xs) ->
      let params = match params_opt with None -> [] | Some xs -> xs in
      let params = list formal_param params in
      let st = G.Block (t1, stmts xs, t2) in
      let def = { G.fparams = params; frettype = None; fbody = st } in
      G.Lambda def
  | S x -> 
      let st = stmt x in
      G.OtherExpr (G.OE_StmtExpr, [G.S st])
  | D x -> 
      let st = definition x in
      G.OtherExpr (G.OE_StmtExpr, [G.S st])

and formal_param = function
  | Formal_id id -> 
      G.ParamClassic (G.param_of_id id)
  | Formal_amp (t, id) ->
      let param = G.ParamClassic (G.param_of_id id) in
      G.OtherParam (G.OPO_Ref, [G.Tk t; G.Pa param])
  | Formal_star (t, id) ->
      let attr = G.KeywordAttr (G.Variadic, t) in
      let p = { (G.param_of_id id) with G.pattrs = [attr] } in
      G.ParamClassic p
  | Formal_rest (t) ->
      let attr = G.KeywordAttr (G.Variadic, t) in
      let p = { G.pattrs = [attr]; pinfo = G.empty_id_info ();
                ptype = None; pname = None; pdefault = None } in
      G.ParamClassic p
  | Formal_hash_splat (t, idopt) ->
      let attr = G.KeywordAttr (G.Variadic, t) in
      let p = 
        match idopt with
        | None ->
            { G.pattrs = [attr]; pinfo = G.empty_id_info ();
              ptype = None; pname = None; pdefault = None }
        | Some id -> { (G.param_of_id id) with G.pattrs = [attr] }
       in
       G.ParamClassic p
  | Formal_default (id, _t, e) ->
      let e = expr e in
      let p = { (G.param_of_id id) with G.pdefault = Some e } in
      G.ParamClassic p
  (* TODO? diff with Formal_default? *)
  | Formal_kwd (id, _t, eopt) ->
      let eopt = option expr eopt in
      let p = 
        match eopt with
        | None -> (G.param_of_id id)
        | Some e -> { (G.param_of_id id) with G.pdefault = Some e }
      in
      G.ParamClassic p
  | Formal_tuple (_t1, _xs, _t2) ->
      raise Todo

and scope_resolution = function
  | TopScope (t, v) -> 
      let id = variable v in
      let qualif = G.QTop t in
      let name = id, { G.name_qualifier = Some qualif; name_typeargs = None }in
      G.IdQualified (name, G.empty_id_info())
  | Scope (e, t, v_or_m) -> 
      let id = variable_or_method_name v_or_m in
      let e = expr e in
      let qualif = G.QExpr (e, t) in
      let name = id, { G.name_qualifier = Some qualif; name_typeargs = None }in
      G.IdQualified (name, G.empty_id_info())


and variable (id, _kind) = 
  ident id

and variable_or_method_name = function
  | SV v -> variable v
  | SM m -> 
      (match method_name m with
      | Left id -> id
      | Right _ -> failwith "TODO: variable_or_method_name"
      )

and method_name = function
  | MethodId v -> Left (variable v)
  | MethodIdAssign (id, teq, id_kind) ->
      let (s, t) = variable (id, id_kind) in
      Left (s^"=", combine_tok t teq)
  | MethodUOperator (_, t) | MethodOperator (_, t) -> 
      Left (PI.str_of_info t, t)
  | MethodDynamic e -> Right (expr e)
  | MethodAtom _x -> raise Todo

and binary_msg = function
  | Op_PLUS ->   G.Plus
  | Op_MINUS ->  G.Minus
  | Op_TIMES ->  G.Mult
  | Op_REM ->    G.Mod
  | Op_DIV ->    G.Div
  | Op_LSHIFT -> G.LSL
  | Op_RSHIFT -> G.LSR
  | Op_BAND ->   G.BitAnd
  | Op_BOR ->    G.BitOr
  | Op_XOR ->    G.BitXor
  | Op_POW ->    G.Pow
  | Op_CMP ->    G.Cmp
  | Op_EQ ->     G.Eq
  | Op_EQQ ->    G.PhysEq (* abuse PhysEq here, maybe not semantic*)
  | Op_NEQ ->    G.NotEq
  | Op_GEQ ->    G.GtE
  | Op_LEQ ->    G.LtE
  | Op_LT ->     G.Lt
  | Op_GT ->     G.Gt
  | Op_MATCH ->  G.RegexpMatch
  | Op_NMATCH -> G.NotMatch
  | Op_DOT2 -> G.Range
  (* never in Binop, only in DotAccess or MethodDef *)
  | Op_AREF | Op_ASET -> raise Impossible

and binary (op, t) e1 e2 =
  match op with
  | B msg ->
      let op = binary_msg msg in 
     G.Call (G.IdSpecial (G.Op op, t), fb [G.Arg e1; G.Arg e2])
  | Op_kAND | Op_AND -> 
     G.Call (G.IdSpecial (G.Op G.And, t), fb [G.Arg e1; G.Arg e2])
  | Op_kOR | Op_OR -> 
     G.Call (G.IdSpecial (G.Op G.Or, t), fb [G.Arg e1; G.Arg e2])
  | Op_ASSIGN ->
     G.Assign (e1, t, e2)
  | Op_OP_ASGN op ->
      let op = 
        match op with
        | B msg -> binary_msg msg
        | Op_AND -> G.And
        | Op_OR -> G.Or
        (* see lexer_ruby.mll code for T_OP_ASGN *)
        | _ -> raise Impossible
      in
     G.AssignOp (e1, (op, t), e2)
   | Op_ASSOC -> 
      G.Tuple ([e1;e2])
   | Op_DOT3 ->
     (* coupling: make sure to check for the string in generic_vs_generic *)
     G.Call (G.IdSpecial (G.Op G.Range, t), fb [G.Arg e1; G.Arg e2])
      


and unary (op,t) e = 
  match op with
  | U msg -> 
      let op = 
        match msg with
        | Op_UMinus -> G.Minus
        | Op_UPlus -> G.Plus
        | Op_UBang -> G.Not
        | Op_UTilde -> G.BitNot
      in
      G.Call (G.IdSpecial (G.Op op, t), fb [G.Arg e])
   | Op_UNot -> G.Call (G.IdSpecial (G.Op G.Not, t), fb [G.Arg e])
   | Op_DefinedQuestion -> G.Call (G.IdSpecial (G.Defined, t), fb [G.Arg e])
   | Op_UStarStar -> G.Call (G.IdSpecial (G.HashSplat, t), fb [G.Arg e])
   (* should be only in arguments, to pass procs. I abuse Ref for now *)
   | Op_UAmper -> G.Ref (t, e)


and literal = function
  | Bool x -> G.L (G.Bool (wrap bool x))
  | Num x -> G.L (G.Int (wrap string x))
  | Float x -> G.L (G.Float (wrap string x))
  | Complex x -> G.L (G.Imag (wrap string x))
  | Rational (x, _tTODOadd_info_in_x) -> G.L (G.Ratio (wrap string x))
  | Char x -> G.L (G.Char (wrap string x))
  | Nil t -> G.L (G.Null (tok t))
  | String _
  | Regexp _
  | Atom _
     -> raise Todo

and expr_as_stmt = function
  | S x -> stmt x
  | D x -> definition x
  | e -> 
      let e = expr e in
      G.ExprStmt (e, fake ";")

and stmt = function
  | _ -> raise Todo

and definition = function
  | _ -> raise Todo

and stmts xs = 
  list expr_as_stmt xs


let  program xs = 
  stmts xs


let any = function
  | E x -> 
      (match x with
      | S x -> G.S (stmt x)
      | D x -> G.S (definition x)
      | _ -> G.E (expr x)
      )
  | Pr xs -> G.Ss (stmts xs)
