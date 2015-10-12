(**
  * bdu_side_effects.ml
  * openkappa
  * Jérôme Feret, projet Abstraction, INRIA Paris-Rocquencourt
  * 
  * Creation: 2015, the 30th of September
  * Last modification: 
  * 
  * Compute the relations between sites in the BDU data structures
  * 
  * Copyright 2010,2011,2012,2013,2014 Institut National de Recherche en Informatique et   
  * en Automatique.  All rights reserved.  This file is distributed     
  * under the terms of the GNU Library General Public License *)

open Cckappa_sig
open Int_storage
open Bdu_analysis_type
open Bdu_contact_map
open Set_and_map

let warn parameters mh message exn default =
  Exception.warn parameters mh (Some "BDU side effects") message exn (fun () -> default)  

let trace = false

(************************************************************************************)
(*compute side effects, return a list of pair [rule_id * binding_state].
  For example:
  'r0' A() ->
  'r1' A(x) ->
  'r2' A(x!B.x) -> A(x)
  'r3' A(x,y), C(y) -> A(x,y!1), C(y!1)
  
  The result of this function is:
  - A(x): [(r0, _); (r2, B.x)]
  - A(y): [(r0, _); (r1, _)]
*)

(*compute half-break action: rule r2 is a half-break action.*)

let half_break_action parameter error handler rule_id half_break store_result =
  List.fold_left (fun (error, store_result) (site_address, state_op) ->
    (*site_address: {agent_index, site, agent_type}*)
    let agent_type = site_address.agent_type in
    let site = site_address.site in
    (*state*)
    let error, (min, max) =
      match state_op with
      | None ->
        begin
          let error, state_value =
            Misc_sa.unsome
              (Nearly_Inf_Int_Int_storage_Imperatif_Imperatif.get
                 parameter
                 error
                 (agent_type, site)
                 handler.states_dic)
              (fun error -> warn parameter error (Some "line 54") Exit
                (Dictionary_of_States.init()))
          in
          let error, last_entry =
            Dictionary_of_States.last_entry parameter error state_value in
          error, (1, last_entry)
        end
      | Some interval -> error, (interval.min, interval.max)
    in
    (*old*)
    let error, old_list =
      match AgentMap.unsafe_get parameter error agent_type store_result with
      | error, None -> error, []
      | error, Some l -> error, l
    in
    (*new*)
    let new_list = List.concat [[rule_id, site, min]; old_list] in
    (*store*)
    let error, store_result =
      AgentMap.set
        parameter
        error
        agent_type
        (List.rev new_list)
        store_result
    in
    error, store_result    
  ) (error, store_result) half_break

(*FIX*)

let half_break_action' parameter error handler rule_id half_break store_result =
  (*module (agent_type, site) -> (rule_id, binding_state) list*)
  let add_link (a, b) (r, state) store_result =
    let l, old =
      try Int2Map_HalfBreak_effect.find (a, b) store_result
      with Not_found -> [], []
    in
    Int2Map_HalfBreak_effect.add (a, b) (l, (r, state) :: old) store_result
  in
  let error, store_result =
    List.fold_left (fun (error, store_result) (site_address, state_op) ->
      (*site_address: {agent_index, site, agent_type}*)
      let agent_type = site_address.agent_type in
      let site = site_address.site in
      (*state*)
      let error, (state_min, state_max) =
        match state_op with
        | None ->
          begin
            let error, state_value =
              Misc_sa.unsome
                (Nearly_Inf_Int_Int_storage_Imperatif_Imperatif.get
                   parameter
                   error
                   (agent_type, site)
                   handler.states_dic)
                (fun error -> warn parameter error (Some "line 54") Exit
                  (Dictionary_of_States.init()))
            in
            let error, last_entry =
              Dictionary_of_States.last_entry parameter error state_value in
            error, (1, last_entry)
          end
        | Some interval -> error, (interval.min, interval.max)
      in
      (*return result*)
      let store_result =
        add_link (agent_type, site) (rule_id, state_min) store_result
      in
      error, store_result  
  ) (error, store_result) half_break
  in
  (*Map function*)
  let store_result =
    Int2Map_HalfBreak_effect.map (fun (l, x) -> List.rev l, x) store_result
  in
  error, store_result


