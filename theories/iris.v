(** Iris bindings **)

(* (C) J. Pichon, M. Bodin - see LICENSE.txt *)

From mathcomp Require Import ssreflect ssrbool eqtype seq.

(* There is a conflict between ssrnat and Iris language. *)
(* Also a conflict between ssrnat and stdpp on the notation .* *)

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

From stdpp Require Import gmap strings.
From iris.algebra Require Import auth.
From iris.bi.lib Require Import fractional.
From iris.proofmode Require Import tactics.
From iris.base_logic.lib Require Import gen_heap proph_map gen_inv_heap.
From iris.program_logic Require Import weakestpre total_weakestpre.
From iris.program_logic Require Export language lifting.

Require Export common operations_iris datatypes_iris datatypes_properties_iris properties_iris.
Require Import iris_locations.

Definition iris_expr := host_expr.
Definition iris_val := host_value.
(* Use gmap to specify the host variable store instead. *)
Definition host_state := gmap id iris_val.
Definition state : Type := host_state * store_record * list host_value.
Definition observation := unit. (* TODO: ??? *)

Definition of_val (v : iris_val) : iris_expr := HE_value v.

Definition to_val (e : iris_expr) : option iris_val :=
  match e with
  | HE_value v => Some v
  | _ => None
  end.
  
