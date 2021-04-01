(** Iris bindings **)
(* (C) J. Pichon, M. Bodin - see LICENSE.txt *)

From mathcomp Require Import ssreflect ssrbool eqtype seq.

(* There is a conflict between ssrnat and Iris language. *)
(* Also a conflict between ssrnat and stdpp on the notation .* *)
From iris.program_logic Require Import ectx_lifting total_ectx_lifting.
From iris.program_logic Require Import language ectx_language ectxi_language.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Require Import common operations datatypes datatypes_properties opsem interpreter binary_format_parser.

From stdpp Require Import gmap.
From iris.proofmode Require Import tactics.
From iris.algebra Require Import auth.
From iris.bi.lib Require Import fractional.
From iris.base_logic.lib Require Export gen_heap proph_map gen_inv_heap.
From iris.program_logic Require Export weakestpre total_weakestpre.
From iris.heap_lang Require Import locations.

Definition expr := host_expr.
Definition val := host_value.
(* We have to overwrite the definition here for Iris's usage of gmap for heaps. *)
Definition host_state := gmap id (option val).
Definition state : Type := host_state * store_record * (list host_value).
Definition observation := unit. (* TODO: ??? *)

Definition of_val (v : val) : expr := HE_value v.

Fixpoint to_val (e : expr) : option val :=
  match e with
  | HE_value v => Some v
  | _ => None
  end.

(* https://softwarefoundations.cis.upenn.edu/qc-current/Typeclasses.html *)
Global Instance val_eq_dec : EqDecision val.
Proof. decidable_equality. Defined.

Inductive pure_reduce : host_state -> store_record -> list host_value -> host_expr ->
                        host_state -> store_record -> list host_value -> host_expr -> Prop :=
  (* TODO: basic exprs -- arith ops, list ops left *)
  | pr_getglobal:
      forall hs s locs id hv ,
      (* Upd: ok it does make sense for the lookup result to carry a double Some, since
           gmap lookup itself returns an option.

         After some thoughts, this double option should be allowing us a way to know that 
           a memory is actually freed -- so we can distinguish between what we don't know and
           what we know to be non-existent.

         Also, the error message from the Lookup typeclass doesn't point to a specific line.. *)
      hs !! id = Some (Some hv) ->
      pure_reduce hs s locs (HE_getglobal id) hs s locs (HE_value hv)
  | pr_getglobal_trap:
    forall hs s locs id,
      hs !! id = None ->
      pure_reduce hs s locs (HE_getglobal id) hs s locs (HE_value HV_trap)
  | pr_setglobal_value:
    forall hs s locs id hv hs',
      hv <> HV_trap ->
      hs' = <[id := Some hv]> hs ->
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
      List.nth_error locs (nat_of_N n) = Some hv ->
      pure_reduce hs s locs (HE_getlocal n) hs s locs (HE_value hv)
  | pr_getlocal_trap:
    forall hs s locs n,
      List.nth_error locs (nat_of_N n) = None ->
      pure_reduce hs s locs (HE_getlocal n) hs s locs (HE_value HV_trap)
  | pr_setlocal:
    forall hs s locs n id locs' hv hvd,
      hs !! id = Some (Some hv) ->
      (nat_of_N n) < length locs ->
      locs' = set_nth hvd locs (nat_of_N n) hv ->
      pure_reduce hs s locs (HE_setlocal n id) hs s locs' (HE_value hv)
  | pr_setlocal_trap1:
    forall hs s locs n id,
      hs !! id = None ->
      pure_reduce hs s locs (HE_setlocal n id) hs s locs (HE_value HV_trap)
  | pr_setlocal_trap2:
    forall hs s locs n id hv,
      hs !! id = Some (Some hv) ->
      (nat_of_N n) >= length locs ->
      pure_reduce hs s locs (HE_setlocal n id) hs s locs (HE_value HV_trap)
  | pr_if_true:
    forall hs s locs id e1 e2 hv,
      hs !! id = Some (Some hv) ->
      hv <> HV_wasm_value (VAL_int32 (Wasm_int.int_zero i32m)) ->
      pure_reduce hs s locs (HE_if id e1 e2) hs s locs e1
  | pr_if_false: 
    forall hs s locs id e1 e2 hv,
      hs !! id = Some (Some hv) ->
      hv = HV_wasm_value (VAL_int32 (Wasm_int.int_zero i32m)) ->
      pure_reduce hs s locs (HE_if id e1 e2) hs s locs e2
  | pr_if_trap: 
    forall hs s locs id e1 e2,
      hs !! id = None ->
      pure_reduce hs s locs (HE_if id e1 e2) hs s locs (HE_value HV_trap)
  | pr_while:
    forall hs s locs id e,
      pure_reduce hs s locs (HE_while id e) hs s locs (HE_if id (HE_seq e (HE_while id e)) (HE_value (HV_wasm_value (VAL_int32 (Wasm_int.int_zero i32m)))))
  (* record exprs *)
  | pr_new_rec:
    forall hs s locs kip hvs kvp,
      list_extra.those2 (map (fun id => hs !! id) (unzip2 kip)) = Some hvs ->
      zip (unzip1 kip) hvs = kvp ->
      pure_reduce hs s locs (HE_new_rec kip) hs s locs (HE_value (HV_record kvp))
  | pr_new_rec_trap:
    forall hs s locs kip,
      list_extra.those (map (fun id => hs !! id) (unzip2 kip)) = None ->
      pure_reduce hs s locs (HE_new_rec kip) hs s locs (HE_value HV_trap)
  | pr_getfield:
    forall hs s locs id fname kvp hv,
      hs !! id = Some (Some (HV_record kvp)) ->
      getvalue_kvp kvp fname = Some hv ->
      pure_reduce hs s locs (HE_get_field id fname) hs s locs (HE_value hv)
  | pr_getfield_trap1:
    forall hs s locs id fname kvp,
      hs !! id = Some (Some (HV_record kvp)) ->
      getvalue_kvp kvp fname = None ->
      pure_reduce hs s locs (HE_get_field id fname) hs s locs (HE_value HV_trap)
  | pr_getfield_trap2:
    forall hs s locs id fname hv,
      hs !! id = Some (Some hv) ->
      host_typeof hv <> Some HT_record ->
      pure_reduce hs s locs (HE_get_field id fname) hs s locs (HE_value HV_trap)
  | pr_getfield_trap3:
    forall hs s locs id fname,
      hs !! id = None ->
      pure_reduce hs s locs (HE_get_field id fname) hs s locs (HE_value HV_trap)
  (* function exprs *)
  | pr_new_host_func:
    forall hs s locs htf locsn e s' n,
      s' = {|s_funcs := s.(s_funcs) ++ [::FC_func_host htf locsn e]; s_tables := s.(s_tables); s_mems := s.(s_mems); s_globals := s.(s_globals) |} ->
      n = length s.(s_funcs) ->
      pure_reduce hs s locs (HE_new_host_func htf (N_of_nat locsn) e) hs s' locs (HE_value (HV_wov (WOV_funcref (Mk_funcidx n))))
  | pr_call_wasm:
    forall hs s ids cl id i j vts bes tf vs tn tm vars locs,
      hs !! id = Some (Some (HV_wov (WOV_funcref (Mk_funcidx i)))) ->
      List.nth_error s.(s_funcs) i = Some cl ->
      cl = FC_func_native j tf vts bes ->
      tf = Tf tn tm ->
      list_extra.those2 (map (fun id => hs !! id) ids) = Some vars ->
      list_host_value_to_wasm vars = Some vs ->
      tn = map typeof vs ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_wasm_frame ((v_to_e_list vs) ++ [::AI_invoke i]))
  | pr_call_trap1:
    forall hs s locs id ids,
      hs !! id = None ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_value HV_trap)
  | pr_call_trap2:
    forall hs s locs id ids v,
      hs !! id = Some (Some v) ->
      is_funcref v = false ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_value HV_trap)
  | pr_call_trap3:
    forall hs s locs id ids i,
      hs !! id = Some (Some (HV_wov (WOV_funcref (Mk_funcidx i)))) ->
      List.nth_error s.(s_funcs) i = None ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_value HV_trap)  
  | pr_call_trap4:
    forall hs s locs id ids,
      list_extra.those2 (map (fun id => hs !! id) ids) = None ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_value HV_trap)
  | pr_call_wasm_trap1:
    forall hs s locs id ids i cl j tf vts bes vars tn tm,
      hs !! id = Some (Some (HV_wov (WOV_funcref (Mk_funcidx i)))) ->
      List.nth_error s.(s_funcs) i = Some cl ->
      cl = FC_func_native j tf vts bes ->
      tf = Tf tn tm ->
      list_extra.those2 (map (fun id => hs !! id) ids) = Some vars ->
      list_host_value_to_wasm vars = None ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_value HV_trap)  
  | pr_call_wasm_trap2:
    forall hs s locs id ids i cl j tf vts bes vars tn tm vs,
      hs !! id = Some (Some (HV_wov (WOV_funcref (Mk_funcidx i)))) ->
      List.nth_error s.(s_funcs) i = Some cl ->
      cl = FC_func_native j tf vts bes ->
      tf = Tf tn tm ->
      list_extra.those2 (map (fun id => hs !! id) ids) = Some vars ->
      list_host_value_to_wasm vars = Some vs ->
      tn <> map typeof vs ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_value HV_trap)  
  | pr_call_host:
    forall hs s ids cl id i n e tf tn tm vars vs locs,
      hs !! id = Some (Some (HV_wov (WOV_funcref (Mk_funcidx i)))) ->
      List.nth_error s.(s_funcs) i = Some cl ->
      cl = FC_func_host tf n e ->
      tf = Tf tn tm ->
      list_extra.those2 (map (fun id => hs !! id) ids) = Some vars ->
      list_host_value_to_wasm vars = Some vs -> (* TODO: change this to explicit casts, then add a trap case. *)
      tn = map typeof vs ->
      pure_reduce hs s locs (HE_call id ids) hs s locs (HE_wasm_frame ((v_to_e_list vs) ++ [::AI_invoke i]))
  (* wasm state exprs *)
  | pr_table_create:
    forall hs s locs s' tab len n,
      tab = create_table len ->
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables) ++ [::tab]; s_mems := s.(s_mems); s_globals := s.(s_globals) |} ->
      n = length s.(s_tables) ->
      pure_reduce hs s locs (HE_wasm_table_create len) hs s' locs (HE_value (HV_wov (WOV_tableref (Mk_tableidx n))))
  | pr_table_set:
    forall hs s locs idt n id v tn tab tab' s' tabd fn hvd,
      hs !! idt = Some (Some (HV_wov (WOV_tableref (Mk_tableidx tn)))) ->
      List.nth_error s.(s_tables) tn = Some tab ->
      hs !! id = Some (Some v) ->
      v = HV_wov (WOV_funcref (Mk_funcidx fn)) ->
      tab' = {|table_data := set_nth hvd tab.(table_data) n (Some fn); table_max_opt := tab.(table_max_opt) |} ->
      s' = {|s_funcs := s.(s_funcs); s_tables := set_nth tabd s.(s_tables) tn tab'; s_mems := s.(s_mems); s_globals := s.(s_globals) |} ->
      pure_reduce hs s locs (HE_wasm_table_set idt (N_of_nat n) id) hs s' locs (HE_value v)
  | pr_table_get:
    forall hs s locs idt n tn tab fn,
      hs !! idt = Some (Some (HV_wov (WOV_tableref (Mk_tableidx tn)))) ->
      List.nth_error s.(s_tables) tn = Some tab ->
      List.nth_error tab.(table_data) n = Some (Some fn) ->
      pure_reduce hs s locs (HE_wasm_table_get idt (N_of_nat n)) hs s locs (HE_value (HV_wov (WOV_funcref (Mk_funcidx fn))))
  | pr_memory_create:
    forall hs s locs s' sz sz_lim n,
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables); s_mems := s.(s_mems) ++ [::create_memory sz sz_lim]; s_globals := s.(s_globals) |} ->
      n = length s.(s_mems) ->
      pure_reduce hs s locs (HE_wasm_memory_create sz sz_lim) hs s' locs (HE_value (HV_wov (WOV_memoryref (Mk_memidx n))))
  | pr_memory_set:
    forall hs s locs idm n id mn m m' md' s' memd b,
      hs !! idm = Some (Some (HV_wov (WOV_memoryref (Mk_memidx mn)))) ->
      List.nth_error s.(s_mems) mn = Some m ->
      hs !! id = Some (Some (HV_byte b)) ->
      memory_list.mem_update n b m.(mem_data) = Some md' ->
      m' = {|mem_data := md'; mem_max_opt := m.(mem_max_opt) |} ->
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables); s_mems := set_nth memd s.(s_mems) mn m'; s_globals := s.(s_globals) |} ->
      pure_reduce hs s locs (HE_wasm_memory_set idm n id) hs s' locs (HE_value (HV_byte b))
  | pr_memory_get:
    forall hs s locs idm n b m mn,
      hs !! idm = Some (Some (HV_wov (WOV_memoryref (Mk_memidx mn)))) ->
      List.nth_error s.(s_mems) mn = Some m ->
      memory_list.mem_lookup n m.(mem_data) = Some b ->
      pure_reduce hs s locs (HE_wasm_memory_get idm n) hs s locs (HE_value (HV_byte b))
  | pr_memory_grow:
    forall hs s s' locs idm n m m' mn memd,
      hs !! idm = Some (Some (HV_wov (WOV_memoryref (Mk_memidx mn)))) ->
      List.nth_error s.(s_mems) mn = Some m ->
      mem_grow m n = Some m' ->
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables); s_mems := set_nth memd s.(s_mems) mn m'; s_globals := s.(s_globals) |} ->
      pure_reduce hs s locs (HE_wasm_memory_grow idm n) hs s' locs (HE_value (HV_wasm_value (VAL_int32 (Wasm_int.int_of_Z i32m (Z.of_N (mem_size m'))))))
  | pr_globals_create:
    forall hs s locs s' g n,
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables); s_mems := s.(s_mems); s_globals := s.(s_globals) ++ [::g] |} ->
      n = length s.(s_globals) ->
      pure_reduce hs s locs (HE_wasm_global_create g) hs s' locs (HE_value (HV_wov (WOV_globalref (Mk_globalidx n))))
  | pr_global_set:
    forall hs s locs gn idg id s' v g g' gd,
      hs !! id = Some (Some (HV_wasm_value v)) ->
      hs !! idg = Some (Some (HV_wov (WOV_globalref (Mk_globalidx gn)))) ->
      List.nth_error s.(s_globals) gn = Some g ->
      g.(g_mut) = MUT_mut ->
      typeof v = typeof (g.(g_val)) ->
      g' = {|g_mut := MUT_mut; g_val := v|} ->
      s' = {|s_funcs := s.(s_funcs); s_tables := s.(s_tables); s_mems := s.(s_mems); s_globals := set_nth gd s.(s_globals) gn g'|} ->
      pure_reduce hs s locs (HE_wasm_global_set idg id) hs s' locs (HE_value (HV_wasm_value v))
  | pr_global_get:
    forall hs s locs idg g gn v,
      hs !! idg = Some (Some (HV_wov (WOV_globalref (Mk_globalidx gn)))) ->
      g.(g_val) = v ->
      pure_reduce hs s locs (HE_wasm_global_get idg) hs s locs (HE_value (HV_wasm_value v))
  (* wasm module expr *)
  | pr_compile:
    forall hs s locs id mo hvl hbytes,
      hs !! id = Some (Some (HV_list hvl)) ->
      to_bytelist hvl = Some hbytes ->
      run_parse_module (map byte_of_compcert_byte hbytes) = Some mo -> (* Check: is this correct? *)
      pure_reduce hs s locs (HE_compile id) hs s locs (HE_value (HV_module mo))
  (* TODO: replace the proxy *)
  | pr_instantiate:
    forall hs s locs idm idr mo r rec,
      hs !! idm = Some (Some (HV_module mo)) ->
      hs !! idr = Some (Some (HV_record r)) ->
      pure_reduce hs s locs (HE_instantiate idm idr) hs s locs rec
  (* miscellaneous *)
  | pr_seq_const:
    forall hs s locs v e,
      pure_reduce hs s locs (HE_seq (HE_value v) e) hs s locs e
  | pr_wasm_return:
    forall hs s locs vs,      
      pure_reduce hs s locs (HE_wasm_frame (v_to_e_list vs)) hs s locs (HE_value (HV_list (map (fun wv => (HV_wasm_value wv)) vs)))
  | pr_wasm_return_trap:
      forall hs s locs,
      pure_reduce hs s locs (HE_wasm_frame ([::AI_trap])) hs s locs (HE_value (HV_trap))
  | pr_host_return:
    forall hs s locsf locs ids e vs tn,
      list_extra.those2 (map (fun id => hs !! id) ids) = Some vs ->
      pure_reduce hs s locsf (HE_host_frame tn locs (HE_seq (HE_return ids) e)) hs s locsf (HE_value (HV_list vs))
   

