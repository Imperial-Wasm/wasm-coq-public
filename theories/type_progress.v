(** Proof of progress **)
(* (C) Rao Xiaojia, M. Bodin - see LICENSE.txt *)

From mathcomp Require Import ssreflect ssrfun ssrnat ssrbool eqtype seq.
From Coq Require Import Program.Equality NArith Omega.
From Wasm Require Export operations typing type_checker datatypes_properties typing opsem properties.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Section Host.

Variable host_function : eqType.

Let store_record := store_record host_function.
Let function_closure := function_closure host_function.
Let administrative_instruction := administrative_instruction host_function.

Let to_e_list : seq basic_instruction -> seq administrative_instruction := @to_e_list _.
Let to_b_list : seq administrative_instruction -> seq basic_instruction := @to_b_list _.
Let e_typing : store_record -> t_context -> seq administrative_instruction -> function_type -> Prop :=
  @e_typing _.
Let reduce_simple : seq administrative_instruction -> seq administrative_instruction -> Prop :=
  @reduce_simple _.
Let const_list : seq administrative_instruction -> bool := @const_list _.
Let lholed := lholed host_function.
Let lfilled : depth -> lholed -> seq administrative_instruction -> seq administrative_instruction -> bool :=
  @lfilled _.
Let sfunc : store_record -> instance -> nat -> option function_closure := @sfunc _.
Let sglob : store_record -> instance -> nat -> option global := @sglob _.
Let smem_ind : store_record -> instance -> option nat := @smem_ind _.

Let host := host host_function.

Variable host_instance : host.

Let host_state := host_state host_instance.

Let reduce : host_state -> store_record -> seq value -> seq administrative_instruction -> instance ->
             host_state -> store_record -> seq value -> seq administrative_instruction -> Prop
  := @reduce _ _.

Definition terminal_form (es: seq administrative_instruction) :=
  const_list es \/ es = [::Trap].

Lemma reduce_trap_left: forall vs,
    const_list vs ->
    vs <> [::] ->
    reduce_simple (vs ++ [::Trap]) [::Trap].
Proof.
  move => vs HConst H.
  destruct vs => //=; eapply rs_trap; try by destruct vs => //=.
  assert (LF : lfilledInd 0 (LBase (a::vs) [::]) [::Trap] (a::vs++[::Trap])).
  { by apply LfilledBase. }
  apply/lfilledP.
  by apply LF.
Qed.

Lemma v_e_trap: forall vs es,
    const_list vs ->
    vs ++ es = [::Trap] ->
    vs = [::] /\ es = [::Trap].
Proof.
  move => vs es HConst H.
  destruct vs => //=.
  destruct vs => //=. destruct es => //=.
  simpl in H. inversion H. by subst.
Qed.

Lemma cat_split: forall {X:Type} (l l1 l2: seq X),
    l = l1 ++ l2 ->
    l1 = take (size l1) l /\
    l2 = drop (size l1) l.
Proof.
  move => X l l1.
  generalize dependent l.
  induction l1 => //=; move => l l2 HCat; subst => //=.
  - split. by rewrite take0. by rewrite drop0.
  - edestruct IHl1.
    instantiate (1 := l2). eauto.
    split => //.
    by f_equal.
Qed.

Lemma reduce_composition: forall s cs vs es es0 i s' vs' es' hs hs',
    const_list cs ->
    reduce hs s vs es i hs' s' vs' es' ->
    reduce hs s vs (cs ++ es ++ es0) i hs' s' vs' (cs ++ es' ++ es0).
Proof.
  move => s cs vs es es0 i s' vs' es' hs hs' HConst HReduce.
  eapply r_label; eauto; apply/lfilledP.
  - instantiate (1 := (LBase cs es0)). instantiate (1 := 0).
    by apply LfilledBase.
  - by apply LfilledBase.
Qed.

Lemma reduce_composition_right: forall s vs es es0 i s' vs' es' hs hs',
    reduce hs s vs es i hs' s' vs' es' ->
    reduce hs s vs (es ++ es0) i hs' s' vs' (es' ++ es0).
Proof.
  move => s vs es es0 i s' vs' es' hs hs' HReduce.
  eapply reduce_composition in HReduce.
  instantiate (1 := es0) in HReduce.
  instantiate (1 := [::]) in HReduce.
  by simpl in HReduce.
  by [].
Qed.

Lemma reduce_composition_left: forall s cs vs es i s' vs' es' hs hs',
    const_list cs ->
    reduce hs s vs es i hs' s' vs' es' ->
    reduce hs s vs (cs ++ es) i hs' s' vs' (cs ++ es').
Proof.
  move => s vs es es0 i s' vs' es' hs hs' HConst HReduce.
  eapply reduce_composition in HReduce; eauto.
  instantiate (1 := [::]) in HReduce.
  by repeat rewrite cats0 in HReduce.
Qed.

Lemma lfilled0_empty: forall es,
    lfilled 0 (LBase [::] [::]) es es.
Proof.
  move => es.
  apply/lfilledP.
  assert (LF : lfilledInd 0 (LBase [::] [::]) es ([::] ++ es ++ [::])); first by apply LfilledBase.
  by rewrite cats0 in LF.
Qed.

Lemma label_lfilled1: forall n es es0,
    lfilled 1 (LRec [::] n es0 (LBase [::] [::]) [::]) es [::Label n es0 es].
Proof.
  move => n es es0.
  apply/lfilledP.
  replace [:: Label n es0 es] with ([::] ++ [::Label n es0 es] ++ [::]) => //.
  apply LfilledRec => //.
  assert (LF : lfilledInd 0 (LBase [::] [::]) es ([::] ++ es ++ [::])); first by apply LfilledBase.
  simpl in LF. by rewrite cats0 in LF.
Qed.

Lemma terminal_form_v_e: forall vs es,
    const_list vs ->
    terminal_form (vs ++ es) ->
    terminal_form es.
Proof.
  move => vs es HConst HTerm.
  unfold terminal_form in HTerm.
  destruct HTerm.
  - unfold terminal_form. left.
    apply const_list_split in H. by destruct H.
  - destruct vs => //=.
    + simpl in H. subst. unfold terminal_form. by right.
    + destruct vs => //=. destruct es => //=.
      simpl in H. inversion H. by subst.
Qed.

Lemma terminal_trap: terminal_form [::Trap].
Proof.
  unfold terminal_form. by right.
Qed.

Lemma e_b_inverse: forall es,
    es_is_basic es ->
    to_e_list (to_b_list es) = es.
Proof.
  move => es HBasic.
  by erewrite e_b_elim; eauto.
Qed.

Lemma typeof_append: forall ts t vs,
    map typeof vs = ts ++ [::t] ->
    exists v,
      vs = take (size ts) vs ++ [::v] /\
      map typeof (take (size ts) vs) = ts /\
      typeof v = t.
Proof.
  move => ts t vs HMapType.
  apply cat_split in HMapType.
  destruct HMapType.
  rewrite -map_take in H.
  rewrite -map_drop in H0.
  destruct (drop (size ts) vs) eqn:HDrop => //=.
  destruct l => //=.
  inversion H0. subst.
  exists v.
  split => //.
  rewrite -HDrop. by rewrite cat_take_drop.
Qed.

Hint Unfold reduce_simple : core.
Hint Constructors opsem.reduce_simple : core.