(* https://softwarefoundations.cis.upenn.edu/qc-current/Typeclasses.html *)
Global Instance val_eq_dec : EqDecision iris_val.
Proof.
  decidable_equality.
Defined.

Lemma of_to_val e v : to_val e = Some v → of_val v = e.
Proof.
  destruct e => //=.
  move => H. by inversion H.
Qed.

Definition wasm_zero := HV_wasm_value (VAL_int32 (Wasm_int.int_zero i32m)).

Inductive reduce_simple : list administrative_instruction -> list administrative_instruction -> Prop :=

(** unop **)
  | rs_unop : forall v op t,
    reduce_simple [::AI_basic (BI_const v); AI_basic (BI_unop t op)] [::AI_basic (BI_const (@app_unop op v))]
                   
(** binop **)
  | rs_binop_success : forall v1 v2 v op t,
    app_binop op v1 v2 = Some v ->
    reduce_simple [::AI_basic (BI_const v1); AI_basic (BI_const v2); AI_basic (BI_binop t op)] [::AI_basic (BI_const v)]
  | rs_binop_failure : forall v1 v2 op t,
    app_binop op v1 v2 = None ->
    reduce_simple [::AI_basic (BI_const v1); AI_basic (BI_const v2); AI_basic (BI_binop t op)] [::AI_trap]
                  
  (** testops **)
  | rs_testop_i32 :
    forall c testop,
    reduce_simple [::AI_basic (BI_const (VAL_int32 c)); AI_basic (BI_testop T_i32 testop)] [::AI_basic (BI_const (VAL_int32 (wasm_bool (@app_testop_i i32t testop c))))]
  | rs_testop_i64 :
    forall c testop,
    reduce_simple [::AI_basic (BI_const (VAL_int64 c)); AI_basic (BI_testop T_i64 testop)] [::AI_basic (BI_const (VAL_int32 (wasm_bool (@app_testop_i i64t testop c))))]

  (** relops **)
  | rs_relop: forall v1 v2 t op,
    reduce_simple [::AI_basic (BI_const v1); AI_basic (BI_const v2); AI_basic (BI_relop t op)] [::AI_basic (BI_const (VAL_int32 (wasm_bool (app_relop op v1 v2))))]
                    
  (** convert and reinterpret **)
  | rs_convert_success :
    forall t1 t2 v v' sx,
    types_agree t1 v ->
    cvt t2 sx v = Some v' ->
    reduce_simple [::AI_basic (BI_const v); AI_basic (BI_cvtop t2 CVO_convert t1 sx)] [::AI_basic (BI_const v')]
  | rs_convert_failure :
    forall t1 t2 v sx,
    types_agree t1 v ->
    cvt t2 sx v = None ->
    reduce_simple [::AI_basic (BI_const v); AI_basic (BI_cvtop t2 CVO_convert t1 sx)] [::AI_trap]
  | rs_reinterpret :
    forall t1 t2 v,
    types_agree t1 v ->
    reduce_simple [::AI_basic (BI_const v); AI_basic (BI_cvtop t2 CVO_reinterpret t1 None)] [::AI_basic (BI_const (wasm_deserialise (bits v) t2))]

  (** control-flow operations **)
  | rs_unreachable :
    reduce_simple [::AI_basic BI_unreachable] [::AI_trap]
  | rs_nop :
    reduce_simple [::AI_basic BI_nop] [::]
  | rs_drop :
    forall v,
    reduce_simple [::AI_basic (BI_const v); AI_basic BI_drop] [::]
  | rs_select_false :
    forall n v1 v2,
    n = Wasm_int.int_zero i32m ->
    reduce_simple [::AI_basic (BI_const v1); AI_basic (BI_const v2); AI_basic (BI_const (VAL_int32 n)); AI_basic BI_select] [::AI_basic (BI_const v2)]
  | rs_select_true :
    forall n v1 v2,
    n <> Wasm_int.int_zero i32m ->
    reduce_simple [::AI_basic (BI_const v1); AI_basic (BI_const v2); AI_basic (BI_const (VAL_int32 n)); AI_basic BI_select] [::AI_basic (BI_const v1)]
  | rs_block :
      forall vs es n m t1s t2s,
        const_list vs ->
        length vs = n ->
        length t1s = n ->
        length t2s = m ->
        reduce_simple (vs ++ [::AI_basic (BI_block (Tf t1s t2s) es)]) [::AI_label m [::] (vs ++ to_e_list es)]
  | rs_loop :
      forall vs es n m t1s t2s,
        const_list vs ->
        length vs = n ->
        length t1s = n ->
        length t2s = m ->
        reduce_simple (vs ++ [::AI_basic (BI_loop (Tf t1s t2s) es)]) [::AI_label n [::AI_basic (BI_loop (Tf t1s t2s) es)] (vs ++ to_e_list es)]
  | rs_if_false :
      forall n tf e1s e2s,
        n = Wasm_int.int_zero i32m ->
        reduce_simple ([::AI_basic (BI_const (VAL_int32 n)); AI_basic (BI_if tf e1s e2s)]) [::AI_basic (BI_block tf e2s)]
  | rs_if_true :
      forall n tf e1s e2s,
        n <> Wasm_int.int_zero i32m ->
        reduce_simple ([::AI_basic (BI_const (VAL_int32 n)); AI_basic (BI_if tf e1s e2s)]) [::AI_basic (BI_block tf e1s)]
  | rs_label_const :
      forall n es vs,
        const_list vs ->
        reduce_simple [::AI_label n es vs] vs
  | rs_label_trap :
      forall n es,
        reduce_simple [::AI_label n es [::AI_trap]] [::AI_trap]
  | rs_br :
      forall n vs es i LI lh,
        const_list vs ->
        length vs = n ->
        lfilled i lh (vs ++ [::AI_basic (BI_br i)]) LI ->
        reduce_simple [::AI_label n es LI] (vs ++ es)
  | rs_br_if_false :
      forall n i,
        n = Wasm_int.int_zero i32m ->
        reduce_simple [::AI_basic (BI_const (VAL_int32 n)); AI_basic (BI_br_if i)] [::]
  | rs_br_if_true :
      forall n i,
        n <> Wasm_int.int_zero i32m ->
        reduce_simple [::AI_basic (BI_const (VAL_int32 n)); AI_basic (BI_br_if i)] [::AI_basic (BI_br i)]
  | rs_br_table : (* ??? *)
      forall iss c i j,
        length iss > Wasm_int.nat_of_uint i32m c ->
        List.nth_error iss (Wasm_int.nat_of_uint i32m c) = Some j ->
        reduce_simple [::AI_basic (BI_const (VAL_int32 c)); AI_basic (BI_br_table iss i)] [::AI_basic (BI_br j)]
  | rs_br_table_length :
      forall iss c i,
        length iss <= (Wasm_int.nat_of_uint i32m c) ->
        reduce_simple [::AI_basic (BI_const (VAL_int32 c)); AI_basic (BI_br_table iss i)] [::AI_basic (BI_br i)]
  | rs_local_const :
      forall es n f,
        const_list es ->
        length es = n ->
        reduce_simple [::AI_local n f es] es
  | rs_local_trap :
      forall n f,
        reduce_simple [::AI_local n f [::AI_trap]] [::AI_trap]
  | rs_return : (* ??? *)
      forall n i vs es lh f,
        const_list vs ->
        length vs = n ->
        lfilled i lh (vs ++ [::AI_basic BI_return]) es ->
        reduce_simple [::AI_local n f es] vs
  | rs_tee_local :
      forall i v,
        is_const v ->
        reduce_simple [::v; AI_basic (BI_tee_local i)] [::v; v; AI_basic (BI_set_local i)]
  | rs_trap :
      forall es lh,
        es <> [::AI_trap] ->
        lfilled 0 lh [::AI_trap] es ->
        reduce_simple es [::AI_trap]
.
(*
  | rs_binop_success : forall v1 v2 v op t,
    app_binop op v1 v2 = Some v ->
    reduce_simple [::AI_basic (BI_const v1); AI_basic (BI_const v2); AI_basic (BI_binop t op)] [::AI_basic (BI_const v)]
  | rs_binop_failure : forall v1 v2 op t,
    app_binop op v1 v2 = None ->
    reduce_simple [::AI_basic (BI_const v1); AI_basic (BI_const v2); AI_basic (BI_binop t op)] [::AI_trap]
 *)
Inductive pure_reduce : host_state -> store_record -> list host_value -> host_expr ->
                        host_state -> store_record -> list host_value -> host_expr -> Prop :=
(* TODO: basic exprs -- arith ops, list ops left *)
  | pr_binop_success:
    forall hs s locs id1 id2 v1 v2 v op,
      hs !! id1 = Some (HV_wasm_value v1) ->
      hs !! id2 = Some (HV_wasm_value v2) ->
      app_binop op v1 v2 = Some v ->
      pure_reduce hs s locs (HE_binop op id1 id2) hs s locs (HE_value (HV_wasm_value v))
  | pr_binop_trap1:
    forall hs s locs id1 id2 v1 v2 op,
      hs !! id1 = Some (HV_wasm_value v1) ->
      hs !! id2 = Some (HV_wasm_value v2) ->
      app_binop op v1 v2 = None ->
      pure_reduce hs s locs (HE_binop op id1 id2) hs s locs (HE_value HV_trap)
  | pr_binop_trap2:
    forall hs s locs id1 id2 op,
      hs !! id1 = None ->
      pure_reduce hs s locs (HE_binop op id1 id2) hs s locs (HE_value HV_trap)
  | pr_binop_trap3:
    forall hs s locs id1 id2 op,
      hs !! id2 = None ->
      pure_reduce hs s locs (HE_binop op id1 id2) hs s locs (HE_value HV_trap)
  | pr_binop_trap4:
    forall hs s locs id1 id2 v1 op,
      hs !! id1 = Some v1 ->
      host_value_to_wasm v1 = None ->
      pure_reduce hs s locs (HE_binop op id1 id2) hs s locs (HE_value HV_trap)
  | pr_binop_trap5:
    forall hs s locs id1 id2 v2 op,
      hs !! id2 = Some v2 ->
      host_value_to_wasm v2 = None ->
      pure_reduce hs s locs (HE_binop op id1 id2) hs s locs (HE_value HV_trap)
  | pr_list_concat:
    forall hs s locs id1 id2 l1 l2,
      hs !! id1 = Some (HV_list l1) ->
      hs !! id2 = Some (HV_list l2) ->
      pure_reduce hs s locs (HE_list_concat id1 id2) hs s locs (HE_value (HV_list (l1 ++ l2)))
  | pr_list_concat_trap1:
    forall hs s locs id1 id2,
      hs !! id1 = None ->
      pure_reduce hs s locs (HE_list_concat id1 id2) hs s locs (HE_value HV_trap)
  | pr_list_concat_trap2:
    forall hs s locs id1 id2,
      hs !! id2 = None ->
      pure_reduce hs s locs (HE_list_concat id1 id2) hs s locs (HE_value HV_trap)
  | pr_list_concat_trap3:
    forall hs s locs id1 id2 v1,
      hs !! id1 = Some v1 ->
      host_typeof v1 <> Some HT_list ->
      pure_reduce hs s locs (HE_list_concat id1 id2) hs s locs (HE_value HV_trap)
  | pr_list_concat_trap4:
    forall hs s locs id1 id2 v2,
      hs !! id2 = Some v2 ->
      host_typeof v2 <> Some HT_list ->
      pure_reduce hs s locs (HE_list_concat id1 id2) hs s locs (HE_value HV_trap)
  | pr_getglobal:
    forall hs s locs id hv ,
      hs !! id = Some hv ->
      pure_reduce hs s locs (HE_getglobal id) hs s locs (HE_value hv)
  | pr_getglobal_trap:
    forall hs s locs id,
      hs !! id = None ->
      pure_reduce hs s locs (HE_getglobal id) hs s locs (HE_value HV_trap)
  | pr_setglobal_value:
    forall hs s locs id hv hs',
      hv <> HV_trap ->
      hs' = <[id := hv]> hs ->
      pure_reduce hs s locs (HE_setglobal id (HE_value hv)) hs' s locs (HE_value hv)
  | pr_setglobal_trap:
    forall hs s locs id,
      pure_reduce hs s locs (HE_setglobal id (HE_value HV_trap)) hs s locs (HE_value HV_trap)
  | pr_setglobal_step:
    forall hs s locs e hs' s' locs' e' id,
      pure_reduce hs s locs e hs' s' locs' e' ->
      pure_reduce hs s locs (HE_setglobal id e) hs' s' locs' (HE_setglobal id e')
  | pr_getlocal:
    forall hs s locs n hv,
      locs !! (nat_of_N n) = Some hv ->
      pure_reduce hs s locs (HE_getlocal n) hs s locs (HE_value hv)
  | pr_getlocal_trap:
    forall hs s locs n,
      locs !! (nat_of_N n) = None ->
      pure_reduce hs s locs (HE_getlocal n) hs s locs (HE_value HV_trap)
  | pr_setlocal:
    forall hs s locs n id locs' hv,
      hs !! id = Some hv ->
      (nat_of_N n) < length locs ->
      locs' = list_insert (N.to_nat n) hv locs ->
      pure_reduce hs s locs (HE_setlocal n id) hs s locs' (HE_value hv)
  | pr_setlocal_trap1:
    forall hs s locs n id,
      hs !! id = None ->
      pure_reduce hs s locs (HE_setlocal n id) hs s locs (HE_value HV_trap)
  | pr_setlocal_trap2:
    forall hs s locs n id hv,
      hs !! id = Some hv ->
      (nat_of_N n) >= length locs ->
      pure_reduce hs s locs (HE_setlocal n id) hs s locs (HE_value HV_trap)
  | pr_if_true:
    forall hs s locs id e1 e2 hv,
      hs !! id = Some hv ->
      hv <> HV_wasm_value (VAL_int32 (Wasm_int.int_zero i32m)) ->
      hv ≠ HV_trap ->
      pure_reduce hs s locs (HE_if id e1 e2) hs s locs e1
  | pr_if_false: 
    forall hs s locs id e1 e2 hv,
      hs !! id = Some hv ->
      hv = HV_wasm_value (VAL_int32 (Wasm_int.int_zero i32m)) ->
      pure_reduce hs s locs (HE_if id e1 e2) hs s locs e2
  | pr_if_trap: 
    forall hs s locs id e1 e2 hv,
      hs !! id = Some hv ->
      hv = HV_trap ->
      pure_reduce hs s locs (HE_if id e1 e2) hs s locs (HE_value HV_trap)
  | pr_if_none: 
    forall hs s locs id e1 e2,
      hs !! id = None ->
      pure_reduce hs s locs (HE_if id e1 e2) hs s locs (HE_value HV_trap)
  | pr_while:
    forall hs s locs id e,
      pure_reduce hs s locs (HE_while id e) hs s locs (HE_if id (HE_seq e (HE_while id e)) (HE_value (HV_wasm_value (VAL_int32 (Wasm_int.int_zero i32m)))))
  (* record exprs *)
  | pr_new_rec:
    forall hs s locs kip hvs kvp,
      list_extra.those (fmap (fun id => hs !! id) kip.*2) = Some hvs ->
      zip kip.*1 hvs = kvp ->
      pure_reduce hs s locs (HE_new_rec kip) hs s locs (HE_value (HV_record kvp))
  | pr_new_rec_trap:
    forall hs s locs kip,
      list_extra.those (fmap (fun id => hs !! id) kip.*2) = None ->
      pure_reduce hs s locs (HE_new_rec kip) hs s locs (HE_value HV_trap)
  | pr_getfield:
    forall hs s locs id fname kvp hv,
      hs !! id = Some (HV_record kvp) ->
      lookup_kvp kvp fname = Some hv -> 
      pure_reduce hs s locs (HE_get_field id fname) hs s locs (HE_value hv)
  | pr_getfield_trap1:
    forall hs s locs id fname kvp,
      hs !! id = Some (HV_record kvp) ->
      lookup_kvp kvp fname = None ->
      pure_reduce hs s locs (HE_get_field id fname) hs s locs (HE_value HV_trap)
  | pr_getfield_trap2:
    forall hs s locs id fname hv,
      hs !! id = Some hv ->
      host_typeof hv <> Some HT_record ->
      pure_reduce hs s locs (HE_get_field id fname) hs s locs (HE_value HV_trap)
  | pr_getfield_trap3:
    forall hs s locs id fname,
      hs !! id = None ->
      pure_reduce hs s locs (HE_get_field id fname) hs s locs (HE_value HV_trap)
  (* function exprs *)
  | pr_new_host_func:
    forall hs s locs htf locsn e s' n,
      s' = {|s_funcs := s.(s_funcs) ++ [::datatypes_iris.FC_func_host htf locsn e]; s_tables := s.(s_tables); s_mems := s.(s_mems); s_globals := s.(s_globals) |} ->
      n = length s.(s_funcs) ->
      pure_reduce hs s locs (HE_new_host_func htf (N_of_nat locsn) e) hs s' locs (HE_value (HV_wov (WOV_funcref (Mk_funcidx n))))
  | pr_call_wasm:
    forall hs s ids cl id i j vts bes tf vs tn tm vars locs,
      hs !! id = Some (HV_wov (WOV_funcref (Mk_funcidx i))) ->
      s.(s_funcs) !! i = Some cl ->
      cl = FC_func_native j tf vts bes ->
      tf = Tf tn tm ->
      list_extra.those (fmap (fun id => hs !! id) ids) = Some vars ->
      list_extra.those (fmap host_value_to_wasm vars) = Some vs ->
      tn = fmap typeof vs ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_wasm_frame ((v_to_e_list vs) ++ [::AI_invoke i]))
  | pr_call_trap1:
    forall hs s locs id ids,
      hs !! id = None ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_value HV_trap)
  | pr_call_trap2:
    forall hs s locs id ids v,
      hs !! id = Some v ->
      is_funcref v = false ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_value HV_trap)
  | pr_call_trap3:
    forall hs s locs id ids i,
      hs !! id = Some (HV_wov (WOV_funcref (Mk_funcidx i))) ->
      s.(s_funcs) !! i = None ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_value HV_trap)  
  | pr_call_trap4:
    forall hs s locs id ids,
      list_extra.those (fmap (fun id => hs !! id) ids) = None ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_value HV_trap)
  | pr_call_wasm_trap1:
    forall hs s locs id ids i cl j tf vts bes vars tn tm,
      hs !! id = Some (HV_wov (WOV_funcref (Mk_funcidx i))) ->
      s.(s_funcs) !! i = Some cl ->
      cl = FC_func_native j tf vts bes ->
      tf = Tf tn tm ->
      list_extra.those (fmap (fun id => hs !! id) ids) = Some vars ->
      list_extra.those (fmap host_value_to_wasm vars) = None ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_value HV_trap)  
  | pr_call_wasm_trap2:
    forall hs s locs id ids i cl j tf vts bes vars tn tm vs,
      hs !! id = Some (HV_wov (WOV_funcref (Mk_funcidx i))) ->
      s.(s_funcs) !! i = Some cl ->
      cl = FC_func_native j tf vts bes ->
      tf = Tf tn tm ->
      list_extra.those (fmap (fun id => hs !! id) ids) = Some vars ->
      list_extra.those (fmap host_value_to_wasm vars) = Some vs ->
      tn <> fmap typeof vs ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_value HV_trap)  
  | pr_call_host:
    forall hs s ids cl id i n e tf tn tm vars locs,
      hs !! id = Some (HV_wov (WOV_funcref (Mk_funcidx i))) ->
      s.(s_funcs) !! i = Some cl ->
      cl = FC_func_host tf n e ->
      tf = Tf tn tm ->
      list_extra.those (fmap (fun id => hs !! id) ids) = Some vars ->
      length ids = length tn ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_host_frame tm (vars ++ List.repeat wasm_zero (length tm)) e)
  | pr_call_host_trap1:
    forall hs s ids cl id i n e tf tn tm locs,
      hs !! id = Some (HV_wov (WOV_funcref (Mk_funcidx i))) ->
      s.(s_funcs) !! i = Some cl ->
      cl = FC_func_host tf n e ->
      tf = Tf tn tm ->
      length ids <> length tn ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_value HV_trap)
  (* wasm state exprs *)
  | pr_table_create:
    forall hs s locs s' tab len n,
      tab = create_table len ->
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables) ++ [::tab]; s_mems := s.(s_mems); s_globals := s.(s_globals) |} ->
      n = length s.(s_tables) ->
      pure_reduce hs s locs (HE_wasm_table_create len) hs s' locs (HE_value (HV_wov (WOV_tableref (Mk_tableidx n))))
  | pr_table_set:
    forall hs s locs idt n id v tn tab tab' s' fn,
      hs !! idt = Some (HV_wov (WOV_tableref (Mk_tableidx tn))) ->
      s.(s_tables) !! tn = Some tab ->
      hs !! id = Some v ->
      v = HV_wov (WOV_funcref (Mk_funcidx fn)) ->
      N.to_nat n < length tab.(table_data) ->
      tab' = {|table_data := <[(N.to_nat n) := (Some fn)]> tab.(table_data); table_max_opt := tab.(table_max_opt) |} ->
      s' = {|s_funcs := s.(s_funcs); s_tables := list_insert tn tab' s.(s_tables); s_mems := s.(s_mems); s_globals := s.(s_globals) |} ->
      pure_reduce hs s locs (HE_wasm_table_set idt n id) hs s' locs (HE_value v)
  | pr_table_get:
    forall hs s locs idt n tn tab fn,
      hs !! idt = Some (HV_wov (WOV_tableref (Mk_tableidx tn))) ->
      s.(s_tables) !! tn = Some tab ->
      tab.(table_data) !! (N.to_nat n) = Some (Some fn) ->
      pure_reduce hs s locs (HE_wasm_table_get idt n) hs s locs (HE_value (HV_wov (WOV_funcref (Mk_funcidx fn))))
  | pr_memory_create:
    forall hs s locs s' sz sz_lim n,
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables); s_mems := s.(s_mems) ++ [::create_memory sz sz_lim]; s_globals := s.(s_globals) |} ->
      n = length s.(s_mems) ->
      pure_reduce hs s locs (HE_wasm_memory_create sz sz_lim) hs s' locs (HE_value (HV_wov (WOV_memoryref (Mk_memidx n))))
  | pr_memory_set:
    forall hs s locs idm n id md' mn m m' s' b,
      hs !! idm = Some (HV_wov (WOV_memoryref (Mk_memidx mn))) ->
      s.(s_mems) !! mn = Some m ->
      hs !! id = Some (HV_byte b) ->
      memory_list.mem_update n b m.(mem_data) = Some md' ->
      m' = {|mem_data := md'; mem_max_opt := m.(mem_max_opt) |} ->
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables); s_mems := list_insert mn m' s.(s_mems); s_globals := s.(s_globals) |} ->
      pure_reduce hs s locs (HE_wasm_memory_set idm n id) hs s' locs (HE_value (HV_byte b))
  | pr_memory_get:
    forall hs s locs idm n b m mn,
      hs !! idm = Some (HV_wov (WOV_memoryref (Mk_memidx mn))) ->
      s.(s_mems) !! mn = Some m ->
      memory_list.mem_lookup n m.(mem_data) = Some b ->
      pure_reduce hs s locs (HE_wasm_memory_get idm n) hs s locs (HE_value (HV_byte b))
  | pr_memory_grow:
    forall hs s s' locs idm n m m' mn,
      hs !! idm = Some (HV_wov (WOV_memoryref (Mk_memidx mn))) ->
      s.(s_mems) !! mn = Some m ->
      mem_grow m n = Some m' ->
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables); s_mems := list_insert mn m' s.(s_mems); s_globals := s.(s_globals) |} ->
      pure_reduce hs s locs (HE_wasm_memory_grow idm n) hs s' locs (HE_value (HV_wasm_value (VAL_int32 (Wasm_int.int_of_Z i32m (Z.of_N (mem_size m'))))))
  (* allows memory_grow to fail nondeterministically *)
  | pr_memory_grow_fail_nondet:
    forall hs s locs idm n,
      pure_reduce hs s locs (HE_wasm_memory_grow idm n) hs s locs (HE_value (HV_trap))
  | pr_globals_create:
    forall hs s locs s' g n,
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables); s_mems := s.(s_mems); s_globals := s.(s_globals) ++ [::g] |} ->
      n = length s.(s_globals) ->
      pure_reduce hs s locs (HE_wasm_global_create g) hs s' locs (HE_value (HV_wov (WOV_globalref (Mk_globalidx n))))
  | pr_global_set:
    forall hs s locs gn idg id s' v g g',
      hs !! id = Some (HV_wasm_value v) ->
      hs !! idg = Some (HV_wov (WOV_globalref (Mk_globalidx gn))) ->
      s.(s_globals) !! gn = Some g ->
      g.(g_mut) = MUT_mut ->
      typeof v = typeof (g.(g_val)) ->
      g' = {|g_mut := MUT_mut; g_val := v|} ->
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables); s_mems := s.(s_mems); s_globals := list_insert gn g' s.(s_globals)|} ->
      pure_reduce hs s locs (HE_wasm_global_set idg id) hs s' locs (HE_value (HV_wasm_value v))
  | pr_global_get:
    forall hs s locs idg g gn v,
      hs !! idg = Some (HV_wov (WOV_globalref (Mk_globalidx gn))) ->
      s.(s_globals) !! gn = Some g ->
      g.(g_val) = v ->
      pure_reduce hs s locs (HE_wasm_global_get idg) hs s locs (HE_value (HV_wasm_value v))
  (* wasm module expr *)
   (* TODO: add this back after specifying the concrete host *)
 (* | pr_compile:
    forall hs s locs id mo hvl hbytes,
      hs !! id = Some (HV_list hvl) ->
      to_bytelist hvl = Some hbytes ->
      run_parse_module (map byte_of_compcert_byte hbytes) = Some mo -> (* Check: is this correct? *)
      pure_reduce hs s locs (HE_compile id) hs s locs (HE_value (HV_module mo))*)
  (* TODO: replace the proxy *)
  | pr_instantiate:
    forall hs s locs idm idr mo r rec,
      hs !! idm = Some (HV_module mo) ->
      hs !! idr = Some (HV_record r) ->
      pure_reduce hs s locs (HE_instantiate idm idr) hs s locs rec
  (* miscellaneous *)
  | pr_seq_const:
    forall hs s locs v e,
      pure_reduce hs s locs (HE_seq (HE_value v) e) hs s locs e
  | pr_seq:
    forall hs s locs hs' s' locs' e1 e1' e2,
      pure_reduce hs s locs e1 hs' s' locs' e1' ->
      pure_reduce hs s locs (HE_seq e1 e2) hs' s' locs' (HE_seq e1' e2)
  | pr_wasm_return:
    forall hs s locs vs,      
      pure_reduce hs s locs (HE_wasm_frame (v_to_e_list vs)) hs s locs (HE_value (HV_list (fmap (fun wv => (HV_wasm_value wv)) vs)))
  | pr_wasm_return_trap:
    forall hs s locs,
      pure_reduce hs s locs (HE_wasm_frame ([::AI_trap])) hs s locs (HE_value (HV_trap))
  | pr_wasm_frame:
    forall hs s locs we hs' s' we',
      wasm_reduce hs s empty_frame we hs' s' empty_frame we' ->
      pure_reduce hs s locs (HE_wasm_frame we) hs' s' locs (HE_wasm_frame we')
  | pr_host_return:
    forall hs s locsf locs ids e vs tn,
      list_extra.those (fmap (fun id => hs !! id) ids) = Some vs ->
      pure_reduce hs s locsf (HE_host_frame tn locs (HE_seq (HE_return ids) e)) hs s locsf (HE_value (HV_list vs))
  | pr_host_return_trap:
    forall hs s locsf locs ids e tn,
      list_extra.those (fmap (fun id => hs !! id) ids) = None ->
      pure_reduce hs s locsf (HE_host_frame tn locs (HE_seq (HE_return ids) e)) hs s locsf (HE_value HV_trap)

(* TODO: needs all the host_expr reduction steps: compile, instantiate, etc. *)
(* TODO: needs restructuring to make sense *)
with wasm_reduce : host_state -> store_record -> datatypes_iris.frame -> list administrative_instruction ->
                   host_state -> store_record -> datatypes_iris.frame -> list administrative_instruction -> Prop :=
  | wr_simple :
      forall e e' s f hs,
        reduce_simple e e' ->
        wasm_reduce hs s f e hs s f e'

  (** calling operations **)
  | wr_call :
      forall s f i a hs,
        f.(f_inst).(inst_funcs) !! i = Some a ->
        wasm_reduce hs s f [::AI_basic (BI_call i)] hs s f [::AI_invoke a]
  | wr_call_indirect_success :
      forall s f i a cl tf c hs,
        stab_addr s f (Wasm_int.nat_of_uint i32m c) = Some a ->
        s.(s_funcs) !! a = Some cl ->
        cl_type cl = tf ->
        stypes s f.(f_inst) i = Some tf ->
        wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 c)); AI_basic (BI_call_indirect i)] hs s f [::AI_invoke a]
  | wr_call_indirect_failure1 :
      forall s f i a cl tf c hs,
        stab_addr s f (Wasm_int.nat_of_uint i32m c) = Some a ->
        s.(s_funcs) !! a = Some cl ->
        cl_type cl = tf ->
        stypes s f.(f_inst) i <> Some tf ->
        wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 c)); AI_basic (BI_call_indirect i)] hs s f [::AI_trap]
  | wr_call_indirect_failure2 :
      forall s f i c hs,
        stab_addr s f (Wasm_int.nat_of_uint i32m c) = None ->
        wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 c)); AI_basic (BI_call_indirect i)] hs s f [::AI_trap]
  | wr_invoke_native :
      forall a cl t1s t2s ts es ves vcs n m k zs s f f' i hs,
        s.(s_funcs) !! a = Some cl ->
        cl = FC_func_native i (Tf t1s t2s) ts es ->
        ves = v_to_e_list vcs ->
        length vcs = n ->
        length ts = k ->
        length t1s = n ->
        length t2s = m ->
        n_zeros ts = zs ->
        f'.(f_inst) = i ->
        f'.(f_locs) = vcs ++ zs ->
        wasm_reduce hs s f (ves ++ [::AI_invoke a]) hs s f [::AI_local m f' [::AI_basic (BI_block (Tf [::] t2s) es)]]
  | wr_invoke_host :
    (* TODO: check *)
    forall a cl e tf t1s t2s ves vcs m n s s' f hs hs' vs,
      s.(s_funcs) !! a = Some cl ->
      cl = FC_func_host tf n e ->
      tf = Tf t1s t2s ->
      ves = v_to_e_list vcs ->
      length vcs = n ->
      length t1s = n ->
      length t2s = m ->
      (* TODO: check if this is what we want *)
      fmap (fun x => HV_wasm_value x) vcs = vs ->
      wasm_reduce hs s f (ves ++ [::AI_invoke a]) hs' s' f [::AI_host_frame t1s vs e]

  | wr_host_step :
    (* TODO: check *)
    forall hs s (f : datatypes_iris.frame) ts vs e hs' s' vs' e',
      pure_reduce hs s vs e hs' s' vs' e' ->
        wasm_reduce hs s f [::AI_host_frame ts vs e] hs' s' f [::AI_host_frame ts vs' e']
  | wr_host_return :
    (* TODO: check *)
    forall hs s f ts vs ids vs' vs'',
    list_extra.those (fmap (fun id => hs !! id) ids) = Some vs' ->
    Some vs'' = list_extra.those (fmap (fun x => match x with | HV_wasm_value v => Some v | _ => None end) vs') ->
    wasm_reduce hs s f [::AI_host_frame ts vs (HE_return ids)] hs s f (v_to_e_list vs'')
(*  
  | wr_host_new_host_func :
    (* TODO: check *)
    forall hs s f ts vs tf n e idx idx_h hs' s',
    idx = List.length s.(s_funcs) ->
    idx_h = List.length hs.(hs_funcs) ->
    hs' = {| hs_varmap := hs.(hs_varmap); hs_funcs := hs.(hs_funcs) ++ [::e] |} ->
    s' = {| s_funcs := s.(s_funcs) ++ [::(FC_func_host tf (Mk_funcidx idx_h))]; s_tables := s.(s_tables); s_mems := s.(s_mems); s_globals := s.(s_globals) |} ->
    wasm_reduce hs s f [::AI_host_frame ts vs (HE_new_host_func tf n e)]
      hs' s' f [::AI_host_frame ts vs (HE_value (HV_wov (WOV_funcref (Mk_funcidx idx_h))))]
*)
  (** get, set, load, and store operations **)
  | wr_get_local :
      forall f v j s hs,
        f.(f_locs) !! j = Some v ->
        wasm_reduce hs s f [::AI_basic (BI_get_local j)] hs s f [::AI_basic (BI_const v)]
  | wr_set_local :
      forall f f' i v s hs,
        f'.(f_inst) = f.(f_inst) ->
        f'.(f_locs) = list_insert i v f.(f_locs) ->
        wasm_reduce hs s f [::AI_basic (BI_const v); AI_basic (BI_set_local i)] hs s f' [::]
  | wr_get_global :
      forall s f i v hs,
        sglob_val s f.(f_inst) i = Some v ->
        wasm_reduce hs s f [::AI_basic (BI_get_global i)] hs s f [::AI_basic (BI_const v)]
  | wr_set_global :
      forall s f i v s' hs,
        supdate_glob s f.(f_inst) i v = Some s' ->
        wasm_reduce hs s f [::AI_basic (BI_const v); AI_basic (BI_set_global i)] hs s' f [::]
  | wr_load_success :
    forall s i f t bs k a off m hs,
      smem_ind s f.(f_inst) = Some i ->
      s.(s_mems) !! i = Some m ->
      load m (Wasm_int.N_of_uint i32m k) off (t_length t) = Some bs ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_load t None a off)] hs s f [::AI_basic (BI_const (wasm_deserialise bs t))]
  | wr_load_failure :
    forall s i f t k a off m hs,
      smem_ind s f.(f_inst) = Some i ->
      s.(s_mems) !! i = Some m ->
      load m (Wasm_int.N_of_uint i32m k) off (t_length t) = None ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_load t None a off)] hs s f [::AI_trap]
  | wr_load_packed_success :
    forall s i f t tp k a off m bs sx hs,
      smem_ind s f.(f_inst) = Some i ->
      s.(s_mems) !! i = Some m ->
      load_packed sx m (Wasm_int.N_of_uint i32m k) off (tp_length tp) (t_length t) = Some bs ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_load t (Some (tp, sx)) a off)] hs s f [::AI_basic (BI_const (wasm_deserialise bs t))]
  | wr_load_packed_failure :
    forall s i f t tp k a off m sx hs,
      smem_ind s f.(f_inst) = Some i ->
      s.(s_mems) !! i = Some m ->
      load_packed sx m (Wasm_int.N_of_uint i32m k) off (tp_length tp) (t_length t) = None ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_load t (Some (tp, sx)) a off)] hs s f [::AI_trap]
  | wr_store_success :
    forall t v s i f mem' k a off m hs,
      types_agree t v ->
      smem_ind s f.(f_inst) = Some i ->
      s.(s_mems) !! i = Some m ->
      store m (Wasm_int.N_of_uint i32m k) off (bits v) (t_length t) = Some mem' ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_const v); AI_basic (BI_store t None a off)] hs (upd_s_mem s (update_list_at s.(s_mems) i mem')) f [::]
  | wr_store_failure :
    forall t v s i f m k off a hs,
      types_agree t v ->
      smem_ind s f.(f_inst) = Some i ->
      s.(s_mems) !! i = Some m ->
      store m (Wasm_int.N_of_uint i32m k) off (bits v) (t_length t) = None ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_const v); AI_basic (BI_store t None a off)] hs s f [::AI_trap]
  | wr_store_packed_success :
    forall t v s i f m k off a mem' tp hs,
      types_agree t v ->
      smem_ind s f.(f_inst) = Some i ->
      s.(s_mems) !! i = Some m ->
      store_packed m (Wasm_int.N_of_uint i32m k) off (bits v) (tp_length tp) = Some mem' ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_const v); AI_basic (BI_store t (Some tp) a off)] hs (upd_s_mem s (update_list_at s.(s_mems) i mem')) f [::]
  | wr_store_packed_failure :
    forall t v s i f m k off a tp hs,
      types_agree t v ->
      smem_ind s f.(f_inst) = Some i ->
      s.(s_mems) !! i = Some m ->
      store_packed m (Wasm_int.N_of_uint i32m k) off (bits v) (tp_length tp) = None ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_const v); AI_basic (BI_store t (Some tp) a off)] hs s f [::AI_trap]

  (** memory **)
  | wr_current_memory :
    forall i f m n s hs,
      smem_ind s f.(f_inst) = Some i ->
      s.(s_mems) !! i = Some m ->
      mem_size m = n ->
      wasm_reduce hs s f [::AI_basic (BI_current_memory)] hs s f [::AI_basic (BI_const (VAL_int32 (Wasm_int.int_of_Z i32m (Z.of_N n))))]
  | wr_grow_memory_success :
    forall s i f m n mem' c hs,
      smem_ind s f.(f_inst) = Some i ->
      s.(s_mems) !! i = Some m ->
      mem_size m = n ->
      mem_grow m (Wasm_int.N_of_uint i32m c) = Some mem' ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 c)); AI_basic BI_grow_memory] hs (upd_s_mem s (update_list_at s.(s_mems) i mem')) f [::AI_basic (BI_const (VAL_int32 (Wasm_int.int_of_Z i32m (Z.of_N n))))]
  | wr_grow_memory_failure :
    forall i f m n s c hs,
      smem_ind s f.(f_inst) = Some i ->
      s.(s_mems) !!i = Some m ->
      mem_size m = n ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 c)); AI_basic BI_grow_memory] hs s f [::AI_basic (BI_const (VAL_int32 int32_minus_one))]

  (** label and local **)
  | wr_label :
    forall s f es les s' f' es' les' k lh hs hs',
      wasm_reduce hs s f es hs' s' f' es' ->
      lfilled k lh es les ->
      lfilled k lh es' les' ->
      wasm_reduce hs s f les hs' s' f' les'
  | wr_local :
    forall s f es s' f' es' n f0 hs hs',
      wasm_reduce hs s f es hs' s' f' es' ->
      wasm_reduce hs s f0 [::AI_local n f es] hs' s' f0 [::AI_local n f' es']