(************************************************************************************)
(*compute remove action: r0 and r1 are remove action *)

let site_free_of_port port = port.site_free

let remove_action parameter error rule_id remove store_result =
  List.fold_left (fun (error, store_result) (agent_index, agent, list_undoc) ->
    (*let store_remove_with_info, store_remove_without_info = store_result in*)
    let agent_type = agent.agent_name in
    (*NOTE: if it is a site_free then do not consider this case.*)
    (*-------------------------------------------------------------------------*)
    (*remove with no information: r0 is the rule with this property*)
    let pair_list =
      List.fold_left (fun current_list site ->
        let list = (rule_id, site) :: current_list in
        list
      ) [] list_undoc
    in
    (*old*)
    let error, old_pair_list =
      match AgentMap.unsafe_get parameter error agent_type store_result with
      | error, None -> error, []
      | error, Some l -> error, l
    in
    (*new*)
    let new_pair_list = List.concat [pair_list; old_pair_list] in
    (*-------------------------------------------------------------------------*)
    (*store*)
    let error, store_result =
      AgentMap.set
        parameter
        error
        agent_type
        (List.rev new_pair_list)
        store_result
    in
    error, store_result
  ) (error, store_result) remove

(*FIXED*)
let remove_action' parameter error rule_id remove store_result =
  let add_link (a, b) r store_result =
    let l, old =
      try Int2Map_Remove_effect.find (a, b) store_result
      with Not_found -> [], []
    in
    Int2Map_Remove_effect.add (a, b) (l, r :: old) store_result
  in
  let error, store_result =
    List.fold_left (fun (error, store_result) (agent_index, agent, list_undoc) ->
      let agent_type = agent.agent_name in
      (*NOTE: if it is a site_free then do not consider this case.*)
      (*result*)
      let store_result =
        List.fold_left (fun store_result site ->
          add_link (agent_type, site) rule_id store_result
        ) store_result list_undoc
      in
      error, store_result
    ) (error, store_result) remove
  in
  let store_result =
    Int2Map_Remove_effect.map (fun (l, x) -> List.rev l, x) store_result
  in
  error, store_result

(************************************************************************************)
(*compute side effects: this is an update before discover bond function *)

let collect_side_effects parameter error handler rule_id half_break remove store_result =
  let store_half_break_action, store_remove_action = store_result in
  (*if there is a half_break action*)
  let error, store_half_break_action =
    half_break_action
      parameter
      error
      handler
      rule_id
      half_break
      store_half_break_action
  in
  (*if there is a remove action*)
  let error, store_remove_action =
    remove_action
      parameter
      error
      rule_id
      remove
      store_remove_action
  in
  error, (store_half_break_action, store_remove_action)

(*FIXED*)
let collect_side_effects' parameter error handler rule_id half_break remove store_result =
  let store_half_break_action, store_remove_action = store_result in
  (*if there is a half_break action*)
  let error, store_half_break_action =
    half_break_action'
      parameter
      error
      handler
      rule_id
      half_break
      store_half_break_action
  in
  (*if there is a remove action*)
  let error, store_remove_action =
    remove_action'
      parameter
      error
      rule_id
      remove
      store_remove_action
  in
  error, (store_half_break_action, store_remove_action)

(************************************************************************************)
(*a bond is discovered for the first time:
  For example:
  'r0' A() ->
  'r1' A(x) ->
  'r2' A(x!B.x) -> A(x)
  'r3' A(x), B(x) -> A(x!1), B(x!1)
  'r4' A(x,y), C(y) -> A(x,y!1), C(y!1)
  
  'r3' has a bond on the rhs, for any (rule_id, state) belong to side
  effects of A(x); state is compatible with B(x!1), add rule_id into update
  function.
*)