Ltac invert_typeof_vcs :=
  lazymatch goal with
  | H: map typeof ?vcs = [::_; _; _] |- _ =>
    destruct vcs => //=; destruct vcs => //=; destruct vcs => //=; destruct vcs => //=;
    simpl in H; inversion H; subst; clear H
  | H: map typeof ?vcs = [::_; _] |- _ =>
    destruct vcs => //=; destruct vcs => //=; destruct vcs => //=;
    simpl in H; inversion H; subst; clear H
  | H: map typeof ?vcs = [::_] |- _ =>
    destruct vcs => //=; destruct vcs => //=;
    simpl in H; inversion H; subst; clear H
  | H: map typeof ?vcs = [::] |- _ =>
    destruct vcs => //=;
    simpl in H; inversion H; subst; clear H
  end.
(*
Ltac invert_inst_typing :=
  lazymatch goal with
  | H: inst_typing _ ?i ?C |- _ =>
    unfold inst_typing in H;
    destruct i => //=;
    destruct C => //=;
    destruct tc_local => //=;
    destruct tc_label => //=;
    destruct tc_return => //=
  end.
*)

Lemma nth_error_map: forall {X Y:Type} (l: seq X) n f {fx: Y},
    List.nth_error (map f l) n = Some fx ->
    exists x, List.nth_error l n = Some x /\
    f x = fx.
Proof.
  move => X Y l n.
  generalize dependent l.
  induction n => //; move => l f fx HN.
  - destruct l => //=.
    simpl in HN. inversion HN. subst. by eauto.
  - destruct l => //=.
    simpl in HN. by apply IHn.
Qed.

Lemma func_context_store: forall s i C j x,
    inst_typing s i C ->
    j < length (tc_func_t C) ->
    List.nth_error (tc_func_t C) j = Some x ->
    sfunc s i j <> None.
Proof.
  move => s i C j x HIT HLength HN.
  unfold sfunc. unfold operations.sfunc. unfold option_bind.
  unfold sfunc_ind.
  unfold inst_typing in HIT.
  destruct i => //=. destruct C => //=.
  destruct tc_local => //=. destruct tc_label => //=. destruct tc_return => //=.
  remove_bools_options.
  remember H3 as H4. clear HeqH4.
  apply all2_size in H3.
  repeat rewrite -length_is_size in H3.
  simpl in HLength.
  rewrite -H3 in HLength.
  move/ltP in HLength.
  apply List.nth_error_Some in HLength.
  destruct (List.nth_error i_funcs j) eqn:HN1 => //=.
  apply List.nth_error_Some.
  unfold functions_agree in H4.
  eapply all2_projection in H4; eauto.
  remove_bools_options.
  by move/ltP in H4.
Qed.

Lemma glob_context_store: forall s i C j g,
    inst_typing s i C ->
    j < length (tc_global C) ->
    List.nth_error (tc_global C) j = Some g ->
    sglob s i j <> None.
Proof.
  move => s i C j g HIT HLength HN.
  unfold sglob. unfold operations.sglob. unfold option_bind.
  unfold sglob_ind.
  unfold inst_typing in HIT.
  destruct i => //=. destruct C => //=.
  destruct tc_local => //=. destruct tc_label => //=. destruct tc_return => //=.
  remove_bools_options.
  remember H2 as H4. clear HeqH4.
  apply all2_size in H2.
  repeat rewrite -length_is_size in H2.
  simpl in HLength.
  rewrite -H2 in HLength.
  move/ltP in HLength.
  apply List.nth_error_Some in HLength.
  destruct (List.nth_error i_globs j) eqn:HN1 => //=.
  apply List.nth_error_Some.
  unfold globals_agree in H4.
  eapply all2_projection in H4; eauto.
  remove_bools_options.
  by move/ltP in H4.
Qed.

Lemma mem_context_store: forall s i C,
    inst_typing s i C ->
    tc_memory C <> [::] ->
    exists n, smem_ind s i = Some n /\
              List.nth_error (s_mems s) n <> None.
Proof.
  move => s i C HIT HMemory.
  unfold inst_typing in HIT.
  destruct i => //=. destruct C => //=.
  destruct tc_local => //=. destruct tc_label => //=. destruct tc_return => //=.
  remove_bools_options.
  simpl in HMemory. unfold smem_ind. simpl.
  remember H0 as H4. clear HeqH4.
  apply all2_size in H0.
  destruct i_memory => //=; first by destruct tc_memory.
  exists m. split => //.
  destruct tc_memory => //.
  simpl in H4.
  unfold memi_agree in H4.
  by remove_bools_options.
Qed.

(*
  Except [::Br i] or [::Return], every other basic instruction can be
    prepended by several consts to be reduceable to something else.

  Although we only actually need bes to be not Return or Br, we have to state an
    entire lfilled proposition as a condition due to composition.
 *)

Definition not_lf_br (es: seq administrative_instruction) (n: nat) :=
  forall k lh, ~ lfilled n lh [::Basic (Br k)] es.

Definition not_lf_return (es: seq administrative_instruction) (n: nat) :=
  forall lh, ~ lfilled n lh [::Basic Return] es.

Lemma lf_composition: forall es es2 e0 lh n,
    lfilled n lh e0 es ->
    exists lh', lfilled n lh' e0 (es ++ es2).