.

Inductive head_reduce: state -> iris_expr -> state -> iris_expr -> Prop :=
  | purer_headr:
    forall hs s locs e hs' s' locs' e',
      pure_reduce hs s locs e hs' s' locs' e' ->
      head_reduce (hs, s, locs) e (hs', s', locs') e'.

Definition head_step (e : iris_expr) (s : state) (os : list observation) (e' : iris_expr) (s' : state) (es' : list iris_expr) : Prop :=
  head_reduce s e s' e' /\
  os = nil /\
  es' = nil. (* ?? *)

Lemma head_step_not_val: forall e1 σ1 κ e2 σ2 efs,
  head_step e1 σ1 κ e2 σ2 efs ->
  to_val e1 = None.
Proof.
  move => e1 σ1 κ e2 σ2 efs H.
  destruct H as [HR _].
  inversion HR as [hs s locs e hs' s' locs' e' H]; subst.
  by inversion H.
Qed.

Lemma wasm_mixin : LanguageMixin of_val to_val head_step.
Proof.
  split => //.
  - by apply of_to_val.
  - by apply head_step_not_val.
Qed.

Canonical Structure wasm_lang := Language wasm_mixin.

Definition proph_id := unit. (* ??? *)

Class hsG Σ := HsG {
  hs_invG : invG Σ;
  hs_gen_hsG :> gen_heapG id iris_val Σ
}.

Class locG Σ := LocG {
  loc_invG : invG Σ;
  loc_gen_hsG :> gen_heapG N iris_val Σ
}.

Class wfuncG Σ := WFuncG {
  func_invG : invG Σ;
  func_gen_hsG :> gen_heapG N function_closure Σ;
}.

Class wtabG Σ := WTabG {
  tab_invG : invG Σ;
  tab_gen_hsG :> gen_heapG (N*N) funcelem Σ;
}.

Class wmemG Σ := WMemG {
  mem_invG : invG Σ;
  mem_gen_hsG :> gen_heapG (N*N) byte Σ;
}.

Class wglobG Σ := WGlobG {
  glob_invG : invG Σ;
  glob_gen_hsG :> gen_heapG N global Σ;
}.

Instance heapG_irisG `{!hsG Σ, !locG Σ, !wfuncG Σ, !wtabG Σ, !wmemG Σ, !wglobG Σ} : irisG wasm_lang Σ := {
  iris_invG := hs_invG; (* TODO: determine the correct invariant. Or, do we have any actually? *)
  state_interp σ _ κs _ :=
    let (hss, locs) := σ in
    let (hs, s) := hss in
    ((gen_heap_interp hs) ∗
      (gen_heap_interp (gmap_of_list locs)) ∗
      (gen_heap_interp (gmap_of_list s.(s_funcs))) ∗
      (gen_heap_interp (gmap_of_table s.(s_tables))) ∗
      (gen_heap_interp (gmap_of_memory s.(s_mems))) ∗
      (gen_heap_interp (gmap_of_list s.(s_globals)))
    )%I;
  fork_post _ := True%I;
  num_laters_per_step _ := 0;
  state_interp_mono _ _ _ _ := fupd_intro _ _
  
}.

(* This means the proposition that 'the location l of the heap has value v, and we own q of it' 
     (fractional algebra). 
   We really only need either 0/1 permission for our language, though. *)
Notation "i ↦ₕ{ q } v" := (mapsto (L:=id) (V:=host_value) i q v%V)
                           (at level 20, q at level 5, format "i ↦ₕ{ q } v") : bi_scope.
Notation "i ↦ₕ v" := (mapsto (L:=id) (V:=host_value) i (DfracOwn 1) v%V)
                      (at level 20, format "i ↦ₕ v") : bi_scope.
Notation "n ↦ₗ{ q } v" := (mapsto (L:=N) (V:=host_value) n q v%V)
                           (at level 20, q at level 5, format "n ↦ₗ{ q } v") : bi_scope.
Notation "n ↦ₗ v" := (mapsto (L:=N) (V:=host_value) n (DfracOwn 1) v%V)
                      (at level 20, format "n ↦ₗ v") : bi_scope.
(* Unfortunately Unicode does not have every letter in the subscript small latin charset, so we 
     will have to fall back on indices for now. It's best to use subscripts with 2 letters such
     as wf/wt/wm/wg, but immediately we realize we don't have w in the character set. A 
     workaround is to use some pretty printing macro option in emacs, but that will not be 
     displayed when viewed on github etc. *)
Notation "n ↦₁{ q } v" := (mapsto (L:=N) (V:=function_closure) n q v%V)
                           (at level 20, q at level 5, format "n ↦₁{ q } v") : bi_scope.
Notation "n ↦₁ v" := (mapsto (L:=N) (V:=function_closure) n (DfracOwn 1) v%V)
                      (at level 20, format "n ↦₁ v") : bi_scope.
Notation "n ↦₂{ q } [ i ] v" := (mapsto (L:=N*N) (V:=funcelem) (n, i) q v%V)
                           (at level 20, q at level 5, format "n ↦₂{ q } [ i ] v") : bi_scope.
Notation "n ↦₂[ i ] v" := (mapsto (L:=N*N) (V:=funcelem) (n, i) (DfracOwn 1) v%V)
                      (at level 20, format "n ↦₂[ i ] v") : bi_scope.
Notation "n ↦₃{ q } [ i ] v" := (mapsto (L:=N*N) (V:=byte) (n, i) q v%V)
                           (at level 20, q at level 5, format "n ↦₃{ q } [ i ] v") : bi_scope.
Notation "n ↦₃[ i ] v" := (mapsto (L:=N*N) (V:=byte) (n, i) (DfracOwn 1) v% V)
                           (at level 20, format "n ↦₃[ i ] v") : bi_scope.
Notation "n ↦₄{ q } v" := (mapsto (L:=N) (V:=global) n q v%V)
                           (at level 20, q at level 5, format "n  ↦₄{ q } v") : bi_scope.
Notation "n ↦₄ v" := (mapsto (L:=N) (V:=global) n (DfracOwn 1) v%V)
                      (at level 20, format "n ↦₄ v") : bi_scope.

Global Instance wasm_lang_inhabited : Inhabited (language.state wasm_lang) :=
  populate (∅, Build_store_record [::] [::] [::] [::], [::]).

Section lifting.

Context `{!hsG Σ, !locG Σ, !wfuncG Σ, !wtabG Σ, !wmemG Σ, !wglobG Σ}.

Implicit Types σ : state.

Ltac inv_head_step :=
  repeat match goal with
  | _ => progress simplify_map_eq/= (* simplify memory stuff *)
  | H : to_val _ = Some _ |- _ => apply of_to_val in H
  | H : head_step ?e _ _ _ _ _ |- _ =>
     inversion H; subst; clear H
  | H : head_reduce _ ?e _ _ |- _ => (* in our language simply inverting head_step won't produce
     anything meaningful as we just get a head_reduce back, so we need a further inversion.
     Moreover, the resulting pure_reduce also needs one last inversion. *)
    inversion H => //; subst; clear H
  | H : pure_reduce _ _ _ ?e _ _ _ _ |- _ =>
    try (is_var e; fail 1); (* this is the case where we want to avoid inverting if e is a var. *)
    inversion H => //; subst; clear H
  | H : _ = [] /\ _ = [] |- _ => (* this is to resolve the resulting equalities from head_step. *) 
     destruct H
         end.

(* The following 3 lemmas establish that reducible is the same as taking a head_step in our
     language. *)
Lemma reducible_head_step e σ:
  reducible e σ ->
  exists e' σ', head_step e σ [] e' σ' [].
Proof.
  move => HRed. unfold reducible in HRed.
  destruct HRed as [?[?[?[? HRed]]]].
  inversion HRed; simpl in *; subst.
  inv_head_step.
  by repeat eexists.
Qed.

Lemma head_step_reducible e σ e' σ':
  head_step e σ [] e' σ' [] ->
  reducible e σ.
Proof.
  intro HRed. unfold reducible => /=.
  by do 4 eexists.
Qed.

Lemma hs_red_equiv e σ:
  reducible e σ <-> exists e' σ', head_step e σ [] e' σ' [].
Proof.
  split; first by apply reducible_head_step.
  intro HRed. destruct HRed as [?[??]]. by eapply head_step_reducible.
Qed.

Open Scope string_scope.

Lemma wp_getglobal s E id q v:
  {{{ id ↦ₕ{ q } v }}} (HE_getglobal id) @ s; E
  {{{ RET v; id ↦ₕ{ q } v }}}.
Proof.
  (* Some explanations on proofmode tactics and patterns are available on 
       https://gitlab.mpi-sws.org/iris/iris/blob/master/docs/proof_mode.md *)
  (* After 2 days the solution is finally found -- need to 'Open Scope string_scope' first. *)
  iIntros (Φ) "Hl HΦ".
  iApply wp_lift_atomic_step => //.
  (*
    This is just another iIntros although with something new: !>. This !> pattern is for
      removing the ={E}=* from our goal (this symbol represents an update modality).
  *)
  iIntros (σ1 ns κ κs nt) "Hσ !>".
  destruct σ1 as [[hs ws] locs].
  iSimpl in "Hσ".
  iDestruct "Hσ" as "[Hhs Ho]".
  iDestruct (gen_heap_valid with "Hhs Hl") as %?.
  iSplit.
  - destruct s => //.
    (* iPureIntro takes an Iris goal ⌜ P ⌝ into a Coq goal P. *)
    iPureIntro.
    apply hs_red_equiv.
    repeat eexists.
    by apply pr_getglobal.
  - iIntros (e2 σ2 efs Hstep); inv_head_step.
    (* There are two cases -- either the lookup result v is an actual valid value, or a trap. *)
    + repeat iModIntro; repeat (iSplit; first done). iFrame. iSplit => //. by iApply "HΦ".
    (* But it can't be a trap since we already have full knowledge from H what v should be. *)    
    + by rewrite H5 in H. (* TODO: fix this bad pattern of using generated hypothesis names *)  
Qed.

(* If we have full ownership then we can also set the value of it -- provided that the value
     is not a trap. *)
Lemma wp_setglobal_value s E id w v:
  v <> HV_trap ->
  {{{ id ↦ₕ w }}} HE_setglobal id (HE_value v) @ s; E
  {{{ RET v; id ↦ₕ v }}}.
Proof.
  intros HNTrap.
  iIntros (Φ) "Hl HΦ". iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ !>".
  destruct σ1 as [[hs ws] locs].
  iSimpl in "Hσ".
  iDestruct "Hσ" as "[Hhs Ho]".
  iDestruct (gen_heap_valid with "Hhs Hl") as %?.
  (* Dealing with the lookup hypothesis first again. TODO: maybe refactor this into another 
       ltac as well *)
  iSplit.
  - destruct s => //. iPureIntro.
    apply hs_red_equiv. repeat eexists.
    by apply pr_setglobal_value.
  - iIntros (v2 σ2 efs Hstep); inv_head_step.
    iModIntro.
    (* This eliminates the update modality by updating hs *)
    iMod (gen_heap_update with "Hhs Hl") as "[Hhs Hl]".
    iModIntro.
    iFrame.
    iSplit => //.
    by iApply "HΦ".
Qed.
      
Lemma wp_setglobal_trap s E id Ψ:
  {{{ Ψ }}} HE_setglobal id (HE_value HV_trap) @ s; E
  {{{ RET (HV_trap); Ψ }}}.
Proof.
  iIntros (Φ) "Hl HΦ". iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ !>".
  iSplit.
  - destruct s => //.
    iPureIntro. destruct σ1 as [[hs ws] locs].
    apply hs_red_equiv. repeat eexists.
    by apply pr_setglobal_trap.
  - iIntros (e2 σ2 efs Hstep); inv_head_step.
    repeat iModIntro. iFrame. iSplit => //. by iApply "HΦ".
Qed.
 
(* Manually deal with evaluation contexts. Supposedly this proof should be similar to
     wp_bind. *)
(*
  Technically this lemma might be correct without the v ≠ HV_trap, but Hev can't be 
    simplfied without it somehow. Actually will this lemma be true without the v ≠ trap part?
 *)
(*
  {P} e {Q} ≡ P -∗ WP e {Q} ?

  also get unfolded by iStartProof to

  P -∗ (Q -∗ Φ v) -∗ WP e {v. Φ v}

  But page 139 of ILN says they are almost equivalent (and indeed equivalent when e is not a val).
*)
Lemma wp_setglobal_reduce s E id e Ψ Φ:
  WP e @ s; E {{ v, ⌜ v <> HV_trap ⌝ ∗ Ψ v }} ∗
  (∀ v, (( ⌜ v <> HV_trap ⌝ ∗ Ψ v) -∗ WP (HE_setglobal id (HE_value v)) @ s; E {{ Φ }})) ⊢
  WP (HE_setglobal id e) @ s; E {{ Φ }}.
Proof.
  iIntros "[Hev Hv]".
  (*
    iLöb does a Löb induction. In Iris the Löb rule is:
      Q /\ ▷P ⊢ P -> Q ⊢ P

    What iLöb does is basically adding another hypothesis IH which is the entire current goal
      (including the premises), but with a later modality. It is then sufficient to prove the 
      current goal given that the goal holds later -- so Löb induction is a coinduction.
      http://adam.chlipala.net/cpdt/html/Coinductive.html
  *)
  iLöb as "IH" forall (E e Φ).
  rewrite wp_unfold /wp_pre /=.
  destruct (to_val e) as [v|] eqn:He.
  { apply of_to_val in He as <-. iApply fupd_wp. by iApply "Hv". }
  rewrite wp_unfold /wp_pre /=.
  iIntros (σ1 ns κ κs nt) "Hσ".
  (* How to resolve this fancy update modality? *)
  (* Update: using iMod is fine, just that in this case Iris doens't automatically
       instantiate the variables for Hev for some reasons. *)
  (* $! means instantiate the hypothesis with the following variables. *)
  iMod ("Hev" $! σ1 ns κ κs nt with "Hσ") as "[% H]".
  iModIntro; iSplit.
  {
    destruct s; eauto.
    (* There are some weird consequences with our choice of having 0 ectx item while
         still using the ectxi_language framework: reducible is now equivalent to a head_step. *)
    apply hs_red_equiv in H. destruct H as [e' [σ' H]].
    iPureIntro.
    apply hs_red_equiv. exists (HE_setglobal id e'), σ'.
    inv_head_step.
    unfold head_step; repeat split => //.
    by apply pr_setglobal_step.
  }
  iIntros (e2 σ2 efs Hstep).
  inversion Hstep; simpl in *; subst.
  inv_head_step.
  (* The pattern "[//]" seems to mean automaitcally deduce the required assumption for 
       elimnating the modality using H (like inserting an eauto). *)
  (* TODO: I forgot what's going on here. Add comments on how these modalities are resolved. *)
  iMod ("H" $! e' (hs', s', locs') [] with "[//]") as "H". iIntros "!>!>!>".
  iMod "H". iMod "H". repeat iModIntro. iSimpl in "H".
  iDestruct "H" as "[Hheap H]".
  iSplitL "Hheap"; first by eauto.
  iSplitL; last by eauto.
  iDestruct "H" as "[H _]".
  (* "[$]" seems to mean 'find the useful hypotheses by yourself', as this can be normally
    resolved by with "Hv H". Interestingly enough, "[//]" won't work. What's the difference? *)
  by iApply ("IH" with "[$]").
  (* Now we've actually proved this thing finally.. *)  
Qed.

(* This is rather easy, following the same idea as getglobal. *)
Lemma wp_getlocal s E n q v:
  {{{ n ↦ₗ{ q } v }}} (HE_getlocal n) @ s; E
  {{{ RET v; n ↦ₗ{ q } v }}}.
Proof.
  iIntros (Φ) "Hl HΦ".
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ms κ κs mt) "Hσ !>".
  destruct σ1 as [[hs ws] locs].
  iSimpl in "Hσ".
  iDestruct "Hσ" as "[Hhs [Hlocs Ho]]".
  iDestruct (gen_heap_valid with "Hlocs Hl") as %?.
  rewrite gmap_of_list_lookup in H.
  unfold option_map in H.
  remember (locs !! N.to_nat n) as lookup_res eqn:Hlookup; destruct lookup_res; inversion H; subst; clear H.
  iSplit.
  - destruct s => //.
    iPureIntro. apply hs_red_equiv.
    repeat eexists. by apply pr_getlocal. 
  - iIntros (e2 σ2 efs Hstep); inv_head_step.
    + repeat iModIntro; repeat (iSplit; first done).
      rewrite H4 in Hlookup. inversion Hlookup.
      iFrame. iSplit => //. by iApply "HΦ".
    + by rewrite H4 in Hlookup.
Qed.

(* This is now very interesting and a bit different to setglobal, since we need to retrieve the
     value to be set from a resource first. 
   Note the ownership required for the different types of resources.
*)
Lemma wp_setlocal s E n q id w v:
  {{{ n ↦ₗ w ∗ id ↦ₕ{ q } v }}} (HE_setlocal n id) @ s; E
  {{{ RET v; n ↦ₗ v ∗ id ↦ₕ{ q } v}}}.
Proof.
  iIntros (Φ) "[Hl Hh] HΦ".
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ms κ κs mt) "Hσ !>".
  destruct σ1 as [[hs ws] locs].
  iSimpl in "Hσ".
  iDestruct "Hσ" as "[Hhs [Hlocs Ho]]".
  (* This is the first case where we have two types of resources in the precondition. We do
       iDestruct on each of them to gather the required information into the Coq context first,
       as the Iris propositions won't be available to use after iPureIntro. *)
  iDestruct (gen_heap_valid with "Hlocs Hl") as %?.
  rewrite gmap_of_list_lookup in H.
  unfold option_map in H.
  remember (locs !! N.to_nat n) as lookup_res eqn:Hlookup_locs; destruct lookup_res; inversion H; subst; clear H.
  iDestruct (gen_heap_valid with "Hhs Hh") as %?.
  iSplit.
  - destruct s => //.
    iPureIntro. apply hs_red_equiv.
    repeat eexists.
    apply pr_setlocal => //.
    by apply lookup_lt_Some with (x := w).
  - iIntros (e2 σ2 efs Hstep); inv_head_step.
    + iModIntro.
      (* Don't just mindlessly iModIntro again! This would waste the update modality, while we 
           need it to get the locs resources modified. *)
      iMod (gen_heap_update with "Hlocs Hl") as "[Hlocs Hl]".
      simpl.
      repeat iModIntro.
      (* It takes rather long for Iris to find the correct frame. *)
      iFrame.
      simpl.
      rewrite gmap_of_list_insert => //.
      iSplitL "Hlocs" => //.
      iSplit => //. iApply "HΦ". by iFrame.
    + by rewrite H11 in H.
    + symmetry in Hlookup_locs. apply lookup_lt_Some in Hlookup_locs.
      lia.
Qed.

Lemma he_if_reducible: forall id e1 e2 σ,
  @reducible wasm_lang (HE_if id e1 e2) σ.
Proof.
  move => id e1 e2 [[hs ws] locs].
  apply hs_red_equiv.
  destruct (hs !! id) as [res|] eqn:Hlookup.
  - destruct (decide (res = HV_wasm_value (VAL_int32 (Wasm_int.int_zero i32m)))); subst.
    + repeat eexists; by eapply pr_if_false.
    + destruct (decide (res = HV_trap)); subst; repeat eexists.
      * by eapply pr_if_trap.
      * by eapply pr_if_true.
  - repeat eexists. by eapply pr_if_none.
Qed.

(* We now get to some control flow instructions. It's a bit tricky since rules like these
     do not need to be explicitly dealt with in Heaplang, but instead taken automatically by 
     defining it as an evaluation context. We have to see what needs to be done here. The proof
     to this should be a standard model to other context-like instructions (seq, etc.). *)
(* TODO: Add detailed comments on how to resolve fupd in both iris 3.3 and new iris *)
Lemma wp_if s E id q v w e1 e2 P Q:
  v ≠ HV_trap ->
  {{{ P ∗ id ↦ₕ{ q } v ∗ ⌜ v ≠ wasm_zero ⌝ }}} e1 @ s; E {{{ RET w; Q }}} ∗
  {{{ P ∗ id ↦ₕ{ q } v ∗ ⌜ v = wasm_zero ⌝ }}} e2 @ s; E {{{ RET w; Q }}} ⊢
  {{{ P ∗ id ↦ₕ{ q } v }}} (HE_if id e1 e2) @ s; E
  {{{ RET w; Q }}}.
Proof.
  move => HNTrap.
  iIntros "[#HT #HF]".
  (* If the goal involves more than one triples (unlike the previous proofs), the conclusion 
       will somehow have a □ modality around. That's not a problem nonetheless since our premises
       are persistent as well. *)
  iModIntro.
  iIntros (Φ) "[HP Hh] HΦ".
  iApply wp_lift_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  destruct σ1 as [[hs ws] locs].
  iSimpl in "Hσ".
  iDestruct "Hσ" as "[Hhs Ho]".
  iDestruct (gen_heap_valid with "Hhs Hh") as %?.
  (* I really wish we're using the new version of Iris, where we can just apply one of the new
       fupd intro lemmas to get this fupd into a premise. But we don't have that currently. *)
  (* UPD: After some treasure hunting, this is also doable in Iris 3.3 via an iMod! *)
  (* TODO: add comments on resolving this fupd modality. Iris 3.3: only do iMod 
       fupd_intro_mask'. New Iris: either iMod fupd_intro_subseteq or iApply fupd_mask_intro. *)
  (* TODO: upgrade to the current version of Iris -- upgrade Coq to 8.12? But need to fix 
       CompCert compilation issues. Maybe better when there's no ongoing changes *)
  iApply fupd_mask_intro; first by set_solver.
  iIntros "Hfupd".
  iSplit.
  - iPureIntro. destruct s => //.
    by apply he_if_reducible.
  - iModIntro.
    iIntros (e0 σ2 efs HStep).
    inv_head_step.
    (* There are 4 cases for the lookup result: non-zero/zero/trap/none. trap is automatically
         resolved by the first premise, and none is impossible by the mapsto predicate. *)
    + iMod "Hfupd".
      iModIntro.
      iFrame.
      iApply ("HT" with "[HP Hh]") => //; by iFrame.
    + iMod "Hfupd".
      iModIntro.
      iFrame.
      iApply ("HF" with "[HP Hh]") => //; by iFrame.
    + by rewrite H in H12.
Qed.

(* a simper-to-use version that only needs the branch for true. Note that this and the following
     lemma combined form a solution to Exercise 4.9 in ILN. *)
Lemma wp_if_true s E id q v w e1 e2 P Q:
  v ≠ HV_trap ->
  v ≠ wasm_zero ->
  {{{ P ∗ id ↦ₕ{ q } v }}} e1 @ s; E {{{ RET w; Q }}} ⊢
  {{{ P ∗ id ↦ₕ{ q } v }}} (HE_if id e1 e2) @ s; E
  {{{ RET w; Q }}}.
Proof.
  move => HNTrap HNZero.
  iIntros "#HT".
  iApply wp_if => //.
  iSplit.
  - iModIntro.
    iIntros (Φ) "[HP [Hh Hn0]] HQ".
    iApply ("HT" with "[HP Hh Hn0]"); by iFrame.
  - iModIntro.
    iIntros (Φ) "[? [?%]] ?"; subst => //.
Qed.

Lemma wp_if_false s E id q v e1 e2 P Q:
  {{{ P ∗ id ↦ₕ{ q } wasm_zero }}} e2 @ s; E {{{ RET v; Q }}} ⊢
  {{{ P ∗ id ↦ₕ{ q } wasm_zero }}} (HE_if id e1 e2) @ s; E
  {{{ RET v; Q }}}.
Proof.
  iIntros "#HF".
  iApply wp_if => //.
  iSplit.
  - iModIntro.
    by iIntros (Φ) "[? [?%]] ?" => //.
  - iModIntro.
    iIntros (Φ) "[HP [Hh ?]] HQ".
    iApply ("HF" with "[HP Hh]"); by iFrame.
Qed.

(* 
  Almost the same as if -- actually easier, since there's only one case. 
  We could certainly follow the same proof structure of if. However here we choose another 
    approach, noting that this step is a 'pure' step, in the sense that there is only one
    reduction pathway which does not depend on any resource of the state. Therefore we can apply
    'wp_lift_pure_step' to avoid having to manually opening the states and dealing with fupd 
    modalities.
  Note that we do not actually need any knowledge on the host variable id, since we're delaying
    the lookup to one step later.
*)
Lemma wp_while s E id w e P Q:
  {{{ P }}} (HE_if id (HE_seq e (HE_while id e)) (HE_value wasm_zero)) @ s; E {{{ RET w; Q }}} ⊢
  {{{ P }}} (HE_while id e) @ s; E {{{ RET w; Q }}}.
Proof.
  iIntros "#HT".
  iModIntro.
  iIntros (Φ) "HP HQ".
  iApply wp_lift_pure_step_no_fork.
  - move => σ1. destruct σ1 as [[hs ws] locs].
    destruct s => //.
    apply hs_red_equiv.
    repeat eexists. by apply pr_while.
  - move => κ σ1 e2 σ2 efs HStep.
    by inv_head_step.
  - repeat iModIntro.
    iIntros (κ e2 efs σ) "%".
    inv_head_step.
    iApply ("HT" with "HP"); by iAssumption.
Qed.

Lemma those_none: forall {T: Type} (l: list (option T)),
  list_extra.those l = None <-> None ∈ l.
Proof.
  intros.
  rewrite - list_extra.those_those0.
  induction l => //=.
  - split => //.
    unfold elem_of.
    move => HContra.
    by inversion HContra.
  - destruct a => //; rewrite elem_of_cons.
    + unfold option_map.
      destruct (those0 l) eqn:Hthose.
      * split => //.
        move => [H|H]; try by inversion H.
        apply IHl in H.
        by inversion H.
      * split => //. intros _.
        right. by apply IHl.
    + split => //.
      intros _. by left.
Qed.

Lemma those_length: forall {T: Type} (l: list (option T)) (le: list T),
  list_extra.those l = Some le -> length l = length le.
Proof.
  move => T l le H.
  rewrite - list_extra.those_those0 in H.
  move: l le H.
  induction l => //=.
  - move => le H. simpl in H.
    by inversion H.
  - move => le H.
    destruct a => //=.
    unfold option_map in H.
    destruct (those0 _) eqn:H2 => //=.
    inversion H; subst; clear H.
    simpl.
    f_equal.
    by apply IHl.
Qed.

Lemma those_lookup: forall {T: Type} (l: list (option T)) (le: list T) n,
  list_extra.those l = Some le -> option_map (fun x => Some x) (le !! n) = l !! n.
Proof.
  move => T l le n Hthose.
  rewrite - those_those0 in Hthose.
  move : le n Hthose.
  induction l => //=; move => le n Hthose.
  - inversion Hthose; subst; clear Hthose.
    unfold option_map.
    by repeat rewrite list_lookup_empty.
  - destruct a => //=.
    unfold option_map in *.
    destruct le => //=; first by destruct (those0 l).
    destruct n => //=.
    + destruct (those0 l) => //.
      by inversion Hthose.
    + destruct (those0 l) => //.
      inversion Hthose; subst; clear Hthose.
      by apply IHl. 
Qed.
      
Lemma wp_new_rec s E (kip: list (field_name * id)) (w: list (field_name * host_value)) P:
  length kip = length w ->
  (∀ i key id,
      ⌜ kip !! i = Some (key, id) ⌝ -∗
      ∃ v, ⌜ w !! i = Some (key, v)⌝ ∗
      □(P -∗ ( id ↦ₕ v ))) ⊢
  {{{ P }}} (HE_new_rec kip) @ s; E {{{ RET (HV_record w); P }}}.
Proof.
  move => HLength.
  iIntros "#Hkvp".
  iModIntro.
  iIntros (Φ) "HP HQ".
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  destruct σ1 as [[hs ws] locs].
  iSimpl in "Hσ".
  iDestruct "Hσ" as "[Hhs Ho]".
  repeat iModIntro.
  iSplit.
  - iPureIntro.
    destruct s => //.
    apply hs_red_equiv.
    destruct (list_extra.those (fmap (fun id => hs !! id) (kip.*2))) eqn:Hkvp; repeat eexists.
    + by eapply pr_new_rec.
    + by eapply pr_new_rec_trap.
  - iModIntro.
    iIntros (e2 σ2 efs HStep).
    repeat iModIntro.
    iAssert ( ∀ (i: nat) (key: field_name) (id: id), ⌜ kip !! i = Some (key, id) ⌝ -∗
                           ∃ v, ⌜w !! i = Some (key, v) ⌝ ∗ ⌜ hs !! id = Some v ⌝ )%I as "%H".
    {
      iIntros (i key id) "Hlookup".
      iAssert ((∃ v, ⌜ w !! i = Some (key, v) ⌝ ∗ □(P -∗ id ↦ₕ v))%I) with "[Hlookup]" as "H".
      {
        by iApply "Hkvp".
      }
      iDestruct "H" as (v) "[H1 #H2]".
      iExists v.
      iFrame.
      iDestruct (gen_heap_valid with "Hhs [H2 HP]") as %?; first by iApply "H2".
      by iPureIntro.
    }
    inv_head_step; iFrame; iSplit => //.
    + iAssert (⌜ zip kip.*1 hvs = w ⌝)%I as "%Heq".
      {
        iPureIntro.
        move: kip hvs HLength H H2.
        induction w => //; move => kip hvs HLength H H2.
        * simpl in HLength.
          by destruct kip => //.
        * destruct kip => //=.
          simpl in HLength.
          inversion HLength. clear HLength.
          destruct hvs => //=.
          - simpl in H2.
            apply those_length in H2.
            simpl in H2.
            by inversion H2.
          - destruct p => /=.
            rewrite - list_extra.those_those0 in H2.
            simpl in H2.
            destruct (hs' !! i) eqn: Hlookup => //.
            unfold option_map in H2.
            destruct (those0 _) eqn: H3 => //.
            inversion H2; subst; clear H2.
            rewrite list_extra.those_those0 in H3.
            apply IHw in H3 => //.
            + rewrite H3.
              f_equal.
              assert (exists v, (a :: w) !! 0 = Some (f, v) /\ hs' !! i = Some v) as HL; first by apply H.
              simpl in HL.
              destruct HL as [v [H4 H5]].
              inversion H4; subst; clear H4.
              rewrite H5 in Hlookup. by inversion Hlookup.
            + move => i0 key id Hlookup0.
              assert (exists v, (a :: w) !! (S i0) = Some (key, v) /\ hs' !! id = Some v) as Hgoal.
              { apply H.
                by rewrite lookup_cons_ne_0 => /=. }
              simpl in Hgoal.
              assumption.
      }
      subst. by iApply "HQ".
    + apply those_none in H5.
      resolve_finmap.
      destruct x0. simpl in *.
      apply H in Helem.
      destruct Helem as [v [Heq2 Hlookup]].
      by rewrite Hlookup in Heq.
Qed.

Lemma wp_getfield s E id fieldname kvp v:
  lookup_kvp kvp fieldname = Some v ->
  {{{ id ↦ₕ (HV_record kvp) }}} (HE_get_field id fieldname) @ s; E {{{ RET v; id ↦ₕ (HV_record kvp) }}}.
Proof.
  move => HkvpLookup.
  iIntros (Φ) "Hh HΦ".
  iApply wp_lift_atomic_step => //.
  iIntros (σ ns κ κs nt) "Hσ !>".
  destruct σ as [[hs ws] locs].
  iSimpl in "Hσ".
  iDestruct "Hσ" as "[Hhs Ho]".
  iDestruct (gen_heap_valid with "Hhs Hh") as "%".
  iSplit.
  - iPureIntro.
    destruct s => //.
    apply hs_red_equiv.
    repeat eexists.
    by eapply pr_getfield.
  - iModIntro.
    iIntros (e2 σ2 efs) "%HStep".
    destruct σ2 as [[hs2 ws2] locs2] => //=.
    iModIntro.
    inv_head_step.
    + iFrame.
      iSplit => //=.
      by iApply "HΦ".
    + by rewrite H in H11.    
Qed.

Lemma wp_seq_value s E v w e P Q:
  v ≠ HV_trap ->
  {{{ P }}} e @ s; E {{{ RET w; Q }}} -∗
  {{{ P }}} HE_seq (HE_value v) e @ s; E {{{ RET w; Q }}}.
Proof.
  move => Hvalue.
  iIntros "#HE !>" (Φ) "HP HΦ".
  iApply wp_lift_pure_step_no_fork.
  - move => σ.
    destruct σ as [[hs ws] locs].
    destruct s => //.
    apply hs_red_equiv.
    repeat eexists.
    by apply pr_seq_const.
  - move => κ σ1 e2 σ2 efs HStep.
    by inv_head_step.
  - repeat iModIntro.
    iIntros (κ e2 efs σ) "%HStep".
    inv_head_step.
    iApply ("HE" with "HP"); by iAssumption.
Qed.    

(* TODO: add another version that uses hoare triples instead of wps. *)
Lemma wp_seq s E e1 e2 Φ Ψ:
  (WP e1 @ s; E {{ v, Ψ v }} ∗
  (∀ v, (Ψ v) -∗ WP e2 @ s; E {{ Φ }})) ⊢
  WP HE_seq e1 e2 @ s; E {{ Φ }}.    
Proof.
  iLöb as "IH" forall (E e1 Φ Ψ).
  iIntros "[H1 H2]".
  repeat rewrite wp_unfold /wp_pre /=.
  iIntros (σ ns κ κs nt) "Hσ".
  destruct (to_val e1) as [v|] eqn:He.
  { apply of_to_val in He as <-.
    iMod "H1".
    iApply fupd_mask_intro; first by set_solver.
    iIntros "HMask".
    iSplit.
    - iPureIntro. destruct s => //=.
      apply hs_red_equiv.
      destruct σ as [[??]?].
      repeat eexists.
      by apply pr_seq_const.
    - iIntros (e0 σ2 efs) "%HStep".
      inv_head_step.
      repeat iModIntro.
      iMod "HMask".
      repeat iModIntro.
      iFrame.
      by iApply "H2"; iAssumption.
  }
  iMod ("H1" $! σ ns κ κs nt with "Hσ") as "[% H]".  
  iModIntro; iSplit.
  {
    destruct s; eauto.
    iPureIntro.
    apply hs_red_equiv in H. destruct H as [e' [σ' H]].
    inv_head_step.
    apply hs_red_equiv.
    repeat eexists.
    by apply pr_seq.
  }
  iIntros (e0 σ2 efs Hstep).
  inv_head_step.
  iMod ("H" $! e1' (hs', s', locs') [] with "[//]") as "H". iIntros "!>!>!>".
  iMod "H". iMod "H". repeat iModIntro. iSimpl in "H".
  iDestruct "H" as "[Hheap [H _]]".
  iFrame.
  iSplit => //.
  iApply "IH".
  by iFrame.
Qed.

Lemma wp_seq_hoare s E e1 e2 P Q R v w:
  ({{{ P }}} e1 @ s; E {{{ RET v; Q }}} ∗
  {{{ Q }}} e2 @ s; E {{{ RET w; R }}})%I ⊢
  {{{ P }}} HE_seq e1 e2 @ s; E {{{ RET w; R }}}.
Proof.
  iIntros "[#H1 #H2]" (Φ) "!> HP HΦ".
  iApply wp_seq.
  iSplitL "HP HΦ".
  - iApply ("H1" with "HP").
    iIntros "!> HQ".
    (* This is actually subtle: we need to 'carry' all the information to the second part. *)
    instantiate (1 := (fun v => (Q ∗ (R -∗ Φ w)))%I).
    by iFrame.
  - iIntros (v0) "[HQ HΦ]".
    by iApply ("H2" with "HQ").
Qed.
  
(*
  | pr_host_return:
    forall hs s locsf locs ids e vs tn,
      list_extra.those (fmap (fun id => hs !! id) ids) = Some vs ->
      pure_reduce hs s locsf (HE_host_frame tn locs (HE_seq (HE_return ids) e)) hs s locsf (HE_value (HV_list vs))

  Note that we actually have the list of local variables living in the instruction here...

  This spec is proved, but it sounds a bit weak. For example, no information about the local
     variable is extracted from P and no similar information is obtained in the post condition.
 *)

Lemma wp_return s E tn locs ids e (vs: list host_value) P:
  length vs = length ids ->
  (∀ n id, ⌜ ids !! n = Some id ⌝ -∗ ∃ v, ⌜ vs !! n = Some v ⌝ ∗ □ (P -∗ id ↦ₕ v)) ⊢
  {{{ P }}} (HE_host_frame tn locs (HE_seq (HE_return ids) e)) @ s; E {{{ RET (HV_list vs); True }}}.
Proof.
  move => HLength.
  iIntros "#Href !>" (Φ) "HP HΦ".
  iApply wp_lift_atomic_step => //=.
  iIntros (σ1 ns κ κs nt) "Hσ !>".
  destruct σ1 as [[hs ws] ls].
  iDestruct "Hσ" as "[Hhs Ho]".
  iSplit.
  - iPureIntro.
    destruct s => //.
    apply hs_red_equiv.
    destruct (those (fmap (fun (id: datatypes_iris.id) => hs !! id) ids)) eqn:Hlookup; repeat eexists.
    + by eapply pr_host_return.
    + by eapply pr_host_return_trap.
  - iIntros "!>" (e2 σ2 efs HStep) "!>".
    destruct σ2 as [[hs2 ws2] locs2].
    iAssert ( ∀ (n: nat) (id: datatypes_iris.id), ⌜ ids !! n = Some id ⌝ -∗
                           ∃ v, ⌜vs !! n = Some v ⌝ ∗ ⌜ hs !! id = Some v ⌝ )%I as "%H".
    {
      iIntros (n id) "Hlookup".
      iAssert ((∃ v, ⌜ vs !! n = Some v ⌝ ∗ □(P -∗ id ↦ₕ v))%I) with "[Hlookup]" as "H".
      {
        by iApply "Href".
      }
      iDestruct "H" as (v) "[H1 #H2]".
      iExists v.
      iFrame.
      iDestruct (gen_heap_valid with "Hhs [H2 HP]") as %?; first by iApply "H2".
      by iPureIntro.
    }
    inv_head_step; iFrame; iSplit => //.
    + replace vs0 with vs; first iApply "HΦ" => //.
      apply list_eq.
      move => i.
      destruct (ids !! i) eqn:Hlookup.
      * apply those_lookup with (n := i) in H13.
        unfold option_map in H13.
        symmetry in H13.
        rewrite list_lookup_fmap in H13.
        rewrite Hlookup in H13.
        simpl in H13.
        destruct (vs0 !! i) => //=.
        inversion H13; clear H13.
        apply H in Hlookup.
        destruct Hlookup as [x [Heqvs Heqhs]].
        by rewrite Heqhs.
      * apply those_length in H13.
        rewrite fmap_length in H13.
        apply lookup_ge_None in Hlookup.
        assert (vs !! i = None) as H1.
        { apply lookup_ge_None. by rewrite HLength. }
        assert (vs0 !! i = None).
        { apply lookup_ge_None. by rewrite - H13. }
        by rewrite H1.
    + apply those_none in H13.
      resolve_finmap.
      apply H in Helem0.
      destruct Helem0 as [hv [Heq' Helem]].
      by rewrite Helem in Heq.
Qed.
      
(*
  | pr_new_host_func:
    forall hs s locs htf locsn e s' n,
      s' = {|s_funcs := s.(s_funcs) ++ [::datatypes_iris.FC_func_host htf locsn e]; s_tables := s.(s_tables); s_mems := s.(s_mems); s_globals := s.(s_globals) |} ->
      n = length s.(s_funcs) ->
      pure_reduce hs s locs (HE_new_host_func htf (N_of_nat locsn) e) hs s' locs (HE_value (HV_wov (WOV_funcref (Mk_funcidx n))))
 *)

Lemma wp_new_host_func s E htf locsn e:
  ⊢
  (WP HE_new_host_func htf (N_of_nat locsn) e @ s; E
  {{ fun v => match v with
           | HV_wov (WOV_funcref (Mk_funcidx n)) => N.of_nat n ↦₁ FC_func_host htf locsn e
           | _ => False
           end
  }})%I.
Proof.
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  destruct σ1 as [[hs ws] locs].
  iSimpl in "Hσ".
  iDestruct "Hσ" as "[?[?[Hwf ?]]]".
  iModIntro.
  iSplit.
  - iPureIntro.
    destruct s => //.
    apply hs_red_equiv.
    repeat eexists.
    by apply pr_new_host_func.
  - iModIntro.
    iIntros (e2 σ2 efs HStep).
    destruct σ2 as [[hs2 ws2] locs2].
    inv_head_step.
    iMod (gen_heap_alloc with "Hwf") as "(Hσ & Hl & Hm)".
    {
      instantiate (1 := N.of_nat (length ws.(s_funcs))).
      rewrite gmap_of_list_lookup.
      rewrite Nat2N.id.
      by rewrite lookup_ge_None.
    }
    iModIntro.
    iFrame.
    by rewrite - gmap_of_list_append.
Qed.    

Lemma he_call_reducible id ids hs ws locs:
  @reducible wasm_lang (HE_call id ids) (hs, ws, locs).
Proof.
  apply hs_red_equiv.
  destruct (hs !! id) eqn: Heqid; last by eapply pr_call_trap1 in Heqid; repeat eexists.
  destruct i; try by eapply pr_call_trap2 in Heqid; repeat eexists.
  destruct w; try by eapply pr_call_trap2 in Heqid; repeat eexists.
  destruct f; try by eapply pr_call_trap2 in Heqid; repeat eexists.
  destruct (ws.(s_funcs) !! n) eqn: Hfref; last by eapply pr_call_trap3 in Hfref; repeat eexists.
  destruct (list_extra.those (fmap (fun id => hs !! id) ids)) eqn: Hvals; last by eapply pr_call_trap4 in Hvals; repeat eexists.
  destruct f.
  - destruct f as [tn tm].
    destruct (list_extra.those (fmap host_value_to_wasm l)) eqn: Hwvs; last by eapply pr_call_wasm_trap1 in Hwvs => //; repeat eexists.
    assert ({tn = fmap typeof l2} + {tn <> fmap typeof l2}); first by decidable_equality.
    destruct H as [H|H]; subst.
    + by eapply pr_call_wasm in Heqid; repeat eexists.
    + by eapply pr_call_wasm_trap2 in H; repeat eexists.
  - destruct f as [tn tm].
    destruct (decide (length ids = length tn)) as [H|H]; subst.
    + by eapply pr_call_host in Hfref; repeat eexists.      
    + by eapply pr_call_host_trap1 in H; repeat eexists.
Qed.
  
Lemma wp_call_wasm id ids vs i s E P Q v j tn tm vts bes:
  length ids = length vs ->
  fmap typeof vs = tn ->
  (⌜ P =
     (id ↦ₕ HV_wov (WOV_funcref (Mk_funcidx i)) ∗
      N.of_nat i ↦₁ FC_func_native j (Tf tn tm) vts bes ∗
      (∀ n idx, ⌜ ids !! n = Some idx ⌝ -∗ ∃ wv, ⌜ vs !! n = Some wv ⌝ ∗ idx ↦ₕ HV_wasm_value wv)) ⌝) -∗
  {{{ P }}} (HE_wasm_frame ((v_to_e_list vs) ++ [::AI_invoke i])) @ s; E {{{ RET v; Q }}} -∗
  {{{ P }}} HE_call id ids @ s; E {{{ RET v; Q }}}.
Proof.
  move => HLen HType.
  iIntros "% #HwFrame" (Φ) "!> HP HΦ".
  subst.
  iDestruct "HP" as "[Hfref [Hfbody Hval]]".
  iApply wp_lift_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  iApply fupd_mask_intro; first by set_solver.
  iIntros "Hfupd".
  destruct σ1 as [[hs ws] locs].
  iSimpl in "Hσ".
  iDestruct "Hσ" as "[Hhs [? [Hwf ?]]]".
  iSplit.
  - iPureIntro.
    destruct s => //=.
    by apply he_call_reducible.
  - iIntros "!>" (e2 σ2 efs HStep).
    iMod "Hfupd".
    iDestruct (gen_heap_valid with "Hhs Hfref") as "%Hfref".
    iDestruct (gen_heap_valid with "Hwf Hfbody") as "%Hfbody".
    iAssert (∀ n idx, ⌜ids !! n = Some idx ⌝ -∗ ∃ wv, ⌜ vs !! n = Some wv ⌝ ∗ ⌜ hs !! idx = Some (HV_wasm_value wv) ⌝)%I as "%Hval".
    { iIntros (n idx H).
      iSpecialize ("Hval" $! n idx H).
      iDestruct "Hval" as (wv) "[?Hid]".
      iExists wv.
      iFrame.
      by iDestruct (gen_heap_valid with "Hhs Hid") as "%".
    }
    rewrite gmap_of_list_lookup in Hfbody.
    rewrite Nat2N.id in Hfbody.
    iModIntro.
    inv_head_step; iFrame.
    + replace vs0 with vs; first by iApply ("HwFrame" with "[Hfref Hfbody Hval]"); iFrame.
      apply list_eq. move => n.
      destruct (ids !! n) eqn:Hlookupid.
      * apply those_lookup with (n0 := n) in H6.
        rewrite list_lookup_fmap in H6.
        apply those_lookup with (n0 := n) in H11.
        rewrite list_lookup_fmap in H11. 
        unfold host_value_to_wasm in H11.
        unfold option_map in H6, H11.
        rewrite Hlookupid in H6.
        destruct (vars !! n) as [hv'|] eqn:Hvars => //.
        destruct (vs0 !! n) => //.
        simpl in H6, H11.
        inversion H6; subst; clear H6.
        inversion H11; subst; clear H11.
        destruct hv' => //.
        inversion H2; subst; clear H2.
        rewrite H0 in Hvars.
        apply Hval in Hlookupid.
        destruct Hlookupid as [hv [Heqvs Heqwv]].
        rewrite Heqvs.
        rewrite - H0 in Heqwv.
        by inversion Heqwv.
      * apply lookup_ge_None in Hlookupid.
        assert (length vs <= n); first by rewrite HLen in Hlookupid.
        assert (vs !! n = None) as Hvsn; first by apply lookup_ge_None.
        rewrite Hvsn; clear Hvsn.
        symmetry.
        apply lookup_ge_None.
        replace (length vs0) with (length ids) => //.
        apply those_length in H6, H11. 
        rewrite fmap_length in H6.
        rewrite fmap_length in H11.
        lia.
    + by rewrite Hfref in H10.
    + apply those_none in H10.
      resolve_finmap.
      apply Hval in Helem0.
      destruct Helem0 as [hv [Heqvs Heqwv]].
      by rewrite - Heq in Heqwv.
    + apply those_none in H15.
      resolve_finmap.
      apply those_lookup with (n := x0) in H10.
      rewrite list_lookup_fmap in H10.
      rewrite Helem0 in H10.
      destruct (ids !! x0) eqn: Hids => //.
      simpl in H10.
      inversion H10; subst; clear H10.
      apply Hval in Hids.
      destruct Hids as [hv [Heqvs Heqwv]].
      rewrite Heqwv in H0.
      inversion H0; subst; clear H0.
      by simpl in Heq.
    + exfalso; apply H16; clear H16.
      apply list_eq. move => n.
      repeat rewrite list_lookup_fmap.
      apply those_lookup with (n0 := n) in H6, H11.
      unfold option_map in H6, H11.
      rewrite list_lookup_fmap in H6.
      rewrite list_lookup_fmap in H11.
      destruct (ids !! n) eqn:Hlookupid => //=.
      * unfold host_value_to_wasm in H11.
        destruct (vars !! n) => //.
        destruct (vs0 !! n) => //.
        simpl in H6, H11.
        destruct h => //.
        inversion H6; subst; clear H6.
        inversion H11; subst; clear H11.
        apply Hval in Hlookupid.
        destruct Hlookupid as [hv [Heqvs Heqwv]].
        rewrite - H0 in Heqwv.
        inversion Heqwv; subst; clear Heqwv.
        by rewrite Heqvs.
      * apply lookup_ge_None in Hlookupid.
        destruct (vars !! n) => //.
        simpl in *.
        destruct (vs0 !! n) => //.
        assert (vs !! n = None) as H; last by rewrite H => //.
        apply lookup_ge_None.
        by rewrite - HLen.
Qed.

(*
  | pr_call_host:
    forall hs s ids cl id i n e tf tn tm vars locs,
      hs !! id = Some (HV_wov (WOV_funcref (Mk_funcidx i))) ->
      s.(s_funcs) !! i = Some cl ->
      cl = FC_func_host tf n e ->
      tf = Tf tn tm ->
      list_extra.those (fmap (fun id => hs !! id) ids) = Some vars ->
      length ids = length tn ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_host_frame tm (vars ++ List.repeat wasm_zero (length tm)) e)
*)
Lemma wp_call_host id ids hvs i s E P Q v tn tm n e:
  length ids = length hvs ->
  length ids = length tn ->
  (⌜ P =
     (id ↦ₕ HV_wov (WOV_funcref (Mk_funcidx i)) ∗
      N.of_nat i ↦₁ FC_func_host (Tf tn tm) n e ∗
      (∀ n idx, ⌜ ids !! n = Some idx ⌝ -∗ ∃ hv, ⌜ hvs !! n = Some hv ⌝ ∗ idx ↦ₕ hv)) ⌝) -∗
  {{{ P }}} (HE_host_frame tm (hvs ++ List.repeat wasm_zero (length tm)) e) @ s; E {{{ RET v; Q }}} -∗
  {{{ P }}} HE_call id ids @ s; E {{{ RET v; Q }}}.
Proof.
  move => HLen HLenType.
  iIntros "% #HhFrame" (Φ) "!> HP HΦ".
  subst.
  iDestruct "HP" as "[Hfref [Hfbody Hval]]".
  iApply wp_lift_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  iApply fupd_mask_intro; first by set_solver.
  iIntros "Hfupd".
  destruct σ1 as [[hs ws] locs].
  iSimpl in "Hσ".
  iDestruct "Hσ" as "[Hhs [? [Hwf ?]]]".
  iSplit.
  - iPureIntro.
    destruct s => //=.
    by apply he_call_reducible.
  - iIntros "!>" (e2 σ2 efs HStep).
    iMod "Hfupd".
    iDestruct (gen_heap_valid with "Hhs Hfref") as "%Hfref".
    iDestruct (gen_heap_valid with "Hwf Hfbody") as "%Hfbody".
    iAssert (∀ n idx, ⌜ids !! n = Some idx ⌝ -∗ ∃ hv, ⌜ hvs !! n = Some hv ⌝ ∗ ⌜ hs !! idx = Some hv ⌝)%I as "%Hval".
    { iIntros (n0 idx H).
      iSpecialize ("Hval" $! n0 idx H).
      iDestruct "Hval" as (hv) "[?Hid]".
      iExists hv.
      iFrame.
      by iDestruct (gen_heap_valid with "Hhs Hid") as "%".
    }
    rewrite gmap_of_list_lookup in Hfbody.
    rewrite Nat2N.id in Hfbody.
    iModIntro.
    inv_head_step; iFrame.
    + by rewrite Hfref in H10.
    + apply those_none in H10.
      resolve_finmap.
      apply Hval in Helem0.
      destruct Helem0 as [hv [Heqvs Heqhv]].
      by rewrite - Heq in Heqhv.
    + replace vars with hvs; first by iApply ("HhFrame" with "[Hfref Hfbody Hval]"); iFrame.
      apply list_eq. move => m.
      destruct (ids !! m) eqn:Hlookupid.
      * apply those_lookup with (n0 := m) in H10.
        rewrite list_lookup_fmap in H10.
        unfold option_map in H10.
        rewrite Hlookupid in H10.
        destruct (vars !! m) as [hv|] eqn:Hvars => //.
        simpl in H10.
        inversion H10; subst; clear H10.
        rewrite H0.
        apply Hval in Hlookupid.
        destruct Hlookupid as [hv' [Heqvs Heqhv]].
        rewrite Heqvs.
        rewrite - H0 in Heqhv.
        by inversion Heqhv; subst.
      * apply lookup_ge_None in Hlookupid.
        assert (length hvs <= m); first by rewrite HLen in Hlookupid.
        assert (hvs !! m = None) as Hvsn; first by apply lookup_ge_None.
        rewrite Hvsn; clear Hvsn.
        symmetry.
        apply lookup_ge_None.
        apply those_length in H10.
        rewrite fmap_length in H10.
        lia.
Qed.

(*
  (* wasm state exprs *)
  | pr_table_create:
    forall hs s locs s' tab len n,
      tab = create_table len ->
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables) ++ [::tab]; s_mems := s.(s_mems); s_globals := s.(s_globals) |} ->
      n = length s.(s_tables) ->
      pure_reduce hs s locs (HE_wasm_table_create len) hs s' locs (HE_value (HV_wov (WOV_tableref (Mk_tableidx n))))
 *)

Lemma wp_table_create len s E:
  ⊢
  (WP HE_wasm_table_create len @ s; E
  {{ fun v => match v with
           | HV_wov (WOV_tableref (Mk_tableidx n)) => ∀ (i:N), ⌜ (i < len)%N ⌝ -∗ N.of_nat n ↦₂[ i ] None
           | _ => False
           end
  }})%I.
Proof.
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  destruct σ1 as [[hs ws] locs].
  iSimpl in "Hσ".
  iDestruct "Hσ" as "[?[?[? [Hwt ?]]]]".
  iModIntro.
  iSplit.
  - iPureIntro.
    destruct s => //.
    apply hs_red_equiv.
    repeat eexists.
    by eapply pr_table_create.
  - iModIntro.
    iIntros (e2 σ2 efs HStep).
    destruct σ2 as [[hs2 ws2] locs2].
    inv_head_step.
    (* gen_heap_alloc_big allocates a chunk of heap at once, which is exactly what we need here.

       https://gitlab.mpi-sws.org/iris/iris/-/blob/master/iris/base_logic/lib/gen_heap.v

       We actually also get a 'meta_token' when allocating fresh resources in the heap, meaning
       that 'no meta data has been associated with the namespaces in the mask for the location'.
       Whatever that means, it does not seem to be needed here.

    *)
    iMod (gen_heap_alloc_big with "Hwt") as "(Hwt & Hl & Hm)".
    {
      unfold gmap_of_table.
      instantiate (1 := new_2d_gmap_at_n (N.of_nat (length ws.(s_tables))) (N.to_nat len) None).
      by apply gmap_of_table_append_disjoint.
    }
    iModIntro.
    iFrame.
    iSplitL "Hwt".
    + by rewrite gmap_of_table_append.
    + iSplit => //.
      iIntros (i) "%H".
      (* This is the correct usage of premises with big_sepM [∗ map] like this. Add a bit more
         comments in the future -- this will surely be forgotten in the future. *)
      iDestruct (big_sepM_lookup with "Hl") as "Hni" => //.
      apply new_2d_gmap_at_n_lookup.
      lia.
Qed.

Ltac simplify_lookup :=
  repeat match goal with
  | H: gmap_of_table _ !! _ = _ |- _ =>
       unfold gmap_of_table in H
  | H: gmap_of_memory _ !! _ = _ |- _ =>
       unfold gmap_of_memory in H
  | H: gmap_of_list_2d _ !! _ = _ |- _ =>
       rewrite gmap_of_list_2d_lookup in H
  | H: gmap_of_list_lookup _ !! _ = _ |- _ =>
       rewrite gmap_of_list_lookup in H
  | H: match ?term with
       | Some _ => _
       | None => None
       end = Some _ |- _ =>
       let Heq := fresh "Heq" in
       destruct term eqn: Heq => //
  | H: context C [N.of_nat (N.to_nat _)] |- _ =>
    rewrite N2Nat.id in H
  | H: context C [N.to_nat (N.of_nat _)] |- _ =>
    rewrite Nat2N.id in H
  end.

(*
  | pr_table_set:
    forall hs s locs idt n id v tn tab tab' s' fn,
      hs !! idt = Some (HV_wov (WOV_tableref (Mk_tableidx tn))) ->
      s.(s_tables) !! tn = Some tab ->
      hs !! id = Some v ->
      v = HV_wov (WOV_funcref (Mk_funcidx fn)) ->
      tab' = {|table_data := list_insert n (Some fn) tab.(table_data); table_max_opt := tab.(table_max_opt) |} ->
      s' = {|s_funcs := s.(s_funcs); s_tables := list_insert tn tab' s.(s_tables); s_mems := s.(s_mems); s_globals := s.(s_globals) |} ->
      pure_reduce hs s locs (HE_wasm_table_set idt (N_of_nat n) id) hs s' locs (HE_value v)
 *)
Lemma wp_table_set s E idt n id f fn tn:
  {{{ id ↦ₕ (HV_wov (WOV_funcref (Mk_funcidx fn))) ∗ idt ↦ₕ (HV_wov (WOV_tableref (Mk_tableidx tn))) ∗ (N.of_nat tn) ↦₂[ n ] f }}} HE_wasm_table_set idt n id @ s; E {{{ RET (HV_wov (WOV_funcref (Mk_funcidx fn))); id ↦ₕ (HV_wov (WOV_funcref (Mk_funcidx fn))) ∗ idt ↦ₕ (HV_wov (WOV_tableref (Mk_tableidx tn))) ∗ (N.of_nat tn) ↦₂[ n ] (Some fn) }}}.
Proof.
  iIntros (Φ) "[Hfuncref [Htableref Hfunc]] HΦ".
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  destruct σ1 as [[hs ws] locs].
  iDestruct "Hσ" as "[Hhs [? [? [Hwt ?]]]]".
  iDestruct (gen_heap_valid with "Hhs Hfuncref") as "%Hfuncref".
  iDestruct (gen_heap_valid with "Hhs Htableref") as "%Htableref".
  iDestruct (gen_heap_valid with "Hwt Hfunc") as "%Hfunc".
  simplify_lookup.
  rewrite list_lookup_fmap in Heq.
  destruct (s_tables _ !! _) eqn:Hlookup => //.
  simpl in Heq. inversion Heq. subst. clear Heq.
  iModIntro.
  iSplit.
  - iPureIntro.
    destruct s => //.
    apply hs_red_equiv.
    repeat eexists.
    eapply pr_table_set => //.
    unfold table_to_list in Hfunc.
    by apply lookup_lt_Some in Hfunc.
  - iIntros "!>" (e2 σ2 efs HStep).
    inv_head_step.
    iMod (gen_heap_update with "Hwt Hfunc") as "[Hwt Hfunc]".
    iModIntro.
    iFrame.
    erewrite gmap_of_table_insert => //; last by rewrite Nat2N.id.
    rewrite Nat2N.id.
    iFrame.
    iSplitL => //.
    iApply ("HΦ" with "[Hfuncref Htableref Hfunc]").
    by iFrame.
Qed.
  
(*
  | pr_table_get:
    forall hs s locs idt n tn tab fn,
      hs !! idt = Some (HV_wov (WOV_tableref (Mk_tableidx tn))) ->
      s.(s_tables) !! tn = Some tab ->
      tab.(table_data) !! n = Some (Some fn) ->
      pure_reduce hs s locs (HE_wasm_table_get idt (N_of_nat n)) hs s locs (HE_value (HV_wov (WOV_funcref (Mk_funcidx fn))))
 *)
Lemma wp_table_get s E id n fn tn:
  {{{ id ↦ₕ (HV_wov (WOV_tableref (Mk_tableidx tn))) ∗ (N.of_nat tn) ↦₂[ n ] (Some fn) }}} HE_wasm_table_get id n @ s; E {{{ RET (HV_wov (WOV_funcref (Mk_funcidx fn))); id ↦ₕ (HV_wov (WOV_tableref (Mk_tableidx tn))) ∗ (N.of_nat tn) ↦₂[ n ] (Some fn) }}}.
Proof.
  iIntros (Φ) "[Htableref Hfunc] HΦ".
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  destruct σ1 as [[hs ws] locs].
  iDestruct "Hσ" as "[Hhs [? [? [Hwt ?]]]]".
  iDestruct (gen_heap_valid with "Hhs Htableref") as "%Htableref".
  iDestruct (gen_heap_valid with "Hwt Hfunc") as "%Hfunc".
  simplify_lookup.
  rewrite list_lookup_fmap in Heq.
  destruct (s_tables _ !! _) eqn:Hlookup => //.
  simpl in Heq.
  inversion Heq; subst; clear Heq.
  iModIntro.
  iSplit.
  - iPureIntro.
    destruct s => //.
    apply hs_red_equiv.
    repeat eexists.
    by eapply pr_table_get.
  - iIntros "!>" (e2 σ2 efs HStep).
    inv_head_step.
    iModIntro.
    iFrame.
    iSplitL => //.
    iApply "HΦ".
    by iFrame.
Qed.

  (*
  | pr_memory_create:
    forall hs s locs s' sz sz_lim n,
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables); s_mems := s.(s_mems) ++ [::create_memory sz sz_lim]; s_globals := s.(s_globals) |} ->
      n = length s.(s_mems) ->
      pure_reduce hs s locs (HE_wasm_memory_create sz sz_lim) hs s' locs (HE_value (HV_wov (WOV_memoryref (Mk_memidx n))))
   *)

Lemma wp_memory_create sz sz_lim s E:
  ⊢
  (WP HE_wasm_memory_create sz sz_lim @ s; E
  {{ fun v => match v with
           | HV_wov (WOV_memoryref (Mk_memidx n)) => ∀ (i:N), ⌜ (i < sz)%N ⌝ -∗ N.of_nat n ↦₃[ i ] #00
           | _ => False
           end
  }})%I.
Proof.
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  destruct σ1 as [[hs ws] locs].
  iSimpl in "Hσ".
  iDestruct "Hσ" as "[?[?[? [? [Hwm ?]]]]]".
  iModIntro.
  iSplit.
  - iPureIntro.
    destruct s => //.
    apply hs_red_equiv.
    repeat eexists.
    by eapply pr_memory_create.
  - iModIntro.
    iIntros (e2 σ2 efs HStep).
    destruct σ2 as [[hs2 ws2] locs2].
    inv_head_step.
    iMod (gen_heap_alloc_big with "Hwm") as "(Hwm & Hl & Hm)".
    {
      instantiate (1 := new_2d_gmap_at_n (N.of_nat (length ws.(s_mems))) (N.to_nat sz) #00).
      by apply gmap_of_memory_append_disjoint.
    }
    iModIntro.
    iFrame.
    iSplitL "Hwm".
    + by rewrite gmap_of_memory_append.
    + iSplit => //.
      iIntros (i) "%H".
      iDestruct (big_sepM_lookup with "Hl") as "Hni" => //.
      rewrite new_2d_gmap_at_n_lookup => //.
      lia.
Qed.

(*  
  | pr_memory_set:
    forall hs s locs idm n id md' mn m m' s' b,
      hs !! idm = Some (HV_wov (WOV_memoryref (Mk_memidx mn))) ->
      s.(s_mems) !! mn = Some m ->
      hs !! id = Some (HV_byte b) ->
      memory_list.mem_update n b m.(mem_data) = Some md' ->
      m' = {|mem_data := md'; mem_max_opt := m.(mem_max_opt) |} ->
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables); s_mems := list_insert mn m' s.(s_mems); s_globals := s.(s_globals) |} ->
      pure_reduce hs s locs (HE_wasm_memory_set idm n id) hs s' locs (HE_value (HV_byte b))
 *)
Lemma wp_memory_set s E idm n id mn sb b:
  {{{ id ↦ₕ (HV_byte b) ∗ idm ↦ₕ (HV_wov (WOV_memoryref (Mk_memidx mn))) ∗ (N.of_nat mn) ↦₃[ n ] sb }}} HE_wasm_memory_set idm n id @ s; E {{{ RET (HV_byte b); id ↦ₕ (HV_byte b) ∗ idm ↦ₕ (HV_wov (WOV_memoryref (Mk_memidx mn))) ∗ (N.of_nat mn) ↦₃[ n ] b }}}.
Proof.
  iIntros (Φ) "[Hbyte [Hmemref Hmembyte]] HΦ".
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  destruct σ1 as [[hs ws] locs].
  iDestruct "Hσ" as "[Hhs [? [? [? [Hwm ?]]]]]".
  iDestruct (gen_heap_valid with "Hhs Hbyte") as "%Hbyte".
  iDestruct (gen_heap_valid with "Hhs Hmemref") as "%Hmemref".
  iDestruct (gen_heap_valid with "Hwm Hmembyte") as "%Hmembyte".
  simplify_lookup.
  rewrite list_lookup_fmap in Heq.
  destruct (s_mems _ !! _) eqn:Hlookup => //.
  simpl in Heq. inversion Heq. subst. clear Heq.
  iModIntro.
  iSplit.
  - iPureIntro.
    destruct s => //.
    apply hs_red_equiv.
    repeat eexists.
    eapply pr_memory_set => //.
    unfold memory_to_list in Hmembyte.
    unfold memory_list.mem_update => /=.
    destruct (n <? _)%N eqn:HLen => //.
    apply lookup_lt_Some in Hmembyte.
    exfalso.
    apply N.ltb_nlt in HLen.
    lia.
  - iIntros "!>" (e2 σ2 efs HStep).
    inv_head_step.
    iMod (gen_heap_update with "Hwm Hmembyte") as "[Hwm Hmembyte]".
    iModIntro.
    iFrame.
    erewrite gmap_of_memory_insert => //=.
    + unfold memory_list.mem_update in H10.
      rewrite Nat2N.id.
      iFrame.
      iSplitL => //.
      iApply ("HΦ" with "[Hbyte Hmemref Hmembyte]").
      by iFrame.
    + by rewrite Nat2N.id.
    + apply lookup_lt_Some in Hmembyte.
      by unfold memory_to_list in Hmembyte.
Qed.

(*
  | pr_memory_get:
    forall hs s locs idm n b m mn,
      hs !! idm = Some (HV_wov (WOV_memoryref (Mk_memidx mn))) ->
      s.(s_mems) !! mn = Some m ->
      memory_list.mem_lookup n m.(mem_data) = Some b ->
      pure_reduce hs s locs (HE_wasm_memory_get idm n) hs s locs (HE_value (HV_byte b))
 *)
Lemma wp_memory_get s E n id mn b:
  {{{ id ↦ₕ (HV_wov (WOV_memoryref (Mk_memidx mn))) ∗ (N.of_nat mn) ↦₃[ n ] b }}} HE_wasm_memory_get id n @ s; E {{{ RET (HV_byte b); id ↦ₕ (HV_wov (WOV_memoryref (Mk_memidx mn))) ∗ (N.of_nat mn) ↦₃[ n ] b }}}.
Proof.
  iIntros (Φ) "[Hmemoryref Hbyte] HΦ".
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  destruct σ1 as [[hs ws] locs].
  iDestruct "Hσ" as "[Hhs [? [? [? [Hwm ?]]]]]".
  iDestruct (gen_heap_valid with "Hhs Hmemoryref") as "%Hmemoryref".
  iDestruct (gen_heap_valid with "Hwm Hbyte") as "%Hbyte".
  simplify_lookup.
  rewrite list_lookup_fmap in Heq.
  destruct (s_mems _ !! _) eqn:Hlookup => //.
  simpl in Heq.
  inversion Heq; subst; clear Heq.
  iModIntro.
  iSplit.
  - iPureIntro.
    destruct s => //.
    apply hs_red_equiv.
    repeat eexists.
    eapply pr_memory_get; eauto.
    unfold memory_list.mem_lookup.
    by rewrite nth_error_lookup.
  - iIntros "!>" (e2 σ2 efs HStep).
    inv_head_step.
    iModIntro.
    iFrame.
    iSplitL => //.
    unfold memory_list.mem_lookup in H12.
    rewrite nth_error_lookup in H12.
    unfold memory_to_list in Hbyte.
    rewrite H12 in Hbyte.
    inversion Hbyte; subst; clear Hbyte.
    iApply "HΦ".
    by iFrame.
Qed.
(*
  | pr_memory_grow:
    forall hs s s' locs idm n m m' mn,
      hs !! idm = Some (HV_wov (WOV_memoryref (Mk_memidx mn))) ->
      s.(s_mems) !! mn = Some m ->
      mem_grow m n = Some m' ->
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables); s_mems := list_insert mn m' s.(s_mems); s_globals := s.(s_globals) |} ->
      pure_reduce hs s locs (HE_wasm_memory_grow idm n) hs s' locs (HE_value (HV_wasm_value (VAL_int32 (Wasm_int.int_of_Z i32m (Z.of_N (mem_size m'))))))
 *)
      
