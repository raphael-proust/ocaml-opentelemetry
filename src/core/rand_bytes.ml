open struct
  let rand = Array.init 8 (fun _ -> Random.State.make_self_init ())

  let mutex = Array.init 8 (fun _ -> Mutex.create ())

  let ( let@ ) = ( @@ )
end

(** What rand state do we use? *)
let[@inline] shard () : int = Thread.id (Thread.self ()) land 0b111

let default_rand_bytes_8 () : bytes =
  let shard = shard () in
  let@ () = Util_mutex.protect mutex.(shard) in
  let rand = rand.(shard) in

  let b = Bytes.create 8 in
  for i = 0 to 1 do
    (* rely on the stdlib's [Random] being thread-or-domain safe *)
    let r = Random.State.bits rand in
    (* 30 bits, of which we use 24 *)
    Bytes.set b (i * 3) (Char.chr (r land 0xff));
    Bytes.set b ((i * 3) + 1) (Char.chr ((r lsr 8) land 0xff));
    Bytes.set b ((i * 3) + 2) (Char.chr ((r lsr 16) land 0xff))
  done;
  let r = Random.State.bits rand in
  Bytes.set b 6 (Char.chr (r land 0xff));
  Bytes.set b 7 (Char.chr ((r lsr 8) land 0xff));
  b

let default_rand_bytes_16 () : bytes =
  let shard = shard () in
  let@ () = Util_mutex.protect mutex.(shard) in
  let rand = rand.(shard) in

  let b = Bytes.create 16 in
  for i = 0 to 4 do
    let r = Random.State.bits rand in
    (* 30 bits, of which we use 24 *)
    Bytes.set b (i * 3) (Char.chr (r land 0xff));
    Bytes.set b ((i * 3) + 1) (Char.chr ((r lsr 8) land 0xff));
    Bytes.set b ((i * 3) + 2) (Char.chr ((r lsr 16) land 0xff))
  done;
  let r = Random.State.bits rand in
  Bytes.set b 15 (Char.chr (r land 0xff));
  (* last byte *)
  b

let rand_bytes_16_ref = ref default_rand_bytes_16

let rand_bytes_8_ref = ref default_rand_bytes_8

(** Generate a 16B identifier *)
let[@inline] rand_bytes_16 () = !rand_bytes_16_ref ()

(** Generate an 8B identifier *)
let[@inline] rand_bytes_8 () = !rand_bytes_8_ref ()