Proof.
  move => es es2 e0 lh n HLF.
  move/lfilledP in HLF.
  inversion HLF; subst.
  - exists (LBase vs (es' ++ es2)).
    apply/lfilledP.
    repeat rewrite -catA.
    by apply LfilledBase.
  - exists (LRec vs n0 es' lh' (es'' ++ es2)).
    apply/lfilledP.
    repeat rewrite -catA.
    by apply LfilledRec.
Qed.

Lemma lf_composition_left: forall cs es e0 lh n,
    const_list cs ->
    lfilled n lh e0 es ->
    exists lh', lfilled n lh' e0 (cs ++ es).
Proof.
  move => cs es e0 lh n HConst HLF.
  move/lfilledP in HLF.
  inversion HLF; subst.
  - exists (LBase (cs ++ vs) es').
    apply/lfilledP.
    rewrite (catA cs vs).
    apply LfilledBase.
    by apply const_list_concat.
  - exists (LRec (cs ++ vs) n0 es' lh' es'').
    apply/lfilledP.
    rewrite (catA cs vs).
    apply LfilledRec => //.
    by apply const_list_concat.
Qed.

Lemma nlfbr_right: forall es n es',
    not_lf_br (es ++ es') n ->
    not_lf_br es n.
Proof.
  unfold not_lf_br.
  move => es n es' HNLF k lh HContra.
  eapply lf_composition in HContra.
  instantiate (1 := es') in HContra.
  destruct HContra.
  by eapply HNLF; eauto.
Qed.

Lemma nlfret_right: forall es n es',
    not_lf_return (es ++ es') n ->
    not_lf_return es n.
Proof.
  unfold not_lf_return.
  move => es n es' HNLF lh HContra.
  eapply lf_composition in HContra.
  instantiate (1 := es') in HContra.
  destruct HContra.
  by eapply HNLF; eauto.
Qed.

Lemma nlfbr_left: forall es n cs,
    const_list cs ->
    not_lf_br (cs ++ es) n ->
    not_lf_br es n.
Proof.
  unfold not_lf_return.
  move => es n cs HConst HNLF k lh HContra.
  eapply lf_composition_left in HContra => //.
  {
    instantiate (1 := cs) in HContra.
    destruct HContra.
    by eapply HNLF; eauto.
  }
  by [].
Qed.

Lemma nlfret_left: forall es n cs,
    const_list cs ->
    not_lf_return (cs ++ es) n ->
    not_lf_return es n.
Proof.
  unfold not_lf_return.
  move => es n cs HConst HNLF lh HContra.
  eapply lf_composition_left in HContra => //.
  {
    instantiate (1 := cs) in HContra.
    destruct HContra.
    by eapply HNLF; eauto.
  }
  by [].
Qed.

(*
The version in properties.v cannot be applied since we need to apply this lemma
  on the version of to_e_list with host (defined in this section).
*)
Lemma to_e_list_cat: forall l1 l2,
    to_e_list (l1 ++ l2) = to_e_list l1 ++ to_e_list l2.
Proof.
Admitted.

(*
This lemma is already proved in preservation.v. However, it's less trivial to move
  that to properties.v, since it has a lot of dependencies on the previous proofs
  in preservation. So we either move all of them to a common file, or is it sensible
  to just import presevation here?
*)
Lemma Const_list_typing: forall C vs t1s t2s,
    be_typing C (to_b_list (v_to_e_list vs)) (Tf t1s t2s) ->
    t2s = t1s ++ (map typeof vs).
Proof.
Admitted.

(** A common scheme in the progress proof, with a continuation. **)
Ltac solve_progress_cont cont :=
  repeat eexists;
  solve [
      apply r_simple; solve [ eauto | constructor; eauto | cont; eauto ]
    | cont ].

(** The same, but without continuation. **)
Ltac solve_progress :=
  solve_progress_cont ltac:(fail).

Lemma t_progress_be: forall C bes ts1 ts2 vcs lab ret s vs i hs,
    store_typing s ->
    inst_typing s i C ->
    be_typing (upd_label (upd_local_return C (map typeof vs) ret) lab) bes (Tf ts1 ts2) ->
    map typeof vcs = ts1 ->
    not_lf_br (to_e_list bes) 0 ->
    not_lf_return (to_e_list bes) 0 ->
    const_list (to_e_list bes) \/
    exists s' vs' es' hs', reduce hs s vs (v_to_e_list vcs ++ to_e_list bes) i hs' s' vs' es'.
Proof.
  move => C bes ts1 ts2 vcs lab ret s vs i hs HST HIT HType HConstType HNBr HNRet.
  generalize dependent vcs.
  gen_ind HType; try by left.
  - (* Unop_i *)
    right. invert_typeof_vcs.
    by destruct v => //=; solve_progress.
  - (* Unop_f *)
    right. invert_typeof_vcs.
    by destruct v => //=; solve_progress.
  - (* binop_i *)
    right. invert_typeof_vcs.
    destruct v => //=; destruct v0 => //=.
    + destruct (@app_binop_i i32t op s0 s1) eqn:HBinary; solve_progress.
    + destruct (@app_binop_i i64t op s0 s1) eqn:HBinary; solve_progress.
  - (* binop_f *)
    right. invert_typeof_vcs.
    destruct v => //=; destruct v0 => //=.
    + destruct (@app_binop_f f32t op s0 s1) eqn:HBinary; solve_progress.
    + destruct (@app_binop_f f64t op s0 s1) eqn:HBinary; solve_progress.
  - (* testop *)
    right. invert_typeof_vcs.
    by destruct v => //=; solve_progress.
  - (* relop_i *)
    right. invert_typeof_vcs.
    by destruct v => //=; destruct v0 => //=; solve_progress.
  - (* relop_f *)
    right. invert_typeof_vcs.
    by destruct v => //=; destruct v0 => //=; solve_progress.
  - (* cvtop *)
    right. invert_typeof_vcs.
    destruct (cvt t1 sx v) eqn:HConvert; destruct v => //=; solve_progress.
  - (* reinterpret *)
    right. invert_typeof_vcs.
    by destruct v => //=; solve_progress_cont ltac:(apply rs_reinterpret).
  - (* Unreachable *)
    right.
    exists s, vs, (v_to_e_list vcs ++ [::Trap]), hs.
    apply reduce_composition_left; first by apply v_to_e_is_const_list.
    apply r_simple. by constructor.
  - (* Nop *)
    right.
    exists s, vs, (v_to_e_list vcs ++ [::]), hs.
    apply reduce_composition_left; first by apply v_to_e_is_const_list.
    apply r_simple. by constructor.
  - (* Drop *)
    right. invert_typeof_vcs. solve_progress.
  - (* Select *)
    right. invert_typeof_vcs.
    destruct v1 => //=.
    by destruct (s0 == Wasm_int.int_zero i32m) eqn:Heq0; move/eqP in Heq0; solve_progress.
  - (* Block *)
    right.
    exists s, vs, [::Label (length tm) [::] (v_to_e_list vcs ++ to_e_list es)], hs.
    apply r_simple. eapply rs_block; eauto.
    + by apply v_to_e_is_const_list.
    + repeat rewrite length_is_size.
      rewrite v_to_e_size.
      subst.
      by rewrite size_map.
  - (* Loop *)
    right.
    exists s, vs, [::Label (length vcs) [::Basic (Loop (Tf ts1 ts2) es)] (v_to_e_list vcs ++ to_e_list es)], hs.
    apply r_simple. rewrite HConstType.
    eapply rs_loop; eauto; repeat rewrite length_is_size.
    + by apply v_to_e_is_const_list.
    + by rewrite v_to_e_size.
    + rewrite -HConstType. by rewrite size_map.
  - (* if *)
    right.
    apply typeof_append in HConstType.
    destruct HConstType as [v [Ha [Hb Hc]]].
    rewrite Ha. rewrite -v_to_e_cat.
    rewrite -catA.
    destruct v => //=.
    destruct (s0 == Wasm_int.int_zero i32m) eqn:Heq0; move/eqP in Heq0.
    + exists s, vs, (v_to_e_list (take (size tn) vcs) ++ [::Basic (Block (Tf tn ts2) es2)]), hs.
      apply reduce_composition_left; first by apply v_to_e_is_const_list.
      apply r_simple. by eapply rs_if_false.
    + exists s, vs, (v_to_e_list (take (size tn) vcs) ++ [::Basic (Block (Tf tn ts2) es1)]), hs.
      apply reduce_composition_left; first by apply v_to_e_is_const_list.
      by apply r_simple; eauto.
  - (* Br *)
    subst.
    exfalso.
    unfold not_lf_br in HNBr.
    apply (HNBr i0 (LBase [::] [::])).
    by apply lfilled0_empty. 
  - (* Br_if *)
    right.
    apply typeof_append in HConstType.
    destruct HConstType as [v [Ha [Hb Hc]]].
    rewrite Ha. rewrite -v_to_e_cat.
    rewrite -catA.
    destruct v => //=.
    destruct (s0 == Wasm_int.int_zero i32m) eqn:Heq0; move/eqP in Heq0.
    + exists s, vs, (v_to_e_list (take (size ts2) vcs) ++ [::]), hs.
      apply reduce_composition_left; first by apply v_to_e_is_const_list.
      by apply r_simple; eauto.
    + exists s, vs, (v_to_e_list (take (size ts2) vcs) ++ [::Basic (Br i0)]), hs.
      apply reduce_composition_left; first by apply v_to_e_is_const_list.
      by apply r_simple; eauto.
  - (* Br_table *)
    right.
    apply cat_split in HConstType. destruct HConstType.
    assert (Evcs : vcs = take (size t1s) vcs ++ drop (size t1s) vcs); first by rewrite cat_take_drop.
    rewrite Evcs.
    symmetry in H6. rewrite -map_drop in H6. apply typeof_append in H6.
    destruct H6 as [v [Ha [Hb Hc]]].
    destruct v => //=.
    rewrite Ha.
    repeat rewrite -v_to_e_cat.
    repeat rewrite -catA. rewrite catA.
    destruct (length ins > Wasm_int.nat_of_uint i32m s0) eqn:HLength; move/ltP in HLength.
    + remember HLength as H8. clear HeqH8.
      apply List.nth_error_Some in H8.
      destruct (List.nth_error ins (Wasm_int.nat_of_uint i32m s0)) eqn:HN => //=.
      exists s, vs, ((v_to_e_list (take (size t1s) vcs) ++ v_to_e_list (take (size ts) (drop (size t1s) vcs))) ++ [::Basic (Br n)]), hs.
      apply reduce_composition_left.
      { by apply const_list_concat; apply v_to_e_is_const_list. }
      apply r_simple. apply rs_br_table => //.
      by lias.
    + assert (Inf : length ins <= Wasm_int.nat_of_uint i32m s0); first by lias.
      move/leP in Inf.
      remember Inf as Inf'. clear HeqInf'.
      apply List.nth_error_None in Inf.
      exists s, vs, ((v_to_e_list (take (size t1s) vcs) ++ v_to_e_list (take (size ts) (drop (size t1s) vcs))) ++ [::Basic (Br i0)]), hs.
      apply reduce_composition_left.
      { by apply const_list_concat; apply v_to_e_is_const_list. }
      apply r_simple. apply rs_br_table_length => //.
      by lias.
  - (* Return *)
    subst.
    exfalso.
    unfold not_lf_return in HNRet.
    apply (HNRet (LBase [::] [::])).
    by apply lfilled0_empty.
  - (* Call *)
    right. subst.
    simpl in H. simpl in H0.
    eapply func_context_store in H; eauto.
    destruct (sfunc s i i0) eqn:HCL => //.
    exists s, vs, (v_to_e_list vcs ++ [:: (Invoke f)]), hs.
    apply reduce_composition_left; first by apply v_to_e_is_const_list.
    by apply r_call => //. 
  - (* Call_indirect *)
    right.
    simpl in H.
    simpl in H0.
    simpl in H1.
    apply typeof_append in HConstType. destruct HConstType as [v [Ha [Hb Hc]]].
    destruct v => //=.
    rewrite Ha. rewrite -v_to_e_cat. rewrite -catA.
    exists s, vs.
    destruct (stab s i (Wasm_int.nat_of_uint i32m s0)) eqn:Hstab.
    + (* Some cl *)
      destruct (stypes s i i0 == Some (cl_type f)) eqn:Hclt; move/eqP in Hclt.
      * exists (v_to_e_list (take (size t1s) vcs) ++ [::Invoke f]), hs.
        apply reduce_composition_left; first by apply v_to_e_is_const_list.
        simpl.
        by eapply r_call_indirect_success; eauto.
      * exists (v_to_e_list (take (size t1s) vcs) ++ [::Trap]), hs.
        apply reduce_composition_left; first by apply v_to_e_is_const_list.
        by eapply r_call_indirect_failure1; eauto.
    + (* None *)
      exists (v_to_e_list (take (size t1s) vcs) ++ [::Trap]), hs.
      apply reduce_composition_left; first by apply v_to_e_is_const_list.
      by apply r_call_indirect_failure2.

  - (* Get_local *)
    right. invert_typeof_vcs.
    simpl in H. simpl in H0.
    apply nth_error_map in H0.
    destruct H0 as [x' [HN HType]].
    rewrite length_is_size in H.
    rewrite size_map in H.
    apply split3 in HN => //.
    exists s, vs, [::Basic (EConst x')], hs.
    rewrite HN.
    apply r_get_local.
    rewrite length_is_size.
    rewrite size_take. by rewrite H.

  - (* Set_local *)
    right. invert_typeof_vcs.
    simpl in H.
    rewrite length_is_size in H. rewrite size_map in H. rewrite -length_is_size in H.
    exists s, (set_nth v vs i0 v), [::], hs.
    by apply r_set_local.

  - (* Tee_local *)
    right. invert_typeof_vcs.
    exists s, vs, [::Basic (EConst v); Basic (EConst v); Basic (Set_local i0)], hs.
    by apply r_simple; eauto.

  - (* Get_global *)
    right. invert_typeof_vcs.
    simpl in H. simpl in H0.
    unfold option_map in H0.
    destruct (List.nth_error (tc_global C0) i0) eqn:HN => //=.
    eapply glob_context_store in HN; eauto.
    assert (D : sglob_val s i i0 <> None).
    { unfold sglob_val. unfold sglob in HN. unfold option_map. by destruct (operations.sglob s i i0). }
    destruct (sglob_val s i i0) eqn:Hglobval => //=.
    exists s, vs, [::Basic (EConst v)], hs.
    by apply r_get_global.

  - (* Set_global *)
    right. invert_typeof_vcs.
    destruct (supdate_glob s i i0 v) eqn:Hs.
    + exists s0, vs, [::], hs.
      by apply r_set_global.
    + unfold supdate_glob in Hs. unfold option_bind in Hs.
      simpl in H. simpl in H0.
      eapply glob_context_store in H0; eauto.
      unfold sglob in H0. unfold operations.sglob in H0. unfold option_bind in H0.
      destruct (sglob_ind s i i0) eqn:Hglob => //.
      unfold supdate_glob_s in Hs. unfold option_map in Hs.
      destruct (List.nth_error (s_globals s) n) => //.

  - (* Load *)
    right. subst.
    simpl in H.
    exists s, vs.
    invert_typeof_vcs. destruct v => //=.
    eapply mem_context_store in H; eauto.
    destruct H as [n [HMenInd HMem]].
    destruct (List.nth_error (s_mems s) n) eqn:HN => //=.
    destruct tp_sx.
    + (* Load Some *)
      destruct p as [tp sx].
      simpl in H0. remove_bools_options.
      destruct (load_packed sx m (Wasm_int.N_of_uint i32m s0) off (tp_length tp) (t_length t)) eqn:HLoadResult.
      * exists [::Basic (EConst (wasm_deserialise b t))], hs.
        by eapply r_load_packed_success; eauto.
      * exists [::Trap], hs.
        by eapply r_load_packed_failure; eauto.
    + (* Load None *)
      simpl in H0.
      destruct (load m (Wasm_int.N_of_uint i32m s0) off (t_length t)) eqn:HLoadResult.
      * exists [::Basic (EConst (wasm_deserialise b t))], hs.
        by eapply r_load_success; eauto.
      * exists [::Trap], hs.
        by eapply r_load_failure; eauto.

  - (* Store *)
    right. subst.
    simpl in H.
    invert_typeof_vcs. destruct v => //=.
    eapply mem_context_store in H; eauto.
    destruct H as [n [HMenInd HMem]].
    destruct (List.nth_error (s_mems s) n) eqn:HN => //=.
    destruct tp as [tp |].
    + (* Store Some *)
      simpl in H0. remove_bools_options.
      destruct (store_packed m (Wasm_int.N_of_uint i32m s0) off (bits v0) (tp_length tp)) eqn:HStoreResult.
      * exists (upd_s_mem s (update_list_at s.(s_mems) n m0)), vs, [::], hs.
        eapply r_store_packed_success; eauto.
        by unfold types_agree; apply/eqP.
      * exists s, vs, [::Trap], hs.
        eapply r_store_packed_failure; eauto.
        by unfold types_agree; apply/eqP.
    + (* Store None *)
      simpl in H0.
      destruct (store m (Wasm_int.N_of_uint i32m s0) off (bits v0) (t_length (typeof v0))) eqn:HStoreResult.
      * exists (upd_s_mem s (update_list_at s.(s_mems) n m0)), vs, [::], hs.
        eapply r_store_success; eauto.
        by unfold types_agree; apply/eqP.
      * exists s, vs, [::Trap], hs.
        eapply r_store_failure; eauto.
        by unfold types_agree; apply/eqP.

  - (* Current_memory *)
    right. invert_typeof_vcs.
    simpl in H.
    eapply mem_context_store in H; eauto.
    destruct H as [n [HMemInd HMem]].
    destruct (List.nth_error (s_mems s) n) eqn:HN => //=.
    exists s, vs, [::Basic (EConst (ConstInt32 (Wasm_int.int_of_Z i32m (Z.of_nat (mem_size m)))))], hs.
    by eapply r_current_memory; eauto.

  - (* Grow_memory *)
    right. invert_typeof_vcs.
    simpl in H.
    eapply mem_context_store in H; eauto.
    destruct H as [n [HMemInd HMem]].
    destruct (List.nth_error (s_mems s) n) eqn:HN => //=.
    destruct v => //=.
    (* Similarly, for this proof we can just use trap and use the failure case. *)
    exists s, vs, [::Basic (EConst (ConstInt32 int32_minus_one))], hs.
    by eapply r_grow_memory_failure; eauto.

  - (* Composition *)
    subst.
    rewrite to_e_list_cat in HNBr.
    rewrite to_e_list_cat in HNRet.
    clear H.
    edestruct IHHType1; eauto.
    { by eapply nlfbr_right; eauto. }
    { by eapply nlfret_right; eauto. }
    + (* Const *)
      apply const_es_exists in H. destruct H as [cs HConst].
      apply b_e_elim in HConst. destruct HConst. subst.
      rewrite e_b_inverse in HNRet; last by apply const_list_is_basic; apply v_to_e_is_const_list.
      rewrite e_b_inverse in HNBr; last by apply const_list_is_basic; apply v_to_e_is_const_list.
      apply Const_list_typing in HType1. subst.
      edestruct IHHType2; eauto.
      { by eapply nlfbr_left; try apply v_to_e_is_const_list; eauto. }
      { by eapply nlfret_left; try apply v_to_e_is_const_list; eauto. }
      { by rewrite -map_cat. }
      * left. rewrite to_e_list_cat. apply const_list_concat => //.
        by rewrite e_b_inverse => //; apply v_to_e_is_const_list.
      * destruct H as [es' HReduce].
        right.
        rewrite to_e_list_cat.
        rewrite e_b_inverse; last by apply const_list_is_basic; apply v_to_e_is_const_list.
        exists es'.
        rewrite catA.
        by rewrite v_to_e_cat.
    + (* reduce *)
      destruct H as [s' [vs' [es' [hs' HReduce]]]].
      right.
      rewrite to_e_list_cat.
      exists s', vs', (es' ++ to_e_list [::e]), hs'.
      rewrite catA.
      by apply reduce_composition_right.

  - (* Weakening *)
    apply cat_split in HConstType.
    destruct HConstType.
    rewrite -map_take in H1. rewrite -map_drop in H5.
    subst.
    edestruct IHHType; eauto.
    right.
    destruct H2 as [s' [vs' [es' [hs' HReduce]]]].
    replace vcs with (take (size ts) vcs ++ drop (size ts) vcs); last by apply cat_take_drop.
    rewrite -v_to_e_cat. rewrite -catA.
    exists s', vs', (v_to_e_list (take (size ts) vcs) ++ es'), hs'.
    apply reduce_composition_left => //.
    by apply v_to_e_is_const_list.
Qed. (* TODO *)

(*
Traceback:
  WTP: config_typing i s vs es ts <=
       s_typing s None i vs es ts && (store_typing s) <=
       e_typing s (C [local = map typeof vs, label = [::], return = None]) es (Tf [::] ts) && ...

  So we only need the part of e_typing with label and return being empty.

  However, it's insufficient to state the e_typing lemma as above, since non-empty label and
    return are required for the Local and Label cases respectively.

  Note that for Br i to be typeable, the length of label must be at least i+1 due to the
    requirement List.nth_error (tc_label C) i = Some ts. This means that there must be
    at least k+1 labels below the current Br i instruction. So say if the current instruction
    list satisfies lfilled n ..., then we have i<n.

  In particular, since in the be_typing case we have no labels (as label is not a basic
    instruction, we have i<0, i.e. we don't need to deal with Br there!

  Similarly, for Return to be typeable, tc_return C must be not None; but that is the case
    only if there's already a Local outside the Return instruction. So we don't have to deal
    with Return in be_typing either.
 *)

Definition br_reduce (es: seq administrative_instruction) :=
  exists n lh, lfilled n lh [::Basic (Br n)] es.

Definition return_reduce (es: seq administrative_instruction) :=
  exists n lh, lfilled n lh [::Basic Return] es.

(** [br_reduce] is decidable. **)
Lemma br_reduce_decidable : forall es, decidable (br_reduce es).
Proof.
  move=> es. apply: pickable_decidable. apply: pickable2_weaken.
  apply lfilled_pickable_rec_gen => es' lh n.
  by apply: lfilled_decidable_base.
Defined.

(** [return_reduce] is decidable. **)
Lemma return_reduce_decidable : forall es, decidable (return_reduce es).
Proof.
  move=> es. apply: pickable_decidable. apply: pickable2_weaken.
  apply lfilled_pickable_rec => es'.
  by apply: lfilled_decidable_base.
Defined.


Local Lemma cat_abcd_a_bc_d: forall {X:Type} (a b c d: seq X),
    a ++ b ++ c ++ d = a ++ (b ++ c) ++ d.
Proof.
  move => X a b c d.
  f_equal. by rewrite catA.
Qed.

Lemma br_reduce_label_length: forall n k lh es s C ts2,
    lfilled n lh [::Basic (Br (n + k))] es ->
    e_typing s C es (Tf [::] ts2) ->
    length (tc_label C) > k.
Proof.
  move => n k lh es s C ts2 HLF.
  generalize dependent ts2. generalize dependent C.
  generalize dependent s.
  move/lfilledP in HLF.
  dependent induction HLF; move => s C ts2 HType.
  - invert_e_typing.
    destruct ts => //=; destruct t1s => //=; clear H1.
    rewrite add0n in H5.
    apply et_to_bet in H5; auto_basic.
    simpl in H5. apply Break_typing in H5.
    destruct H5 as [ts [ts2 [H7 [H8 H9]]]].
    unfold plop2 in H8. move/eqP in H8.
    apply/ltP.
    apply List.nth_error_Some. by rewrite H8.
  - invert_e_typing.
    destruct ts => //=; destruct t1s => //=; clear H1.
    assert (Inf : k+1 < length (tc_label (upd_label C ([::ts1] ++ tc_label C)))).
    { eapply IHHLF; eauto.
      repeat (f_equal; try by lias). }
    simpl in Inf. by lias.
Qed.

Lemma return_reduce_return_some: forall n lh es s C ts2,
    lfilled n lh [::Basic Return] es ->
    e_typing s C es (Tf [::] ts2) ->
    tc_return C <> None.
Proof.
  move => n lh es s C ts2 HLF.
  generalize dependent s. generalize dependent C. generalize dependent ts2.
  move/lfilledP in HLF.
  dependent induction HLF; subst; move => ts2 C s HType.
  - invert_e_typing.
    destruct ts; destruct t1s => //=; clear H1.
    apply et_to_bet in H5; auto_basic.
    simpl in H5. apply Return_typing in H5.
    destruct H5 as [ts [ts' [H7 H8]]]. subst.
    by rewrite H8.
  - invert_e_typing.
    destruct ts; destruct t1s => //=; clear H1.
    assert (R : tc_return (upd_label C ([::ts1] ++ tc_label C)) <> None);
    { by eapply IHHLF; eauto. }
    by simpl in R.
Qed.

Lemma br_reduce_extract_vs: forall n k lh es s C ts ts2,
    lfilled n lh [::Basic (Br (n + k))] es ->
    e_typing s C es (Tf [::] ts2) ->
    List.nth_error (tc_label C) k = Some ts ->
    exists vs lh', const_list vs /\
      lfilled n lh' (vs ++ [::Basic (Br (n + k))]) es /\
      length vs = length ts.
Proof.
  move => n k lh es s C ts ts2 HLF.
  move/lfilledP in HLF.
  generalize dependent ts. generalize dependent ts2.
  generalize dependent C. generalize dependent s.
  dependent induction HLF; subst; move => s C ts2 ts HType HN.
  - invert_e_typing.
    destruct ts0; destruct t1s => //; clear H1.
    rewrite add0n in H5.
    apply et_to_bet in H5; auto_basic.
    simpl in H5.
    apply Break_typing in H5.
    destruct H5 as [ts3 [ts3' [H7 [H8 H9]]]]. subst.
    unfold plop2 in H8. move/eqP in H8.
    rewrite HN in H8. inversion H8. subst.
    apply et_to_bet in H3; last by apply const_list_is_basic.
    apply const_es_exists in H.
    destruct H as [vs' H]. subst.
    apply Const_list_typing in H3. simpl in H3.
    rewrite catA in H3. symmetry in H3.
    apply cat_split in H3. destruct H3.
    replace vs' with (take (size (ts1 ++ ts3')) vs' ++ drop (size (ts1 ++ ts3')) vs'); last by apply cat_take_drop.
    exists (v_to_e_list (drop (size (ts1 ++ ts3')) vs')), (LBase (v_to_e_list (take (size (ts1 ++ ts3')) vs')) es').
    repeat split.
    + by apply v_to_e_is_const_list.
    + apply/lfilledP.
      rewrite -v_to_e_cat. rewrite -catA.
      rewrite cat_abcd_a_bc_d.
      by apply LfilledBase; apply v_to_e_is_const_list.
    + rewrite H0.
      repeat rewrite length_is_size.
      rewrite v_to_e_size. rewrite -map_drop.
      by rewrite size_map.
  - invert_e_typing.
    destruct ts0; destruct t1s => //; clear H1.
    edestruct IHHLF; eauto.
    { instantiate (1 := k.+1).
      repeat (f_equal; try by lias). }
    {  simpl. by eauto. }
    destruct H0 as [lh2 [HConst [HLF2 HLength]]].
    replace (k0.+1+k) with (k0+k.+1); last by lias.
    repeat eexists. repeat split => //; eauto.
    move/lfilledP in HLF2. apply/lfilledP.
    instantiate (1 := (LRec vs (length ts2) es' lh2 es'')).
    apply LfilledRec => //.
    by apply HLength.
Qed.

Lemma return_reduce_extract_vs: forall n lh es s C ts ts2,
    lfilled n lh [::Basic Return] es ->
    e_typing s C es (Tf [::] ts2) ->
    tc_return C = Some ts ->
    exists vs lh', const_list vs /\
      lfilled n lh' (vs ++ [::Basic Return]) es /\
      length vs = length ts.
Proof.
  move => n lh es s C ts ts2 HLF.
  move/lfilledP in HLF.
  generalize dependent ts. generalize dependent ts2.
  generalize dependent C. generalize dependent s.
  dependent induction HLF; subst; move => s C ts2 ts HType HN.
  - invert_e_typing.
    destruct ts0; destruct t1s => //; clear H1.
    apply et_to_bet in H5; auto_basic.
    simpl in H5.
    apply Return_typing in H5.
    destruct H5 as [ts2 [ts2' [H7 H8]]]. subst.
    rewrite HN in H8. inversion H8. subst.
    apply et_to_bet in H3; last by apply const_list_is_basic.
    apply const_es_exists in H.
    destruct H as [vs' H]. subst.
    apply Const_list_typing in H3. simpl in H3.
    rewrite catA in H3. symmetry in H3.
    apply cat_split in H3. destruct H3.
    replace vs' with (take (size (ts1 ++ ts2')) vs' ++ drop (size (ts1 ++ ts2')) vs'); last by apply cat_take_drop.
    exists (v_to_e_list (drop (size (ts1 ++ ts2')) vs')), (LBase (v_to_e_list (take (size (ts1 ++ ts2')) vs')) es').
    repeat split.
    + by apply v_to_e_is_const_list.
    + apply/lfilledP.
      rewrite -v_to_e_cat. rewrite -catA.
      rewrite cat_abcd_a_bc_d.
      by apply LfilledBase; apply v_to_e_is_const_list.
    + rewrite H0.
      repeat rewrite length_is_size.
      rewrite v_to_e_size. rewrite -map_drop.
      by rewrite size_map.
  - invert_e_typing.
    destruct ts0; destruct t1s => //; clear H1.
    edestruct IHHLF; eauto.
    destruct H0 as [lh2 [HConst [HLF2 HLength]]].
    repeat eexists. repeat split => //; eauto.
    move/lfilledP in HLF2. apply/lfilledP.
    instantiate (1 := (LRec vs (length ts2) es' lh2 es'')).
    apply LfilledRec => //.
    by apply HLength.
Qed.

Lemma le_add: forall n m,
    n <= m ->
    exists k, m = n+k.
Proof.
  move => n m. generalize dependent n.
  induction m => //=; move => n H.
  - destruct n => //=. by exists 0.
  - destruct n => //=.
    + by exists (m.+1).
    + apply IHm in H. destruct H as [k H].
      exists k. by lias.
Qed.

(*
  These two guarantees that the extra conditions we put in progress_e are true -- the second
    being true only if the function doesn't return anything (so we are not in the middle of some
    Local functions).
*)
Lemma s_typing_lf_br: forall s rs i vs es ts,
    s_typing s rs i vs es ts ->
    (forall n lh k, lfilled n lh [::Basic (Br k)] es -> k < n).
Proof.
  move => s rs i vs es ts HType n lh k HLF.
  inversion HType; subst.
  destruct (k<n) eqn: H3 => //=.
  move/ltP in H3.
  assert (Inf : n <= k); first by lias.
  apply le_add in Inf.
  destruct Inf as [j Inf]. subst.
  clear H3.
  eapply br_reduce_label_length in H1; eauto.
  simpl in H1.
  assert (E : tc_label C0 = [::]); first by eapply inst_t_context_label_empty; eauto.
  by rewrite Inf in H1.
Qed.

Lemma s_typing_lf_return: forall s i vs es ts,
    s_typing s None i vs es ts ->
    (forall n, not_lf_return es n).
Proof.
  unfold not_lf_return.
  move => s i vs es ts HType n lh HContra.
  inversion HType; subst.
  by eapply return_reduce_return_some in H1; eauto.
Qed.

Lemma t_progress_e: forall s i C C' vs vcs es tf ts1 ts2 lab ret,
    e_typing s C es tf ->
    tf = Tf ts1 ts2 ->
    C = (upd_label (upd_local_return C' (map typeof vs) ret) lab) ->
    inst_typing s i C' ->
    map typeof vcs = ts1 ->
    store_typing s ->
    (forall n lh k, lfilled n lh [::Basic (Br k)] es -> k < n) ->
    (forall n, not_lf_return es n) ->
    terminal_form (v_to_e_list vcs ++ es) \/
    exists s' vs' es', reduce s vs (v_to_e_list vcs ++ es) i s' vs' es'.
Proof.
  (* e_typing *)
  move => s i C C' vs vcs es tf ts1 ts2 lab ret HType.
  move: i C' vs vcs ts1 ts2 lab ret.
  (* Initially I had the wrong order of lab and ret --
       The error message here is extremely misleading *)
  apply e_typing_ind' with (e := HType)
    (P := fun s C es tf (_ : e_typing s C es tf) => forall i C' vs vcs ts1 ts2 lab ret,
              tf = Tf ts1 ts2 ->
              C = (upd_label (upd_local_return C' (map typeof vs) ret) lab) ->
              inst_typing s i C' ->
              map typeof vcs = ts1 ->
              store_typing s ->
              (forall n lh k, lfilled n lh [::Basic (Br k)] es -> k < n) ->
              (forall n, not_lf_return es n) ->
              terminal_form (v_to_e_list vcs ++ es) \/
              exists s' vs' es', reduce s vs (v_to_e_list vcs ++ es) i s' vs' es')
    (P0 := fun s rs i vs es ts (_ : s_typing s rs i vs es ts) =>
              store_typing s ->
              (forall n lh k, lfilled n lh [::Basic (Br k)] es -> k < n) ->
              (forall n, not_lf_return es n) ->
              (const_list es /\ length es = length ts) \/
              es = [::Trap] \/
              exists s' vs' es', reduce s vs es i s' vs' es'); clear.
  (* The previous variables s/C/es/tf still lingers here so we need to clear *)
(*  generalize dependent vcs.
  dependent induction HType; subst; move => vcs HIT HConstType HST HBrDepth HNRet. *)
  - (* Basic *)
    move => s C bes tf HType.
    move => i C' vs vcs ts1 ts2 lab ret HTF HContext HInst HConstType HST HBrDepth HNRet.
    subst.
    eapply t_progress_be in HType; try instantiate (1 := vs) in HType; try by eauto.
    destruct HType as [HType | [s' [vs' [es' HType]]]].
    + left.
      unfold terminal_form; left.
      apply const_list_concat => //. by apply v_to_e_is_const_list.
    + right.
      repeat eexists. by apply HType.
    + unfold not_lf_br. move => k lh HContra.
      by apply HBrDepth in HContra.
  - (* Composition *)
    move => s C es e t1s t2s t3s HType1 IHHType1 HType2 IHHType2.
    move => i C' vs vcs ts1 ts2 lab ret HTF HContext HInst HConstType HST HBrDepth HNRet.
    inversion HTF; subst.
    edestruct IHHType1; eauto.
    { move => n lh k HLF.
      eapply lf_composition in HLF.
      destruct HLF as [lh' HLF].
      instantiate (1 := [::e]) in HLF.
      eapply HBrDepth.
      by apply HLF. }
    { move => n.
      eapply nlfret_right. by apply HNRet. }
    + (* Terminal *)
      unfold terminal_form in H. destruct H.
      * (* Const *)
        apply const_list_split in H. destruct H as [HC1 HC2].
        apply et_to_bet in HType1; last by apply const_list_is_basic.
        apply const_es_exists in HC2.
        destruct HC2 as [esv HC2]. subst.
        apply Const_list_typing in HType1. subst.
        edestruct IHHType2; eauto.
        { by apply map_cat. }
        { move => n lh k HLF.
          eapply lf_composition_left in HLF.
          instantiate (1 := v_to_e_list esv) in HLF.
          destruct HLF as [lh' HLF].
          eapply HBrDepth; eauto.
          by apply v_to_e_is_const_list. }
        { move => n.
          eapply nlfret_left.
          instantiate (1 := v_to_e_list esv); first by apply v_to_e_is_const_list.
          by apply HNRet. }
        -- (* Terminal *)
          unfold terminal_form in H. destruct H.
          ++ left. unfold terminal_form. left.
             rewrite -v_to_e_cat in H.
             by rewrite catA.
          ++ apply extract_list1 in H. destruct H.
             rewrite -v_to_e_cat in H.
             destruct vcs => //=.
             destruct esv => //=.
             left. subst. by apply terminal_trap.
        -- (* reduce *)
          rewrite -v_to_e_cat in H.
          rewrite -catA in H.
          by right.
      * (* Trap *)
        destruct vcs => //=; destruct es => //=; destruct es => //=.
        simpl in H. inversion H. subst.
        right.
        exists s, vs, [::Trap].
        apply r_simple.
        eapply rs_trap => //.
        instantiate (1 := (LBase [::] [::e])).
        apply/lfilledP.
        by apply LfilledBase => //=; apply v_to_e_is_const_list.
    + (* reduce *)
      destruct H as [s' [vs' [es' HReduce]]].
      right.
      exists s', vs', (es' ++ [::e]).
      eapply r_label; eauto; try apply/lfilledP.
      * assert (LF : lfilledInd 0 (LBase [::] [::e]) (v_to_e_list vcs ++ es) ([::] ++ (v_to_e_list vcs ++ es) ++ [::e]));
          first by apply LfilledBase.
        simpl in LF. rewrite -catA in LF. by apply LF.
      * by apply LfilledBase.
  - (* Weakening *)
    (* This is interetingly easy. Think more carefully: the only part that is
       relevant in the reduction is ts1, but ts1 is only required for typing the
       const list. So we just separate the new const list into 2 parts and add
       the first part to the result correspondingly! *)
    move => s C es ts t1s t2s HType IHHType.
    move => i C' vs vcs ts1 ts2 lab ret HTF HContext HInst HConstType HST HBrDepth HNRet.
    inversion HTF; subst.
    symmetry in H0. apply cat_split in H0. destruct H0 as [HCT1 HCT2].
    rewrite - map_take in HCT1.
    rewrite - map_drop in HCT2.
    assert (Evcs : vcs = take (size ts) vcs ++ drop (size ts) vcs).
    { symmetry. by apply cat_take_drop. }
    rewrite Evcs. rewrite - v_to_e_cat.
    edestruct IHHType; eauto.
    + (* Terminal *)
      unfold terminal_form in H0.
      destruct H0 => //=.
      * (* Const *)
        left. unfold terminal_form. left.
        rewrite -catA. apply const_list_concat => //.
        by apply v_to_e_is_const_list.
      * (* Trap *)
        apply v_e_trap in H0; last by apply v_to_e_is_const_list.
        destruct H0. subst.
        rewrite H0.
        destruct (drop (size ts) vcs) eqn:HDrop => //=.
        clear H0. rewrite cats0 in H. rewrite -H.
        rewrite cats0.
        destruct vcs => //.
        -- left. by apply terminal_trap.
        -- right.
           exists s, vs, [::Trap].
           apply r_simple.
           apply reduce_trap_left => //.
           by apply v_to_e_is_const_list.
    + (* reduce *)
      destruct H0 as [s' [vs' [es' HReduce]]].
      right.
      exists s', vs', (v_to_e_list (take (size ts) vcs) ++ es').
      rewrite -catA.
      by apply reduce_composition_left => //; apply v_to_e_is_const_list.
  - (* Trap *)
    destruct vcs => //; first by left; apply terminal_trap.
    right.
    exists s, vs, [::Trap].
    apply r_simple.
    apply reduce_trap_left => //.
    by apply v_to_e_is_const_list.
  - (* Local *)
    move => s C n j vs0 es ts HType IHHType HLength.
    move => i C' vs vcs ts1 ts2 lab ret HTF HContext HInst HConstType HST HBrDepth HNRet.
    inversion HTF; subst; clear HTF.
    symmetry in H0.
    invert_typeof_vcs.
    right.
    destruct (return_reduce_decidable es) as [HEMT | HEMF].
    { inversion HType; subst.
      unfold return_reduce in HEMT.
      destruct HEMT as [n [lh HLF]].
      (* HEMT is almost what we need to prove the rs_return reduction, but we also need to prove
           that there are some consts of suitable length before the [::Basic Return] as well.
         Done as a separate lemma. *)
      eapply return_reduce_extract_vs in HLF; eauto.
      instantiate (1 := ts2) in HLF.
      destruct HLF as [cs [lh' [HConst [HLF2 HLength]]]].
      repeat eexists.
      apply r_simple.
      eapply rs_return; eauto.
      by [].
    }
    edestruct IHHType as [ | [ | ]]; eauto.
    {
      move => n lh k HLF.
      by eapply s_typing_lf_br in HLF; eauto.
    }
    { unfold return_reduce in HEMF. unfold not_lf_return.
      move => n lh HContra.
      apply HEMF. by eauto.
    }
    + (* Const *)
      destruct H.
      exists s, vs, es.
      apply r_simple.
      by apply rs_local_const.
    + (* Trap *)
      subst.
      exists s, vs, [::Trap].
      apply r_simple.
      by apply rs_local_trap.
    + (* reduce *)
      destruct H as [s' [vs' [es' HReduce]]].
      exists s', vs, [::Local (length ts2) j vs' es'].
      by apply r_local; apply HReduce.
  - (* Invoke *)
    move => s C cl tf HType.
    move => i C' vs vcs ts1 ts2 lab ret HTF HContext HInst HConstType HST HBrDepth HNRet.
    inversion HType; subst.
    inversion H5; subst; clear H5.
    + (* Native *)
      (* Very weirdly, this case requires almost nothing.
         Take some time and look at this again later. *)
      right.
      exists s, vs, [:: Local (length ts2) i0 (vcs ++ n_zeros ts) [::Basic (Block (Tf [::] ts2) es)]].
      eapply r_invoke_native; eauto.
      repeat rewrite length_is_size. by rewrite size_map.
    + (* Host *)
      right.
      (* There are two possible reduction paths dependning on whether the host
         call was successful. However for the proof here we just have to show that
         on exists -- so just use the easier failure case. *)
      exists s, vs, [::Trap].
      eapply r_invoke_host_failure; eauto.
      repeat rewrite length_is_size.
      by rewrite size_map.
  - (* Label *)
    move => s C e0s es ts t2s n HType1 IHHType1 HType2 IHHType2 HLength.
    move => i C' vs vcs ts1 ts2 lab ret HTF HContext HInst HConstType HST HBrDepth HNRet.
    inversion HTF; subst.
    symmetry in H0. invert_typeof_vcs.
    rewrite upd_label_overwrite in HType2. simpl in HType2.
    destruct (br_reduce_decidable es) as [HEMT | HEMF].
    { unfold br_reduce in HEMT.
      destruct HEMT as [n [lh HLF]].
      right. 
      assert (LF : lfilled n lh [::Basic (Br (n+0))] es); first by rewrite addn0.
      eapply br_reduce_extract_vs in H => //; eauto.
      instantiate (1 := ts) in H.
      destruct H as [cs [lh' [HConst [HLF2 HLength]]]].
      rewrite addn0 in HLF2.
      repeat eexists.
      apply r_simple.
      eapply rs_br; eauto.
      by [].
    }
    edestruct IHHType2; eauto.
    { rewrite upd_label_overwrite. simpl. eauto. }
    { unfold br_reduce in HEMF.
      move => n lh k HLF.
      assert (Inf : k < n.+1). (* FIXME: Proof items to be added here. *)
      eapply HBrDepth.
      move/lfilledP in HLF.
      apply/lfilledP.
      assert (LF : lfilledInd (n.+1) (LRec [::] (length ts) e0s lh [::]) [::Basic (Br k)] ([::] ++ [::Label (length ts) e0s es] ++ [::]));
        first by apply LfilledRec.
      rewrite cats0 in H. simpl in H.
      apply H.
      rewrite ltnS in H.
      rewrite leq_eqVlt in H.
      remove_bools_options => //.
      subst.
      exfalso.
      apply HEMF. repeat eexists. by apply HLF.
    }
    { unfold not_lf_return.
      move => n lh HContra.
      unfold not_lf_return in HNRet.
      eapply HNRet.
      move/lfilledP in HContra.
      apply/lfilledP.
      assert (LF : lfilledInd (n.+1) (LRec [::] (length ts) e0s lh [::]) [::Basic Return] ([::] ++ [::Label (length ts) e0s es] ++ [::]));
        first by apply LfilledRec.
      by apply H.
    }
    + (* Terminal *)
      apply terminal_form_v_e in H.
      unfold terminal_form in H. destruct H.
      * (* Const *)
        right.
        exists s, vs, es.
        apply r_simple.
        by apply rs_label_const.
      * (* Trap *)
        right. subst.
        exists s, vs, [::Trap].
        apply r_simple.
        by apply rs_label_trap.
        by apply v_to_e_is_const_list.
    + (* reduce *)
      (* This is also surprisingly easy... *)
      destruct H as [s' [vs' [es' HReduce]]].
      right.
      simpl in HReduce.
      exists s', vs', [::Label (length ts) e0s es'].
      by eapply r_label; eauto; apply label_lfilled1.
  - (* s_typing *)
    move => s j vs0 es rs ts C C0 tvs HIT HContext HType IHHType HRetType HST HBrDepth HNRet.
    subst.
    edestruct IHHType; eauto.
    { (* Context *)
      assert (E : tc_local C0 = [::]).
      { by eapply inst_t_context_local_empty; eauto. }
      rewrite E. simpl.
      replace (upd_local_return C0 tvs rs) with
          (upd_label (upd_local_return C0 tvs rs) [::]); first by eauto.
      (* replace *)
      assert (E' : tc_label (upd_local_return C0 tvs rs) = [::]).
      { simpl. by eapply inst_t_context_label_empty; eauto. }
      rewrite -E'.
      by apply upd_label_unchanged. }
    { by instantiate (1 := [::]). }
    + unfold terminal_form in H. destruct H.
      * (* Const *)
        left. split => //.
        apply et_to_bet in HType; last by apply const_list_is_basic.
        simpl in H.
        apply const_es_exists in H. destruct H as [es' H]. subst.
        apply Const_list_typing in HType. subst.
        repeat rewrite length_is_size. simpl.
        rewrite v_to_e_size. by rewrite size_map.
      * (* Trap *)
        right. by left.
    + (* reduce *)
       simpl in H. right. by right.
Qed.

Theorem t_progress: forall s vs es i ts,
    config_typing i s vs es ts ->
    terminal_form es \/
    exists s' vs' es', reduce s vs es i s' vs' es'.
Proof.
  move => s vs es i ts HType.
  inversion HType. subst.
  inversion H0. subst.
  eapply t_progress_e with (vcs := [::]) (ret := None) (lab := [::]) in H3; eauto.
  - assert (E : tc_local C0 = [::]).
    { by eapply inst_t_context_local_empty; eauto. }
    rewrite E. simpl.
    replace (upd_local_return C0 tvs None) with
        (upd_label (upd_local_return C0 tvs None) [::]); first by eauto.
    assert (E' : tc_label (upd_local_return C0 tvs None) = [::]).
    { simpl. by eapply inst_t_context_label_empty; eauto. }
    rewrite -E'.
    by apply upd_label_unchanged. 
  - by eapply s_typing_lf_br; eauto.
  - by eapply s_typing_lf_return; eauto.
Qed.

End Host.
