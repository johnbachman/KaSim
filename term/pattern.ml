(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

type link = UnSpec | Free | Link of int * int (** node_id, site_id *)

(** The link of site k of node i is [fst nodes(i).(k)].

    The internal state of site k of node i is [snd nodes(i).(k)]. A
    negative number means UnSpec. *)
type cc =
  {
    nodes_by_type: int list array;
    nodes: (link * int) array Mods.IntMap.t;
  (*pattern graph id -> [|... (link_j,state_j)...|] i.e agent_id on site_j has
    a link link_j and internal state state_j (-1 means any) *)
    recogn_nav: Navigation.t;
  }

type t = cc

type id = int

let compare_canonicals cc cc' = Mods.int_compare cc cc'

let is_equal_canonicals cc cc' = compare_canonicals cc cc' = 0

let hash_prime = 29

let coarse_hash cc =
  Array.fold_right
    (fun l acc -> List.length l + hash_prime * acc)
    cc.nodes_by_type 0

let id_to_yojson cc = `Int cc

let id_of_yojson = function
  | `Int cc -> cc
  | x ->
    raise (Yojson.Basic.Util.Type_error ("Not a pattern id",x))

module Set = Mods.IntSet

module ObsMap = struct
  include Mods.DynArray
  let dummy x = make 0 x
end

let empty_cc sigs =
  let nbt = Array.make (Signature.size sigs) [] in
  {nodes_by_type = nbt; recogn_nav = [];
   nodes = Mods.IntMap.empty;}

let raw_find_ty tys id =
  let rec aux i =
    assert (i >= 0);
    if List.mem id tys.(i) then i else aux (pred i)
  in aux (Array.length tys - 1)

let find_ty cc id = raw_find_ty cc.nodes_by_type id

let add_origin deps = function
  | None -> deps
  | Some x -> Operator.DepSet.add x deps

let reconstruction_navigation cc = cc.recogn_nav

(** Errors *)
let already_specified ?sigs x i =
  ExceptionDefn.Malformed_Decl
    (Locality.dummy_annot
       (Format.asprintf "Site %a of agent %a already specified"
          (Agent.print_site ?sigs x) i
          (Agent.print ?sigs ~with_id:false) x))

let dangling_node ~sigs tys x =
  ExceptionDefn.Malformed_Decl
    (Locality.dummy_annot
       (Format.asprintf
          "Cannot proceed because last declared agent %a/*%i*/%a"
          (Signature.print_agent sigs) (raw_find_ty tys x) x
          Format.pp_print_string " is not linked to its connected component."))

let identity_injection cc =
  Renaming.identity
    (Array.fold_left (fun x y -> List.rev_append y x) [] cc.nodes_by_type)

(** pick a root in the CC. Any root works.
    In this case pick the last node of smallest type *)
let raw_find_root nodes_by_type =
  let rec aux ty =
    if ty = Array.length nodes_by_type
    then None
    else match nodes_by_type.(ty) with
      | [] -> aux (succ ty)
      | h::t ->
        let x = List.fold_left (fun _ x -> x) h t in
        Some(x,ty)
  in aux 0

let find_root cc = raw_find_root cc.nodes_by_type

let weight cc =
  let links,double =
    Mods.IntMap.fold
      (fun _ ->
         Array.fold_right
           (fun (i,s) (l,d) -> if i <> UnSpec then
               (succ (if s <> -1 then succ l else l),
               if i <> Free then succ d else d)
             else ((if s <> -1 then succ l else l),d)))
      cc.nodes (0,0) in
  (links - double/2)

let are_compatible ?possibilities ~strict root1 cc1 root2 cc2 =
  let tick x =
    match possibilities with
    | None -> ()
    | Some s -> s := Mods.Int2Set.remove x !s in
  let rec aux at_least_one_edge rename = function
    | [] -> if at_least_one_edge then Some rename else None
    | (o,p as pair)::todos ->
      let () = tick pair in
      match Tools.array_fold_left2i
              (fun _ c (lx,ix) (ly,iy) ->
                 match c with
                 | None -> c
                 | Some (one_edge,todo,ren) ->
                   if ((not strict && (ix = -1||iy = -1)) || ix = iy) then
                     match lx, ly with
                     | (Link _, Free| Free, Link _) -> None
                     | (UnSpec, Free| Free, UnSpec
                       | Link _, UnSpec |UnSpec, Link _) ->
                       if strict then None
                       else Some (one_edge || (ix <> -1 && ix = iy),todo,ren)
                     | UnSpec, UnSpec ->
                       Some (one_edge || (ix <> -1 && ix = iy),todo,ren)
                     | Free, Free -> Some (true,todo,ren)
                     | Link (n1,s1), Link (n2,s2) ->
                       if s1 = s2 then
                         if Renaming.mem n1 ren then
                           if Renaming.apply ren n1 = n2
                           then Some (true,todo,ren)
                           else None
                         else match Renaming.add n1 n2 ren with
                           | None -> None
                           | Some r' ->
                             if find_ty cc1 n1 = find_ty cc2 n2
                             then Some (true,(n1,n2)::todo,r')
                             else None
                       else None
                   else None
              )
              (Some (at_least_one_edge,todos,rename))
              (Mods.IntMap.find_default [||] o cc1.nodes)
              (Mods.IntMap.find_default [||] p cc2.nodes) with
      | None -> None
      | Some (one_edges',todos',ren') -> aux one_edges' ren' todos' in
  match Renaming.add root1 root2 Renaming.empty with
  | None -> assert false
  | Some r ->
    let a_single_agent =
      Array.fold_left (fun b (l,i) -> b && i = -1 && l = UnSpec)
        true (Mods.IntMap.find_default [||] root1 cc1.nodes) ||
      Array.fold_left (fun b (l,i) -> b && i = -1 && l = UnSpec)
        true (Mods.IntMap.find_default [||] root2 cc2.nodes) in
    aux a_single_agent r [root1,root2]

(** @returns injection from a to b *)
let equal a b =
  match Tools.array_min_equal_not_null
          (Array.map (fun x -> List.length x,x) a.nodes_by_type)
          (Array.map (fun x -> List.length x,x) b.nodes_by_type) with
  | None -> None
  | Some ([],ags) -> if ags = [] then Some Renaming.empty else None
  | Some (h1::_,ags) ->
    List.fold_left
      (fun bool ag ->
         match bool with
         | Some _ -> bool
         | None -> are_compatible ~strict:true h1 a ag b)
      None ags

let automorphisms a =
  match
    Array.fold_left
      (fun acc x -> Tools.min_pos_int_not_zero acc (List.length x,x))
      (0,[]) a.nodes_by_type
  with
  | _, [] -> [Renaming.empty]
  | _, (h :: _ as l) ->
    List.fold_left (fun acc ag ->
        match are_compatible ~strict:true h a ag a with
        | None -> acc
        | Some r -> r::acc) [] l

let potential_pairing =
  Tools.array_fold_left2i
    (fun _ acc la -> List.fold_left
        (fun acc b -> List.fold_left
            (fun acc a -> Mods.Int2Set.add (a,b) acc) acc la) acc)
    Mods.Int2Set.empty

let matchings a b =
  let possibilities = ref (potential_pairing a.nodes_by_type b.nodes_by_type) in
  let rec for_one_root acc =
    match Mods.Int2Set.choose !possibilities with
    | None -> acc
    | Some (x,y) ->
      match are_compatible ~possibilities ~strict:false x a y b with
      | None -> for_one_root acc
      | Some r -> for_one_root (r::acc) in
  for_one_root []

(*turns a cc into a path(:list) in the domain*)
let raw_to_navigation (full:bool) nodes_by_type nodes =
  let rec build_for (first,out) don = function
    | [] -> List.rev out
    | h :: t ->
      let first',out',todo =
        Tools.array_fold_lefti
          (fun i (first,ans,re as acc) (l,s) ->
             let (first',ans',_ as acc') =
               if (full || first) && s >= 0 then
                 (false,
                  (((if first
                     then Navigation.Fresh (h,raw_find_ty nodes_by_type h)
                     else Navigation.Existing h),i),
                   Navigation.ToInternal s)::ans,re)
               else acc in
             match l with
             | UnSpec -> acc'
             | Free ->
               if full || first'
               then (false,
                     (((if first'
                        then Navigation.Fresh (h,raw_find_ty nodes_by_type h)
                        else Navigation.Existing h),i),
                      Navigation.ToNothing)::ans',re)
               else acc'
             | Link (n,l) ->
               if List.mem n don || (n = h && i > l) then acc'
               else if n = h || List.mem n re
               then
                 if full || first'
                 then (false,
                       (((if first'
                          then Navigation.Fresh (h,raw_find_ty nodes_by_type h)
                          else Navigation.Existing h),i),
                        Navigation.ToNode (Navigation.Existing n,l))::ans',re)
                 else acc'
               else
                 (false,
                  (((if first'
                     then Navigation.Fresh (h,raw_find_ty nodes_by_type h)
                     else Navigation.Existing h),i),
                   Navigation.ToNode
                     (Navigation.Fresh(n,raw_find_ty nodes_by_type n),l))::ans',
                  n::re))
          (first,out,t) (Mods.IntMap.find_default [||] h nodes) in
      build_for (first',out') (h::don) todo
  in
  match raw_find_root nodes_by_type with
  | None -> [] (*empty path for x0*)
  | Some (x,_) -> (*(ag_sort,ag_id)*)
    build_for (true,[]) (*wip*) [] (*already_done*) [x] (*todo*)

let rec sub_minimize_renaming r = function
  | [], _ -> r
  | _::_, [] -> assert false
  | x::q as l,y::q' -> match Renaming.add x y r with
    | Some r' -> sub_minimize_renaming r' (q,q')
    | None -> sub_minimize_renaming r (l,q')

let minimize_renaming dst_nbt ref_nbt =
  let re = Tools.array_fold_lefti
      (fun ty ->
         List.fold_left (fun r id ->
             let ids' =
               List_util.smart_filter (fun id' -> id <> id') dst_nbt.(ty) in
             if ids' == dst_nbt.(ty) then r
             else let () = dst_nbt.(ty) <- ids' in
               Option_util.unsome Renaming.empty (Renaming.add id id r)))
      Renaming.empty ref_nbt in
  Tools.array_fold_lefti
    (fun ty r ids -> sub_minimize_renaming r (ids,ref_nbt.(ty))) re dst_nbt

let minimize cand_nbt cand_nodes ref_nbt =
  let re = minimize_renaming cand_nbt ref_nbt in
  let nodes_by_type =
    Array.map (List.filter (fun a -> Renaming.mem a re)) ref_nbt in
  let nodes =
    Mods.IntMap.fold
      (fun id sites acc ->
         let sites' = Array.map (function
             | Link (n,s),i -> Link (Renaming.apply re n,s),i
             | (UnSpec|Free),_ as x -> x) sites in
         Mods.IntMap.add (Renaming.apply re id) sites' acc)
      cand_nodes Mods.IntMap.empty in
  { nodes_by_type; nodes;
    recogn_nav =
      raw_to_navigation false nodes_by_type nodes; }

let infs cc1 cc2 =
  let possibilities =
    ref (potential_pairing cc1.nodes_by_type cc2.nodes_by_type) in
  let rec aux rename nodes = function
    | [] -> nodes
    | (o,p as pair)::todos ->
      let () = possibilities := Mods.Int2Set.remove pair !possibilities in
      let lnk1 = Mods.IntMap.find_default [||] o cc1.nodes in
      let (todos',ren'),outl =
        Tools.array_fold_left_mapi
          (fun k (todo,ren as acc) (ly,iy) ->
             let (lx,ix) = lnk1.(k) in
             match lx, ly with
             | (Link _, Free| Free, Link _
               | Link _, UnSpec |UnSpec, Link _
               | UnSpec, Free| Free, UnSpec
               | UnSpec, UnSpec) ->
               acc,(UnSpec,if ix = iy then iy else -1)
             | Free, Free -> acc,(Free,if ix = iy then iy else -1)
             | Link (n1,s1) as x, Link (n2,s2) ->
               if s1 = s2 then
                 if Renaming.mem n1 ren then
                   (acc,
                    ((if Renaming.apply ren n1 = n2 then x else UnSpec),
                     if ix = iy then iy else -1))
                 else match Renaming.add n1 n2 ren with
                   | None -> acc,(UnSpec,if ix = iy then iy else -1)
                   | Some r' ->
                     if find_ty cc1 n1 = find_ty cc2 n2
                     then ((n1,n2)::todo,r'),(x,if ix = iy then iy else -1)
                     else acc,(UnSpec,if ix = iy then iy else -1)
               else (acc,(UnSpec,if ix = iy then iy else -1))
          )
          (todos,rename)
          (Mods.IntMap.find_default [||] p cc2.nodes) in
      if Array.fold_left (fun b (l,i) -> b && l = UnSpec && i < 0) true outl
      then aux ren' nodes todos'
      else aux ren' (Mods.IntMap.add o outl nodes) todos' in

  let rec for_one_root acc =
    match Mods.Int2Set.choose !possibilities with
    | None -> acc
    | Some (root1,root2) ->
      match Renaming.add root1 root2 Renaming.empty with
      | None -> assert false
      | Some r ->
        let nodes = aux r Mods.IntMap.empty [root1,root2] in
        let acc' =
          if Mods.IntMap.is_empty nodes then acc else
            let nodes_by_type = Array.map
                (List.filter (fun a -> Mods.IntMap.mem a nodes))
                cc1.nodes_by_type in
            (minimize nodes_by_type nodes cc1.nodes_by_type)::acc in
        for_one_root acc'
  in for_one_root []

let intersection renaming cc1 cc2 =
  let nodes,image =
    Renaming.fold
      (fun i j (accn,l as acc) ->
         match Mods.IntMap.find_option i cc1.nodes with
         | None -> acc
         | Some nodes1 ->
           match Mods.IntMap.find_option j cc2.nodes with
           | None -> acc
           | Some nodes2 ->
             let out = Array.mapi
                 (fun k (l2,i2) ->
                    let (l1,i1) = nodes1.(k) in
                    ((if l1 = UnSpec then UnSpec else l2),
                     (if i1 = -1 then -1 else i2))) nodes2 in
             (Mods.IntMap.add j out accn, j::l))
      renaming (Mods.IntMap.empty,[]) in
  let nodes_by_type = Array.map
      (List.filter (fun a -> List.mem a image)) cc2.nodes_by_type in
  { nodes_by_type; nodes;
    recogn_nav = raw_to_navigation false nodes_by_type nodes; }

let print_cc ~new_syntax ?sigs ?cc_id f cc =
  let print_intf (ag_i, _ as ag) link_ids neigh =
    snd
      (Tools.array_fold_lefti
         (fun p (not_empty, (free, link_ids as out)) (el, st) ->
            let () =
              if st >= 0
              then Format.fprintf
                  f "%t%a"
                  (if not_empty then Pp.comma else Pp.empty)
                  (Agent.print_internal ?sigs ag p) st
              else
              if  el <> UnSpec then
                Format.fprintf
                  f "%t%a"
                  (if not_empty then Pp.comma else Pp.empty)
                  (Agent.print_site ?sigs ag) p in
            match el with
            | UnSpec ->
              if st >= 0 then
                let () = if not new_syntax then Format.fprintf f "?" in
                (true,out)
              else (not_empty,out)
            | Free ->
              let () = if new_syntax then Format.fprintf f "!." in
              (true,out)
            | Link (dst_a,dst_p) ->
              let i,out' =
                match
                  Mods.Int2Map.find_option (dst_a,dst_p) link_ids
                with
                | Some x -> (x, out)
                | None ->
                  (free, (succ free,
                          Mods.Int2Map.add (ag_i,p) free link_ids))
              in
              let () = Format.fprintf f "!%i" i in
              true, out')
         (false, link_ids) neigh)
  in
  let () = match cc_id with
    | None -> ()
    | Some cc_id -> Format.fprintf f "/*cc%i*/@ " cc_id in
  let (_, _) =
    Mods.IntMap.fold
      (fun x el (not_empty,link_ids) ->
         let ag_x = (x,find_ty cc x) in
         let () =
           Format.fprintf
             f "%t@[<h>%a("
             (if not_empty then Pp.comma else Pp.empty)
             (Agent.print ?sigs ~with_id:(cc_id<>None)) ag_x in
         let out = print_intf ag_x link_ids el in
         let () = Format.fprintf f ")@]" in
         true, out)
      cc.nodes (false, (1, Mods.Int2Map.empty))
  in
  ()

let to_yojson cc =
  match Mods.IntMap.max_key cc.nodes with
  | None -> `Null
  | Some m ->
    let s = succ m in
    let sorts = Array.make s None in
    let () =
      Array.iteri
        (fun ty -> List.iter (fun id -> sorts.(id) <- Some ty))
        cc.nodes_by_type in
    `Assoc [
      "sorts",
      `List
        (Array.fold_right
           (fun x acc -> (match x with None -> `Null | Some i -> `Int i)::acc)
           sorts []);
      "nodes",
      `List (Tools.recti
               (fun acc i -> (match Mods.IntMap.find_option i cc.nodes with
                    | None -> `Null
                    | Some a ->
                      `List (Array.fold_right
                               (fun (l,s) acc ->
                                  `List [(match l with
                                      | Free -> `Bool true
                                      | Link (n,s) ->
                                        `Assoc ["node",`Int n;"site",`Int s]
                                      | UnSpec -> `Bool false);
                                     if s < 0 then `Null else `Int s]::acc)
                               a []))::acc)
               [] s);
    ]

let of_yojson sig_decl = function
  | `Assoc ["sorts",`List s;"nodes",`List n;]
  | `Assoc ["nodes",`List n;"sorts",`List s] ->
    let _,nodes =
      List.fold_left
        (fun (i,acc) -> function
           | `Null -> (succ i,acc)
           | `List l ->
             (succ i,
              Mods.IntMap.add i
                (Tools.array_map_of_list (function
                     | `List [`Bool b;`Null] -> (if b then Free else UnSpec),-1
                     | `List [`Assoc ["node",`Int n;"site",`Int s]
                             | `Assoc ["site",`Int s;"node",`Int n]; `Null] ->
                       Link (n,s),-1
                     | `List [`Bool b;`Int s] -> (if b then Free else UnSpec),s
                     | `List [`Assoc ["node",`Int n;"site",`Int s]
                             | `Assoc ["site",`Int s;"node",`Int n]; `Int st] ->
                       Link (n,s),st
                     | x ->
                       raise (Yojson.Basic.Util.Type_error ("Invalid node",x))
                   ) l) acc)
           | x -> raise (Yojson.Basic.Util.Type_error ("Invalid node links",x)))
    (0,Mods.IntMap.empty) n in
    let nodes_by_type = Array.make (Signature.size sig_decl) [] in
    let () =
      List.iteri (fun i -> function
          | `Null -> ()
          | `Int ty -> nodes_by_type.(ty) <- i :: nodes_by_type.(ty)
          | x -> raise (Yojson.Basic.Util.Type_error ("Wrong node type",x)))
        s in
    {nodes_by_type;nodes;
     recogn_nav = raw_to_navigation false nodes_by_type nodes}
  | `Null -> empty_cc sig_decl
  | x -> raise (Yojson.Basic.Util.Type_error ("Not a pattern",x))

let add_fully_specified_to_graph sigs graph cc =
  let e,g =
    Tools.array_fold_lefti
      (fun ty ->
         List.fold_left
           (fun (emb,g) x ->
              let a, g' = Edges.add_agent sigs ty g in
              let emb' = Mods.IntMap.add x (a,ty) emb in
              let g'' =
                Tools.array_fold_lefti
                  (fun s acc (l,i) ->
                     let acc' =
                       if i <> -1 then Edges.add_internal a s i acc else acc in
                     match l with
                     | UnSpec | Free -> Edges.add_free a s acc'
                     | Link (x',s') ->
                       match Mods.IntMap.find_option x' emb' with
                       | None -> acc'
                       | Some ag' -> fst @@ Edges.add_link (a,ty) s ag' s' acc')
                  g' (Mods.IntMap.find_default [||] x cc.nodes) in
              (emb',g'')))
      (Mods.IntMap.empty,graph) cc.nodes_by_type in
  let r =
    Mods.IntMap.fold
      (fun i (a,_) r -> Option_util.unsome Renaming.empty (Renaming.add i a r))
      e Renaming.empty  in
  (g,r)

let merge_compatible reserved_ids free_id inj1_to_2 cc1 cc2 =
  let img = Renaming.image inj1_to_2 in
  let available_ids =
    Array.map (List.filter (fun id -> not (Mods.IntSet.mem id img)))
      reserved_ids in
  let used_ids =
    Array.map
      (List_util.map_option
         (fun id -> if Renaming.mem id inj1_to_2
           then Some (Renaming.apply inj1_to_2 id)
           else None))
      cc1.nodes_by_type in
  let available_in_cc1 =
    Array.mapi
      (fun i l -> Tools.recti
          (fun l _ -> List.tl l) l (List.length cc1.nodes_by_type.(i)))
      reserved_ids in
  let free_id_for_cc1 = ref free_id in

  let get_cc2 j ((inj1,free_id),inj2,(todos1,todos2) as pack) =
    if Renaming.mem j inj2 then (Renaming.apply inj2 j,pack)
    else
      let ty = find_ty cc2 j in
      let img,free_id' =
        match available_ids.(ty) with
        | [] -> free_id,succ free_id
        | h :: t -> let () = available_ids.(ty) <- t in
          h,free_id in
      let () = used_ids.(ty) <- img :: used_ids.(ty) in
      let o =
        match available_in_cc1.(ty) with
        | [] -> let x = !free_id_for_cc1 in let () = incr free_id_for_cc1 in x
        | h :: t -> let () = available_in_cc1.(ty) <- t in h in
      img,
      (((match Renaming.add o img inj1 with Some x -> x | None -> assert false),
        free_id'),
       (match Renaming.add j img inj2 with Some x -> x | None -> assert false),
       (todos1,(j,img)::todos2)) in

  let get_cc1 i ((inj1,free_id),inj2,(todos1,todos2) as pack) =
    if Renaming.mem i inj1 then (Renaming.apply inj1 i,pack)
    else
      let ty = find_ty cc1 i in
      let img,free_id' =
        match available_ids.(ty) with
        | [] -> free_id,succ free_id
        | h :: t -> let () = available_ids.(ty) <- t in
          h,free_id in
      let () = used_ids.(ty) <- img :: used_ids.(ty) in
      img,
      (((match Renaming.add i img inj1 with Some x -> x | None -> assert false),
        free_id'),inj2,((i,img)::todos1,todos2)) in
  let pack',nodes =
    let rec glue pack inj2 nodes = function
      | [], [] -> (pack,nodes)
      | [], (i,j) :: todos2 ->
        let nodesi = Mods.IntMap.find_default [||] i cc2.nodes in
        let nodeso = Array.copy nodesi in
        let (pack',inj2',todos') =
        Tools.array_fold_lefti
          (fun k acc -> function
             | (UnSpec | Free), _ -> acc
             | Link (n,s),st ->
               let n',acc' = get_cc2 n acc in
               let () = nodeso.(k) <- (Link (n',s),st) in acc')
          (pack,inj2,([],todos2)) nodesi in
        glue pack' inj2' (Mods.IntMap.add j nodeso nodes) todos'
      | (i,j) :: todos1, todos2 ->
        let nodesi = Mods.IntMap.find_default [||] i cc1.nodes in
        let nodeso = Array.copy nodesi in
        let (pack',inj2',todos') =
          match Mods.IntMap.find_option j cc2.nodes with
          | None ->
            Tools.array_fold_lefti
              (fun k acc -> function
                 | (UnSpec | Free),_ -> acc
                 | Link (n,s),st ->
                   let n',acc' = get_cc1 n acc in
                   let () = nodeso.(k) <- (Link (n',s),st) in acc')
              (pack,inj2,(todos1,todos2)) nodesi
          | Some nodesj ->
            Tools.array_fold_lefti
              (fun k acc -> function
                 | Free,_ ->
                   let _,stj = nodesj.(k) in
                   let () = if stj  <> -1 then nodeso.(k) <- (Free,stj) in acc
                 | Link (n,s),sti ->
                   let _,stj = nodesj.(k) in
                   let sto = if stj  <> -1 then stj else sti in
                   let n',acc' = get_cc1 n acc in
                   let () = nodeso.(k) <- (Link (n',s),sto) in acc'
                 | UnSpec,sti -> match nodesj.(k) with
                   | UnSpec,stj ->
                     let () =
                       if stj  <> -1 then nodeso.(k) <- (UnSpec,stj) in acc
                   | Free,stj ->
                     let () =
                       nodeso.(k) <- (Free,if stj <> -1 then stj else sti) in
                     acc
                   | Link (n,s),stj ->
                     let sto = if stj  <> -1 then stj else sti in
                     let n',acc' = get_cc2 n acc in
                     let () = nodeso.(k) <- (Link (n',s),sto) in acc')
              (pack,inj2,(todos1,todos2)) nodesi in
        glue pack' inj2' (Mods.IntMap.add j nodeso nodes) todos' in
    glue (inj1_to_2,free_id) (Renaming.identity (Mods.IntSet.elements img))
         Mods.IntMap.empty (Renaming.to_list inj1_to_2,[]) in
  let nodes_by_type = Array.map (List.sort Mods.int_compare) used_ids in
  let () =
    Array.iteri
      (fun i x -> reserved_ids.(i) <-
          List_util.merge_uniq Mods.int_compare nodes_by_type.(i) x)
      available_ids in
  (pack',
   {
     nodes_by_type; nodes;
     recogn_nav = raw_to_navigation false nodes_by_type nodes;
   })

let build_navigation_between inj_d_to_o cc_o cc_d =
  let rec handle_links discovered next_round recogn intern = function
    | [] ->
      if next_round = [] then (List.rev_append recogn intern)
      else handle_links discovered [] recogn intern next_round
    | ((i,j,s),(n',s') as h) :: todos ->
      let n = Renaming.apply inj_d_to_o n' in
      match Mods.IntSet.mem j discovered, Mods.IntSet.mem n' discovered with
      | (false, false) ->
        handle_links discovered (h::next_round) recogn intern todos
      | (true, true) ->
        let intern' =
          ((Navigation.Existing i,s),
           Navigation.ToNode (Navigation.Existing n,s'))::intern in
        handle_links discovered next_round recogn intern' todos
      | true, false ->
        let recogn' =
          ((Navigation.Existing i,s),
           Navigation.ToNode
             (Navigation.Fresh (n,find_ty cc_d n'),s'))::recogn in
        handle_links
          (Mods.IntSet.add n' discovered) next_round recogn' intern todos
       | false, true ->
         let recogn' =
           ((Navigation.Existing n,s'),
            Navigation.ToNode
              (Navigation.Fresh (i,find_ty cc_d j),s))::recogn in
         handle_links
           (Mods.IntSet.add j discovered) next_round recogn' intern todos in
    let discov,all_links,intern =
      Renaming.fold
        (fun j i (disc,links,inter) ->
           let nodesd = Mods.IntMap.find_default [||] j cc_d.nodes in
         let disc',nodeso =
           match Mods.IntMap.find_option i cc_o.nodes with
           | None ->
             disc,
             Array.make (Array.length nodesd) (UnSpec,-1)
           | Some nodeso ->
             Mods.IntSet.add j disc,nodeso in
         Tools.array_fold_left2i
           (fun s (dis,li,int as acc) (ol,os) (dl,ds) ->
              let (_,_, int' as acc') =
                if os = -1 && ds <> -1
                then (dis,li,((Navigation.Existing i,s),Navigation.ToInternal ds)::int)
                else acc in
              if ol <> UnSpec then acc' else
                match dl with
                | UnSpec -> acc'
                | Free ->
                  dis,li,((Navigation.Existing i,s),Navigation.ToNothing)::int'
                | Link (n,s') ->
                  if n > (*la*)j || (n = j && s > s') then acc'
                  else dis,((i,j,s),(n,s'))::li,int')
         (disc',links,inter) nodeso nodesd)
      inj_d_to_o (Mods.IntSet.empty,[],[]) in
    handle_links discov [] [] intern all_links

module Env : sig
  type transition = {
    next: Navigation.t;
    dst: id (* id of cc and also address in the Env.domain map*);
    inj: Renaming.t; (* From dst To ("this" cc + extra edge) *)
  }

  type point = {
    content: cc;
    roots: (int list (*ids*) * int (*ty*)) option;
    deps: Operator.DepSet.t;
    mutable sons: transition list;
  }

   val content: point -> cc
   val roots: point -> (int list (*ids*) * int (*ty*)) option
   val deps: point -> Operator.DepSet.t
   val sons: point -> transition list

  type t = {
    sig_decl: Signature.s;
    id_by_type: int list array;
    max_obs: int;
    domain: point array;
    elementaries: (Navigation.step * id) list array array;
    single_agent_points: (id*Operator.DepSet.t) option array;
  }

  val get : t -> int -> point
  val get_single_agent : int -> t -> (id * Operator.DepSet.t) option

  val get_elementary : t -> Navigation.step -> (id * point * Renaming.t) option

  val signatures : t -> Signature.s
  val new_obs_map : t -> (id -> 'a) -> 'a ObsMap.t

  val print : Format.formatter -> t -> unit
  val to_yojson : t -> Yojson.Basic.json
  val of_yojson : Yojson.Basic.json -> t
end = struct
  type transition = {
    next: Navigation.t;
    dst: id (* id of cc and also address in the Env.domain map*);
    inj: Renaming.t; (* From dst To ("this" cc + extra edge) *)
  }

  type point = {
    content: cc;
    roots: (int list (*ids*) * int (*ty*)) option;
    deps: Operator.DepSet.t;
    mutable sons: transition list;
  }

  let content p = p.content
  let roots p = p.roots
  let deps p = p.deps
  let sons p = p.sons

  type t = {
    sig_decl: Signature.s;
    id_by_type: int list array;
    max_obs: int;
    domain: point array;
    elementaries: (Navigation.step * id) list array array;
    single_agent_points: (id*Operator.DepSet.t) option array;
  }

  let signatures env = env.sig_decl

  let print f env =
    let pp_point p_id f p =
      Format.fprintf
        f "@[<hov 2>@[<h>%a@]@ %t-> @[(%a)@]@]"
        (print_cc ~new_syntax:true ~sigs:env.sig_decl ~cc_id:p_id) p.content
        (fun f -> if p.roots <> None then
            Format.fprintf
              f "@[[%a]@]@ "
              (Pp.set Operator.DepSet.elements Pp.space Operator.print_rev_dep)
              p.deps)
        (Pp.list
           Pp.space
           (fun f s ->
              Format.fprintf
                f "@[%a(%a)@ %i@]"
                (Navigation.print env.sig_decl (find_ty p.content))
                s.next
                Renaming.print s.inj s.dst))
        p.sons in
    Format.fprintf
      f "@[<v>%a@]"
      (Pp.array Pp.space pp_point)
      env.domain

  let get_single_agent ty env = env.single_agent_points.(ty)

  let get env cc_id = env.domain.(cc_id)

  let transition_to_yojson t =
    `Assoc [
      "dst", `Int t.dst;
      "inj", Renaming.to_yojson t.inj;
      "nav", Navigation.to_yojson t.next;
    ]
  let transition_of_yojson = function
    | `Assoc [ "dst", `Int dst; "inj", r; "nav", n ]
    | `Assoc [ "dst", `Int dst; "nav", n; "inj", r ]
    | `Assoc [ "inj", r; "nav", n; "dst", `Int dst ]
    | `Assoc [ "nav", n; "inj", r; "dst", `Int dst ]
    | `Assoc [ "inj", r; "dst", `Int dst; "nav", n ]
    | `Assoc [ "nav", n; "dst", `Int dst; "inj", r ] ->
      { dst; inj = Renaming.of_yojson r; next = Navigation.of_yojson n; }
    | x ->
      raise (Yojson.Basic.Util.Type_error ("Incorrect transition",x))

  let point_to_yojson p =
    `Assoc [
      "content",to_yojson p.content;
      "roots", JsonUtil.of_option
        (fun (ids,ty) ->
           `List [`List (List.map JsonUtil.of_int ids); `Int ty]) p.roots;
      "deps", `Bool (not @@ Operator.DepSet.is_empty p.deps);
      "sons", `List (List.map transition_to_yojson p.sons);
    ]

  let point_of_yojson sig_decl = function
    | `Assoc l as x when List.length l = 4 ->
      begin
        try {
          content = of_yojson sig_decl (List.assoc "content" l);
          roots = (match List.assoc "roots" l with
              | `Null -> None
              | `List [ `List ids; `Int ty ] ->
                Some (List.map Yojson.Basic.Util.to_int ids,ty)
              | _ -> raise Not_found);
          deps = Operator.DepSet.empty;
          sons = (match List.assoc "sons" l with
              | `List l -> List.map transition_of_yojson l
              | _ -> raise Not_found);
        }
        with Not_found ->
          raise (Yojson.Basic.Util.Type_error ("Incorrect domain point",x))
      end
    | x ->
      raise (Yojson.Basic.Util.Type_error ("Incorrect domain point",x))

  let to_yojson env =
    `Assoc [
      "signatures", Signature.to_json env.sig_decl;
      "single_agents", `List
        (Array.fold_right (fun x acc ->
             (match x with None -> `Null | Some (id,_deps) -> `Int id)::acc)
            env.single_agent_points []);
      "elementaries", `List
        (Array.fold_right (fun x acc ->
             `List (Array.fold_right (fun x acc ->
                 `List (List.map (fun (st,d) ->
                     `List [Navigation.step_to_yojson st; `Int d]) x)
                 ::acc) x [])
             ::acc)
            env.elementaries []);
      "dag", `List
        (Array.fold_right (fun x acc ->
             (point_to_yojson x)::acc) env.domain []);
    ]

  let of_yojson = function
    | `Assoc l as x when List.length l = 4 ->
      begin
        let sig_decl = Signature.of_json (List.assoc "signatures" l) in
        try
          {
            sig_decl;
            single_agent_points = (match List.assoc "single_agents" l with
                | `List l  ->
                  Tools.array_map_of_list
                    (Yojson.Basic.Util.to_option
                       (function `Int i -> (i,Operator.DepSet.empty)
                               | x ->
                                 raise (Yojson.Basic.Util.Type_error
                                          ("Wrong single_agent",x)))
                    ) l
                | _ -> raise Not_found);
            elementaries = (match List.assoc "elementaries" l with
                | `List l  ->
                  Tools.array_map_of_list (function
                      | `List l -> Tools.array_map_of_list (function
                          | `List l -> List.map (function
                              | `List [s; `Int d] ->
                                (Navigation.step_of_yojson s,d)
                              | _ -> raise Not_found) l
                          | _ -> raise Not_found) l
                      | _ -> raise Not_found) l
                | _ -> raise Not_found);
            domain =  (match List.assoc "dag" l with
                | `List l  ->
                  Tools.array_map_of_list (point_of_yojson sig_decl) l
                | _ -> raise Not_found);
            id_by_type = [||];
            max_obs = -1;
          }
        with Not_found ->
          raise (Yojson.Basic.Util.Type_error ("Incorrect update domain",x))
      end
    | x ->
      raise (Yojson.Basic.Util.Type_error ("Incorrect update domain",x))

  let new_obs_map env f = Mods.DynArray.init env.max_obs f

  let get_elementary domain = function
    | (Navigation.Existing _,_),_ -> assert false
    | (Navigation.Fresh (_,ty),s),_ as edge ->
      let sa = domain.elementaries.(ty) in
      let rec find_good_edge = function (*one should use a hash here*)
        | [] -> None
        | (st,cc_id) :: tail ->
          match Navigation.compatible_point Renaming.empty st edge with
          | None ->  find_good_edge tail
          | Some inj' ->
            let dst = get domain cc_id in
            Some (cc_id,dst,inj') in
      find_good_edge sa.(s)

end

let print ~new_syntax ?domain ~with_id f id =
  match domain with
  | None -> Format.pp_print_int f id
  | Some env ->
    let cc_id = if with_id then Some id else None in
    print_cc ~new_syntax ~sigs:(Env.signatures env) ?cc_id
      f env.Env.domain.(id).Env.content

let embeddings_to_fully_specified domain a_id b =
  let a = domain.Env.domain.(a_id).Env.content in
  match find_root a with
  | None -> [Renaming.empty]
  | Some (h,ty) ->
    List.fold_left (fun acc ag ->
      match are_compatible ~strict:false h a ag b with
      | None -> acc
      | Some r -> r::acc) [] b.nodes_by_type.(ty)

type prepoint = {
  p_id: id;
  element: cc;
  depending: Operator.DepSet.t;
  roots: (int list (*ids*) * int (*ty*)) option;
}

type work = {
  sigs: Signature.s;
  cc_env: prepoint list Mods.IntMap.t Mods.IntMap.t;
  reserved_id: int list array;
  used_id: int list array;
  free_id: int;
  cc_id: int;
  cc_nodes: (link*int) array Mods.IntMap.t;
  dangling: int; (* node_id *)
}

module PreEnv (*: sig
  type t = {
    sig_decl: Signature.s;
    id_by_type: int list array;
    nb_id: int;
    domain: prepoint list Mods.IntMap.t Mods.IntMap.t;
    mutable used_by_a_begin_new: bool;
  }

  type stat = { nodes: int; nav_steps: int }

  val empty : Signature.s -> t
  val fresh :
    Signature.s -> int list array -> int ->
    prepoint list Mods.IntMap.t Mods.IntMap.t -> t
  val to_work : t -> work

  val add_cc :
    toplevel:bool -> ?origin:Operator.DepSet.elt ->
    prepoint list Mods.IntMap.t Mods.IntMap.t -> id -> cc ->
    prepoint list Mods.IntMap.t Mods.IntMap.t * Renaming.t * cc * id

  val sigs : t -> Signature.s

  val finalize : max_sharing:bool -> t ->
                 (int list * (int * int) list) array array -> Env.t * stat

  val of_env : Env.t -> t
end*) = struct
  type t = {
    sig_decl: Signature.s;
    id_by_type: int list array;
    nb_id: int;
    domain: prepoint list Mods.IntMap.t Mods.IntMap.t;
    mutable used_by_a_begin_new: bool;
  }

  type stat = { nodes: int; nav_steps: int }

  let fresh sigs id_by_type nb_id domain =
    {
      sig_decl = sigs;
      id_by_type = id_by_type;
      nb_id = nb_id;
      domain = domain;
      used_by_a_begin_new = false;
    }

  let empty sigs =
    let nbt' = Array.make (Signature.size sigs) [] in
    fresh sigs nbt' 1 Mods.IntMap.empty

  let fresh_id env =
    succ
      (Mods.IntMap.fold
         (fun _ -> Mods.IntMap.fold
             (fun _ x acc ->
                List.fold_left (fun acc p -> max acc p.p_id) acc x))
         env.domain 0)

  let check_vitality env = assert (env.used_by_a_begin_new = false)

  let to_work env =
    let () = check_vitality env in
    let () = env.used_by_a_begin_new <- true in
    {
      sigs = env.sig_decl;
      cc_env = env.domain;
      reserved_id = env.id_by_type;
      used_id = Array.make (Array.length env.id_by_type) [];
      free_id = env.nb_id;
      cc_id = fresh_id env;
      cc_nodes = Mods.IntMap.empty;
      dangling = 0;
    }

  let sigs env = env.sig_decl

  let empty_point sigs =
    {Env.content = empty_cc sigs; Env.roots = None;
     Env.deps = Operator.DepSet.empty; Env.sons = [];}

  let fill_elem sigs bottom =
    let elementaries =
      Array.init (Signature.size sigs)
        (fun i -> Array.make (Signature.arity sigs i) []) in
    let () =
      Mods.IntMap.iter
        (fun _ -> List.iter (fun p ->
             match p.element.recogn_nav with
             | [] | ((Navigation.Existing _,_),_) :: _ -> assert false
             | ((Navigation.Fresh _,_),_) :: _ :: _ -> ()
             | [(Navigation.Fresh (_,ty1),s1),arr as step] ->
               let sa1 = elementaries.(ty1) in
               let () = sa1.(s1) <- (step,p.p_id) :: sa1.(s1) in
               match arr with
               | Navigation.ToNode (Navigation.Fresh (_,ty2),s2) ->
                 if ty1 = ty2 && s1 <> s2 then
                   sa1.(s2) <- (step,p.p_id) :: sa1.(s2)
                 else
                   let sa2 = elementaries.(ty2) in
                   sa2.(s2) <- (step,p.p_id) :: sa2.(s2)
               | Navigation.ToNode (Navigation.Existing _,s2) ->
                 sa1.(s2) <- (step,p.p_id) :: sa1.(s2)
               | Navigation.ToNothing | Navigation.ToInternal _ -> ()))
        bottom in
    elementaries

  let rec insert_navigation domain dst inj_dst2nav p_id nav =
    let point = domain.(p_id) in
    let rec insert_nav_sons = function
      | [] ->
        let () =
          point.Env.sons <-
            {Env.dst; Env.inj = inj_dst2nav; Env.next = nav} :: point.Env.sons
        in List.length nav
      | h :: t ->
        match Navigation.is_subnavigation
                (identity_injection point.Env.content) nav h.Env.next with
        | None -> insert_nav_sons t
        | Some (_,[]) -> let () = assert (h.Env.dst = dst) in 0
        | Some (inj_nav'2p,nav') ->
          let pre_inj_nav'2q =
            Renaming.compose false inj_nav'2p (Renaming.inverse h.Env.inj) in
          let (inj_nav''2q,nav'') =
            Navigation.rename pre_inj_nav'2q nav' in
          insert_navigation domain dst
            (Renaming.compose false inj_dst2nav inj_nav''2q) h.Env.dst nav'' in
    insert_nav_sons point.Env.sons

  let add_cc ~toplevel ?origin env p_id element =
    let w = weight element in
    let hash = coarse_hash element in
    let rec aux = function
      | [] ->
        let roots = if toplevel then
            match find_root element with
            | None -> None
            | Some (rid,rty) ->
              Some (List.sort Mods.int_compare
                      (List.map
                         (fun r -> Renaming.apply r rid)
                         (automorphisms element)),rty)
          else None in
        [{p_id; element;roots;
          depending=add_origin Operator.DepSet.empty origin}],
        identity_injection element,element,p_id
      | h :: t -> match equal element h.element with
        | None -> let a,b,c,d = aux t in h::a,b,c,d
        | Some r ->
          let roots =
            if h.roots <> None || not toplevel then h.roots
            else match find_root element with
              | None -> None
              | Some (rid,rty) ->
                Some (List.sort Mods.int_compare
                        (List.map
                           (fun r -> Renaming.apply r rid)
                           (automorphisms element)),rty) in
          {p_id=h.p_id; element=h.element;
           depending=add_origin h.depending origin; roots;
          }::t,r,h.element,h.p_id in
    let env_w = Mods.IntMap.find_default Mods.IntMap.empty w env in
    let env_w_h,r,out,out_id = aux (Mods.IntMap.find_default [] hash env_w) in
    Mods.IntMap.add w (Mods.IntMap.add hash env_w_h env_w) env,r,out,out_id

  let rec saturate_one ~max_sharing this max_l level (_,domain as acc) =
    function
    | [] -> if level < max_l then
        saturate_one ~max_sharing this max_l (succ level) acc
          (Mods.IntMap.fold (fun _ -> List.rev_append)
             (Mods.IntMap.find_default Mods.IntMap.empty (succ level) domain)
             [])
      else acc
    | h :: t ->
      let news =
        if max_sharing then infs this.element h.element
        else
          List.rev_map
            (fun r -> intersection r this.element h.element)
            (matchings this.element h.element) in
      let acc' =
        List.fold_left
          (fun (mid,acc) cc ->
             let id' = succ mid in
             let x,_,_,id = add_cc ~toplevel:false acc id' cc in
             ((if id = id' then id else mid),x))
          acc news in
       saturate_one ~max_sharing this max_l level acc' t
  let rec saturate_level ~max_sharing max_l level (_,domain as acc) =
    if level < 2 then acc else
      match Mods.IntMap.find_option level domain with
      | None -> saturate_level ~max_sharing max_l (pred level) acc
      | Some list ->
        let rec aux acc = function
          | [] -> saturate_level ~max_sharing max_l (pred level) acc
          | h::t -> aux (saturate_one ~max_sharing h max_l level acc t) t in
        aux acc (Mods.IntMap.fold (fun _ -> List.rev_append) list [])
  let saturate ~max_sharing domain =
    match Mods.IntMap.max_key domain with
    | None -> 0,domain
    | Some l ->
      let si =
        Mods.IntMap.fold
          (fun _ -> Mods.IntMap.fold
              (fun _ l m -> List.fold_left (fun m p -> max m p.p_id) m l))
          domain 0 in
      saturate_level ~max_sharing l l (si,domain)


  let of_env env =
    let add_cc acc p =
      let w = weight p.element in
      let hash = coarse_hash p.element in
      let acc_w = Mods.IntMap.find_default Mods.IntMap.empty w acc in
      Mods.IntMap.add w
        (Mods.IntMap.add hash (p::Mods.IntMap.find_default [] hash acc_w) acc_w)
        acc in
    let domain' =
      Tools.array_fold_lefti (fun p_id acc p ->
          add_cc acc {p_id; element=p.Env.content;
                      depending=p.Env.deps;roots=p.Env.roots;})
        Mods.IntMap.empty env.Env.domain in
    {
      sig_decl = env.Env.sig_decl;
      nb_id = succ (Array.fold_left (List.fold_left max) 0 env.Env.id_by_type);
      id_by_type = env.Env.id_by_type;
      domain = domain';
      used_by_a_begin_new = false;
    }
end

(** Operation to create cc *)
let check_dangling wk =
  if wk.dangling <> 0 then
    raise (dangling_node ~sigs:wk.sigs wk.used_id wk.dangling)

let begin_new env = PreEnv.to_work env

let raw_finish_new ~toplevel ?origin wk =
  let () = check_dangling wk in
  (* rebuild env *)
  let () =
    Tools.iteri
      (fun i -> wk.reserved_id.(i) <-
          List.rev_append wk.used_id.(i) wk.reserved_id.(i))
      (Array.length wk.used_id) in
  let cc_candidate =
    { nodes_by_type = wk.used_id; nodes = wk.cc_nodes;
      recogn_nav = raw_to_navigation false wk.used_id wk.cc_nodes} in
  let preenv,r,out,out_id = PreEnv.add_cc
      ~toplevel ?origin wk.cc_env wk.cc_id cc_candidate in
  PreEnv.fresh wk.sigs wk.reserved_id wk.free_id preenv,r,out,out_id

let finish_new ?origin wk = raw_finish_new ~toplevel:true ?origin wk

let new_link wk ((x,_ as n1),i) ((y,_ as n2),j) =
  let x_n = Mods.IntMap.find_default [||] x wk.cc_nodes in
  let y_n = Mods.IntMap.find_default [||] y wk.cc_nodes in
  match x_n.(i), y_n.(j) with
  | (UnSpec, stx), (UnSpec,sty) ->
    let () = x_n.(i) <- (Link (y,j),stx) in
    let () = y_n.(j) <- (Link (x,i),sty) in
    if wk.dangling = x || wk.dangling = y
    then { wk with dangling = 0 }
    else wk
  | ((Free | Link _),_), _ ->
    raise (already_specified ~sigs:wk.sigs n1 i)
  | _, ((Free | Link _),_) ->
    raise (already_specified ~sigs:wk.sigs n2 j)

let new_free wk ((x,_ as n),i) =
  let x_n = Mods.IntMap.find_default [||] x wk.cc_nodes in
  match x_n.(i) with
  | UnSpec,st -> let () = x_n.(i) <- (Free,st) in wk
  | (Free | Link _),_ -> raise (already_specified ~sigs:wk.sigs n i)

let new_internal_state wk ((x,_ as n), i) va =
  let x_n = Mods.IntMap.find_default [||] x wk.cc_nodes in
  let (l,s) = x_n.(i) in
  if s >= 0 then raise (already_specified ~sigs:wk.sigs n i)
  else let () = x_n.(i) <- (l,va) in wk

let new_node wk type_id =
  let () = check_dangling wk in
  let arity = Signature.arity wk.sigs type_id in
  match wk.reserved_id.(type_id) with
  | h::t ->
    let () = wk.used_id.(type_id) <- h :: wk.used_id.(type_id) in
    let () = wk.reserved_id.(type_id) <- t in
    let node = (h,type_id) in
    (node,
     { wk with
       dangling = if Mods.IntMap.is_empty wk.cc_nodes then 0 else h;
       cc_nodes = Mods.IntMap.add h (Array.make arity (UnSpec,-1)) wk.cc_nodes;
     })
  | [] ->
    let () = wk.used_id.(type_id) <- wk.free_id :: wk.used_id.(type_id) in
    let node = (wk.free_id, type_id) in
    (node,
     { wk with
       free_id = succ wk.free_id;
       dangling = if Mods.IntMap.is_empty wk.cc_nodes then 0 else wk.free_id;
       cc_nodes =
         Mods.IntMap.add wk.free_id (Array.make arity (UnSpec,-1)) wk.cc_nodes;
     })

let minimal_env env contact_map =
  Tools.array_fold_lefti
    (fun ty ->
       Tools.array_fold_lefti
         (fun s acc (ints,links) ->
            let w = begin_new acc in
            let n,w = new_node w ty in
            let w = new_free w (n,s) in
            let acc',_,_,_ = raw_finish_new ~toplevel:false w in
            let acc'' =
              List.fold_left
                (fun acc i ->
                   let w = begin_new acc in
                   let n,w = new_node w ty in
                   let w = new_internal_state w (n,s) i in
                   let out,_,_,_ = raw_finish_new ~toplevel:false w in
                   out) acc' ints in
            List.fold_left
              (fun acc (ty',s') ->
                 let w = begin_new acc in
                 let n,w = new_node w ty in
                 let n',w = new_node w ty' in
                 let w = new_link w (n,s) (n',s') in
                 let out,_,_,_ = raw_finish_new ~toplevel:false w in
                 if ty = ty' && s < s' then
                   let w = begin_new out in
                   let n,w = new_node w ty in
                   let w = new_link w (n,s) (n,s') in
                   let out',_,_,_ = raw_finish_new ~toplevel:false w in
                   out'
                 else out) acc'' links
         ))
    env contact_map

let fold f_agent f_site cc acc =
  let acc =
    Tools.array_fold_lefti
      (fun agent_type acc list_pos ->
        List.fold_left
          (fun acc pos -> f_agent ~pos ~agent_type acc)
          acc
          list_pos
      )
      acc
      cc.nodes_by_type
  in
  Mods.IntMap.fold
    (fun pos intf acc ->
       Tools.array_fold_lefti
         (fun site acc state -> f_site ~pos ~site state acc)
         acc
         intf
    )
    cc.nodes
    acc

let finalize ~max_sharing env contact_map =
  let env = minimal_env env contact_map in
  let si,complete_domain = PreEnv.saturate ~max_sharing env.PreEnv.domain in
  let domain = Array.make (succ si) (PreEnv.empty_point env.PreEnv.sig_decl) in
  let singles =
    Mods.IntMap.find_default Mods.IntMap.empty 1 complete_domain in
  let elementaries = PreEnv.fill_elem env.PreEnv.sig_decl singles in
  let () =
    Mods.IntMap.iter
      (fun _ -> List.iter
            (fun x ->
              domain.(x.p_id) <-
                { Env.content = x.element; Env.sons = [];
                  Env.deps = x.depending; Env.roots = x.roots; }))
      singles in
  let nav_steps =
    Mods.IntMap.fold
      (fun level domain_level acc_level ->
        if level <= 1 then acc_level else
          Mods.IntMap.fold
            (fun _ l acc ->
              List.fold_left (fun acc x ->
                      let () =  domain.(x.p_id) <-
                          { Env.content = x.element; Env.sons = [];
                            Env.roots = x.roots; Env.deps = x.depending;} in
                      Mods.IntMap.fold (fun _ ll accl->
                          List.fold_left (fun acc e ->
                              match matchings e.element x.element with
                              | [] -> acc
                              | injs ->
                                List.fold_left
                                  (fun acc inj_e_x ->
                                     let (inj_e2sup,_),sup =
                                       merge_compatible env.PreEnv.id_by_type
                                                        env.PreEnv.nb_id
                                         inj_e_x e.element x.element in
                                     match equal sup x.element with
                                     | None -> assert false
                                     | Some inj_sup2x ->
                                       let inj =
                                         Renaming.inverse
                                           (Renaming.compose
                                              false inj_e2sup inj_sup2x) in
                                       let nav = build_navigation_between
                                           inj e.element x.element in
                                       PreEnv.insert_navigation domain x.p_id
                                                                inj e.p_id nav
                                       + acc
                                  )
                                  acc injs
                            ) accl ll) singles acc) acc l)
               domain_level acc_level)
        complete_domain 0 in
  let level0 = Mods.IntMap.find_default Mods.IntMap.empty 0 complete_domain in
  let single_agent_points =
    Array.make (Array.length env.PreEnv.id_by_type) None in
  let () =
    Mods.IntMap.iter (fun _ ->
          List.iter
            (fun p ->
               match find_root p.element with
               | None -> ()
               | Some (_,ty) ->
                 let () = domain.(p.p_id) <-
                     { Env.content = p.element; Env.roots = p.roots;
                       Env.deps = p.depending; Env.sons = []; } in
                 single_agent_points.(ty) <- Some (p.p_id,p.depending)))
        level0 in
  {
    Env.sig_decl = env.PreEnv.sig_decl;
    Env.id_by_type = env.PreEnv.id_by_type;
    Env.max_obs = PreEnv.fresh_id env;
    Env.domain;
    Env.elementaries;
    Env.single_agent_points;
  },{ nodes = si; PreEnv.nav_steps }