(*get a list of binding information*)
let get_list_of_binding parameter error store_binding_forward =
  Int2Map_CM_state.fold
    (fun (agent_type_1,site_type_1,state_1) (l1,l2) current_result_1 ->
      if l1 <> []
      then
	()
      else
	();
      List.fold_left (fun current_result_2 (agent_type_2, site_type_2, state_2) ->
	let l =
	  (agent_type_1, site_type_1, state_1, agent_type_2, site_type_2, state_2)
	  :: current_result_2 in
	l
      ) current_result_1 l2
    ) store_binding_forward []

(*------------------------------------------------------------------------*)
(*testing the binding of the first agent if it belongs to side effect or not*)
    
let get_binding_half_break_set parameter error agent_type_1 site_type_1 state_1
    store_half_break store_result =
  AgentMap.fold parameter error
    (fun parameter error agent_type_effect l store_current_result ->
      let result_list, store_rule_list =
	List.fold_left (fun (current_result, store_rule_set)
	  (rule_id_effect, site_effect, state_effect) ->
	    begin
	      if agent_type_1 = agent_type_effect &&
		site_type_1 = site_effect &&
		state_1 = state_effect
	      then
		let error, rule_set =
		  Site_map_and_set.add_set
		    parameter
		    error
		    rule_id_effect
		    current_result
		in
		(*store result with its agent_type*)
		let error, store_rule_set =
		  AgentMap.set
		    parameter
		    error
		    agent_type_1
		    rule_set
		    store_rule_set
		in
		(rule_set, store_rule_set)
	      else
		(current_result, store_rule_set)
	    end	    
	) (Site_map_and_set.empty_set, store_current_result) l
      in
      (*store*)
      error, store_rule_list
    ) store_half_break store_result

(*------------------------------------------------------------------------*)    
(*testing the binding of the first agent (without state information) 
  if it belongs to side effect or not - remove action in general*)
    
let get_binding_remove_set parameter error agent_type_1 site_type_1
    store_remove store_result =
  AgentMap.fold parameter error
    (fun parameter error agent_type_effect l store_current_result ->
      let result_list, store_rule_list =
	List.fold_left (fun (current_result, store_rule_set)
	  (rule_id_effect, site_effect) ->
	  begin
	    if agent_type_1 = agent_type_effect &&
	      site_type_1 = site_effect
	    then
	      let error, rule_set =
		Site_map_and_set.add_set
		  parameter
		  error
		  rule_id_effect
		  current_result
	      in
	      let error, store_rule_set =
		AgentMap.set
		  parameter
		  error
		  agent_type_1
		  rule_set
		  store_rule_set
	      in
		(rule_set, store_rule_set)
	    else
	      (current_result, store_rule_set)
	  end
	) (Site_map_and_set.empty_set, store_current_result) l
      in
      error, store_rule_list
    ) store_remove store_result

(*------------------------------------------------------------------------*)
    
let get_covering_classes_modified_binding_set parameter error agent_type_2
    site_type_2 state_2 store_covering_classes_modified_sites store_result =
  AgentMap.fold parameter error
    (fun parameter error agent_type_cv l store_current_result ->
      let result_list, store_rule_list =
	List.fold_left (fun (current_result, store_rule_set)
	  (rule_id_cv, site_cv, state_cv) ->
	  begin
	    if agent_type_2 = agent_type_cv &&
	      site_type_2 = site_cv &&
	      state_2 = state_cv
	    then
	      let error, rule_set =
		Site_map_and_set.add_set
		  parameter
		  error
		  rule_id_cv
		  current_result
	      in
	      let error, store_rule_set =
		AgentMap.set
		  parameter
		  error
		  agent_type_cv
		  rule_set
		  store_rule_set
	      in
	      (rule_set, store_rule_set)
	    else
	      (current_result, store_rule_set)
	  end
	) (Site_map_and_set.empty_set, store_current_result) l
      in
      error, store_rule_list
    ) store_covering_classes_modified_sites store_result

