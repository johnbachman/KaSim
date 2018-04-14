let add_relation_one_step parameters error
    ~agent_name ~source ~target array
  =
  let error, old_set =
    match
      Ckappa_sig.Agent_type_site_nearly_Inf_Int_Int_storage_Imperatif_Imperatif.unsafe_get parameters error (agent_name,source) array
    with
    | error, None -> error, Ckappa_sig.Site_map_and_set.Set.empty
    | error, Some a -> error, a
  in
  let error, new_set =
    Ckappa_sig.Site_map_and_set.Set.add_when_not_in parameters error
      target old_set
  in
  Ckappa_sig.Agent_type_site_nearly_Inf_Int_Int_storage_Imperatif_Imperatif.set parameters error (agent_name,source) new_set array

let add_relation_two_steps parameters error
    ~agent_name ~source ~target array
  =
  let error, old_map =
    match
      Ckappa_sig.Agent_type_nearly_Inf_Int_storage_Imperatif.unsafe_get parameters error agent_name array
    with
    | error, None ->
      Ckappa_sig.Site_type_nearly_Inf_Int_storage_Imperatif.create
        parameters
        error
        0
    | error, Some a -> error, a
  in
  let error, old_set =
    match
      Ckappa_sig.Site_type_nearly_Inf_Int_storage_Imperatif.unsafe_get parameters error source  old_map
    with
    | error, None ->
      error, Ckappa_sig.Site_map_and_set.Set.empty
    | error, Some a -> error, a
  in
  let error, new_set =
    Ckappa_sig.Site_map_and_set.Set.add_when_not_in parameters error
      target old_set
  in
  let error, new_map =
    Ckappa_sig.Site_type_nearly_Inf_Int_storage_Imperatif.set parameters error source new_set old_map
  in
  Ckappa_sig.Agent_type_nearly_Inf_Int_storage_Imperatif.set
    parameters error agent_name new_map array


let add_dependence parameters error
    ~agent_name ~site ~counter ~packs ~backward_dependences =
  let error, packs =
    add_relation_two_steps
      parameters error
      ~agent_name ~source:counter ~target:site packs
  in
  let error, backward_dependences =
    add_relation_one_step
      parameters error
      ~agent_name~source:site ~target:counter
      backward_dependences
  in
  error, (packs, backward_dependences)

let compute_packs parameters error handler compil =
  let error, packs =
    Ckappa_sig.Agent_type_nearly_Inf_Int_storage_Imperatif.create parameters error 0
  in
  let error, backward_dependences =
    Ckappa_sig.Agent_type_site_nearly_Inf_Int_Int_storage_Imperatif_Imperatif.create parameters error (0,0)
  in
  let error, (packs, backward_dependences) =
    Ckappa_sig.Rule_nearly_Inf_Int_storage_Imperatif.fold
      parameters
      error
      (fun parameters error _rule_id rule (packs, backward_dependences)  ->
         let rule = rule.Cckappa_sig.e_rule_c_rule in
         let actions = rule.Cckappa_sig.actions.Cckappa_sig.translate_counters in
         let error, agents_with_counters =
           List.fold_left
             (fun
               (error, map) (site_address,_)
               ->
                 let error, is_counter =
                   Handler.is_counter
                     parameters error handler site_address.Cckappa_sig.agent_type site_address.Cckappa_sig.site
                 in
                 if is_counter (* the site is a counter *)
                 then
                   let ag_id = site_address.Cckappa_sig.agent_index in
                   let error, old =
                     Ckappa_sig.Agent_id_map_and_set.Map.find_default_without_logs
                     parameters error []
                     ag_id
                     map
                   in
                   Ckappa_sig.Agent_id_map_and_set.Map.add_or_overwrite
                     parameters error ag_id (site_address.Cckappa_sig.site::old)
                     map

                 else
                   error, map
             )
             (error, Ckappa_sig.Agent_id_map_and_set.Map.empty)
             actions
         in
         let error, (packs, backward_dependences)  =
           Ckappa_sig.Agent_id_map_and_set.Map.fold
             (fun
               ag list_of_counters
               (error, (packs, backward_dependences))
               ->
                 match
                   Ckappa_sig.Agent_id_quick_nearly_Inf_Int_storage_Imperatif.unsafe_get
                     parameters error
                     ag
                     rule.Cckappa_sig.rule_rhs.Cckappa_sig.views
                 with
                 | error, None -> error, (packs, backward_dependences)
                 | error, Some a ->
                   begin
                     match a with
                     | Cckappa_sig.Ghost | Cckappa_sig.Dead_agent _
                     | Cckappa_sig.Unknown_agent _ ->
                       error, (packs, backward_dependences)
                     | Cckappa_sig.Agent ag ->
                       let agent_name = ag.Cckappa_sig.agent_name in
                       Ckappa_sig.Site_map_and_set.Map.fold
                         (fun site _ (error, (packs, backward_dependences)) ->
                            List.fold_left
                              (fun (error, (packs, backward_dependences)) counter ->
                                 add_dependence
                                   parameters error
                                   ~agent_name ~site ~counter ~packs ~backward_dependences)
                              (error, (packs, backward_dependences))
                              list_of_counters)
                         ag.Cckappa_sig.agent_interface
                         (error, (packs, backward_dependences))
                   end
             )
             agents_with_counters
             (error, (packs, backward_dependences))
         in
         error, (packs, backward_dependences)
      ) compil.Cckappa_sig.rules (packs, backward_dependences)
  in
  error, (packs, backward_dependences)



