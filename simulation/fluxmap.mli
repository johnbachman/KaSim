(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

(** Flux map *)
val create_flux :
  Model.t -> Counter.t -> Primitives.din_kind -> string -> Data.din_data
val stop_flux : Model.t -> Counter.t -> Data.din_data -> Data.din

val incr_flux_flux : int -> int -> float -> Data.din_data -> unit
(** [incr_flux_flux of_rule on_rule val flux] *)

val incr_flux_hit : int -> Data.din_data -> unit

val get_flux_name : Data.din_data -> string
val flux_has_name : string -> Data.din_data -> bool
