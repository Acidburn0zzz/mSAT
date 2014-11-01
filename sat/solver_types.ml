(**************************************************************************)
(*                                                                        *)
(*                                  Cubicle                               *)
(*             Combining model checking algorithms and SMT solvers        *)
(*                                                                        *)
(*                  Sylvain Conchon and Alain Mebsout                     *)
(*                  Universite Paris-Sud 11                               *)
(*                                                                        *)
(*  Copyright 2011. This file is distributed under the terms of the       *)
(*  Apache Software License version 2.0                                   *)
(*                                                                        *)
(**************************************************************************)

open Printf

let ale = Hstring.make "<="
let alt = Hstring.make "<"
let agt = Hstring.make ">"

let is_le n = Hstring.compare n ale = 0
let is_lt n = Hstring.compare n alt = 0
let is_gt n = Hstring.compare n agt = 0

module type S = Solver_types_intf.S

module Make (F : Formula_intf.S) = struct

  type formula = F.t

  type var =
    {  vid : int;
       pa : atom;
       na : atom;
       mutable weight : float;
       mutable seen : bool;
       mutable level : int;
       mutable reason: reason;
       mutable vpremise : premise}

  and atom =
    { var : var;
      lit : formula;
      neg : atom;
      mutable watched : clause Vec.t;
      mutable is_true : bool;
      aid : int }

  and clause =
    { name : string;
      mutable atoms : atom Vec.t ;
      mutable activity : float;
      mutable removed : bool;
      learnt : bool;
      cpremise : premise }

  and reason = clause option

  and premise = clause list

  let dummy_lit = F.dummy

  let rec dummy_var =
    { vid = -101;
      pa = dummy_atom;
      na = dummy_atom;
      level = -1;
      reason = None;
      weight = -1.;
      seen = false;
      vpremise = [] }
  and dummy_atom =
    { var = dummy_var;
      lit = dummy_lit;
      watched = {Vec.dummy=dummy_clause; data=[||]; sz=0};
      neg = dummy_atom;
      is_true = false;
      aid = -102 }
  and dummy_clause =
    { name = "";
      atoms = {Vec.dummy=dummy_atom; data=[||]; sz=0};
      activity = -1.;
      removed = false;
      learnt = false;
      cpremise = [] }

  module MA = Map.Make(F)
  type varmap = var MA.t

  let ale = Hstring.make "<="
  let alt = Hstring.make "<"
  let agt = Hstring.make ">"
  let is_le n = Hstring.compare n ale = 0
  let is_lt n = Hstring.compare n alt = 0
  let is_gt n = Hstring.compare n agt = 0

  let normal_form = F.norm

  let cpt_mk_var = ref 0
  let ma = ref MA.empty
  let make_var =
    fun lit ->
      let lit, negated = normal_form lit in
      try MA.find lit !ma, negated
      with Not_found ->
        let cpt_fois_2 = !cpt_mk_var lsl 1 in
        let rec var  =
          { vid = !cpt_mk_var;
            pa = pa;
            na = na;
            level = -1;
            reason = None;
            weight = 0.;
            seen = false;
            vpremise = [];
          }
        and pa =
          { var = var;
            lit = lit;
            watched = Vec.make 10 dummy_clause;
            neg = na;
            is_true = false;
            aid = cpt_fois_2 (* aid = vid*2 *) }
        and na =
          { var = var;
            lit = F.neg lit;
            watched = Vec.make 10 dummy_clause;
            neg = pa;
            is_true = false;
            aid = cpt_fois_2 + 1 (* aid = vid*2+1 *) } in
        ma := MA.add lit var !ma;
        incr cpt_mk_var;
        var, negated

  let made_vars_info () = !cpt_mk_var, MA.fold (fun lit var acc -> var::acc)!ma []

  let add_atom lit =
    let var, negated = make_var lit in
    if negated then var.na else var.pa

  let make_clause name ali sz_ali is_learnt premise =
    let atoms = Vec.from_list ali sz_ali dummy_atom in
    { name  = name;
      atoms = atoms;
      removed = false;
      learnt = is_learnt;
      activity = 0.;
      cpremise = premise}

  let fresh_lname =
    let cpt = ref 0 in
    fun () -> incr cpt; "L" ^ (string_of_int !cpt)

  let fresh_dname =
    let cpt = ref 0 in
    fun () -> incr cpt; "D" ^ (string_of_int !cpt)

  let fresh_name =
    let cpt = ref 0 in
    fun () -> incr cpt; "C" ^ (string_of_int !cpt)

  let to_float i = float_of_int i

  let to_int f = int_of_float f

  let clear () =
    cpt_mk_var := 0;
    ma := MA.empty

  let sign a = if a==a.var.pa then "" else "-"

  let level a =
    match a.var.level, a.var.reason with
    | n, _ when n < 0 -> assert false
    | 0, Some c -> sprintf "->0/%s" c.name
    | 0, None   -> "@0"
    | n, Some c -> sprintf "->%d/%s" n c.name
    | n, None   -> sprintf "@@%d" n

  let value a =
    if a.is_true then sprintf "[T%s]" (level a)
    else if a.neg.is_true then sprintf "[F%s]" (level a)
    else ""

  let value_ms_like a =
    if a.is_true then sprintf ":1%s" (level a)
    else if a.neg.is_true then sprintf ":0%s" (level a)
    else ":X"

  let pp_premise b v =
    List.iter (fun {name=name} -> bprintf b "%s," name) v

  let pp_atom b a =
    bprintf b "%s%d%s [lit:%s] vpremise={{%a}}"
      (sign a) (a.var.vid+1) (value a) (Log.on_fmt F.print a.lit)
      pp_premise a.var.vpremise

  let pp_atoms_list b l = List.iter (bprintf b "%a ; " pp_atom) l
  let pp_atoms_array b arr = Array.iter (bprintf b "%a ; " pp_atom) arr

  let pp_atoms_vec b vec =
    for i = 0 to Vec.size vec - 1 do
      bprintf b "%a ; " pp_atom (Vec.get vec i)
    done

  let pp_clause b {name=name; atoms=arr; cpremise=cp} =
    bprintf b "%s:{ %a} cpremise={{%a}}" name pp_atoms_vec arr pp_premise cp

end