let fold_counter_dep parameter error backward f agent_type site remanent =
  let error, dep_counters =
    match
      Ckappa_sig.Agent_type_site_nearly_Inf_Int_Int_storage_Imperatif_Imperatif.unsafe_get
        parameter error
        (agent_type,site)
        backward
    with
    | error, None ->
      error, Ckappa_sig.Site_map_and_set.Set.empty
    | error, Some a -> error, a
  in
  Ckappa_sig.Site_map_and_set.Set.fold
    (fun counter (error, remanent) ->
       f parameter error agent_type counter site remanent)
    dep_counters
    (error, remanent)

let add_generic_in_agent_description
    parameters error get set update counter agent_restriction =
    let error, counter_restriction =
      match
        Ckappa_sig.Site_type_quick_nearly_Inf_Int_storage_Imperatif.unsafe_get
          parameters error counter agent_restriction
      with
      | error, None -> error,
                       Counters_domain_type.empty_restriction
      | error, Some a -> error, a
    in
    let specific = get counter_restriction in
    let updated = update specific in
    let counter_restriction = set updated counter_restriction in
    let error, agent_restriction =
      Ckappa_sig.Site_type_quick_nearly_Inf_Int_storage_Imperatif.set
        parameters error counter counter_restriction agent_restriction
    in
    error, agent_restriction

let add_test_in_agent_description
    parameters errors test counter agent_restriction =
    add_generic_in_agent_description
      parameters errors
      (fun x -> x.Counters_domain_type.tests)
      (fun x y -> {y with Counters_domain_type.tests = x})
      (fun a -> test::a)
      counter
      agent_restriction

let add_invertible_action_in_agent_description
    parameters errors action counter agent_restriction =
  add_generic_in_agent_description
    parameters errors
    (fun x -> x.Counters_domain_type.invertible_assignments)
    (fun x y -> {y with Counters_domain_type.invertible_assignments = x})
    (fun a -> action::a)
    counter
    agent_restriction

let add_non_invertible_action_in_agent_description
    parameters errors action counter agent_restriction =
      add_generic_in_agent_description
        parameters errors
        (fun x -> x.Counters_domain_type.non_invertible_assignments)
        (fun x y -> {y with Counters_domain_type.non_invertible_assignments = x})
        (fun a -> action::a)
        counter
        agent_restriction