Lemma wp_memory_grow s E idm mn n:
  idm ↦ₕ (HV_wov (WOV_memoryref (Mk_memidx mn)))
  ⊢
  (WP HE_wasm_memory_grow idm n @ s; E
  {{ fun v => match v with
           | HV_wasm_value (VAL_int32 v') => ∃ (new_sz:N) (init_b: byte), (⌜ v' = Wasm_int.int_of_Z i32m (Z.of_N new_sz) ⌝ ∗ ∀ (i:N), ⌜ (i < new_sz * page_size)%N ⌝ -∗ ⌜ ((i + n * page_size)%N >= new_sz * page_size)%N ⌝  -∗ (N.of_nat mn) ↦₃[ i ] init_b)
           | HV_trap => True
           | _ => False     
           end
  }})%I.
Proof.
  iIntros "Hmemref".
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ !>".
  destruct σ1 as [[hs ws] locs].
  iDestruct "Hσ" as "[Hhs [? [? [? [Hwm ?]]]]]".
  iDestruct (gen_heap_valid with "Hhs Hmemref") as "%Hmemref".
  iSplit.
  - iPureIntro.
    destruct s => //.
    apply hs_red_equiv.
    repeat eexists.
    by eapply pr_memory_grow_fail_nondet; eauto.
  - iIntros "!>" (e2 [[hs' ws'] locs'] efs HStep).
    inv_head_step; last by iFrame.
    iMod (gen_heap_alloc_big with "Hwm") as "[Hwm [Hmembytes Htoken]]".
    {
      instantiate (1 := mem_grow_appendix m mn n).
      eapply mem_grow_appendix_disjoint; eauto.
      by eapply lookup_lt_Some.
    }
    iModIntro. iFrame.
    iSplitL "Hwm".
    + erewrite gmap_of_memory_grow; eauto.
      by eapply lookup_lt_Some.
    + iSplit => //.
      iExists (mem_size m'), m.(mem_data).(memory_list.ml_init).
      iSplit => //.
      iIntros (i) "%Hub %Hlb".
      iDestruct (big_sepM_lookup with "Hmembytes") as "Hni" => //.
      apply elem_of_list_to_map; resolve_finmap.
      * assert (x0 = x2); first lia.
        subst.
        rewrite Helem0 in Helem.
        by inversion Helem.
      * apply nodup_imap_inj1.
        move => n1 n2 t1 t2 Heq.
        inversion Heq.
        lia.
      * apply elem_of_lookup_imap.
        exists (N.to_nat (N.sub i (mem_size m * page_size))), m.(mem_data).(memory_list.ml_init).
        apply mem_grow_length in H7.
        unfold mem_size in Hlb.
        rewrite mem_length_divisible in Hlb.
        rewrite H7 in Hlb.
        assert (i >= mem_length m)%N; first lia.
        unfold mem_size.
        rewrite mem_length_divisible.
        split => //.
        -- repeat f_equal.
           rewrite N2Nat.id.
           lia.
        -- apply repeat_lookup.
           unfold mem_size in Hub.
           rewrite mem_length_divisible in Hub.
           lia.          
Qed.
(*
  | pr_globals_create:
    forall hs s locs s' g n,
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables); s_mems := s.(s_mems); s_globals := s.(s_globals) ++ [::g] |} ->
      n = length s.(s_globals) ->
      pure_reduce hs s locs (HE_wasm_global_create g) hs s' locs (HE_value (HV_wov (WOV_globalref (Mk_globalidx n))))
 *)
(*
  This one is more like new_host_func: we're only creating one item here, unlike table/memory 
    creation which creates a chunk of items at once.
*)
Lemma wp_glocal_create s E g:
  ⊢
  (WP HE_wasm_global_create g @ s; E
  {{ fun v => match v with
           | HV_wov (WOV_globalref (Mk_globalidx n)) => N.of_nat n ↦₄ g
           | _ => False
           end
  }})%I.
Proof.
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  destruct σ1 as [[hs ws] locs].
  iSimpl in "Hσ".
  iDestruct "Hσ" as "[?[?[? [? [? Hwg]]]]]".
  iModIntro.
  iSplit.
  - iPureIntro.
    destruct s => //.
    apply hs_red_equiv.
    repeat eexists.
    by apply pr_globals_create.
  - iModIntro.
    iIntros (e2 σ2 efs HStep).
    destruct σ2 as [[hs2 ws2] locs2].
    inv_head_step.
    iMod (gen_heap_alloc with "Hwg") as "(Hσ & Hl & Hm)".
    {
      instantiate (1 := N.of_nat (length ws.(s_globals))).
      rewrite gmap_of_list_lookup.
      rewrite Nat2N.id.
      by rewrite lookup_ge_None.
    }
    iModIntro.
    iFrame.
    by rewrite - gmap_of_list_append.
Qed.    
(*
  | pr_global_set:
    forall hs s locs gn idg id s' v g g',
      hs !! id = Some (HV_wasm_value v) ->
      hs !! idg = Some (HV_wov (WOV_globalref (Mk_globalidx gn))) ->
      s.(s_globals) !! gn = Some g ->
      g.(g_mut) = MUT_mut ->
      typeof v = typeof (g.(g_val)) ->
      g' = {|g_mut := MUT_mut; g_val := v|} ->
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables); s_mems := s.(s_mems); s_globals := list_insert gn g' s.(s_globals)|} ->
      pure_reduce hs s locs (HE_wasm_global_set idg id) hs s' locs (HE_value (HV_wasm_value v))
 *)