(* TODO: needs all the host_expr reduction steps: compile, instantiate, etc. *)
(* TODO: needs restructuring to make sense *)
with wasm_reduce : host_state -> store_record -> datatypes.frame -> list administrative_instruction ->
                   host_state -> store_record -> datatypes.frame -> list administrative_instruction -> Prop :=
  | wr_simple :
      forall e e' s f hs,
        reduce_simple e e' ->
        wasm_reduce hs s f e hs s f e'

  (** calling operations **)
  | wr_call :
      forall s f i a hs,
        List.nth_error f.(f_inst).(inst_funcs) i = Some a ->
        wasm_reduce hs s f [::AI_basic (BI_call i)] hs s f [::AI_invoke a]
  | wr_call_indirect_success :
      forall s f i a cl tf c hs,
        stab_addr s f (Wasm_int.nat_of_uint i32m c) = Some a ->
        List.nth_error s.(s_funcs) a = Some cl ->
        cl_type cl = Some tf ->
        stypes s f.(f_inst) i = Some tf ->
        wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 c)); AI_basic (BI_call_indirect i)] hs s f [::AI_invoke a]
  | wr_call_indirect_failure1 :
      forall s f i a cl tf c hs,
        stab_addr s f (Wasm_int.nat_of_uint i32m c) = Some a ->
        List.nth_error s.(s_funcs) a = Some cl ->
        cl_type cl = Some tf ->
        stypes s f.(f_inst) i <> Some tf ->
        wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 c)); AI_basic (BI_call_indirect i)] hs s f [::AI_trap]
  | wr_call_indirect_failure2 :
      forall s f i c hs,
        stab_addr s f (Wasm_int.nat_of_uint i32m c) = None ->
        wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 c)); AI_basic (BI_call_indirect i)] hs s f [::AI_trap]
  | wr_invoke_native :
      forall a cl t1s t2s ts es ves vcs n m k zs s f f' i hs,
        List.nth_error s.(s_funcs) a = Some cl ->
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
      List.nth_error s.(s_funcs) a = Some cl ->
      cl = FC_func_host tf n e ->
      tf = Tf t1s t2s ->
      ves = v_to_e_list vcs ->
      length vcs = n ->
      length t1s = n ->
      length t2s = m ->
      (* TODO: check if this is what we want *)
      map (fun x => HV_wasm_value x) vcs = vs ->
      wasm_reduce hs s f (ves ++ [::AI_invoke a]) hs' s' f [::AI_host_frame t1s vs e]

  | wr_host_step :
    (* TODO: check *)
    forall hs s (f : datatypes.frame) ts vs e hs' s' vs' e',
      pure_reduce hs s vs e hs' s' vs' e' ->
        wasm_reduce hs s f [::AI_host_frame ts vs e] hs' s' f [::AI_host_frame ts vs' e']
  | wr_host_return :
    (* TODO: check *)
    forall hs s f ts vs ids vs' vs'',
    list_extra.those2 (map (fun id => hs !! id) ids) = Some vs' ->
    Some vs'' = list_extra.those (List.map (fun x => match x with | HV_wasm_value v => Some v | _ => None end) vs') ->
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
        List.nth_error f.(f_locs) j = Some v ->
        wasm_reduce hs s f [::AI_basic (BI_get_local j)] hs s f [::AI_basic (BI_const v)]
  | wr_set_local :
      forall f f' i v s vd hs,
        f'.(f_inst) = f.(f_inst) ->
        f'.(f_locs) = set_nth vd f.(f_locs) i v ->
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
      List.nth_error s.(s_mems) i = Some m ->
      load m (Wasm_int.N_of_uint i32m k) off (t_length t) = Some bs ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_load t None a off)] hs s f [::AI_basic (BI_const (wasm_deserialise bs t))]
  | wr_load_failure :
    forall s i f t k a off m hs,
      smem_ind s f.(f_inst) = Some i ->
      List.nth_error s.(s_mems) i = Some m ->
      load m (Wasm_int.N_of_uint i32m k) off (t_length t) = None ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_load t None a off)] hs s f [::AI_trap]
  | wr_load_packed_success :
    forall s i f t tp k a off m bs sx hs,
      smem_ind s f.(f_inst) = Some i ->
      List.nth_error s.(s_mems) i = Some m ->
      load_packed sx m (Wasm_int.N_of_uint i32m k) off (tp_length tp) (t_length t) = Some bs ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_load t (Some (tp, sx)) a off)] hs s f [::AI_basic (BI_const (wasm_deserialise bs t))]
  | wr_load_packed_failure :
    forall s i f t tp k a off m sx hs,
      smem_ind s f.(f_inst) = Some i ->
      List.nth_error s.(s_mems) i = Some m ->
      load_packed sx m (Wasm_int.N_of_uint i32m k) off (tp_length tp) (t_length t) = None ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_load t (Some (tp, sx)) a off)] hs s f [::AI_trap]
  | wr_store_success :
    forall t v s i f mem' k a off m hs,
      types_agree t v ->
      smem_ind s f.(f_inst) = Some i ->
      List.nth_error s.(s_mems) i = Some m ->
      store m (Wasm_int.N_of_uint i32m k) off (bits v) (t_length t) = Some mem' ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_const v); AI_basic (BI_store t None a off)] hs (upd_s_mem s (update_list_at s.(s_mems) i mem')) f [::]
  | wr_store_failure :
    forall t v s i f m k off a hs,
      types_agree t v ->
      smem_ind s f.(f_inst) = Some i ->
      List.nth_error s.(s_mems) i = Some m ->
      store m (Wasm_int.N_of_uint i32m k) off (bits v) (t_length t) = None ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_const v); AI_basic (BI_store t None a off)] hs s f [::AI_trap]
  | wr_store_packed_success :
    forall t v s i f m k off a mem' tp hs,
      types_agree t v ->
      smem_ind s f.(f_inst) = Some i ->
      List.nth_error s.(s_mems) i = Some m ->
      store_packed m (Wasm_int.N_of_uint i32m k) off (bits v) (tp_length tp) = Some mem' ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_const v); AI_basic (BI_store t (Some tp) a off)] hs (upd_s_mem s (update_list_at s.(s_mems) i mem')) f [::]
  | wr_store_packed_failure :
    forall t v s i f m k off a tp hs,
      types_agree t v ->
      smem_ind s f.(f_inst) = Some i ->
      List.nth_error s.(s_mems) i = Some m ->
      store_packed m (Wasm_int.N_of_uint i32m k) off (bits v) (tp_length tp) = None ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 k)); AI_basic (BI_const v); AI_basic (BI_store t (Some tp) a off)] hs s f [::AI_trap]

  (** memory **)
  | wr_current_memory :
      forall i f m n s hs,
        smem_ind s f.(f_inst) = Some i ->
        List.nth_error s.(s_mems) i = Some m ->
        mem_size m = n ->
        wasm_reduce hs s f [::AI_basic (BI_current_memory)] hs s f [::AI_basic (BI_const (VAL_int32 (Wasm_int.int_of_Z i32m (Z.of_N n))))]
  | wr_grow_memory_success :
    forall s i f m n mem' c hs,
      smem_ind s f.(f_inst) = Some i ->
      List.nth_error s.(s_mems) i = Some m ->
      mem_size m = n ->
      mem_grow m (Wasm_int.N_of_uint i32m c) = Some mem' ->
      wasm_reduce hs s f [::AI_basic (BI_const (VAL_int32 c)); AI_basic BI_grow_memory] hs (upd_s_mem s (update_list_at s.(s_mems) i mem')) f [::AI_basic (BI_const (VAL_int32 (Wasm_int.int_of_Z i32m (Z.of_N n))))]
  | wr_grow_memory_failure :
      forall i f m n s c hs,
        smem_ind s f.(f_inst) = Some i ->
        List.nth_error s.(s_mems) i = Some m ->
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

Inductive head_reduce: state -> expr -> state -> expr -> Prop :=
  | purer_headr:
    forall hs s locs e hs' s' locs' e',
      pure_reduce hs s locs e hs' s' locs' e' ->
      head_reduce (hs, s, locs) e (hs', s', locs') e'.

Definition head_step (e : expr) (s : state) (os : list observation) (e' : expr) (s' : state) (es' : list expr) : Prop :=
  head_reduce s e s' e' /\
  os = nil /\
  es' = nil. (* ?? *) 

Lemma of_to_val e v : to_val e = Some v → of_val v = e.
Proof.
  destruct e => //=.
  move => H. by inversion H.
Qed.

Lemma head_step_not_val: forall e1 σ1 κ e2 σ2 efs,
  head_step e1 σ1 κ e2 σ2 efs ->
  to_val e1 = None.
Proof.
  move => e1 σ1 κ e2 σ2 efs H.
  destruct H as [HR _].
  inversion HR as [hs s locs e hs' s' locs' e' H]; subst.
  by inversion H.
Qed.

(* empty definitions just to enable the tactics in EctxiLanguageMixin as almost all prebuilt
     tactics could only work for EctxilanguageMixin*)
Inductive ectx_item := .

Fixpoint fill_item (Ki: ectx_item) (e: expr) : expr := e.

Lemma wasm_mixin : EctxiLanguageMixin of_val to_val fill_item head_step.
Proof.
  split => //.
  - by apply of_to_val.
  - by apply head_step_not_val.
Qed.

(* binary parser also has a Language definition. *)
Canonical Structure wasm_ectxi_lang := EctxiLanguage wasm_mixin.
Canonical Structure wasm_ectx_lang := EctxLanguageOfEctxi wasm_ectxi_lang.
Canonical Structure wasm_lang := LanguageOfEctx wasm_ectx_lang.

Definition proph_id := unit. (* ??? *)

Class heapG Σ := HeapG {
  heapG_invG : invG Σ;
  heapG_gen_heapG :> gen_heapG id (option val) Σ;
  heapG_proph_mapG :> proph_mapG proph_id (val * val) Σ;
}.

(* Only considering the host variable store for now *)
Definition gmap_of_state (σ : state) : gmap id (option val) :=
  let (hss, locs) := σ in let (hs, s) := hss in hs.

Instance heapG_irisG `{!heapG Σ} : irisG wasm_lang Σ := {
  iris_invG := heapG_invG;
  state_interp σ κs _ := gen_heap_ctx (gmap_of_state σ);
  fork_post z := True%I;
}.

Notation "l ↦ { q } v" := (mapsto (L:=id) (V:=option val) l q (Some v%V))
  (at level 20, q at level 5, format "l  ↦ { q } v") : bi_scope.

Section lifting.

Context `{!heapG Σ}.

Implicit Types σ : state.

  Ltac inv_head_step :=
    repeat match goal with
    | _ => progress simplify_map_eq/= (* simplify memory stuff *)
    | H : to_val _ = Some _ |- _ => apply of_to_val in H
    | H : head_step ?e _ _ _ _ _ |- _ =>
       try (is_var e; fail 1); (* inversion yields many goals if [e] is a variable
       and can thus better be avoided. *)
       inversion H; subst; clear H
    | H : head_reduce _ _ _ _ |- _ =>
      inversion H => //; subst; clear H;
      lazymatch goal with
      | H : pure_reduce _ _ _ _ _ _ _ _ |- _ =>
        inversion H => //; subst; clear H
      | _ => fail 2
      end
    | H : _ = [] /\ _ = [] |- _ =>
       destruct H
           end.

(* See if this works *)
Lemma twp_getglobal s E id q v:
  [[{ id ↦ { q } v }]] HE_getglobal id @ s; E
  [[{ RET v; id ↦ { q } v }]].
Proof.
  (* https://gitlab.mpi-sws.org/iris/iris/blob/master/docs/proof_mode.md *)
  iStartProof.
  (*
    By doing iStartProof we can see that the triple [[{ P }]] e @ s; E [[{ Q }]] is defined as
    forall x: val -> iPropI Σ, P -* (Q -* x v) -* WP e @ s; E [{ v, x v }].
    x should be thought of as an arbitrary proposition on a value v. So this roughly reads:

    For any proposition Φ on v, if we're on a state where P holds, and Q could imply Φ v, then 
      if we execute e and get v back then Φ v holds.
   *)
  (*
    This iIntros introduces the proposition Φ into Coq context and the two 'ifs' (by wands) into
      Iris context and call them Hl and HΦ. So anything inside quotations is going to Iris 
      context while anything inside brackets is going to the Coq context.
  *)
  iIntros (Φ) "Hl HΦ".
  (*
     This lemma seems to be applicable if our instruction is atomic, can take a step, and does 
       not involve concurrency (which is always true in our language). Upon applying the lemma
       we are first asked to prove that the instruction is not a value (trivial). Then we getfield       a very sophisticated expression whose meaning is to be deciphered.
  *)
  iApply twp_lift_atomic_head_step_no_fork; first done.
  (*
    This is just another iIntros although with something new: !>. This !> pattern is for
      removing the ={E}=* from our goal (this symbol represents an update modality).
  *)
  iIntros (σ1 κs n) "Hσ !>".
  (*
    A lot is going on here. The %? pattern in the end actually consists of two things: 
      it should be read as first the %H pattern, which is for moving the destructed hypothesis
      into the Coq context and naming it H; the ? pattern is just saying that this will be
      anonymous (so give it any name). It turns out that it receives a name 'H' as well anyway.

    The iDestruct itself specialises the term (gen_heap_valid with "Hσ Hl") -- called a 'proof 
      mode term' -- and destruct it. It is currently unclear what 'specialise' means. But
      we do have an explanation for what a 'proof mode term' is: the general syntax is

        (H $ t1 ... tn with "spat1 ... spatn")

      where H is a hypothesis or a lemma whose conclusion is of the form P ⊢ Q, the t_i's are 
        for instantiating any quantifiers, and the spat_i's are 'specialization patterns' to 
        instruct how wands and implications are dealt with. In this case, it is like the 
        reverse of what happens in Intros, where we need to provide the lemma with hypotheses
        to remove the wands -- note that the lemma gen_heap_valid is the following:

        gen_heap_ctx σ -* l ↦ { q } v -* ⌜ σ !! l = Some v ⌝

    So we are just providing our Hσ and Hl to help resolve the two assertions before wands.
      Hl is id ↦ { q } v so that fills  the second assertion directly. On the other hand,
      Hσ is 

        state_interp σ1 κs n 

      which is somewhat similar t the second component of our heapG_irisG construct,
      whatever that heapG_irisG means; but that definition does say:

        state_interp σ κs _ := gen_heap_ctx (gmap_of_state σ);

    So we can see intuitively why Hσ could help to resolve the first assertion (although not 
      knowing what exactly has happened).

    Lastly, note that gmap_of_state σ1 is going to be just our host variable store hs due to
      our dummy definition -- but we haven't destructed σ1, so we should get back a hypothesis 

         (gmap_of_state σ1) !! id = Some (Some v), 

      automatically named H due to the ? pattern, and moved into the Coq context due to the %?
      pattern; the double Some comes from gmap contributing 1 and our definition of (option val)
      contributing one.
   *)
  iDestruct (gen_heap_valid with "Hσ Hl") as %?.
  (*
    The iSplit tactics is easier -- it basically tries to split up P * Q into two, but only when
      one of P or Q is persistent (else we'll have to use iSplitl/iSplitr, and also divide our
      Iris hypothesis into two parts and we can only use one part on each side). 
  *)
  iSplit.
  (* The first part asks to prove that HE_getglobal id actually can reduce further. The proof
      is just normal Coq instead of Iris so is left mostly without comments. *)
  - unfold head_reducible_no_obs. inv_head_step. iExists (HE_value v), σ1, [].
    unfold gmap_of_state in H. destruct σ1 as [[hs ws] locs].
    inv_head_step. unfold head_step. repeat iSplit => //.
    (* iPureIntro takes an Iris goal ⌜ P ⌝ into a Coq goal P. *)
    iPureIntro.
    apply purer_headr. by apply pr_getglobal.
  (* The second part asks us to prove that, on all cases where we take a step, we can 
       establish the proposition Φ.
     
     The function 'from_option f y mx' checks what option the mx is: if it's a Some x, then
       return f applied to x; else return y. So in this case we are saying that, if the 
       reduction result e2 is a value v, then we need to prove Φ v; else, if it's not a value,
       we will need to be ready to prove False (why?).
  *)
  - iIntros (κ v2 σ2 efs Hstep); inv_head_step.
    (* There are two cases -- either the lookup result v is an actual valid value, or a trap. *)
    + iModIntro; repeat (iSplit; first done). iFrame. 
      by iApply "HΦ".
    (* But it can't be a trap since we already have full knowledge from H what v should be. *)    
    + by rewrite H in H6.  
Qed.

(* If we have full ownership then we can also set the value of it. *)
Lemma twp_setglobal_value s E id w v:
  v <> HV_trap ->
  [[{ id ↦ { 1 } w }]] HE_setglobal id (HE_value v) @ s; E
  [[{ RET v; id ↦ { 1 } v }]].
Proof.
  intros HNTrap.
  iIntros (Φ) "Hl HΦ". iApply twp_lift_atomic_head_step_no_fork; first done.
  iIntros (σ1 κs n) "Hσ !>". iDestruct (gen_heap_valid with "Hσ Hl") as %?.
  iSplit.
  - unfold head_reducible_no_obs. inv_head_step. 
    unfold gmap_of_state in H. destruct σ1 as [[hs ws] locs].
    inv_head_step. unfold head_step. repeat iSplit => //. 
    iPureIntro. repeat eexists. by apply pr_setglobal_value.
  - iIntros (κ v2 σ2 efs Hstep); inv_head_step.
    (* What does this do? *)
    + iMod (gen_heap_update with "Hσ Hl") as "[$ Hl]".
      iModIntro. repeat (iSplit => //). by iApply "HΦ".
    + by inversion H11.
Qed.

Lemma twp_setglobal_trap s E id:
  [[{ True }]] HE_setglobal id (HE_value HV_trap) @ s; E
  [[{ RET (HV_trap); True }]].
Proof.
  iIntros (Φ) "Hl HΦ". iApply twp_lift_atomic_head_step_no_fork; first done.
  iIntros (σ1 κs n) "Hσ !>".
  iSplit.
  - unfold head_reducible_no_obs. simpl in *. destruct σ1 as [[hs ws] locs].
    iPureIntro. repeat eexists. by apply pr_setglobal_trap.
  - iIntros (κ e2 σ2 efs Hstep); inv_head_step.
    + iModIntro. repeat (iSplit => //). iFrame. by iApply "HΦ".
    + by inversion H10.
Qed.

(* Manually deal with evaluation contexts. *)
(* Think this might be wrong *)
Lemma twp_setglobal_reduce s E id e Q:
  WP e @ s; E {{ v, WP (HE_setglobal id (HE_value v)) @ s; E {{ Q }} }} ⊢
            WP (HE_setglobal id e) @ s; E {{ Q }}.
Proof.
  iIntros "H". iLöb as "IH" forall (E e Q). rewrite wp_unfold /wp_pre.  
  destruct (to_val e) as [v|] eqn:He.
  { apply of_to_val in He as <-. by iApply fupd_wp. }
  rewrite wp_unfold /wp_pre /=; [|done].
  rewrite wp_unfold /wp_pre fill_not_val /=; [|done].
  iIntros (σ1 step κ κs n) "Hσ". iMod ("H" with "[$]") as "[% H]".
  iModIntro; iSplit.
  { destruct s; eauto using reducible_fill. }
  iIntros (e2 σ2 efs Hstep).
  destruct (fill_step_inv e σ1 κ e2 σ2 efs) as (e2'&->&?); auto.
  iMod ("H" $! e2' σ2 efs with "[//]") as "H". iIntros "!>!>".
  iMod "H". iModIntro. iApply (step_fupdN_wand with "H"). iIntros "H".
  iMod "H" as "($ & H & $)". iModIntro. by iApply "IH".
Qed.                            
                              (*
Definition locof (n : nat) := {| loc_car := (Z.of_nat n) |}.

Section lifting.
Context `{!heapG Σ}.
Implicit Types σ : state.

Lemma twp_load s E imm q v :
  [[{ (locof imm) ↦{q} v }]] [Basic (Get_local imm)] @ s; E [[{ RET v; (locof imm) ↦{q} v }]].
Proof.
  iIntros (Φ) "Hl HΦ". iApply twp_lift_atomic_head_step_no_fork; first done.
  iIntros (σ1 κs n) "Hσ !>". iDestruct (@gen_heap_valid with "Hσ Hl") as %?.
  iSplit.
  inv_head_step.
  admit.
  iIntros (κ v2 σ2 efs Hstep); inv_head_step.
  move: H1 => [H1 H2].
  iModIntro; iSplit=> //; iSplit=> //.
  iSplitR.
  admit.
  unfold from_option.
  inversion H0 => {H0}; subst.
  { inversion H3 => {H3}; subst.
    { exfalso.
      admit. }
    { exfalso.
      admit. }
    { simpl.
      clear H0.
      apply lfilled_Ind_Equivalent in H1.
      inversion H1; subst.
      { admit. }
    }
  }
  { simpl.
    exfalso.
    move: H3.
    rewrite app_singleton => H3.
    move: H3 => [[H3 H4]|[H3 H4]]; discriminate. }
  { admit. }
  { admit. }
  { exfalso.
  move: H3.
  rewrite app_nil => [[_ H4]].
  discriminate. }
Admitted.

Lemma twp_wp_step s E e P Φ :
  TCEq (to_val e) None →
  ▷ P -∗
  WP e @ s; E [{ v, P ={E}=∗ Φ v }] -∗ WP e @ s; E {{ Φ }}.
Proof.
  iIntros (?) "HP Hwp".
  iApply (wp_step_fupd _ _ E _ P with "[HP]"); [auto..|].
  { by inversion H; subst. }
  by iApply twp_wp.
Qed.

Lemma wp_load s E imm q v :
  {{{ ▷ locof imm ↦{q} v }}} [Basic (Get_local imm)] @ s; E {{{ RET v; locof imm ↦{q} v }}}.
Proof.
  iIntros (Φ) ">H HΦ". iApply (twp_wp_step with "HΦ").
  iApply (twp_load with "H"); [auto..|]; iIntros "H HΦ". by iApply "HΦ".
Qed.

End lifting.


*)