let collect_tests parameters handler error ag_id ag backward restriction =
  let agent_type = ag.Cckappa_sig.agent_name in
  let view = ag.Cckappa_sig.agent_interface in
  let error, agent_restriction =
    match
      Ckappa_sig.Agent_id_nearly_Inf_Int_storage_Imperatif.unsafe_get
        parameters error
        ag_id
        restriction
    with
    | error, None ->
      Ckappa_sig.Site_type_quick_nearly_Inf_Int_storage_Imperatif.create parameters
        error 0
    | error, Some a -> error, a
  in
  let error, agent_restriction =
    Ckappa_sig.Site_map_and_set.Map.fold
      (fun site port (error, agent_restriction) ->
         let error, is_counter =
           Handler.is_counter parameters error handler
             agent_type site in
         if is_counter
         then
           error, agent_restriction
         else
           let interval = port.Cckappa_sig.site_state in
           let error, max_state = Handler.last_state_of_site parameters error
               handler agent_type site in
           let add_test
               parameter error
               agent_type site agent_restriction state
               cmp int =
             fold_counter_dep
               parameter error backward
               (fun parameters error _agent_type counter site agent_restriction
                 ->
                   let test = Occu1.Bool (site, state), cmp, int in
                   add_test_in_agent_description
                     parameters error
                     test counter agent_restriction
                  )
               agent_type
               site
               agent_restriction
           in
           match interval.Cckappa_sig.min, interval.Cckappa_sig.max with
           | Some a, Some b when a=b ->
             add_test
               parameters error
               agent_type site
               agent_restriction
               a Counters_domain_type.EQ 1
           | Some a, Some b when a=Ckappa_sig.state_index_of_int 1
                              && b = max_state ->
             add_test
               parameters error
               agent_type site
               agent_restriction
               (Ckappa_sig.state_index_of_int 0) Counters_domain_type.EQ 0
           | (Some _ | None), (Some _ | None) ->
             error, agent_restriction
      )
      view
      (error, agent_restriction)
  in
  Ckappa_sig.Agent_id_nearly_Inf_Int_storage_Imperatif.set
    parameters error
    ag_id agent_restriction
    restriction

let collect_updates parameters handler error ag_id agl diff_agr backward restriction =
  let agent_type = agl.Cckappa_sig.agent_name in
  let viewl = agl.Cckappa_sig.agent_interface in
  let diffviewr = diff_agr.Cckappa_sig.agent_interface in
  let error, agent_restriction =
    match
      Ckappa_sig.Agent_id_nearly_Inf_Int_storage_Imperatif.unsafe_get
        parameters error
        ag_id
        restriction
    with
    | error, None ->
      Ckappa_sig.Site_type_quick_nearly_Inf_Int_storage_Imperatif.create
        parameters
        error 0
    | error, Some a -> error, a
  in
  let add_invertible_action
      parameter error
      agent_type site agent_restriction state
      action =
    fold_counter_dep
      parameter error backward
      (fun parameters error _agent_type counter site agent_restriction
        ->
          let action = Occu1.Bool (site, state), action in
          add_invertible_action_in_agent_description
            parameters error
            action counter agent_restriction
         )
      agent_type
      site
      agent_restriction
  in
  let add_non_invertible_action
      parameter error
      agent_type site agent_restriction state
      action =
    fold_counter_dep
      parameter error backward
      (fun parameters error _agent_type counter site agent_restriction
        ->
          let action = Occu1.Bool (site, state), action in
          add_non_invertible_action_in_agent_description
            parameters error
            action counter agent_restriction
         )
      agent_type
      site
      agent_restriction
  in
  let error, agent_restriction =
    Ckappa_sig.Site_map_and_set.Map.fold2
      parameters error
      (fun _ error _ _ agent_restriction -> error, agent_restriction)
      (fun parameters error _ _ agent_restriction ->
         Exception.warn parameters error __POS__ Exit agent_restriction)
      (fun parameters error site portl portr agent_restriction ->
         let error, is_counter =
           Handler.is_counter parameters error handler
             agent_type site in
         if is_counter
         then
           error, agent_restriction
         else
           let intervall = portl.Cckappa_sig.site_state in
           let intervalr = portr.Cckappa_sig.site_state in
           match
             intervalr.Cckappa_sig.min, intervalr.Cckappa_sig.max
           with
           | Some ar, Some br when ar=br ->
             begin
               match
                 intervall.Cckappa_sig.min, intervall.Cckappa_sig.max
              with
              | Some al, Some bl when al=bl ->
              let action1 = ar, 1 in
              let action2 = al, -1 in
              List.fold_left
                (fun (error, agent_restriction) (state,action) ->
                   add_invertible_action
                     parameters error
                     agent_type site agent_restriction state
                     action)
                (error, agent_restriction)
                [action1;action2]
              | Some al, Some bl ->
                let rec declare_potential_updates
                    state list seen =
                  if Ckappa_sig.compare_state_index bl state > 0
                  then list, seen
                  else
                    let list, seen =
                      if state = br
                      then
                        let list = (state, 1)::list in
                        let seen = true in
                        list, seen
                      else
                        let list = (state, 0)::list in
                        list, seen
                    in
                    declare_potential_updates
                      (Ckappa_sig.next_state_index state)
                      list seen
                in
                let list, seen =
                  declare_potential_updates
                    al
                    []
                    false
                in
                let error, agent_restriction =
                  List.fold_left
                    (fun (error, agent_restriction) (state,bool) ->
                       add_non_invertible_action
                         parameters error
                         agent_type site agent_restriction
                         state bool)
                    (error, agent_restriction)
                    list
                in
                if seen then
                  error, agent_restriction
                else
                  add_invertible_action
                    parameters error
                    agent_type site agent_restriction
                    ar 1

              | None, _ | Some _ , None ->
                add_non_invertible_action
                       parameters error
                       agent_type site agent_restriction ar
                       1
            end
           | (Some _ | None), (Some _ | None)  ->
             Exception.warn parameters error __POS__ Exit agent_restriction
          )
          viewl
          diffviewr
          agent_restriction
      in
      Ckappa_sig.Agent_id_nearly_Inf_Int_storage_Imperatif.set
        parameters error
        ag_id agent_restriction
        restriction