(*
  For this to succeed we need not only the full ownership of the global, but the mutability of the
    targetted global as well.
*)
Lemma wp_global_set idg id s E w v gn:
  w.(g_mut) = MUT_mut ->
  typeof v = typeof (w.(g_val)) ->
  {{{ id ↦ₕ HV_wasm_value v ∗ idg ↦ₕ HV_wov (WOV_globalref (Mk_globalidx gn)) ∗ (N.of_nat gn) ↦₄ w }}}
    HE_wasm_global_set idg id @ s; E
                                     {{{ RET (HV_wasm_value v); id ↦ₕ HV_wasm_value v ∗ idg ↦ₕ HV_wov (WOV_globalref (Mk_globalidx gn)) ∗ (N.of_nat gn) ↦₄ {|g_mut := MUT_mut; g_val := v|} }}}.
Proof.
  move => HMut HType.
  iIntros (Φ) "[Hwvalue [Hglobalref Hglobal]] HΦ".
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  destruct σ1 as [[hs ws] locs].
  iDestruct "Hσ" as "[Hhs [? [? [? [? Hwg]]]]]".
  iDestruct (gen_heap_valid with "Hhs Hwvalue") as "%Hwvalue".
  iDestruct (gen_heap_valid with "Hhs Hglobalref") as "%Hglobalref".
  iDestruct (gen_heap_valid with "Hwg Hglobal") as "%Hglobal".
  rewrite gmap_of_list_lookup in Hglobal.
  rewrite Nat2N.id in Hglobal.
  iModIntro.
  iSplit.
  - iPureIntro.
    destruct s => //.
    apply hs_red_equiv.
    repeat eexists.
    by eapply pr_global_set.
  - iIntros "!>" (e2 σ2 efs HStep).
    inv_head_step.
    iMod (gen_heap_update with "Hwg Hglobal") as "[Hwg Hglobal]".
    iModIntro.
    iFrame.
    rewrite - gmap_of_list_insert; last by apply lookup_lt_Some in Hglobal; lia.
    rewrite Nat2N.id.
    iFrame.
    iSplit => //.
    iApply ("HΦ" with "[Hwvalue Hglobalref Hglobal]").
    by iFrame.
