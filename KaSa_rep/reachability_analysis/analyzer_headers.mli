(**
  * analyzer_headers.mli
  * openkappa
  * Jérôme Feret & Ly Kim Quyen, projet Abstraction, INRIA Paris-Rocquencourt
  * 
  * Creation: 2016, the 30th of January
  * Last modification: 
  * 
  * Compute the relations between sites in the BDU data structures
  * 
  * Copyright 2010,2011,2012,2013,2014,2015,2016 Institut National de Recherche 
  * en Informatique et en Automatique.  
  * All rights reserved.  This file is distributed     
  * under the terms of the GNU Library General Public License *)

(** type of the argument of the main function *)
type compilation_result = Cckappa_sig.compil

type rule_id = int

(** type of the static information to be passed to each domain, 
    let us start by this signature at the moment. 
    In a first step, we are going to use only one module, and
    provide it with all the static information that you have computed 
    and that you are using so far.
    Then, we will introduce a collection of independent modules, and 
    dispatch this information between what is common, 
    and what is specific to each domain.*)
type global_static_information =
  compilation_result * Remanent_parameters_sig.parameters

type global_dynamic_information = ()

type event =
  | Check_rule of rule_id

type precondition = unit

type kasa_state = unit

(** This is the type of the encoding of a chemical mixture as a result of compilation *) 
type initial_state = unit

val initialize_global_information:
  Remanent_parameters_sig.parameters ->
  Exception.method_handler ->
  compilation_result ->
  Exception.method_handler * global_static_information * global_dynamic_information
    
val dummy_precondition: precondition					      
 
val get_parameter: global_static_information -> Remanent_parameters_sig.parameters

val get_compilation_information: global_static_information -> compilation_result

val get_initial_state: global_static_information -> initial_state list
