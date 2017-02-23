(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

(** Trace of simulation *)

module Simulation_info : sig
  type 'a t =
    {
      story_id: int ;
      story_time: float ;
      story_event: int ;
      profiling_info: 'a;
    }
  (** type of data to be given with observables for story compression
      (such as date when the obs is triggered*)

  val compare_by_story_id : 'a t -> 'a t -> int

  val update_profiling_info : 'a -> 'b t -> 'a t

  val event : 'a t -> int
  val story_id : 'a t -> int

  val to_json : ('a -> Yojson.Basic.json) -> 'a t -> Yojson.Basic.json
  val of_json : (Yojson.Basic.json -> 'a) -> Yojson.Basic.json -> 'a t
end

type event_kind =
  | RULE of int
  | INIT of int list (** the agents *)
  | PERT of string (** the rule *)

val print_event_kind :
  ?env:Model.t -> Format.formatter -> event_kind -> unit
val print_event_kind_dot_annot :
  Model.t -> Format.formatter -> event_kind -> unit

type step =
  | Subs of int * int
  | Rule of
      int *
      Instantiation.concrete Instantiation.event *
      unit Simulation_info.t
  | Pert of
      string *
      Instantiation.concrete Instantiation.event *
      unit Simulation_info.t
  | Init of Instantiation.concrete Instantiation.action list
  | Obs of
      string *
      Instantiation.concrete Instantiation.test list list *
      unit Simulation_info.t
  | Dummy  of string

type t = step list

val dummy_step : string -> step
val subs_step : int -> int -> step

val step_is_obs : step -> bool
val step_is_init : step -> bool
val step_is_subs : step -> bool
val step_is_rule : step -> bool
val step_is_pert : step -> bool
val has_creation_of_step: step -> bool

val tests_of_step :
  step -> Instantiation.concrete Instantiation.test list
val actions_of_step :
  step ->
  (Instantiation.concrete Instantiation.action list *
   (Instantiation.concrete Instantiation.site *
    Instantiation.concrete Instantiation.binding_state) list)
val side_effects_of_step :
  step -> Instantiation.concrete Instantiation.site list
val simulation_info_of_step: step -> unit Simulation_info.t option

val creation_of_actions :
  ('a -> 'b) -> 'a Instantiation.action list -> 'b list
val creation_of_step : step -> int list

val print_step:
  ?compact:bool -> ?env:Model.t -> Format.formatter -> step -> unit

val step_to_yojson : step -> Yojson.Basic.json
val step_of_yojson : Yojson.Basic.json -> step

val to_yojson : t -> Yojson.Basic.json
val of_yojson : Yojson.Basic.json -> t