Qed.

(*
  | pr_global_get:
    forall hs s locs idg g gn v,
      hs !! idg = Some (HV_wov (WOV_globalref (Mk_globalidx gn))) ->
      g.(g_val) = v ->
      pure_reduce hs s locs (HE_wasm_global_get idg) hs s locs (HE_value (HV_wasm_value v))
 *)
Lemma wp_global_get idg s E g gn:
  {{{ idg ↦ₕ HV_wov (WOV_globalref (Mk_globalidx gn)) ∗ (N.of_nat gn) ↦₄ g }}}
    HE_wasm_global_get idg @ s; E
  {{{ RET (HV_wasm_value g.(g_val)); idg ↦ₕ HV_wov (WOV_globalref (Mk_globalidx gn)) ∗ (N.of_nat gn) ↦₄ g }}}.
Proof.
  iIntros (Φ) "[Hglobalref Hglobal] HΦ".
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  destruct σ1 as [[hs ws] locs].
  iDestruct "Hσ" as "[Hhs [? [? [? [? Hwg]]]]]".
  iDestruct (gen_heap_valid with "Hhs Hglobalref") as "%Hglobalref".
  iDestruct (gen_heap_valid with "Hwg Hglobal") as "%Hglobal".
  rewrite gmap_of_list_lookup in Hglobal.
  rewrite Nat2N.id in Hglobal.
  iModIntro.
  iSplit.
  - iPureIntro.
    destruct s => //.
    apply hs_red_equiv.
    repeat eexists.
    by eapply pr_global_get.
  - iIntros "!>" (e2 σ2 efs HStep).
    inv_head_step.
    iModIntro.
    iFrame.
    iSplit => //.
    iApply ("HΦ" with "[Hglobalref Hglobal]").
    by iFrame.