(*------------------------------------------------------------------------*)
(*combine with binding agents,
  get a list of half_break_rule from side effect with half_break action*)
    
let get_half_break_rule_set parameter error agent_type_1 site_type_1
    state_1 store_half_break store_result_half_break =
  let error, store_result_half_break_rule =
    get_binding_half_break_set
      parameter
      error
      agent_type_1
      site_type_1
      state_1
      store_half_break
      store_result_half_break
  in
  let error, half_break_rule_set =
    match AgentMap.unsafe_get parameter error agent_type_1 store_result_half_break_rule
    with
      | error, None -> error, Site_map_and_set.empty_set
      | error, Some s -> error, s
  in
  error, (store_result_half_break_rule, half_break_rule_set)

(*------------------------------------------------------------------------*)
(*combine with binding agents, 
  get a list of remove_rule from side effect with remove action*)
    
let get_remove_set parameter error agent_type_1 site_type_1 store_remove
    store_result_remove =
  let error, store_result_remove_rule =
    get_binding_remove_set
      parameter
      error
      agent_type_1
      site_type_1
      store_remove
      store_result_remove
  in
  let error, remove_rule_set =
    match AgentMap.unsafe_get parameter error agent_type_1 store_result_remove_rule
    with
      | error, None -> error, Site_map_and_set.empty_set
      | error, Some s -> error, s
  in
  error, (store_result_remove_rule, remove_rule_set)
    
(*------------------------------------------------------------------------*)
(*combine with covering classes, modified sites,
  get the final rule_id list for update function*)
    
let get_rule_id_update_set parameter error agent_type_2 site_type_2
    state_2 half_break_rule_set remove_rule_set
    store_covering_classes_modified_sites store_result_cv_modified
    store_result_rule_id
    =
  let error, store_rule_id_update =
    get_covering_classes_modified_binding_set
      parameter
      error
      agent_type_2
      site_type_2
      state_2
      store_covering_classes_modified_sites
      store_result_cv_modified
  in
  (*get the first list*)
  let error, rule_id_update_set =
    match AgentMap.unsafe_get parameter error agent_type_2 store_rule_id_update
    with
      | error, None -> error, Site_map_and_set.empty_set
      | error, Some s -> error, s
  in
  (*combine with side effects action: half_break and remove*)
  let error, side_effects_rule_set =
    Site_map_and_set.union
      parameter
      error
      half_break_rule_set
      remove_rule_set
  in
  let error, rule_id_set =
    Site_map_and_set.union
      parameter
      error
      side_effects_rule_set
      rule_id_update_set
  in
  (*store the result of first_rule_id_list with its agent_type_2*)
  let error, store_result_rule_id =
    AgentMap.set
      parameter
      error
      agent_type_2
      rule_id_set
      store_result_rule_id
  in
  (*return result*)
  error, (store_rule_id_update, store_result_rule_id)

(*------------------------------------------------------------------------*)
      
