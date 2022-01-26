type shutdown_command = [ `Receive | `Send | `All ]

type read_method = ..
type read_method += Read_source_buffer of ((Cstruct.t list -> unit) -> unit)

class type close = object
  method close : unit
end

let close (t : #close) = t#close

class virtual read = object
  method virtual read_methods : read_method list
  method virtual read_into : Cstruct.t -> int
end

let read_into (t : #read) buf =
  let got = t#read_into buf in
  assert (got > 0 && got <= Cstruct.length buf);
  got

let read_methods (t : #read) = t#read_methods

class virtual source = object (_ : #Generic.t)
  method probe _ = None
  inherit read
end

let cstruct_source data : source =
  object (self)
    val mutable data = data

    inherit source

    method private read_source_buffer fn =
      let rec aux () =
        match data with
        | [] -> raise End_of_file
        | x :: xs when Cstruct.length x = 0 -> data <- xs; aux ()
        | xs -> data <- []; fn xs
      in
      aux ()

    method read_methods =
      [ Read_source_buffer self#read_source_buffer ]

    method read_into dst =
      let avail, src = Cstruct.fillv ~dst ~src:data in
      if avail = 0 then raise End_of_file;
      data <- src;
      avail
  end

let string_source s = cstruct_source [Cstruct.of_string s]

class virtual write = object
  method virtual write : 'a. (#source as 'a) -> unit
end

let copy (src : #source) (dst : #write) = dst#write src

let copy_string s = copy (string_source s)

class virtual sink = object (_ : #Generic.t)
  method probe _ = None
  inherit write
end

let buffer_sink b =
  object
    inherit sink

    method write src =
      let buf = Cstruct.create 4096 in
      try
        while true do
          let got = src#read_into buf in
          Buffer.add_string b (Cstruct.to_string ~len:got buf)
        done
      with End_of_file -> ()
  end

class virtual two_way = object (_ : #Generic.t)
  method probe _ = None
  inherit read
  inherit write

  method virtual shutdown : shutdown_command -> unit
end

let shutdown (t : #two_way) = t#shutdown