Qed.

Lemma he_binop_reducible op id1 id2 hs ws locs:
  @reducible wasm_lang (HE_binop op id1 id2) (hs, ws, locs).
Proof.
  apply hs_red_equiv.
  destruct (hs !! id1) as [v1|] eqn:Hv1; last by eapply pr_binop_trap2 in Hv1; repeat eexists.
  destruct (hs !! id2) as [v2|] eqn:Hv2; last by eapply pr_binop_trap3 in Hv2; repeat eexists.
  destruct (host_value_to_wasm v1) as [wv1|] eqn:Hwv1 => //=; last by eapply pr_binop_trap4 in Hwv1; repeat eexists.
  destruct (host_value_to_wasm v2) as [wv2|] eqn:Hwv2 => //=; last by eapply pr_binop_trap5 in Hwv2; repeat eexists.
  unfold host_value_to_wasm in Hwv1, Hwv2.
  destruct v1, v2 => //.
  inversion Hwv1; subst; clear Hwv1.
  inversion Hwv2; subst; clear Hwv2.
  destruct (app_binop op wv1 wv2) eqn:Hbinop; [eapply pr_binop_success in Hbinop | eapply pr_binop_trap1 in Hbinop] => //; by repeat eexists.
Qed.
  
Lemma wp_binop s E op v1 v2 v id1 id2:
  app_binop op v1 v2 = Some v ->
  {{{ id1 ↦ₕ (HV_wasm_value v1) ∗ id2 ↦ₕ (HV_wasm_value v2) }}} HE_binop op id1 id2 @ s; E {{{ RET (HV_wasm_value v); id1 ↦ₕ (HV_wasm_value v1) ∗ id2 ↦ₕ (HV_wasm_value v2) }}}.