let compute_rule_restrictions parameters error handler (_packs, backward) compil =
  let error, rule_restrictions =
    Ckappa_sig.Rule_id_quick_nearly_Inf_Int_storage_Imperatif.create
      parameters error 0
  in
  Ckappa_sig.Rule_nearly_Inf_Int_storage_Imperatif.fold
    parameters
    error
    (fun parameters error rule_id rule rule_restrictions ->
       let error, restriction =
         match
           Ckappa_sig.Rule_id_quick_nearly_Inf_Int_storage_Imperatif.unsafe_get
             parameters error
             rule_id
             rule_restrictions
         with
         | error, None ->
           Ckappa_sig.Agent_id_nearly_Inf_Int_storage_Imperatif.create
             parameters error
             0
         | error, Some a -> error, a
       in
       let error, restriction =
       Ckappa_sig.Agent_id_quick_nearly_Inf_Int_storage_Imperatif.fold2
         parameters error
         (fun parameters error id l_view restriction ->
           match l_view with
             | (Cckappa_sig.Ghost
               | Cckappa_sig.Unknown_agent _
               | Cckappa_sig.Dead_agent _ ) ->
             (* nothing to do *)
             error, restriction
             | Cckappa_sig.Agent ag ->
             let error, restriction =
                 collect_tests parameters handler error id ag backward restriction
             in
             error, restriction
         )
         (fun parameters error _id _r_diff restriction ->
            Exception.warn parameters error __POS__ Exit restriction)
         (fun parameters error id l_view r_diff restriction ->
            match l_view, r_diff with
            | (Cckappa_sig.Ghost | Cckappa_sig.Unknown_agent _ | Cckappa_sig.Dead_agent _ ), _ ->
              (* nothing to do *)
              error, restriction
            | Cckappa_sig.Agent agl, diff_agr ->
              let error, restriction =
                collect_tests parameters handler error id agl backward
                  restriction
              in
              let error, restriction =
                collect_updates parameters handler error id agl diff_agr backward restriction
              in
              error, restriction

         )
         rule.Cckappa_sig.e_rule_c_rule.Cckappa_sig.rule_lhs.Cckappa_sig.views
         rule.Cckappa_sig.e_rule_c_rule.Cckappa_sig.diff_direct
         restriction
       in
       let error, restriction =
         List.fold_left
           (fun (error, restriction) (site_address,action) ->
              let agent_id = site_address.Cckappa_sig.agent_index in
              let agent_type = site_address.Cckappa_sig.agent_type in
              let site = site_address.Cckappa_sig.site in
              let error, agent_restriction =
                match
                  Ckappa_sig.Agent_id_nearly_Inf_Int_storage_Imperatif.unsafe_get
                    parameters error agent_id restriction
                with
                | error, None ->
                  Ckappa_sig.Site_type_quick_nearly_Inf_Int_storage_Imperatif.create
                    parameters error 0
                | error, Some a -> error, a
              in
              let precondition = action.Cckappa_sig.precondition in
              let translate = action.Cckappa_sig.increment in
              let error, test =
                match
                  precondition.Cckappa_sig.min, precondition.Cckappa_sig.max
                with
                | None, None -> error, None
                | Some a, None -> error, Some (Counters_domain_type.GTEQ,a)
                | None, Some a -> error, Some (Counters_domain_type.LTEQ,a)
                | Some a,Some b when a=b -> error, Some (Counters_domain_type.EQ,a)
                | Some _,Some _ ->
                  Exception.warn parameters error __POS__ Exit None
              in
              let error, agent_restriction =
                match test with
                | None -> error, agent_restriction
                | Some (cmp,threshold) ->
                  let test = Occu1.Counter site, cmp, Ckappa_sig.int_of_state_index threshold in
                  fold_counter_dep
                    parameters error backward
                    (fun parameters error _agent_type counter _site agent_restriction
                      ->
                        add_test_in_agent_description
                          parameters error
                          test counter agent_restriction
                    )
                    agent_type
                    site
                    agent_restriction
              in
              let error, agent_restriction =
                if translate=0
                then error, agent_restriction
                else
                  let action = Occu1.Counter site, translate in
                  fold_counter_dep
                    parameters error backward
                    (fun parameters error _agent_type counter _site agent_restriction
                      ->
                        add_invertible_action_in_agent_description
                          parameters error
                          action counter agent_restriction
                    )
                    agent_type
                    site
                    agent_restriction
              in
              Ckappa_sig.Agent_id_nearly_Inf_Int_storage_Imperatif.set
                parameters error agent_id agent_restriction restriction
           )
           (error, restriction)
         rule.Cckappa_sig.e_rule_c_rule.Cckappa_sig.actions.Cckappa_sig.translate_counters
       in
       Ckappa_sig.Rule_id_quick_nearly_Inf_Int_storage_Imperatif.set
         parameters error
         rule_id restriction
         rule_restrictions
    )
    compil.Cckappa_sig.rules
    rule_restrictions


