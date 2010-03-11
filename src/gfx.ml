
(*
 * Copyright (C) 2007-2010 The laby team
 * You have permission to copy, modify, and redistribute under the
 * terms of the GPL-3.0. For full license terms, see gpl-3.0.txt.
 *)

let log = Log.make ["gfx"]

let conf =
  Conf.void
    (F.x "graphic interface configuration" [])

let conf_tilesize =
  Conf.int ~p:(conf#plug "tile-size") ~d:40
    (F.x "size of tiles in pixels" [])

exception Error of F.t

type ressources =
    {
      size : int;
      void_p : GdkPixbuf.pixbuf;
      exit_p : GdkPixbuf.pixbuf;
      wall_p : GdkPixbuf.pixbuf;
      rock_p : GdkPixbuf.pixbuf;
      web_p : GdkPixbuf.pixbuf;
      nrock_p : GdkPixbuf.pixbuf;
      nweb_p : GdkPixbuf.pixbuf;
      ant_n_p : GdkPixbuf.pixbuf;
      ant_e_p : GdkPixbuf.pixbuf;
      ant_s_p : GdkPixbuf.pixbuf;
      ant_w_p : GdkPixbuf.pixbuf;
    }

type controls =
    {
      window: GWindow.window;
      button_prev: GButton.tool_button;
      button_next: GButton.tool_button;
      button_play: GButton.toggle_tool_button;
      button_backward: GButton.toggle_tool_button;
      button_forward: GButton.toggle_tool_button;
      button_execute: GButton.button;
      px: GMisc.image;
      interprets: GEdit.combo;
      levels: GEdit.combo;
      view_prog: GSourceView2.source_view;
      view_help: GSourceView2.source_view;
      box_help: GPack.box;
      view_mesg: GText.view;
      view_title: GMisc.label;
      view_comment: GMisc.label;
    }

let gtk_init () =
  GtkSignal.user_handler := Pervasives.raise;
  let _ = GtkMain.Main.init () in
  (* work around messed up gtk/lablgtk *)
  Sys.catch_break false;
  begin match Sys.os_type with
  | "Unix" ->
      Sys.set_signal Sys.sigpipe (Sys.Signal_default);
      Sys.set_signal Sys.sigquit (Sys.Signal_default);
  | _ -> ()
  end;
  Sys.set_signal Sys.sigterm (Sys.Signal_default);
  let tile_size = max 5 conf_tilesize#get in
  let pix p =
    let file = Res.get ["tiles"; p ^ ".svg"] in
    begin try
      GdkPixbuf.from_file_at_size file tile_size tile_size
    with
    | GdkPixbuf.GdkPixbufError(GdkPixbuf.ERROR_UNKNOWN_TYPE, _) ->
	let file = Res.get ["tiles"; p ^ ".png"] in
	GdkPixbuf.from_file_at_size file tile_size tile_size
    end
  in
  {
    size = tile_size;
    void_p = pix "void";
    exit_p = pix "exit";
    wall_p = pix "wall";
    rock_p = pix "rock";
    web_p = pix "web";
    nrock_p = pix "nrock";
    nweb_p = pix "nweb";
    ant_n_p = pix "ant-n";
    ant_e_p = pix "ant-e";
    ant_s_p = pix "ant-s";
    ant_w_p = pix "ant-w";
  }

let draw_state state ressources (pixmap : GDraw.pixmap) =
  let size = ressources.size in
  let tile i j p =
    pixmap#put_pixbuf
      ~x:(size / 2 + i * size) ~y:(size / 2 + j * size) p
  in
  let i0, j0 = State.pos state in
  let disp_tile i j t =
    begin match t with
    | `Void -> tile i j ressources.void_p
    | `Exit -> if i <> i0 || j <> j0 then tile i j ressources.exit_p
    | `Wall -> tile i j ressources.wall_p
    | `Rock -> tile i j ressources.rock_p
    | `Web -> tile i j ressources.web_p
    | `NRock -> tile i j ressources.nrock_p
    | `NWeb -> tile i j ressources.nweb_p
    end
  in
  State.iter_map state disp_tile;
  begin match State.dir state with
  | `N -> tile i0 j0 ressources.ant_n_p
  | `E -> tile i0 j0 ressources.ant_e_p
  | `S -> tile i0 j0 ressources.ant_s_p
  | `W -> tile i0 j0 ressources.ant_w_p
  end;
  begin match State.carry state with
  | `Rock -> tile i0 j0 ressources.rock_p
  | `None -> ()
  end

let labeled_combo text packing =
  let box = GPack.hbox ~packing () in
  let _ = GMisc.label ~text ~xpad:5 ~ypad:8 ~packing:box#pack () in
  GEdit.combo ~packing:box#add ()

let label packing =
  GMisc.label ~ypad:5 ~line_wrap:true ~packing ()

let label_txt text packing =
  ignore (GMisc.label ~text ~ypad:5 ~line_wrap:true ~packing ())

let label_language = F.x "Language:" []
let label_level = F.x "Level:" []
let label_prog = F.x "Program:" []
let label_mesg = F.x "Messages:" []
let label_help = F.x "Help:" []

let layout () =
  let scrolled ?(vpolicy=`ALWAYS) packing =
    GBin.scrolled_window ~packing ~hpolicy:`AUTOMATIC ~vpolicy ()
  in
  let monofont = Pango.Font.from_string "monospace" in
  let window = GWindow.window ~resizable:true () in
  let hpaned = GPack.paned `HORIZONTAL ~packing:window#add () in
  hpaned#set_position 620;
  let lvbox = GPack.vbox ~packing:hpaned#add1 () in
  let vpaned = GPack.paned `VERTICAL ~packing:hpaned#add () in
  vpaned#set_position 450;
  let view_title = label lvbox#pack in
  let view_comment = label lvbox#pack in
  let sw_laby = scrolled ~vpolicy:`AUTOMATIC lvbox#add in
  let box_help = GPack.vbox ~packing:lvbox#pack () in
  label_txt (Fd.render_raw label_help) box_help#pack;
  let sw_help = scrolled box_help#pack in
  let view_help =
    GSourceView2.source_view ~editable:false ~packing:sw_help#add ()
  in
  view_help#set_indent 1;
  view_help#misc#modify_font monofont;
  let rtvbox = GPack.vbox ~packing:vpaned#add1 () in
  let interprets = labeled_combo (Fd.render_raw label_language) rtvbox#pack in
  let levels = labeled_combo (Fd.render_raw label_level) rtvbox#pack in
  label_txt (Fd.render_raw label_prog) rtvbox#pack;
  let sw_prog = scrolled rtvbox#add in
  let view_prog =
    GSourceView2.source_view
      ~auto_indent:true ~indent_width:2 ~insert_spaces_instead_of_tabs:true
      ~show_line_numbers:true ~packing:sw_prog#add ()
  in
  view_prog#set_indent 1;
  view_prog#misc#modify_font monofont;
  let rbvbox = GPack.vbox ~packing:vpaned#add2 () in
  label_txt (Fd.render_raw label_mesg) rbvbox#pack;
  let sw_mesg = scrolled rbvbox#add in
  let view_mesg = GText.view ~editable:false ~packing:sw_mesg#add  () in
  view_mesg#misc#modify_font monofont;
  let px = GMisc.image ~packing:sw_laby#add_with_viewport () in
  let toolbar = GButton.toolbar ~packing:rbvbox#pack ~style:`BOTH () in
  let button stock = GButton.tool_button ~packing:toolbar#insert ~stock () in
  let tbutton stock =
    GButton.toggle_tool_button ~packing:toolbar#insert ~stock ()
  in
  let sti = GButton.separator_tool_item in
  let button_prev = button `GO_BACK in
  let button_next = button `GO_FORWARD in
  let _ = sti ~expand:true ~draw:false ~packing:toolbar#insert () in
  let button_backward = tbutton `MEDIA_REWIND in
  let button_play = tbutton `MEDIA_PLAY in
  let button_forward = tbutton `MEDIA_FORWARD in
  view_prog#misc#grab_focus ();
  let bbox = GPack.hbox ~packing:rtvbox#pack () in
  let button_execute = GButton.button ~packing:bbox#pack ~stock:`EXECUTE () in
  button_execute#set_focus_on_click false;
  {
    window = window;
    button_prev = button_prev; button_next = button_next;
    button_play = button_play;
    button_backward = button_backward;
    button_forward = button_forward;
    button_execute = button_execute;
    px = px;
    interprets = interprets; levels = levels;
    view_prog = view_prog; view_mesg = view_mesg;
    box_help = box_help; view_help = view_help;
    view_title = view_title; view_comment = view_comment;
  }