Proof.
  move => Hbinop.
  iIntros (Φ) "[Hv1 Hv2] HΦ".
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  destruct σ1 as [[hs ws] locs].
  iSimpl in "Hσ".
  iDestruct "Hσ" as "[Hhs ?]".
  iDestruct (gen_heap_valid with "Hhs Hv1") as "%Hv1".
  iDestruct (gen_heap_valid with "Hhs Hv2") as "%Hv2".
  iModIntro.
  iSplit.
  - iPureIntro.
    destruct s => //.
    by apply he_binop_reducible.
  - iIntros "!>" (e2 σ2 efs HStep) "!>".
    inv_head_step; iFrame; try iSplit => //.
    + iApply ("HΦ" with "[Hv1 Hv2]"); by iFrame.
    + by rewrite Hv1 in H11.
    + by rewrite Hv2 in H11.
Qed.

Lemma he_list_concat_reducible id1 id2 hs ws locs:
  @reducible wasm_lang (HE_list_concat id1 id2) (hs, ws, locs).
Proof.
  apply hs_red_equiv.
  destruct (hs !! id1) as [v1|] eqn:Hv1; last by eapply pr_list_concat_trap1 in Hv1; repeat eexists.
  destruct (hs !! id2) as [v2|] eqn:Hv2; last by eapply pr_list_concat_trap2 in Hv2; repeat eexists.
  destruct (host_typeof v1) as [t1|] eqn:Ht1 => //=; try destruct t1; try by eapply pr_list_concat_trap3 in Hv1; repeat eexists => //; rewrite Ht1.
  destruct (host_typeof v2) as [t2|] eqn:Ht2 => //=; try destruct t2; try by eapply pr_list_concat_trap4 in Hv2; repeat eexists => //; rewrite Ht2.
  destruct v1, v2 => //.
  repeat eexists.
  by eapply pr_list_concat.
Qed.

Lemma wp_list_concat s E l1 l2 id1 id2:
  {{{ id1 ↦ₕ (HV_list l1) ∗ id2 ↦ₕ (HV_list l2) }}} HE_list_concat id1 id2 @ s; E {{{ RET (HV_list (l1 ++ l2)); id1 ↦ₕ (HV_list l1) ∗ id2 ↦ₕ (HV_list l2) }}}.
Proof.
  iIntros (Φ) "[Hv1 Hv2] HΦ".
  iApply wp_lift_atomic_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  destruct σ1 as [[hs ws] locs].
  iSimpl in "Hσ".
  iDestruct "Hσ" as "[Hhs ?]".
  iDestruct (gen_heap_valid with "Hhs Hv1") as "%Hv1".
  iDestruct (gen_heap_valid with "Hhs Hv2") as "%Hv2".
  iModIntro.
  iSplit.
  - iPureIntro.
    destruct s => //.
    by apply he_list_concat_reducible.
  - iIntros "!>" (e2 σ2 efs HStep) "!>".
    inv_head_step; iFrame; try iSplit => //.
    + iApply ("HΦ" with "[Hv1 Hv2]"); by iFrame.
    + by rewrite Hv1 in H10.
    + by rewrite Hv2 in H10.
Qed.

(* Note that this is not actually true -- memory_grow is allowed to fail non-det. We
   need a way to deal with that. *)
Axiom wasm_reduce_deterministic: forall hs s f we hs1 s1 f1 we1 hs2 s2 f2 we2,
  wasm_reduce hs s f we hs1 s1 f1 we1 ->
  wasm_reduce hs s f we hs2 s2 f2 we2 ->
  (hs1, s1, f1, we1) = (hs2, s2, f2, we2).

Open Scope SEQ.
(*
  A bit ugly that we have to do these. Also it's worth note that we now have 3 different 
    list libraries: Coq.List, stdpp, and seq (ssreflect).
*)
Lemma cat_split {T: Type} (l1 l2 l: list T):
  l1 ++ l2 = l ->
  l1 = seq.take (length l1) l /\
  l2 = seq.drop (length l1) l.
Proof.
  move => HCat.
  rewrite - HCat.
  repeat rewrite length_is_size.
  rewrite take_size_cat => //.
  by rewrite drop_size_cat => //.
Qed.
  
Lemma v_to_e_split: forall vs l1 l2,
  l1 ++ l2 = v_to_e_list vs ->
  l1 = v_to_e_list (seq.take (length l1) vs) /\
  l2 = v_to_e_list (seq.drop (length l1) vs).
Proof.
  move => vs l1 l2 H.
  apply cat_split in H.
  destruct H as [H1 H2].
  rewrite v_to_e_take.
  rewrite v_to_e_drop => //.
Qed.
  
Lemma v_to_e_const2: forall vs l,
  l = v_to_e_list vs ->
  ¬ const_list l -> False.
Proof.
  move => vs l H HContra. subst.
  apply HContra.
  by apply v_to_e_is_const_list.
Qed.

Lemma v_to_e_injection vs1 vs2:
  v_to_e_list vs1 = v_to_e_list vs2 ->
  vs1 = vs2.
Proof.
  move: vs2.
  unfold v_to_e_list.
  induction vs1 => //=; move => vs2 H; destruct vs2 => //.
  simpl in H.
  inversion H; subst; clear H.
  apply IHvs1 in H2.
  by f_equal.
Qed.
  
Ltac resolve_v_to_e:=
  match goal with
  | H: _ ++ _ = v_to_e_list _ |- False =>
    let Hl1 := fresh "Hl1" in
    let Hl2 := fresh "Hl2" in
    apply v_to_e_split in H;
    destruct H as [Hl1 Hl2];
    try apply v_to_e_const2 in Hl1 => //; try apply v_to_e_const2 in Hl2 => //
  end.

Lemma v_to_e_list_irreducible: forall vs we,
  ¬ reduce_simple (v_to_e_list vs) we.
Proof.
  move => vs we HContra.
  inversion HContra; try do 5 (destruct vs => //); subst; try resolve_v_to_e.
  - apply lfilled_Ind_Equivalent in H0.
    inversion H0; subst; clear H0.
    by resolve_v_to_e.
Qed.
    
Lemma trap_irreducible: forall we,
  ¬ reduce_simple ([::AI_trap]) we.
Proof.
  move => we HContra.
  inversion HContra; try do 5 (destruct vs => //).
  subst.
  apply lfilled_Ind_Equivalent in H0.
  by inversion H0.
Qed.

Lemma wp_wasm_reduce_simple_det s E we we' Φ:
  reduce_simple we we' ->
  □WP HE_wasm_frame we' @ s; E {{ Φ }} ⊢
  □WP HE_wasm_frame we @ s; E {{ Φ }}.
Proof.
  move => HReduce.
  iIntros "#Hwp".
  iModIntro.
  iApply wp_lift_pure_step_no_fork.
  - move => σ1.
    destruct s => //.
    apply hs_red_equiv.
    destruct σ1 as [[hs ws] locs].
    repeat eexists.
    apply pr_wasm_frame.
    by apply wr_simple.
  - move => κ σ1 e2 σ2 efs HStep.
    inv_head_step => //.
    repeat split => //.
    f_equal.
    assert ((hs', s', empty_frame, we'0) = (hs, s0, empty_frame, we')) as HDet.
    { eapply wasm_reduce_deterministic => //.
      by apply wr_simple. }
    by inversion HDet.
  - iIntros "!>!>!>" (κ e2 efs σ HStep).
    inv_head_step.
    + by apply v_to_e_list_irreducible in HReduce.
    + by apply trap_irreducible in HReduce.
    + replace we' with we'0; first by iAssumption.
      eapply wr_simple in HReduce.
      eapply wasm_reduce_deterministic in H4 => //.
      by inversion H4.
Qed.

(*
| wr_call :
   forall s f i a hs,
     f.(f_inst).(inst_funcs) !! i = Some a ->
     wasm_reduce hs s f [::AI_basic (BI_call i)] hs s f [::AI_invoke a]
*)
Lemma wp_wasm_call: True.
Admitted.
(*
  | wr_invoke_native :
      forall a cl t1s t2s ts es ves vcs n m k zs s f f' i hs,
        s.(s_funcs) !! a = Some cl ->
        cl = FC_func_native i (Tf t1s t2s) ts es ->
        ves = v_to_e_list vcs ->
        length vcs = n ->
        length ts = k ->
        length t1s = n ->
        length t2s = m ->
        n_zeros ts = zs ->
        f'.(f_inst) = i ->
        f'.(f_locs) = vcs ++ zs ->
        wasm_reduce hs s f (ves ++ [::AI_invoke a]) hs s f [::AI_local m f' [::AI_basic (BI_block (Tf [::] t2s) es)]]
 *)

Lemma wr_wasm_invoke_native s E a inst t1s t2s ts es ves vcs zs m Q v:
  ves = v_to_e_list vcs ->
  length vcs = length t1s ->
  length t2s = m ->
  n_zeros ts = zs ->
  {{{ N.of_nat a ↦₁ FC_func_native inst (Tf t1s t2s) ts es }}} (HE_wasm_frame ([::AI_local m (Build_frame (vcs ++ zs) inst) [::AI_basic (BI_block (Tf [::] t2s) es)]])) @ s; E {{{ RET v; Q }}} ⊢
  {{{ N.of_nat a ↦₁ FC_func_native inst (Tf t1s t2s) ts es }}} (HE_wasm_frame (ves ++ [::AI_invoke a])) @ s; E {{{ RET v; Q }}}.
Proof.
  move => Hves HLen1 HLen2 Hnzero.
  iIntros "#Hprem" (Φ) "!> Hf HΦ".
  iApply wp_lift_step => //.
  iIntros (σ1 ns κ κs nt) "Hσ".
  destruct σ1 as [[hs ws] locs].
  iDestruct "Hσ" as "[? [? [Hwf ?]]]".
  iDestruct (gen_heap_valid with "Hwf Hf") as "%Hfuncref".
  rewrite gmap_of_list_lookup in Hfuncref.
  rewrite Nat2N.id in Hfuncref.
  iApply fupd_mask_intro; first by set_solver.
  iIntros "Hfupd".
  iSplit.
  - iPureIntro.
    destruct s => //.
    apply hs_red_equiv.
    repeat eexists.
    apply pr_wasm_frame.
    by eapply wr_invoke_native with (f' := Build_frame (vcs ++ zs) inst); eauto => //.
  - iIntros "!>" (e2 σ2 efs HStep).
    iMod "Hfupd".
    iModIntro.
    destruct σ2 as [[hs' ws'] locs'] => //=.
    inv_head_step; iFrame.
    + exfalso. symmetry in H4. by resolve_v_to_e.
    + by destruct vcs => //.
    + inversion H4; subst; clear H4 => //=; try do 5 (destruct vcs => //=).
      * admit. (* never happens *)
      * apply concat_cancel_last in H.
        destruct H.
        inversion H1; subst; clear H1.
        apply v_to_e_injection in H. subst.
        rewrite Hfuncref in H0.
        inversion H0; subst; clear H0.
        iFrame.
        replace f' with (Build_frame (vcs ++ n_zeros ts0) (f_inst f')); first by iApply ("Hprem" with ("Hf HΦ")).
        destruct f'.
        f_equal.
        by simpl in H13.
      * apply concat_cancel_last in H.
        destruct H.
        inversion H1; subst; clear H1.
        by rewrite Hfuncref in H0.
      * apply lfilled_Ind_Equivalent in H0.
        admit. (* never happens *)
Admitted.
(*
  | wr_invoke_host :
    (* TODO: check *)
    forall a cl e tf t1s t2s ves vcs m n s s' f hs hs' vs,
      s.(s_funcs) !! a = Some cl ->
      cl = FC_func_host tf n e ->
      tf = Tf t1s t2s ->
      ves = v_to_e_list vcs ->
      length vcs = n ->
      length t1s = n ->
      length t2s = m ->
      (* TODO: check if this is what we want *)
      fmap (fun x => HV_wasm_value x) vcs = vs ->
      wasm_reduce hs s f (ves ++ [::AI_invoke a]) hs' s' f [::AI_host_frame t1s vs e]
*)
End lifting.