let convert_view parameters error handler compil packs agent_type ag =
  match
    ag
  with
| (Some (Cckappa_sig.Ghost
               | Cckappa_sig.Dead_agent _
               | Cckappa_sig.Unknown_agent _)
         | None) ->
  Exception.warn parameters error __POS__ Exit []
| Some (Cckappa_sig.Agent ag_r) ->
  begin
    match
      Ckappa_sig.Agent_type_nearly_Inf_Int_storage_Imperatif.unsafe_get
        parameters error
        agent_type
        packs
    with
    | error, None -> error, []
    | error, Some agent_packs ->
      let interface_r =
        ag_r.Cckappa_sig.agent_interface
      in
      Ckappa_sig.Site_type_nearly_Inf_Int_storage_Imperatif.fold
        parameters error
        (fun parameters error counter site_set list ->
           let error, interface =
             Ckappa_sig.Site_map_and_set.Set.fold
               (fun site (error,interface) ->
                  let error, is_counter =
                    Handler.is_counter
                      parameters error handler agent_type site
                  in
                  let error, state =
                    match
                      Ckappa_sig.Site_map_and_set.Map.find_option_without_logs
                        parameters error
                        site
                        interface_r
                    with
                    | error, None ->
                      if is_counter
                      then
                        begin
                          match
                            Ckappa_sig.AgentSite_map_and_set.Map.find_option_without_logs
                          parameters error
                          (agent_type,site)
                          compil.Cckappa_sig.counter_default
                          with
                          | error, (None | Some None) -> error,  Ckappa_sig.state_index_of_int 0
                          | error, Some (Some a) -> error, a
                        end
                      else error, Ckappa_sig.state_index_of_int 0
                    | error, Some port ->
                      match
                        port.Cckappa_sig.site_state.Cckappa_sig.min,
                        port.Cckappa_sig.site_state.Cckappa_sig.max
                      with Some a, Some b when a=b ->
                        error, a
                         | (Some _ | None), (Some _ | None) ->
                           Exception.warn parameters error __POS__
                             Exit (Ckappa_sig.state_index_of_int 0)
                  in
                  if is_counter
                  then
                    error, (Occu1.Counter site,
                            Ckappa_sig.int_of_state_index state)::interface
                  else
                    let error, last_state =
                      Handler.last_state_of_site parameters error handler agent_type site
                    in
                    let rec aux k interface =
                      if Ckappa_sig.compare_state_index k last_state > 0
                      then interface
                      else
                        let pred = Occu1.Bool (site,k) in
                        let interface =
                          if k=state then
                            (pred,1)::interface
                          else
                            (pred,0)::interface
                        in
                        aux (Ckappa_sig.next_state_index k) interface
                    in
                    error,
                    aux
                      (Ckappa_sig.state_index_of_int 0) interface

               )
               site_set
               (error,[])
           in
           error,
           ((agent_type, counter), interface)::list
        )
        agent_packs
        []
  end

