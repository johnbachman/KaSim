(**
   * symmetries.ml
   * openkappa
   * Jérôme Feret & Ly Kim Quyen, projet Antique, INRIA Paris-Rocquencourt
   *
   * Creation: 2016, the 5th of December
   * Last modification: Time-stamp: <Feb 20 2017>
   *
   * Abstract domain to record relations between pair of sites in connected agents.
   *
   * Copyright 2010,2011,2012,2013,2014,2015,2016 Institut National de Recherche
   * en Informatique et en Automatique.
   * All rights reserved.  This file is distributed
   * under the terms of the GNU Library General Public License *)

(***************************************************************************)
(*TYPE*)
(***************************************************************************)

type symmetries =
  {
    store_contact_map :
      (Ckappa_sig.c_state list *
       (Ckappa_sig.c_agent_name * Ckappa_sig.c_site_name) list)
        Ckappa_sig.Site_map_and_set.Map.t
        Ckappa_sig.Agent_map_and_set.Map.t;
    store_partition_contact_map :
      Ckappa_sig.c_site_name list list Ckappa_sig.Agent_map_and_set.Map.t;
    store_partition_with_predicate :
      Ckappa_sig.c_site_name list list Ckappa_sig.Agent_map_and_set.Map.t;
  }

let init_symmetries =
  {
    store_contact_map = Ckappa_sig.Agent_map_and_set.Map.empty;
    store_partition_contact_map = Ckappa_sig.Agent_map_and_set.Map.empty;
    store_partition_with_predicate = Ckappa_sig.Agent_map_and_set.Map.empty
  }

(***************************************************************************)
(*PARTITION THE CONTACT MAP*)
(***************************************************************************)

let collect_partition_contact_map parameters error contact_map store_result =
  let error, store_result =
    Ckappa_sig.Agent_map_and_set.Map.fold
      (fun agent_type site_map (error, store_result) ->
         Ckappa_sig.Site_map_and_set.Map.fold
           (fun site_type (_state_list, pair_list) (error, store_result) ->
              let error, old_list =
                Common_map.get_agent_type parameters error
                  agent_type []
                  store_result
              in
              let error, site_list =
                List.fold_left (fun (error, current_list) (_a, site_type) ->
                    error, site_type :: current_list
                  ) (error, []) pair_list
              in
              let site_list = site_type :: site_list in
              let new_site_list = site_list :: old_list in
              let error, store_result =
                Ckappa_sig.Agent_map_and_set.Map.add_or_overwrite
                  parameters
                  error
                  agent_type
                  new_site_list
                  store_result
              in
              error, store_result
           ) site_map (error, store_result)
      ) contact_map (error, store_result)
  in
  error, store_result

(***************************************************************************)

let collect_partition_with_predicate parameters error
    partition_contact_map
    (predicate_ab: Ckappa_sig.c_site_name -> Ckappa_sig.c_site_name -> bool)
    store_result =
  let error, store_result =
    Ckappa_sig.Agent_map_and_set.Map.fold
      (fun agent_type list (error, store_result) ->
         let error, old_list =
           Common_map.get_agent_type parameters error
             agent_type
             []
             store_result
         in
         let error, new_partition_list =
           List.fold_left (fun (error, current_list) l ->
               let partition_list =
                 let rec aux acc =
                   match acc with
                   | [] | _ :: [] -> acc
                   | a :: b :: tl ->
                     if predicate_ab a b
                     then acc
                     else aux tl
                 in
                 aux l
               in
               let new_list = partition_list :: current_list in
               error, new_list
             ) (error, []) list
         in
         let error, store_result =
           Ckappa_sig.Agent_map_and_set.Map.add_or_overwrite
             parameters
             error
             agent_type
             new_partition_list
             store_result
         in
         error, store_result
      ) partition_contact_map (error, store_result)
  in
  error, store_result

(***************************************************************************)
(*PRINT*)
(***************************************************************************)

