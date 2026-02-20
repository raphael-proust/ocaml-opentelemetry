type 'a t = {
  kind: string;
  name: string;
  emit: clock:Clock.t -> unit -> Metrics.t list;
  update: 'a -> unit;
}

let all : (clock:Clock.t -> unit -> Metrics.t list) Alist.t = Alist.make ()

let register (instr : 'a t) : unit = Alist.add all instr.emit

module Internal = struct
  let iter_all f = Alist.get all |> List.iter f
end

let float_add (a : float Atomic.t) (delta : float) : unit =
  while
    let cur = Atomic.get a in
    not (Atomic.compare_and_set a cur (cur +. delta))
  do
    ()
  done

module type CUSTOM_IMPL = sig
  type data

  type state

  val kind : string

  val init : unit -> state

  val update : state -> data -> unit

  val to_metrics :
    state ->
    name:string ->
    ?description:string ->
    ?unit_:string ->
    clock:Clock.t ->
    unit ->
    Metrics.t list
end

module Make (I : CUSTOM_IMPL) = struct
  let create ~name ?description ?unit_ () : I.data t =
    let state = I.init () in
    let emit ~clock () =
      I.to_metrics state ~name ?description ?unit_ ~clock ()
    in
    let instrument =
      { kind = I.kind; name; emit; update = I.update state } [@warning "-45"]
    in
    register instrument;
    instrument
end

module Int_counter = struct
  include Make (struct
    type data = int

    type state = int Atomic.t

    let kind = "counter"

    let init () = Atomic.make 0

    let update state delta = ignore (Atomic.fetch_and_add state delta : int)

    let to_metrics state ~name ?description ?unit_ ~clock () =
      let now = Clock.now clock in
      [
        Metrics.sum ~name ?description ?unit_ ~is_monotonic:true
          [ Metrics.int ~now (Atomic.get state) ];
      ]
  end)

  let add (instrument : int t) delta = instrument.update delta
end

module Float_counter = struct
  include Make (struct
    type data = float

    type state = float Atomic.t

    let kind = "counter"

    let init () = Atomic.make 0.

    let update state delta = float_add state delta

    let to_metrics state ~name ?description ?unit_ ~clock () =
      let now = Clock.now clock in
      [
        Metrics.sum ~name ?description ?unit_ ~is_monotonic:true
          [ Metrics.float ~now (Atomic.get state) ];
      ]
  end)

  let add (instrument : float t) delta = instrument.update delta
end

module Int_gauge = struct
  include Make (struct
    type data = int

    type state = int Atomic.t

    let kind = "gauge"

    let init () = Atomic.make 0

    let update state v = Atomic.set state v

    let to_metrics state ~name ?description ?unit_ ~clock () =
      let now = Clock.now clock in
      [
        Metrics.gauge ~name ?description ?unit_
          [ Metrics.int ~now (Atomic.get state) ];
      ]
  end)

  let record (instrument : int t) v = instrument.update v
end

module Float_gauge = struct
  include Make (struct
    type data = float

    type state = float Atomic.t

    let kind = "gauge"

    let init () = Atomic.make 0.

    let update state v = Atomic.set state v

    let to_metrics state ~name ?description ?unit_ ~clock () =
      let now = Clock.now clock in
      [
        Metrics.gauge ~name ?description ?unit_
          [ Metrics.float ~now (Atomic.get state) ];
      ]
  end)

  let record (instrument : float t) v = instrument.update v
end

module Histogram = struct
  let default_bounds =
    [
      0.005;
      0.01;
      0.025;
      0.05;
      0.075;
      0.1;
      0.25;
      0.5;
      0.75;
      1.;
      2.5;
      5.;
      7.5;
      10.;
    ]

  (* Find the index of the first bucket whose upper bound >= v.
     Returns Array.length bounds if v exceeds all bounds (overflow bucket). *)
  let find_bucket (bounds : float array) (v : float) : int =
    let n = Array.length bounds in
    let lo = ref 0 and hi = ref (n - 1) in
    while !lo < !hi do
      let mid = (!lo + !hi) / 2 in
      if bounds.(mid) < v then
        lo := mid + 1
      else
        hi := mid
    done;
    if !lo < n && v <= bounds.(!lo) then
      !lo
    else
      n

  let create ~name ?description ?unit_ ?(bounds = default_bounds) () : float t =
    let bounds_arr = Array.of_list bounds in
    let n_buckets = Array.length bounds_arr + 1 in
    let bucket_counts = Array.init n_buckets (fun _ -> Atomic.make 0) in
    let sum = Atomic.make 0. in
    let count = Atomic.make 0 in
    let update v =
      let bucket = find_bucket bounds_arr v in
      ignore (Atomic.fetch_and_add bucket_counts.(bucket) 1 : int);
      float_add sum v;
      ignore (Atomic.fetch_and_add count 1 : int)
    in
    let emit ~clock () =
      let now = Clock.now clock in
      let count_v = Int64.of_int (Atomic.get count) in
      let sum_v = Atomic.get sum in
      let bc =
        Array.to_list
          (Array.map (fun a -> Int64.of_int (Atomic.get a)) bucket_counts)
      in
      [
        Metrics.histogram ~name ?description ?unit_
          [
            Metrics.histogram_data_point ~now ~count:count_v ~sum:sum_v
              ~bucket_counts:bc ~explicit_bounds:bounds ();
          ];
      ]
    in
    let instrument =
      { kind = "histogram"; name; emit; update } [@warning "-45"]
    in
    register instrument;
    instrument

  let record (instrument : float t) v = instrument.update v
end