let compute_rule_creation parameters error handler (packs, _backward) compil =
  let error, creation =
    Ckappa_sig.Rule_id_quick_nearly_Inf_Int_storage_Imperatif.create parameters error 0
  in
  Ckappa_sig.Rule_nearly_Inf_Int_storage_Imperatif.fold
  parameters
  error
  (fun parameters error rule_id rule rule_creations ->
    let error, creation =
      match
        Ckappa_sig.Rule_id_quick_nearly_Inf_Int_storage_Imperatif.unsafe_get
          parameters error
          rule_id
          rule_creations
      with
      | error, None ->
        Ckappa_sig.Agent_type_site_quick_nearly_Inf_Int_Int_storage_Imperatif_Imperatif.create
          parameters error (0,0)
      | error, Some a -> error, a
    in
    let error, creation =
       List.fold_left
         (fun (error, creation) (ag_id, agent_type) ->
            let error, ag_r =
                Ckappa_sig.Agent_id_quick_nearly_Inf_Int_storage_Imperatif.get
                  parameters error
                  ag_id
                  rule.Cckappa_sig.e_rule_c_rule.Cckappa_sig.rule_rhs.Cckappa_sig.views
            in
            let error, list =
              convert_view parameters error handler compil packs agent_type
                ag_r
            in
            List.fold_left
              (fun (error, creation) ((agent_type, counter), interface) ->
                 let error, old =
                   match
                     Ckappa_sig.Agent_type_site_quick_nearly_Inf_Int_Int_storage_Imperatif_Imperatif.unsafe_get
                       parameters error (agent_type,counter) creation
                   with
                   | error, Some l -> error, l
                   | error, None -> error, []
                 in
                 Ckappa_sig.Agent_type_site_quick_nearly_Inf_Int_Int_storage_Imperatif_Imperatif.set
                   parameters error (agent_type,counter) (interface::old) creation)
              (error, creation) list
         )
         (error, creation)
         rule.Cckappa_sig.e_rule_c_rule.Cckappa_sig.actions.Cckappa_sig.creation
    in
    Ckappa_sig.Rule_id_quick_nearly_Inf_Int_storage_Imperatif.set
      parameters error
      rule_id creation
      rule_creations)
      compil.Cckappa_sig.rules
      creation


let compute_static parameters error handler compil =
  let error, (packs, backward) =
    compute_packs parameters error handler compil
  in
  let error, rule_restrictions =
    compute_rule_restrictions parameters error handler (packs, backward) compil
  in
  let error, rule_creation =
    compute_rule_creation parameters error handler (packs, backward) compil
  in
  error,
  {
    Counters_domain_type.packs = packs ;
    Counters_domain_type.backward_pointers = backward ;
    Counters_domain_type.rule_restrictions =
      rule_restrictions ;
    Counters_domain_type.rule_creation =
      rule_creation ;
  }