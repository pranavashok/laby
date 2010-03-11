(*
   Copyright (C) 2007-2010 Stéphane Gimenez
   You have permission to copy, modify, and redistribute under the
   terms of the GPL-3.0. For full license terms, see gpl-3.0.txt.
*)

(**
   ocaml-dtools
   @author Stéphane Gimenez
*)

type t =
    <
      internal: F.t -> unit;
      fatal: F.t -> unit;
      error: F.t -> unit;
      warning: F.t -> unit;
      info: F.t -> unit;
      debug: int -> F.t -> unit;
    >

let conf =
  Conf.void
    (F.x "log configuration" [])

let default_level =
  begin try
    int_of_string (Sys.getenv "DEBUG")
  with
  | Not_found -> 0
  | Failure "int_of_float" -> 0
  end


let conf_level =
  Conf.int ~p:(conf#plug "level") ~d:default_level
    (F.x "general log level" [])
let conf_timestamps =
  Conf.bool ~p:(conf#plug "timestamps") ~d:false
    (F.x "display timestamps" [])
let conf_timestamps_format =
  Conf.string ~p:(conf_timestamps#plug "format") ~d:"localized"
    ~comments:[
      F.x "<item> for human readable timestamps in local timezone"
	["item", F.string "localized" ]
      ;
      F.x "<item> for subsecond accuracy, and is timezone independant"
	["item", F.string "unix" ]
      ;
    ]
    (F.x "format of displayed timestamps" [])

let conf_file  =
  Conf.bool ~p:(conf#plug "file") ~d:false
    (F.x "log to file" [])
let conf_file_path =
  Conf.string ~p:(conf_file#plug "path")
    (F.x "path to log file" [])
let conf_file_append =
  Conf.bool ~p:(conf_file#plug "append") ~d:true
    (F.x "append log to the file" [])
let conf_file_perms =
  Conf.int ~p:(conf_file#plug "perms") ~d:0o600
    (F.x "log file permissions" [])
let conf_stdout =
  Conf.bool ~p:(conf#plug "stdout") ~d:true
    (F.x "log to stdout" [])

let state : [ `Chan of out_channel | `Buffer of F.t list ] ref =
  ref (`Buffer [])

let timestamp time =
  begin match conf_timestamps_format#get with
  | "unix" -> F.float time
  | _ -> F.time time
  end

(* Avoiding interlacing logs *)
let mutexify : ('a -> 'b) -> 'a -> 'b =
  let m = T.mutex () in
  begin fun f x ->
    m#lock;
    begin try
      let r = f x in m#unlock; r
    with
    | e -> m#unlock; raise e
    end
  end

let to_ch ch s1 s2 =
  Printf.fprintf ch "%s %s\n%!" s1 s2

let to_stdout s1 s2 =
  if conf_stdout#get then
    Printf.printf "%s %s\n%!" s1 s2

let print h x =
  if conf_file#get then
    begin match !state with
    | `Buffer l ->
	state := `Buffer (x :: l);
	if conf_stdout#get then
	  to_stdout (Fd.render_color h) (Fd.render_color x)
    | `Chan ch ->
	let s1 = Fd.render_color h in
	let s2 = Fd.render_color x in
	to_stdout s1 s2;
	to_ch ch s1 s2
    end
  else
    if conf_stdout#get then
      to_stdout (Fd.render_color h) (Fd.render_color x)

let build ?level path =
  let rec aux p l (t : Conf.ut) =
    begin match p with
    | [] -> t :: l
    | s :: q ->
	let st =
	  begin try t#path [s] with
	  | Conf.Unbound _ ->
	      let c =
		Conf.int ~p:(t#plug s) ?d:level
		  (F.x "subordinate log level" [])
	      in
	      c#ut
	  end
	in
	aux q (t :: l) st
    end
  in
  aux path [] conf_level#ut

let tag_label = Fd.tag "log-label"
let tag_internal_error = Fd.tag "log-internal-error"
let tag_fatal_error = Fd.tag "log-fatal-error"
let tag_error = Fd.tag "log-error"
let tag_warning = Fd.tag "log-warning"
let tag_info = Fd.tag "log-info"
let tag_debug = Fd.tag "log-debug"

let make ?level path : t =
  let confs = build ?level path in
  let path_str = Conf.string_of_path path in
  let bracketize m =
    F.b [F.s "["; m ; F.s "]"]
  in
  let dbracketize m l =
    F.b [F.s "["; m ; F.s ":"; l; F.s "]"]
  in
  let proceed h x =
    mutexify (fun () -> print h x) ()
  in
object (self : t)
  val print =
    begin fun heads x ->
      let time = Unix.gettimeofday () in
      let ts = if conf_timestamps#get then [timestamp time] else [] in
      let lb =
	if path_str <> "" then [tag_label (F.s (path_str ^ ":"))] else []
      in
      proceed (F.h (ts @ lb @ heads)) x
    end
  val active =
    begin fun lvl ->
      let rec aux l =
	begin match l with
	| [] -> false
	| t :: q ->
	    begin try lvl <= (Conf.as_int t)#get with
	    | Conf.Undefined _ -> aux q
	    end
	end
      in
      aux confs
    end
  method internal =
    begin match active (-4) with
    | true -> print [tag_internal_error (bracketize (F.x "internal error" []))]
    | false -> (fun _ -> ())
    end
  method fatal =
    begin match active (-3) with
    | true -> print [tag_fatal_error (bracketize (F.x "fatal error" []))]
    | false -> (fun _ -> ())
    end
  method error =
    begin match active (-2) with
    | true -> print [tag_error (bracketize (F.x "error" []))]
    | false -> (fun _ -> ())
    end
  method warning =
    begin match active (-1) with
    | true -> print [tag_warning (bracketize (F.x "warning" []))]
    | false -> (fun _ -> ())
    end
  method info =
    begin match active 0 with
    | true -> print []
    | false -> (fun _ -> ())
    end
  method debug lvl =
    begin match active lvl with
    | true -> print [tag_debug (dbracketize (F.x "debug" []) (F.int lvl))]
    | false -> (fun _ -> ())
    end
end

let master = make []

let init () =
  let time = Unix.gettimeofday () in
  let open_log () =
    if conf_file#get then
      let opts =
	[Open_wronly; Open_creat; Open_nonblock]
	@ (if conf_file_append#get then [Open_append] else [Open_trunc])
      in
      let log_file_path = conf_file_path#get in
      let log_file_perms = conf_file_perms#get in
      state := `Chan (open_out_gen opts log_file_perms log_file_path)
  in
  let proceed () =
    begin match !state with
    | `Buffer l ->
	open_log ();
	begin match !state with
	| `Buffer l -> ()
	| `Chan ch ->
	    let send x = to_ch ch (Fd.render_color x) "" in
	    send (
	      F.x ">>> LOG START <time>" ["time", F.time time]
	    );
	    List.iter send (List.rev l)
	end
    | _ -> ()
    end
  in
  let reopen () =
    begin match !state with
    | `Chan ch -> close_out ch; open_log ()
    | _ -> ()
    end
  in
  begin match Sys.os_type with
  | "Unix" ->  (* Re-open log file on SIGUSR1 -- for logrotate *)
      Sys.set_signal Sys.sigusr1
	(Sys.Signal_handle (fun _ -> mutexify reopen ()));
  | _ -> ()
  end;
  mutexify proceed ()

let start = Srv.make ~name:"srv-log-start" ~before:[Srv.start] init

let close () =
  let time = Unix.gettimeofday () in
  begin match !state with
  | `Chan ch ->
      let send x = to_ch ch (Fd.render_color x) "" in
      let proceed () =
	send (
	  F.x ">>> LOG END <time>" ["time", F.time time]
	);
	close_out ch;
	state := `Buffer []
      in
      mutexify proceed ()
  | _ -> ()
  end

let stop = Srv.make ~name:"srv-log-stop" ~after:[Srv.stop] close