let print_partition_contact_map parameters error store_result =
  Ckappa_sig.Agent_map_and_set.Map.fold
    (fun agent_type l error ->
       List.fold_left (fun error l' ->
           List.fold_left (fun error site ->
               let () =
                 Loggers.fprintf (Remanent_parameters.get_logger parameters)
                   "agent_type:%i:site_type:%i\n"
                   (Ckappa_sig.int_of_agent_name agent_type)
                   (Ckappa_sig.int_of_site_name site)
               in
               error
             ) error l'
         ) error l
    ) store_result error

let print_contact_map parameters error contact_map =
  Ckappa_sig.Agent_map_and_set.Map.fold
    (fun agent site_map error ->
       Ckappa_sig.Site_map_and_set.Map.fold
         (fun site (state_list, pair_agent_site_list) error ->
            let error =
              List.fold_left (fun error (agent_name, site_name) ->
                  let () =
                    Loggers.fprintf (Remanent_parameters.get_logger parameters)
                      "agent_type:%i:site_type:%i\n"
                      (Ckappa_sig.int_of_agent_name agent_name)
                      (Ckappa_sig.int_of_site_name site_name)
                  in
                  error
                ) error (List.rev pair_agent_site_list)
            in
            let error =
              List.fold_left (fun error i ->
                  let () =
                    Loggers.fprintf (Remanent_parameters.get_logger parameters)
                      "agent_type:%i:site_type:%i:state:%i\n"
                      (Ckappa_sig.int_of_agent_name agent)
                      (Ckappa_sig.int_of_site_name site)
                      (Ckappa_sig.int_of_state_index i)
                  in
                  error
                ) error (List.rev state_list)
            in
            error
         ) site_map error
    ) contact_map error

let print_partition_with_predicate parameters error store_result =
  Ckappa_sig.Agent_map_and_set.Map.fold
    (fun agent_type l error ->
       List.fold_left (fun error l' ->
           List.fold_left (fun error site ->
               let () =
                 Loggers.fprintf (Remanent_parameters.get_logger parameters)
                   "agent_type:%i:site_type:%i\n"
                   (Ckappa_sig.int_of_agent_name agent_type)
                   (Ckappa_sig.int_of_site_name site)
               in
               error
             ) error l'
         ) error l
    ) store_result error

(***************************************************************************)
(*DETECT SYMMETRIES*)
(***************************************************************************)

let detect_symmetries parameters error handler contact_map =
  let store_result = init_symmetries in
  (*-------------------------------------------------------------*)
  (*PARTITION A CONTACT MAP RETURN A LIST OF LIST OF SITES*)
  let error, store_partition_contact_map =
    collect_partition_contact_map
      parameters error
      contact_map
      store_result.store_partition_contact_map
  in
  (*-------------------------------------------------------------*)
  (*PARTITION A CONTACT MAP RETURN A LIST OF LIST OF SITES WITH A PREDICATE*)
  let error, store_partition_with_predicate =
    collect_partition_with_predicate
      parameters error
      store_partition_contact_map
      (=) (*REPLACE THIS PREDICATE*)
      store_result.store_partition_with_predicate
  in
  (*-------------------------------------------------------------*)
  let store_result =
    {
      store_contact_map = contact_map;
      store_partition_contact_map = store_partition_contact_map;
      store_partition_with_predicate = store_partition_with_predicate
    }
  in
  (*-------------------------------------------------------------*)
  (*PRINT*)
  let error =
    if Remanent_parameters.get_trace parameters
    then
      let error =
        print_partition_contact_map parameters error
          store_result.store_partition_contact_map
      in
      let _ =
        Loggers.fprintf (Remanent_parameters.get_logger parameters)
          "With predictate\n";
        print_partition_with_predicate
          parameters error
          store_result.store_partition_with_predicate
      in
      error
    else
      error
  in
  (*let error =
    print_contact_map parameters error
      store_result.store_contact_map
    in*)
  error, store_result