let update_bond_side_effects_set parameter error handler 
    store_binding_dual store_side_effects store_covering_classes_modified_sites
    store_result =
  (*------------------------------------------------------------------------*)
  let store_init_half_break,
    store_init_remove,
    store_init_cv,
    store_init_result = store_result
  in
  (*------------------------------------------------------------------------*)
  (*binding: A bond to B and B bond to A*)
  let store_binding_forward, store_binding_reverse = store_binding_dual in
  (*side effects: half-break action and remove action*)
  let store_half_break, store_remove = store_side_effects in
  (*------------------------------------------------------------------------*)
  (*check if there is any binding on the rhs*)
  if Int2Map_CM_state.is_empty store_binding_forward (*TODO:another side as well*)
  then
    error, store_result
  else
    (*------------------------------------------------------------------------*)
    (*call function has binding on the rhs after filter from the contact map*)
    let binding_list =
      get_list_of_binding parameter error store_binding_forward
    in
    (*------------------------------------------------------------------------*)
    (*fold a list of binding, 
      test each the first binding agent with site and state, 
      if it belongs to side effects*)
    let error, store_result =
      List.fold_left (fun
	(error, (store_result_half_break,
		 store_result_remove,
		 store_result_cv_modified,
		 store_result_rule_id))
	(agent_type_1, site_type_1, state_1,
	 agent_type_2, site_type_2, state_2) ->
	  (*------------------------------------------------------------------------*)
	  (*side effects information: half_break action*)
	  let error, (store_result_half_break_rule, half_break_rule_set) =
	    get_half_break_rule_set
	      parameter
	      error
	      agent_type_1
	      site_type_1
	      state_1
	      store_half_break
	      store_result_half_break
	  in
	  (*------------------------------------------------------------------------*)
	  (*side effects information: remove action*)
	  let error, (store_result_remove_rule, remove_rule_set) =
	    get_remove_set
	      parameter
	      error
	      agent_type_1
	      site_type_1
	      store_remove
	      store_result_remove
	  in
	  (*------------------------------------------------------------------------*)
	  (*final rule_id: combine rule_id list inside covering classes
	    and added a list of rule_id inside side effects 
	    (half_break action and remove action)*)
	  let error, (store_rule_id_update, store_result_rule_id) =
	    get_rule_id_update_set
	      parameter
	      error
	      agent_type_2
	      site_type_2
	      state_2
	      half_break_rule_set
	      remove_rule_set
	      store_covering_classes_modified_sites
	      store_result_cv_modified
	      store_result_rule_id
	  in
	  (*------------------------------------------------------------------------*)
	  (*return result*)
	  error,
	  (store_result_half_break_rule,
	   store_result_remove_rule,
	   store_rule_id_update,
	   store_result_rule_id
	  )
      ) (error,
	 (store_init_half_break,
	  store_init_remove,
	  store_init_cv,
	  store_init_result)
      )	binding_list
    in
    error, store_result

(*------------------------------------------------------------------------*)

let store_update parameter error store_covering_classes_modified_sites
    store_result_rule_id store_result =
  AgentMap.fold parameter error
    (fun parameter error agent_type_cv l store_result_1 ->
      AgentMap.fold parameter error
	(fun parameter error agent_type set store_result_2 ->
	  let error, store_result =
	    List.fold_left (fun (error, store_current_result) (rule_id_cv, _, _) ->
	      if agent_type = agent_type_cv
	      then
		(*NOTE: agent type 2*)
		let error, store_result =
		  AgentMap.set
		    parameter
		    error
		    agent_type_cv
		    set
		    store_current_result
		in
		error, store_result
	      else
		let error, result_set =
		  Site_map_and_set.add_set
		    parameter
		    error
		    rule_id_cv
		    Site_map_and_set.empty_set
		in
                (*get old*)
		let error, old_set =
		  match AgentMap.unsafe_get parameter error agent_type_cv
		    store_current_result
		  with
		    | error, None -> error, Site_map_and_set.empty_set
		    | error, Some s -> error, s
		in
                (*new*)
		let error, new_set =
		  Site_map_and_set.union
		    parameter
		    error
		    old_set
		    result_set
		in
                (*store*)
		let error, store_result =
		  AgentMap.set
		    parameter
		    error
		    agent_type_cv
		    new_set
		    store_current_result
		in
		error, store_result
	    ) (error, store_result_2) l
	  in
	  error, store_result
	) store_result_rule_id store_result_1
    ) store_covering_classes_modified_sites store_result
