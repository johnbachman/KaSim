(* Js util *)
(* references
   http://toss.sourceforge.net/ocaml.html
   http://peppermint.jp/temp/ao/ao.ml
x*)
open Js
module Html5 = Tyxml_js.Html5

class type configuration = object
  val value : int Js.t Js.prop
  val lineNumbers : bool Js.t Js.prop
  val gutters : Js.string_array Js.t Js.prop
  val mode : Js.js_string Js.t Js.prop
end
let constructor_configuration : configuration Js.t Js.constr = (Js.Unsafe.variable "Object")
let create_configuration () : configuration Js.t  = jsnew constructor_configuration ()

class type codemirror = object
 method getValue : Js.js_string Js.t meth
 method setValue : Js.js_string Js.t -> unit meth
end;;

let fromTextArea
      (dom : Dom_html.element Js.t)
      (configuration : configuration Js.t)
    : codemirror Js.t =
  (* let () = Js.debugger() in *)
  Js.Unsafe.fun_call
    (Js.Unsafe.js_expr "CodeMirror")##fromTextArea
    [| Js.Unsafe.inject dom ; Js.Unsafe.inject configuration |]
