(** Basic operations over Wasm datatypes **)
(* (C) J. Pichon, M. Bodin - see LICENSE.txt *)

Require Import common.
From mathcomp Require Import ssreflect ssrfun ssrnat ssrbool eqtype seq.
From compcert Require lib.Floats.
Require Export datatypes_properties list_extra.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.


Section Host.

Variable host_function : eqType.

Let function_closure := function_closure host_function.
Let store_record := store_record host_function.
Let administrative_instruction := administrative_instruction host_function.
Let lholed := lholed host_function.


Definition read_bytes (m : memory) (n : nat) (l : nat) : bytes :=
  take l (List.skipn n (mem_data m)).

Definition write_bytes (m : memory) (n : nat) (bs : bytes) : memory :=
  Build_memory
    (app (take n (mem_data m)) (app bs (List.skipn (n + length bs) (mem_data m))))
    (mem_limit m).

Definition mem_append (m : memory) (bs : bytes) :=
  Build_memory
    (app (mem_data m) bs)
    (mem_limit m).

Definition upd_s_mem (s : store_record) (m : seq memory) : store_record :=
  Build_store_record
    (s_funcs s)
    (s_tables s)
    m
    (s_globals s).

Definition mem_size (m : memory) :=
  length (mem_data m).

Definition mem_grow (m : memory) (n : nat) : option memory:=
  let new_mem_data := (mem_data m ++ bytes_replicate (n * 64000) #00) in
  if length new_mem_data > (lim_max (mem_limit m)) * 64000 then None
  else
    Some (Build_memory
            new_mem_data
            (mem_limit m)).

(* TODO: We crucially need documentation here. *)

Definition load (m : memory) (n : nat) (off : static_offset) (l : nat) : option bytes :=
  if mem_size m >= (n + off + l)
  then Some (read_bytes m (n + off) l)
  else None.

Definition sign_extend (s : sx) (l : nat) (bs : bytes) : bytes :=
  (* TODO *) bs.
(* TODO
  let: msb := msb (msbyte bytes) in
  let: byte := (match sx with sx_U => O | sx_S => if msb then -1 else 0) in
  bytes_takefill byte l bytes
*)

Definition load_packed (s : sx) (m : memory) (n : nat) (off : static_offset) (lp : nat) (l : nat) : option bytes :=
  option_map (sign_extend s l) (load m n off lp).

Definition store (m : memory) (n : nat) (off : static_offset) (bs : bytes) (l : nat) : option memory :=
  if (mem_size m) >= (n + off + l)
  then Some (write_bytes m (n + off) (bytes_takefill #00 l bs))
  else None.

Definition store_packed := store.

(* TODO *)
Parameter serialise_i32 : i32 -> bytes.
Parameter serialise_i64 : i64 -> bytes.
Parameter serialise_f32 : f32 -> bytes.
Parameter serialise_f64 : f64 -> bytes.

Definition wasm_deserialise (bs : bytes) (vt : value_type) : value :=
  match vt with
  | T_i32 => ConstInt32 (Wasm_int.Int32.repr (common.Memdata.decode_int bs))
  | T_i64 => ConstInt64 (Wasm_int.Int64.repr (common.Memdata.decode_int bs))
  | T_f32 => ConstFloat32 (Floats.Float32.of_bits (Integers.Int.repr (common.Memdata.decode_int bs)))
  | T_f64 => ConstFloat64 (Floats.Float.of_bits (Integers.Int64.repr (common.Memdata.decode_int bs)))
  end.


Definition typeof (v : value) : value_type :=
  match v with
  | ConstInt32 _ => T_i32
  | ConstInt64 _ => T_i64
  | ConstFloat32 _ => T_f32
  | ConstFloat64 _ => T_f64
  end.

Definition option_projl (A B : Type) (x : option (A * B)) : option A :=
  option_map fst x.

Definition option_projr (A B : Type) (x : option (A * B)) : option B :=
  option_map snd x.

Definition t_length (t : value_type) : nat :=
  match t with
  | T_i32 => 4
  | T_i64 => 8
  | T_f32 => 4
  | T_f64 => 8
  end.

Definition tp_length (tp : packed_type) : nat :=
  match tp with
  | Tp_i8 => 1
  | Tp_i16 => 2
  | Tp_i32 => 4
  end.

Definition is_int_t (t : value_type) : bool :=
  match t with
  | T_i32 => true
  | T_i64 => true
  | T_f32 => false
  | T_f64 => false
  end.

Definition is_float_t (t : value_type) : bool :=
  match t with
  | T_i32 => false
  | T_i64 => false
  | T_f32 => true
  | T_f64 => true
  end.

Definition is_mut (tg : global_type) : bool :=
  tg_mut tg == MUT_mut.


Definition app_unop_i (e : Wasm_int.type) (iop : unop_i) : Wasm_int.sort e -> Wasm_int.sort e :=
  let: Wasm_int.Pack u (Wasm_int.Class eqmx intmx) as e' := e
    return Wasm_int.sort e' -> Wasm_int.sort e' in
  match iop with
  | Ctz => Wasm_int.int_ctz intmx
  | Clz => Wasm_int.int_clz intmx
  | Popcnt => Wasm_int.int_popcnt intmx
  end.

Definition app_unop_f (e : Wasm_float.type) (fop : unop_f) : Wasm_float.sort e -> Wasm_float.sort e :=
  let: Wasm_float.Pack u (Wasm_float.Class eqmx mx) as e' := e
    return Wasm_float.sort e' -> Wasm_float.sort e' in
  match fop with
  | Neg => Wasm_float.float_neg mx
  | Abs => Wasm_float.float_abs mx
  | Ceil => Wasm_float.float_ceil mx
  | Floor => Wasm_float.float_floor mx
  | Trunc => Wasm_float.float_trunc mx
  | Nearest => Wasm_float.float_nearest mx
  | Sqrt => Wasm_float.float_sqrt mx
  end.

Definition app_binop_i (e : Wasm_int.type) (iop : binop_i)
    : Wasm_int.sort e -> Wasm_int.sort e -> option (Wasm_int.sort e) :=
  let: Wasm_int.Pack u (Wasm_int.Class _ mx) as e' := e
    return Wasm_int.sort e' -> Wasm_int.sort e' -> option (Wasm_int.sort e') in
  let: add_some := fun f c1 c2 => Some (f c1 c2) in
  match iop with
  | Add => add_some (Wasm_int.int_add mx)
  | Sub => add_some (Wasm_int.int_sub mx)
  | Mul => add_some (Wasm_int.int_mul mx)
  | Div SX_U => Wasm_int.int_div_u mx
  | Div SX_S => Wasm_int.int_div_s mx
  | Rem SX_U => Wasm_int.int_rem_u mx
  | Rem SX_S => Wasm_int.int_rem_s mx
  | And => add_some (Wasm_int.int_and mx)
  | Or => add_some (Wasm_int.int_or mx)
  | Xor => add_some (Wasm_int.int_xor mx)
  | Shl => add_some (Wasm_int.int_shl mx)
  | Shr SX_U => add_some (Wasm_int.int_shr_u mx)
  | Shr SX_S => add_some (Wasm_int.int_shr_s mx)
  | Rotl => add_some (Wasm_int.int_rotl mx)
  | Rotr => add_some (Wasm_int.int_rotr mx)
  end.

Definition app_binop_f (e : Wasm_float.type) (fop : binop_f)
    : Wasm_float.sort e -> Wasm_float.sort e -> option (Wasm_float.sort e) :=
  let: Wasm_float.Pack u (Wasm_float.Class _ mx) as e' := e
    return Wasm_float.sort e' -> Wasm_float.sort e' -> option (Wasm_float.sort e') in
  let: add_some := fun f c1 c2 => Some (f c1 c2) in
  match fop with
  | Addf => add_some (Wasm_float.float_add mx)
  | Subf => add_some (Wasm_float.float_sub mx)
  | Mulf => add_some (Wasm_float.float_mul mx)
  | Divf => add_some (Wasm_float.float_div mx)
  | Min => add_some (Wasm_float.float_min mx)
  | Max => add_some (Wasm_float.float_max mx)
  | Copysign => add_some (Wasm_float.float_copysign mx)
  end.

Definition app_testop_i (e : Wasm_int.type) (o : testop) : Wasm_int.sort e -> bool :=
  let: Wasm_int.Pack u (Wasm_int.Class _ mx) as e' := e return Wasm_int.sort e' -> bool in
  match o with
  | Eqz => Wasm_int.int_eqz mx
  end.

Definition app_relop_i (e : Wasm_int.type) (rop : relop_i)
    : Wasm_int.sort e -> Wasm_int.sort e -> bool :=
  let: Wasm_int.Pack u (Wasm_int.Class _ mx) as e' := e
    return Wasm_int.sort e' -> Wasm_int.sort e' -> bool in
  match rop with
  | Eq => Wasm_int.int_eq mx
  | Ne => @Wasm_int.int_ne _
  | Lt SX_U => Wasm_int.int_lt_u mx
  | Lt SX_S => Wasm_int.int_lt_s mx
  | Gt SX_U => Wasm_int.int_gt_u mx
  | Gt SX_S => Wasm_int.int_gt_s mx
  | Le SX_U => Wasm_int.int_le_u mx
  | Le SX_S => Wasm_int.int_le_s mx
  | Ge SX_U => Wasm_int.int_ge_u mx
  | Ge SX_S => Wasm_int.int_ge_s mx
  end.

Definition app_relop_f (e : Wasm_float.type) (rop : relop_f)
    : Wasm_float.sort e -> Wasm_float.sort e -> bool :=
  let: Wasm_float.Pack u (Wasm_float.Class _ mx) as e' := e
    return Wasm_float.sort e' -> Wasm_float.sort e' -> bool in
  match rop with
  | Eqf => Wasm_float.float_eq mx
  | Nef => @Wasm_float.float_ne _
  | Ltf => Wasm_float.float_lt mx
  | Gtf => Wasm_float.float_gt mx
  | Lef => Wasm_float.float_le mx
  | Gef => Wasm_float.float_ge mx
  end.

Definition types_agree (t : value_type) (v : value) : bool :=
  (typeof v) == t.

Definition cl_type (cl : function_closure) : function_type :=
  match cl with
  | Func_native _ tf _ _ => tf
  | Func_host tf _ => tf
  end.

Definition rglob_is_mut (g : global) : bool :=
  g_mut g == MUT_mut.

Definition option_bind (A B : Type) (f : A -> option B) (x : option A) :=
  match x with
  | None => None
  | Some y => f y
  end.

Definition stypes (s : store_record) (i : instance) (j : nat) : option function_type :=
  List.nth_error (i_types i) j.
(* TODO: optioned *)

Definition sfunc_ind (s : store_record) (i : instance) (j : nat) : option nat :=
  List.nth_error (i_funcs i) j.

Definition sfunc (s : store_record) (i : instance) (j : nat) : option function_closure :=
  option_bind (List.nth_error (s_funcs s)) (sfunc_ind s i j).

Definition sglob_ind (s : store_record) (i : instance) (j : nat) : option nat :=
  List.nth_error (i_globs i) j.

Definition sglob (s : store_record) (i : instance) (j : nat) : option global :=
  option_bind (List.nth_error (s_globals s))
    (sglob_ind s i j).

Definition sglob_val (s : store_record) (i : instance) (j : nat) : option value :=
  option_map g_val (sglob s i j).

Definition smem_ind (s : store_record) (i : instance) : option nat :=
  match i.(i_memory) with
  | nil => None
  | cons k _ => Some k
  end.

Definition tab_size (t: tableinst) : nat :=
  length (table_data t).

(**
  Get the ith table in the store s, and then get the jth index in the table;
  in the end, retrieve the corresponding function closure from the store.
 **)
(**
  There is the interesting use of option_bind (fun x => x) to convert an element
  of type option (option x) to just option x.
**)
Definition stab_index (s: store_record) (i j: nat) : option nat :=
  let: stabinst := List.nth_error (s_tables s) i in
  option_bind (fun x => x) (
    option_bind
      (fun stab_i => List.nth_error (table_data stab_i) j)
  stabinst).

Definition stab_s (s : store_record) (i j : nat) : option function_closure :=
  let n := stab_index s i j in
  option_bind
    (fun id => List.nth_error (s_funcs s) id)
  n.

Definition stab (s : store_record) (i : instance) (j : nat) : option function_closure :=
  match i.(i_tab) with
  | nil => None
  | k :: _ => stab_s s k j
  end.

Definition update_list_at {A : Type} (l : seq A) (k : nat) (a : A) :=
  take k l ++ [::a] ++ List.skipn (k + 1) l.

Definition supdate_glob_s (s : store_record) (k : nat) (v : value) : option store_record :=
  option_map
    (fun g =>
      let: g' := Build_global (g_mut g) v in
      let: gs' := update_list_at (s_globals s) k g' in
      Build_store_record (s_funcs s) (s_tables s) (s_mems s) gs')
    (List.nth_error (s_globals s) k).

Definition supdate_glob (s : store_record) (i : instance) (j : nat) (v : value) : option store_record :=
  option_bind
    (fun k => supdate_glob_s s k v)
    (sglob_ind s i j).

Definition is_const (e : administrative_instruction) : bool :=
  if e is Basic (EConst _) then true else false.

Definition const_list (es : seq administrative_instruction) : bool :=
  List.forallb is_const es.

Definition those_const_list (es : list administrative_instruction) : option (list value) :=
  those (List.map (fun e => match e with | Basic (EConst v) => Some v | _ => None end) es).

Definition glob_extension (g1 g2: global) : bool.
Proof.
  destruct (g_mut g1).
  - (* Immut *)
    exact ((g_mut g2 == MUT_immut) && (g_val g1 == g_val g2)).
  - (* Mut *)
    destruct (g_mut g2).
    + exact false.
    + destruct (g_val g1) eqn:T1;
      lazymatch goal with
      | H1: g_val g1 = ?T1 _ |- _ =>
        destruct (g_val g2) eqn:T2;
          lazymatch goal with
          | H2: g_val g2 = T1 _ |- _ => exact true
          | _ => exact false
          end
      | _ => exact false
      end.
Defined.

Definition tab_extension (t1 t2 : tableinst) :=
  (tab_size t1 <= tab_size t2) &&
  (t1.(table_max_opt) == t2.(table_max_opt)).

Definition mem_extension (m1 m2 : memory) :=
  (mem_size m1 <= mem_size m2) && (lim_max (mem_limit m1) == lim_max (mem_limit m2)).

Definition store_extension (s s' : store_record) : bool :=
  (s_funcs s == s_funcs s') &&
  (all2 tab_extension s.(s_tables) s'.(s_tables)) &&
  (all2 mem_extension s.(s_mems) s'.(s_mems)) &&
  (all2 glob_extension s.(s_globals) s'.(s_globals)).

Definition to_e_list (bes : seq basic_instruction) : seq administrative_instruction :=
  map Basic bes.

(** [v_to_e_list]: some kind of the opposite of [split_vals_e] (see [interperter.v]:
    takes a list of [v] and gives back a list where each [v] is mapped to [Basic (EConst v)]. **)
Definition v_to_e_list (ves : seq value) : seq administrative_instruction :=
  map (fun v => Basic (EConst v)) ves.

(** Converting a result into a stack. **)
Definition result_to_stack (r : result) :=
  match r with
  | result_values vs => v_to_e_list vs
  | result_trap => [:: Trap]
  end.

Fixpoint lfill (k : nat) (lh : lholed) (es : seq administrative_instruction) : option (seq administrative_instruction) :=
  match k with
  | 0 =>
    if lh is LBase vs es' then
      if const_list vs then Some (app vs (app es es')) else None
    else None
  | k'.+1 =>
    if lh is LRec vs n es' lh' es'' then
      if const_list vs then
        if lfill k' lh' es is Some lfilledk then
          Some (app vs (cons (Label n es' lfilledk) es''))
        else None
      else None
    else None
  end.

Definition lfilled (k : nat) (lh : lholed) (es : seq administrative_instruction) (es' : seq administrative_instruction) : bool :=
  if lfill k lh es is Some es'' then es' == es'' else false.

Inductive lfilledInd : nat -> lholed -> seq administrative_instruction -> seq administrative_instruction -> Prop :=
| LfilledBase: forall vs es es',
    const_list vs ->
    lfilledInd 0 (LBase vs es') es (vs ++ es ++ es')
| LfilledRec: forall k vs n es' lh' es'' es LI,
    const_list vs ->
    lfilledInd k lh' es LI ->
    lfilledInd (k.+1) (LRec vs n es' lh' es'') es (vs ++ [ :: (Label n es' LI) ] ++ es'').

Lemma lfilled_Ind_Equivalent: forall k lh es LI,
    lfilled k lh es LI <-> lfilledInd k lh es LI.
Proof.
  move => k. split.
  - move: lh es LI. induction k; move => lh es LI HFix.
    + unfold lfilled in HFix. simpl in HFix. destruct lh => //=.
      * destruct (const_list l) eqn:HConst => //=.
        { replace LI with (l++es++l0); first by apply LfilledBase.
          symmetry. move: HFix. by apply/eqseqP. }
    + unfold lfilled in HFix. simpl in HFix. destruct lh => //=.
      * destruct (const_list l) eqn:HConst => //=.
        { destruct (lfill k lh es) eqn:HLF => //=.
          { replace LI with (l ++ [ :: (Label n l0 l2)] ++ l1).
          apply LfilledRec; first by [].
          apply IHk. unfold lfilled; first by rewrite HLF.
          symmetry. move: HFix. by apply/eqseqP. }
        }
  - move => HLF. induction HLF.
    + unfold lfilled. unfold lfill. by rewrite H.
    + unfold lfilled. unfold lfill. rewrite H. fold lfill.
      unfold lfilled in IHHLF. destruct (lfill k lh' es) => //=.
      * replace LI with l => //=.
        symmetry. by apply/eqseqP.
Qed.

Lemma lfilledP: forall k lh es LI,
    reflect (lfilledInd k lh es LI) (lfilled k lh es LI).
Proof.
  move => k lh es LI. destruct (lfilled k lh es LI) eqn:HLFBool.
  - apply ReflectT. by apply lfilled_Ind_Equivalent.
  - apply ReflectF. move=> HContra. apply lfilled_Ind_Equivalent in HContra.
    by rewrite HLFBool in HContra.
Qed.

Fixpoint lfill_exact (k : nat) (lh : lholed) (es : seq administrative_instruction) : option (seq administrative_instruction) :=
  match k with
  | 0 =>
    if lh is LBase nil nil then Some es else None
  | k'.+1 =>
    if lh is LRec vs n es' lh' es'' then
      if const_list vs then
        if lfill_exact k' lh' es is Some lfilledk then
          Some (app vs (cons (Label n es' lfilledk) es''))
        else None
      else None
    else None
  end.

Definition lfilled_exact (k : nat) (lh : lholed) (es : seq administrative_instruction) (es' : seq administrative_instruction) : bool :=
  if lfill_exact k lh es is Some es'' then es' == es'' else false.

Definition load_store_t_bounds (a : alignment_exponent) (tp : option packed_type) (t : value_type) : bool :=
  match tp with
  | None => Nat.pow 2 a <= t_length t
  | Some tp' => (Nat.pow 2 a <= tp_length tp') && (tp_length tp' < t_length t) && (is_int_t t)
  end.

Definition cvt_i32 (s : option sx) (v : value) : option i32 :=
  match v with
  | ConstInt32 _ => None
  | ConstInt64 c => Some (wasm_wrap c)
  | ConstFloat32 c =>
    match s with
    | Some SX_U => Wasm_float.float_ui32_trunc f32m c
    | Some SX_S => Wasm_float.float_ui32_trunc f32m c
    | None => None
    end
  | ConstFloat64 c =>
    match s with
    | Some SX_U => Wasm_float.float_ui32_trunc f64m c
    | Some SX_S => Wasm_float.float_ui32_trunc f64m c
    | None => None
    end
  end.

Definition cvt_i64 (s : option sx) (v : value) : option i64 :=
  match v with
  | ConstInt32 c =>
    match s with
    | Some SX_U => Some (wasm_extend_u c)
    | Some SX_S => Some (wasm_extend_s c)
    | None => None
    end
  | ConstInt64 c => None
  | ConstFloat32 c =>
    match s with
    | Some SX_U => Wasm_float.float_ui64_trunc f32m c
    | Some SX_S => Wasm_float.float_si64_trunc f32m c
    | None => None
    end
  | ConstFloat64 c =>
    match s with
    | Some SX_U => Wasm_float.float_ui64_trunc f64m c
    | Some SX_S => Wasm_float.float_si64_trunc f64m c
    | None => None
    end
  end.

Definition cvt_f32 (s : option sx) (v : value) : option f32 :=
  match v with
  | ConstInt32 c =>
    match s with
    | Some SX_U => Some (Wasm_float.float_convert_ui32 f32m c)
    | Some SX_S => Some (Wasm_float.float_convert_si32 f32m c)
    | None => None
    end
  | ConstInt64 c =>
    match s with
    | Some SX_U => Some (Wasm_float.float_convert_ui64 f32m c)
    | Some SX_S => Some (Wasm_float.float_convert_si64 f32m c)
    | None => None
    end
  | ConstFloat32 c => None
  | ConstFloat64 c => Some (wasm_demote c)
  end.

Definition cvt_f64 (s : option sx) (v : value) : option f64 :=
  match v with
  | ConstInt32 c =>
    match s with
    | Some SX_U => Some (Wasm_float.float_convert_ui32 f64m c)
    | Some SX_S => Some (Wasm_float.float_convert_si32 f64m c)
    | None => None
    end
  | ConstInt64 c =>
    match s with
    | Some SX_U => Some (Wasm_float.float_convert_ui64 f64m c)
    | Some SX_S => Some (Wasm_float.float_convert_si64 f64m c)
    | None => None
    end
  | ConstFloat32 c => Some (wasm_promote c)
  | ConstFloat64 c => None
  end.


Definition cvt (t : value_type) (s : option sx) (v : value) : option value :=
  match t with
  | T_i32 => option_map ConstInt32 (cvt_i32 s v)
  | T_i64 => option_map ConstInt64 (cvt_i64 s v)
  | T_f32 => option_map ConstFloat32 (cvt_f32 s v)
  | T_f64 => option_map ConstFloat64 (cvt_f64 s v)
  end.

Definition bits (v : value) : bytes :=
  match v with
  | ConstInt32 c => serialise_i32 c
  | ConstInt64 c => serialise_i64 c
  | ConstFloat32 c => serialise_f32 c
  | ConstFloat64 c => serialise_f64 c
  end.

Definition bitzero (t : value_type) : value :=
  match t with
  | T_i32 => ConstInt32 (Wasm_int.int_zero i32m)
  | T_i64 => ConstInt64 (Wasm_int.int_zero i64m)
  | T_f32 => ConstFloat32 (Wasm_float.float_zero f32m)
  | T_f64 => ConstFloat64 (Wasm_float.float_zero f64m)
  end.

Definition n_zeros (ts : seq value_type) : seq value :=
  map bitzero ts.

(* TODO: lots of lemmas *)

End Host.

Arguments cl_type {host_function}.
Arguments to_e_list [host_function].
Arguments v_to_e_list [host_function].
Arguments result_to_stack [host_function].

