defmodule Otzel.CollaborationTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # Ecto-free multiplayer OT convergence tests.
  #
  # These exercise the canonical collaborative-editing algorithm end to end,
  # against a plain in-memory (ETS) event log — no database, no persistence
  # framework. The client state machines and the server (materialize/1) do
  # exactly what the "collaborative document" checklists describe: clients edit
  # against their current view and submit {diff, based_on}; the server transforms
  # each submission over the official work that preceded it, composes it onto the
  # running document, and stores the EFFECTIVE delta so later roll-ups chain.
  #
  # Two experiments:
  #   * synchronous  — a client flushes and re-materializes atomically.
  #   * asynchronous — a client keeps editing while its reply is in flight, then
  #     rebases its residual onto the server document in place.

  # ── the store: an append-only event log in ETS ─────────────────────────────
  # An event is %{id, diff, based_on}. `id` is a monotonically increasing integer
  # that doubles as the ordering key. `diff` is the canonical ops form (JSON-ish
  # maps); `based_on` is the id the submitting client based its edit on.
  defp new_log, do: :ets.new(:events, [:ordered_set, :public])

  defp append(log, diff, based_on) do
    id = :ets.info(log, :size)
    true = :ets.insert(log, {id, %{id: id, diff: diff, based_on: based_on}})
    id
  end

  defp all_events(log) do
    log
    |> :ets.tab2list()
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  # ── the server: materialize the document from the event log ────────────────
  # Fold the events. For each, roll up the EFFECTIVE deltas of every event after
  # its `based_on` into one official delta, transform the submission over it, and
  # compose onto the running document. Accumulate the effective delta (submission
  # already transformed) so the rollup composes cleanly — raw submissions share a
  # base and do NOT chain-compose.
  defp materialize(events), do: materialize_prefix(events, :all)

  # Materialize only the events up to and including `upto_id` (or :all).
  defp materialize_prefix(events, upto_id) do
    events = take_upto(events, upto_id)

    {content, _history} =
      Enum.reduce(events, {Otzel.quill_init(), []}, fn event, {current, history} ->
        submitted = ensure_delta(event.diff)
        official = official_delta(history, event.based_on)

        incoming =
          case official do
            [] -> submitted
            _ -> Otzel.transform(official, submitted)
          end

        composed = Otzel.compose(current, incoming)
        {composed, history ++ [{event.id, incoming}]}
      end)

    content
  end

  defp take_upto(events, :all), do: events

  defp take_upto(events, id) do
    case Enum.find_index(events, &(&1.id == id)) do
      nil -> events
      idx -> Enum.take(events, idx + 1)
    end
  end

  # The single composed delta of every (effective) event after `based_on`.
  defp official_delta(history, based_on) do
    {_base, official} = partitioned_rollup(history, based_on)
    official
  end

  # Split an ordered [{id, delta}] history at `based_on`, rolling up each side.
  # Returns {base_doc_delta, official_delta}; a nil/unknown based_on makes the
  # whole history official.
  defp partitioned_rollup(history, based_on) do
    {base, tail} = split_at_id(history, based_on)
    {compose_all(base), compose_all(tail)}
  end

  defp split_at_id(history, nil), do: {[], Enum.map(history, &elem(&1, 1))}

  defp split_at_id(history, based_on) do
    case Enum.find_index(history, fn {id, _} -> id == based_on end) do
      nil -> {[], Enum.map(history, &elem(&1, 1))}
      idx ->
        {before_incl, tail} = Enum.split(history, idx + 1)
        {Enum.map(before_incl, &elem(&1, 1)), Enum.map(tail, &elem(&1, 1))}
    end
  end

  defp compose_all([]), do: []
  defp compose_all(deltas), do: Otzel.compose_all(deltas)

  # Canonical ops form of a delta — for storage and structural comparison.
  # Round-tripping through encode! normalizes memoized content and compacts ops.
  defp to_ops(delta) do
    delta
    |> Otzel.encode!()
    |> JSON.decode!()
    |> Map.fetch!("ops")
  end

  defp ensure_delta([]), do: []
  defp ensure_delta([op | _] = delta) when is_struct(op), do: delta
  defp ensure_delta(delta) when is_list(delta), do: Otzel.from_json(delta)

  # ── document / text helpers ────────────────────────────────────────────────
  defp doc(""), do: Otzel.quill_init()
  defp doc(text), do: [Otzel.insert(ensure_newline(text))]

  defp ensure_newline(text) do
    if String.ends_with?(text, "\n"), do: text, else: text <> "\n"
  end

  # ── generators (shared by both experiments) ────────────────────────────────
  defp edit_gen do
    gen all op <- StreamData.member_of([:insert, :insert, :insert, :delete]),
            pos <- pos_gen(),
            char <- StreamData.member_of(~w(a b c d e f g h X Y Z . , " ") ++ ["\n"]) do
      {op, pos, char}
    end
  end

  # Bias positions toward a small "hot" range so concurrent edits from different
  # clients frequently land at the SAME index on the same base — the interleaving
  # most likely to expose rollup/transform-priority bugs. A spread tail still
  # exercises the general case.
  defp pos_gen do
    StreamData.frequency([
      {5, StreamData.integer(0..3)},
      {1, StreamData.integer(0..200)}
    ])
  end

  # ══════════════════════════════════════════════════════════════════════════
  # Experiment 1 — synchronous collaboration
  # ══════════════════════════════════════════════════════════════════════════

  defmodule SyncClient do
    @moduledoc false
    # based_on - event id `server` is anchored to; server - materialized doc as
    # of based_on; pending - composed local edits not yet flushed.
    defstruct [:log, :based_on, :server, pending: []]
  end

  # Current visible document: server ∘ pending.
  defp sync_view(%SyncClient{server: s, pending: []}), do: s
  defp sync_view(%SyncClient{server: s, pending: p}), do: Otzel.compose(s, p)

  defp sync_apply_delta(%SyncClient{} = c, edit) do
    current = sync_view(c)
    mutated = mutate_text(Otzel.to_string(current), edit)
    diff = Otzel.diff(current, doc(mutated))
    pending = if c.pending == [], do: diff, else: Otzel.compose(c.pending, diff)
    %{c | pending: pending}
  end

  # Flush pending to the log, then re-materialize from a fresh replay.
  defp sync_flush(%SyncClient{pending: []} = c), do: sync_refresh(c)

  defp sync_flush(%SyncClient{} = c) do
    append(c.log, to_ops(c.pending), c.based_on)
    sync_refresh(%{c | pending: []})
  end

  defp sync_refresh(%SyncClient{log: log} = c) do
    events = all_events(log)
    head = List.last(events)
    %{c | based_on: head.id, server: materialize(events)}
  end

  # Text-only mutation (no attribution) for the synchronous experiment.
  defp mutate_text(text, {:insert, pos, char}) do
    body = String.trim_trailing(text, "\n")
    i = rem(pos, String.length(body) + 1)
    {a, b} = String.split_at(body, i)
    ensure_newline(a <> char <> b)
  end

  defp mutate_text(text, {:delete, pos, _char}) do
    body = String.trim_trailing(text, "\n")

    if body == "" do
      ensure_newline("")
    else
      i = rem(pos, String.length(body))
      {a, b} = String.split_at(body, i)
      ensure_newline(a <> String.slice(b, 1..-1//1))
    end
  end

  defp sync_token_gen(n_clients) do
    gen all client <- StreamData.integer(0..(n_clients - 1)),
            action <-
              StreamData.frequency([
                {3, StreamData.bind(edit_gen(), &StreamData.constant({:delta, &1}))},
                {1, StreamData.constant({:sync, nil})}
              ]) do
      {client, action}
    end
  end

  property "synchronous: N clients converge under interleaved deltas and syncs" do
    check all n_clients <- StreamData.integer(2..4),
              n_ops <- StreamData.integer(100..200),
              tokens <- StreamData.list_of(sync_token_gen(n_clients), length: n_ops),
              max_runs: 25 do
      log = new_log()

      # Seed with a diff ONTO quill_init (not a raw document) so the stored
      # content is exactly "start\n"; a raw document would compose onto the
      # quill_init newline and double it.
      append(log, to_ops(Otzel.diff(Otzel.quill_init(), doc("start\n"))), nil)
      [seed] = all_events(log)
      server = materialize(all_events(log))

      base = %SyncClient{log: log, based_on: seed.id, server: server, pending: []}
      clients = List.duplicate(base, n_clients) |> List.to_tuple()

      clients =
        Enum.reduce(tokens, clients, fn {i, {kind, arg}}, acc ->
          c = elem(acc, i)

          updated =
            case kind do
              :delta -> sync_apply_delta(c, arg)
              :sync -> sync_flush(c)
            end

          put_elem(acc, i, updated)
        end)

      # Cap off: everyone flushes remaining pending in order, then refreshes.
      clients =
        clients
        |> Tuple.to_list()
        |> Enum.map(&sync_flush/1)
        |> Enum.map(&sync_refresh/1)

      replayed = Otzel.to_string(materialize(all_events(log)))

      for c <- clients do
        assert Otzel.to_string(sync_view(c)) == replayed
      end
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # Experiment 2 — asynchronous collaboration (delayed reply)
  # ══════════════════════════════════════════════════════════════════════════

  defmodule AsyncClient do
    @moduledoc false
    # sent - delta submitted, awaiting ack (nil => no reply in flight);
    # sync_event_id - id of this client's own committed event; fire_at - global
    # step the stashed reply is delivered; index - tags this client's inserts so
    # the oracle can compare op structure, not just text.
    defstruct [:log, :based_on, :server, :sent, :sync_event_id, :fire_at, :index, pending: []]
  end

  defp in_flight?(%AsyncClient{sent: nil}), do: false
  defp in_flight?(%AsyncClient{}), do: true

  # Visible document: server ∘ (sent ∘ extra). `sent` is nil off-flight.
  defp async_view(%AsyncClient{server: s, sent: nil, pending: []}), do: s
  defp async_view(%AsyncClient{server: s, sent: nil, pending: p}), do: Otzel.compose(s, p)

  defp async_view(%AsyncClient{server: s, sent: sent, pending: p}),
    do: Otzel.compose(s, Otzel.compose(sent, p))

  # A local edit folds into `pending`, anchored on the current (flight-aware)
  # view. The edit carries the client's index as an attribute on inserted content
  # so authorship survives compose/transform/replay.
  defp async_apply_delta(%AsyncClient{} = c, edit) do
    current = async_view(c)
    diff = edit_delta(current, edit, c.index)
    pending = if c.pending == [], do: diff, else: Otzel.compose(c.pending, diff)
    %{c | pending: pending}
  end

  # Build an edit as diff(doc, target_doc), where target_doc is the mutated
  # DOCUMENT with the inserted char as an attributed insert op. Diffing two real
  # documents yields a clean, compose-safe delta while %{"c" => index} marks the
  # inserting client. Edits stay inside the body (the trailing "\n" is preserved).
  defp edit_delta(document, edit, index) do
    Otzel.diff(document, target_doc(document, edit, index))
  end

  defp target_doc(document, {:insert, pos, char}, index) do
    {before, rest} = split_body(document, pos, +1)
    [Otzel.insert(before), Otzel.insert(char, %{"c" => index}), Otzel.insert(rest <> "\n")]
  end

  defp target_doc(document, {:delete, pos, _char}, _index) do
    body = String.trim_trailing(Otzel.to_string(document), "\n")

    if body == "" do
      document
    else
      at = rem(pos, String.length(body))
      {before, rest} = String.split_at(body, at)
      [Otzel.insert(before <> String.slice(rest, 1..-1//1) <> "\n")]
    end
  end

  defp split_body(document, pos, offset) do
    body = String.trim_trailing(Otzel.to_string(document), "\n")
    at = rem(pos, String.length(body) + offset)
    String.split_at(body, at)
  end

  # A delta has no net effect only if every op is a plain (attribute-free) retain.
  # An insert, delete, OR a retain carrying attrs (a formatting change) is a real
  # effect that must be flushed and stored.
  defp empty_effect?(delta) do
    Enum.all?(delta, &match?(%Otzel.Op.Retain{attrs: nil}, &1))
  end

  # Process a {:sync, n} at global `step`. Writes the event now; stashes the reply.
  defp send_sync(%AsyncClient{} = c, n, step) do
    c = if in_flight?(c), do: deliver_reply(c), else: c

    # A delta whose net effect is empty must not be submitted — treat as refresh.
    case empty_effect?(c.pending) && [] || c.pending do
      [] ->
        async_refresh(c)

      to_send ->
        sync_event_id = append(c.log, to_ops(to_send), c.based_on)
        stashed = %{c | sent: to_send, pending: [], sync_event_id: sync_event_id}
        # n == 0 (incl. cap-off) delivers immediately; fire_at only matters when deferred.
        if n == 0, do: deliver_reply(stashed), else: %{stashed | fire_at: step + n}
    end
  end

  # Deliver a stashed reply: adopt the server document as of the client's own sync
  # event and rebase the residual onto it in place. No new event is written.
  # `extra` was authored against V = server ∘ sent; both V and new_server are real
  # documents, so the exact rebase bridge is diff(V, new_server).
  defp deliver_reply(%AsyncClient{} = c) do
    new_server = materialize_prefix(all_events(c.log), c.sync_event_id)

    extra_prime =
      case c.pending do
        [] -> []
        extra ->
          v = Otzel.compose(c.server, c.sent)
          Otzel.transform(Otzel.diff(v, new_server), extra)
      end

    %{
      c
      | server: new_server,
        based_on: c.sync_event_id,
        pending: extra_prime,
        sent: nil,
        sync_event_id: nil,
        fire_at: nil
    }
  end

  defp async_refresh(%AsyncClient{log: log} = c) do
    events = all_events(log)
    head = List.last(events)
    %{c | based_on: head.id, server: materialize(events), sent: nil, sync_event_id: nil, fire_at: nil}
  end

  # Deliver every client whose reply is due at `step` (ascending index order).
  defp deliver_due(clients, step) do
    clients
    |> Tuple.to_list()
    |> Enum.map(fn c ->
      if in_flight?(c) and c.fire_at <= step, do: deliver_reply(c), else: c
    end)
    |> List.to_tuple()
  end

  # Delay in global op-steps; n=0 heavily weighted (synchronous), plus small delays.
  defp delay_gen do
    StreamData.frequency([
      {3, StreamData.constant(0)},
      {4, StreamData.integer(1..8)}
    ])
  end

  defp async_token_gen(n_clients) do
    gen all client <- StreamData.integer(0..(n_clients - 1)),
            action <-
              StreamData.frequency([
                {3, StreamData.bind(edit_gen(), &StreamData.constant({:delta, &1}))},
                {1, StreamData.bind(delay_gen(), &StreamData.constant({:sync, &1}))}
              ]) do
      {client, action}
    end
  end

  property "asynchronous: N clients converge under delayed-reply deltas and syncs" do
    check all n_clients <- StreamData.integer(2..4),
              n_ops <- StreamData.integer(100..200),
              tokens <- StreamData.list_of(async_token_gen(n_clients), length: n_ops),
              max_runs: 25 do
      log = new_log()

      append(log, to_ops(Otzel.diff(Otzel.quill_init(), doc("start\n"))), nil)
      [seed] = all_events(log)
      server = materialize(all_events(log))

      clients =
        for index <- 0..(n_clients - 1) do
          %AsyncClient{log: log, based_on: seed.id, server: server, index: index, pending: []}
        end
        |> List.to_tuple()

      # One tick per token; deliver due replies after each token's effect.
      clients =
        tokens
        |> Enum.with_index(1)
        |> Enum.reduce(clients, fn {{i, {kind, arg}}, step}, acc ->
          c = elem(acc, i)

          updated =
            case kind do
              :delta -> async_apply_delta(c, arg)
              :sync -> send_sync(c, arg, step)
            end

          acc
          |> put_elem(i, updated)
          |> deliver_due(step)
        end)

      # Cap off: drain in-flight replies, flush pending synchronously, refresh.
      clients =
        clients
        |> Tuple.to_list()
        |> Enum.map(fn c -> if in_flight?(c), do: deliver_reply(c), else: c end)
        |> Enum.map(fn c -> send_sync(c, 0, :cap) end)
        |> Enum.map(&async_refresh/1)

      replayed_doc = materialize(all_events(log))
      replayed_ops = to_ops(replayed_doc)
      replayed_text = Otzel.to_string(replayed_doc)

      # Strengthened oracle: every client converges to the replay in text AND in
      # op STRUCTURE (attributed inserts included). Structural equality catches OT
      # bugs — wrong tie-break priority, lost authorship, a diff-shortcut landing
      # on the same text — that plain text equality would silently pass.
      for c <- clients do
        view = async_view(c)
        assert Otzel.to_string(view) == replayed_text

        assert to_ops(view) == replayed_ops,
               "client #{c.index} view structurally diverges from the replay"
      end
    end
  end
end