let make_pixmap tile_size level =
  let sizex, sizey = Level.size level in
  let width, height = tile_size * (1 + sizex), tile_size * (1 + sizey) in
  GDraw.pixmap ~width ~height ()

let display_gtk () =
  let amods = Mod.pool () in
  let mods = List.filter (fun x -> x#check) amods in
  let language_list =
    List.sort (compare) (List.map (fun x -> x#name) mods)
  in
  if mods = [] then
    Run.fatal (
      F.x "no mod is available among: <list>" [
	"list", F.v (List.map (fun x -> F.string x#name) amods);
      ]
    );
  let lmod = ref (List.hd mods) in
  let sel_mod m = lmod := List.find (fun x -> x#name = m) mods in
  let levels_list =
    List.sort (compare) (Res.get_list ~ext:"laby" ["levels"])
  in
  let level = ref Level.dummy in
  let bg = ref `WHITE in
  begin try
    let ressources = gtk_init () in
    let c = layout () in
    let pixmap = ref (GDraw.pixmap ~width:1 ~height:1 ()) in
    let mesg m =
      c.view_mesg#buffer#place_cursor c.view_mesg#buffer#end_iter;
      c.view_mesg#buffer#insert (Fd.render_raw m ^ "\n")
    in
    let step state =
      begin match !lmod#probe c.view_mesg#buffer#insert with
      | None -> None
      | Some (action, reply) ->
	  let answer, newstate = State.run action state in
	  reply answer;
	  Some newstate
      end
    in
    let trace_init () = Trace.init (Level.generate !level) step in
    let trace = ref (trace_init ()) in
    let help_update () =
      begin match Level.help !level with
      | "" ->
	  c.box_help#misc#hide ()
      | help ->
	  c.view_help#buffer#set_text (!lmod#help help);
	  c.box_help#misc#show ()
      end
    in
    let show_execute () = c.button_execute#set_relief `NORMAL in
    let hide_execute () = c.button_execute#set_relief `NONE in
    let ctrl_sensitive b =
      c.button_backward#misc#set_sensitive b;
      c.button_forward#misc#set_sensitive b;
      c.button_play#misc#set_sensitive b;
      c.button_prev#misc#set_sensitive b;
      c.button_next#misc#set_sensitive b;
    in
    let update () =
      !pixmap#set_foreground !bg;
      let width, height = !pixmap#size in
      !pixmap#rectangle ~x:0 ~y:0 ~width ~height ~filled:true ();
      draw_state (Trace.current !trace) ressources !pixmap;
      c.px#set_pixmap !pixmap
    in
    let effects () =
      let action = State.action (Trace.current !trace) in
      Say.action mesg action; Sound.action action
    in
    let lmod_stop () =
      !lmod#stop;
      c.view_mesg#buffer#set_text "";
      ctrl_sensitive false;
      trace := trace_init ();
      update ();
      show_execute ()
    in
    let lmod_start () =
      !lmod#set_buf (c.view_prog#buffer#get_text ());
      begin match !lmod#start c.view_mesg#buffer#insert with
      | true ->
	  mesg (F.h [F.s "——"; Say.good_start; F.s "——"]);
	  ctrl_sensitive true
      | false ->
	  mesg (F.h [F.s "——"; Say.bad_start; F.s "——"]);
	  ctrl_sensitive false
      end
    in
    let lmod_save () =
      lmod_stop ();
      !lmod#set_buf (c.view_prog#buffer#get_text ())
    in
    let lmod_load () =
      sel_mod c.interprets#entry#text;
      c.view_prog#buffer#set_text !lmod#get_buf;
      let syntaxd = Res.get ["syntax"] in
      let m = GSourceView2.source_language_manager false in
      m#set_search_path (syntaxd :: m#search_path);
      let name = !lmod#name in
      begin match m#language name with
      | None ->
	  log#warning (
	    F.x "cannot load syntax for <name> mod" [
	      "name", F.string name;
	    ]
	  );
      | Some l ->
	  c.view_prog#source_buffer#set_language (Some l);
	  c.view_help#source_buffer#set_language (Some l);
      end;
      help_update ()
    in
    let newmod () =
      let name = c.interprets#entry#text in
      begin match List.mem name language_list with
      | true -> lmod_save (); lmod_load ()
      | false -> ()
      end
    in
    let play_inactive () =
      c.button_forward#set_active false;
      c.button_backward#set_active false;
      c.button_play#set_active false
    in
    let execute () =
      play_inactive ();
      lmod_stop ();
      lmod_start ();
      hide_execute ();
    in
    let newlevel () =
      let name = c.levels#entry#text in
      begin match List.mem name levels_list with
      | true ->
	  level := Level.load (Res.get ["levels"; name]);
	  pixmap := make_pixmap ressources.size !level;
	  c.view_title#set_text (Level.title !level);
	  c.view_comment#set_text (Level.comment !level);
	  help_update ();
	  play_inactive ();
	  lmod_stop ();
      | false -> ()
      end
    in
    let prev () =
      begin match Trace.prev !trace with
      | `None -> play_inactive ()
      | `Old t -> trace := t; update ()
      end
    in
    let next () =
      begin match Trace.next !trace with
      | `None -> play_inactive ()
      | `New t -> trace := t; update (); effects ()
      | `Old t -> trace := t; update ()
      end
    in
    let play =
      let rid = ref None in
      begin fun direction speed () ->
	begin match !rid with
	| None ->
	    let callback () =
	      begin match direction with
	      |	`Forward -> next (); true
	      | `Backward -> prev (); true
	      end
	    in
	    rid := Some (GMain.Timeout.add ~ms:speed ~callback);
	| Some id ->
	    play_inactive ();
	    GMain.Timeout.remove id; rid := None
	end
      end
    in
    let destroy () =
      lmod_save ();
      c.window#destroy ();
      GMain.Main.quit ()
    in
    let altdestroy _ = destroy (); true in
    c.interprets#set_popdown_strings language_list;
    if List.mem "ocaml" language_list
    then c.interprets#entry#set_text "ocaml";
    c.levels#set_popdown_strings levels_list;
    if List.mem "0.laby" levels_list
    then c.levels#entry#set_text "0.laby";
    (* declaring callbacks *)
    ignore (c.window#event#connect#delete ~callback:altdestroy);
    ignore (c.window#connect#destroy ~callback:destroy);
    ignore (c.button_prev#connect#clicked ~callback:prev);
    ignore (c.button_next#connect#clicked ~callback:next);
    ignore (c.button_play#connect#toggled ~callback:(play `Forward 500));
    ignore (c.button_backward#connect#toggled ~callback:(play `Backward 100));
    ignore (c.button_forward#connect#toggled ~callback:(play `Forward 100));
    ignore (c.button_execute#connect#clicked ~callback:execute);
    ignore (c.interprets#entry#connect#changed ~callback:newmod);
    ignore (c.levels#entry#connect#changed ~callback:newlevel);
    ignore (c.view_prog#buffer#connect#changed ~callback:show_execute);
    (* now we must have everything up *)
    lmod_load ();
    newlevel ();
    c.window#set_default_size 1000 750;
    c.window#show ();
    (* bg color has to be retrieved after c.window#show *)
    bg := `COLOR (c.px#misc#style#light `NORMAL);
    update ();
    ignore (GMain.Main.main ())
  with
  | Gtk.Error m ->
      raise (
	Error (
	  F.x "gtk error: <error>" ["error", F.q (F.string m)]
	)
      )
  end
