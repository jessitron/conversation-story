# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "yaml"
require "tempfile"
require "conversation_story/parser"
require "conversation_story/renderer"
require_relative "story_events"

# Golden-fixture tests: run the parser against every real example log and assert
# the one-event-per-record contract holds — no data lost, required fields, YAML
# round-trips, and the renderer emits exactly one card per event.
class ParserTest < Minitest::Test
  include StoryEvents

  EXAMPLES = Dir.glob(File.expand_path("../examples/*.jsonl", __dir__)).sort

  # `last-prompt` is the one record type we knowingly route to the `unknown`
  # fallback for now (it proves the fallback path renders real data). Any OTHER
  # type showing up as unknown is a regression the test should catch.
  EXPECTED_UNKNOWN_TYPES = ["last-prompt"].freeze

  def test_examples_exist
    refute_empty EXAMPLES, "no example logs found under examples/*.jsonl"
  end

  EXAMPLES.each do |log|
    name = File.basename(log, ".jsonl")

    define_method("test_#{name}_one_event_per_line") do
      doc = ConversationStory::Parser.new(log).to_document
      line_count = File.readlines(log).count { |l| !l.strip.empty? }

      assert_equal line_count, doc["events"].size,
                   "expected one event per non-blank line"
      assert_equal line_count, doc["meta"]["event_count"],
                   "meta.event_count should match"
    end

    define_method("test_#{name}_every_event_has_provenance_and_agent") do
      doc = ConversationStory::Parser.new(log).to_document
      doc["events"].each do |e|
        refute_nil e["agent"], "event #{e["id"]} missing agent"
        assert e.dig("source", "file"), "event #{e["id"]} missing source.file"
        assert_kind_of Integer, e.dig("source", "line"),
                       "event #{e["id"]} missing integer source.line"
        assert_operator e.dig("source", "line"), :>, 0
      end
    end

    define_method("test_#{name}_every_event_has_a_ref_handle") do
      doc = ConversationStory::Parser.new(log).to_document
      doc["events"].each do |e|
        assert_equal "#{name}:#{e.dig("source", "line")}", e["ref"],
                     "event #{e["id"]} ref should be <name>:<line>"
      end
      # refs are unique (one event per line), so they're safe to cite
      refs = doc["events"].map { |e| e["ref"] }
      assert_equal refs.uniq.size, refs.size, "event refs must be unique"
    end

    define_method("test_#{name}_renders_copyable_event_id") do
      doc  = ConversationStory::Parser.new(log).to_document
      html = ConversationStory::Renderer.new(doc).to_html
      visible = visible_cards(doc)
      assert_equal visible.size, html.scan(/class="copy-ref"/).size,
                   "expected one copy-ref chip per visible event"
      assert_includes html, %(data-copy="#{visible.first["ref"]}"),
                       "first visible event's ref should be copyable"
    end

    define_method("test_#{name}_assistant_turns_carry_named_tokens") do
      doc = ConversationStory::Parser.new(log).to_document
      assistants = doc["events"].select { |e| e["kind"] == "assistant_message" }
      refute_empty assistants, "expected some assistant_message events"
      assistants.each do |e|
        assert e["tokens"], "assistant event #{e["id"]} missing tokens"
        assert_kind_of Integer, e.dig("tokens", "input")
        assert_kind_of Integer, e.dig("tokens", "output")
      end
    end

    define_method("test_#{name}_only_expected_unknowns") do
      doc = ConversationStory::Parser.new(log).to_document
      unknown_types = doc["events"]
                      .select { |e| e["kind"] == "unknown" }
                      .map { |e| e.dig("detail", "raw", "type") }
                      .uniq.sort
      assert_equal EXPECTED_UNKNOWN_TYPES.sort, unknown_types,
                   "unexpected record types fell back to `unknown`"
    end

    define_method("test_#{name}_meta_is_populated") do
      meta = ConversationStory::Parser.new(log).to_document["meta"]
      %w[source name session_id git_branch started_at ended_at].each do |k|
        refute_nil meta[k], "meta.#{k} should be present"
      end
      assert_equal "UTC", meta["timezone"]
      assert_equal "main", meta["agents"].first["id"]
    end

    define_method("test_#{name}_yaml_round_trips_safely") do
      doc = ConversationStory::Parser.new(log).to_document
      reloaded = YAML.safe_load(YAML.dump(doc))
      assert_equal doc, reloaded, "story.yaml must round-trip under safe_load"
    end

    define_method("test_#{name}_renders_one_card_per_visible_event") do
      doc  = ConversationStory::Parser.new(log).to_document
      html = ConversationStory::Renderer.new(doc).to_html
      # Nested subagent stories get cards too (inside a .subactions block), so
      # "every visible event" means walking the tree, not the top-level list.
      visible = visible_cards(doc)

      # Hidden (harness-bookkeeping) events are parsed but not rendered, so the
      # page shows one card per VISIBLE event.
      assert_operator doc["events"].reject { |e| e["hidden"] }.size, :<, doc["events"].size,
                      "expected some events to be hidden"
      assert_equal visible.size, html.scan(/class="card /).size,
                   "expected one card per visible event"
      # Each card is anchored by its ref (`<example>:<line>`), so a ref Jess
      # quotes pastes straight into the URL fragment. Check every visible one.
      visible.each do |e|
        assert_includes html, %(id="#{e["ref"]}" href="##{e["ref"]}"),
                        "expected #{e["ref"]} to anchor its own card"
      end
      # the JS defaults selection to a .k-assistant card; make sure one exists
      assert_includes html, "card k-assistant"
    end

    define_method("test_#{name}_tool_calls_have_named_tool_fields") do
      doc = ConversationStory::Parser.new(log).to_document
      calls = doc["events"].select { |e| e["kind"] == "tool_call" }
      refute_empty calls, "expected some tool_call events"
      calls.each do |e|
        assert e.dig("tool", "name"), "tool_call #{e["ref"]} missing tool.name"
        assert e.dig("tool", "use_id"), "tool_call #{e["ref"]} missing tool.use_id"
      end
    end

    define_method("test_#{name}_tool_call_and_result_share_a_link_id") do
      doc = ConversationStory::Parser.new(log).to_document
      events = doc["events"]
      calls_by_use_id = events.select { |e| e["kind"] == "tool_call" }
                              .to_h { |e| [e.dig("tool", "use_id"), e] }
      paired = events.select { |e| e["kind"] == "tool_result" && calls_by_use_id[e.dig("tool", "use_id")] }
      refute_empty paired, "expected at least one tool_result to pair with its tool_call"

      paired.each do |result|
        call = calls_by_use_id[result.dig("tool", "use_id")]
        token = "tool:#{result.dig("tool", "use_id")}"
        assert_includes call["link_ids"] || [], token
        assert_includes result["link_ids"] || [], token
      end
    end
  end

  # episode-8-before:63 is a delivered <task-notification> — a background
  # result arriving as a plain `user` record. It is NOT something Jess typed,
  # and its whole point is the human-readable <summary> field inside the XML.
  def test_task_notification_is_not_attributed_to_jess_and_extracts_summary
    log = File.expand_path("../examples/episode-8-before.jsonl", __dir__)
    doc = ConversationStory::Parser.new(log).to_document
    note = doc["events"].find { |e| e["kind"] == "task_notification" }

    refute_nil note, "expected a task_notification event in episode-8-before"
    assert_equal "system", ConversationStory::Renderer::WHO[note["kind"]]
    refute_match(/<task-notification>/, note["summary"],
                 "summary should be the extracted <summary> text, not the raw XML")
    assert_includes note["summary"], "completed"
  end

  # The enqueue, its dequeue, and the eventual task_notification delivery are
  # one lifecycle for one background task; dequeue/remove carry no id of their
  # own, so pairing with their enqueue is positional (FIFO), and the
  # originating tool_call joins via the tool-use-id embedded in the XML.
  def test_queue_lifecycle_and_notification_share_a_link_id
    log = File.expand_path("../examples/episode-8-before.jsonl", __dir__)
    doc = ConversationStory::Parser.new(log).to_document
    events = doc["events"]

    enqueue = events.find { |e| e["kind"] == "queue_operation" && e["operation"] == "enqueue" }
    notification = events.find { |e| e["kind"] == "task_notification" }
    refute_nil enqueue
    refute_nil notification

    shared = (enqueue["link_ids"] || []) & (notification["link_ids"] || [])
    refute_empty shared, "the enqueue and the notification it eventually delivers should share a link token"
  end

  # ---- subagents ------------------------------------------------------------
  #
  # An `Agent` tool call owns a whole other conversation, logged in its own file
  # under <example>/subagents/. The pair of records in the MAIN log becomes
  # `subagent` (the call) + `subagent_result` (the answer coming back), and the
  # subagent's own log is parsed by this same parser and nested under the call.

  EXAMPLES.each do |log|
    name = File.basename(log, ".jsonl")

    define_method("test_#{name}_agent_calls_become_subagent_events_with_a_nested_story") do
      doc = ConversationStory::Parser.new(log).to_document
      subagents = doc["events"].select { |e| e["kind"] == "subagent" }

      # Not every conversation delegates — a log with no Agent call has nothing
      # to say about nesting, so it sits this one out rather than failing.
      skip "#{name} spawns no Agent" if subagents.empty?

      subagents.each do |e|
        sub = e["subagent"]
        assert sub, "#{e["ref"]}: subagent event missing its nested story"
        assert_match(/\Aagent-\h+\z/, sub["agent_id"])
        refute_empty sub["events"], "#{e["ref"]}: nested story has no events"
        # the nested story is the same document shape, recursively
        assert_equal sub["events"].size, sub["meta"]["event_count"]
        # ...and it is a DIFFERENT log file, with its own line numbers
        sub["events"].each do |nested|
          assert_equal "#{sub["agent_id"]}:#{nested.dig("source", "line")}", nested["ref"]
          assert_equal sub["agent_id"], nested["agent"]
        end
      end
    end

    # The result of an Agent call is not an ordinary tool result: it's the
    # subagent's answer arriving back in the parent conversation, and it carries
    # the subagent's own totals — EXCEPT when the agent was launched to run in
    # the background (`tool.status == "async_launched"`): that result is just
    # the launch acknowledgment, not the answer, so it has no totals yet. The
    # real completion arrives later as a `task_notification`, same as any other
    # background task.
    define_method("test_#{name}_agent_results_become_subagent_result_events") do
      doc = ConversationStory::Parser.new(log).to_document
      results = doc["events"].select { |e| e["kind"] == "subagent_result" }
      subagents = doc["events"].select { |e| e["kind"] == "subagent" }

      assert_equal subagents.size, results.size, "one result per subagent call"
      results.each do |e|
        assert e.dig("tool", "agent_id"), "#{e["ref"]}: missing tool.agent_id"
        if e.dig("tool", "status") == "async_launched"
          assert_nil e.dig("tool", "subagent_tokens"),
                     "#{e["ref"]}: an async launch shouldn't report totals yet"
        else
          assert e.dig("tool", "subagent_tokens", "total_tokens")
        end
        # still linked to the call it answers, like any tool pair
        call = subagents.find { |s| s.dig("tool", "use_id") == e.dig("tool", "use_id") }
        refute_nil call, "#{e["ref"]}: no subagent call with a matching use_id"
        refute_empty (call["link_ids"] || []) & (e["link_ids"] || [])
      end
    end

    # The first record of a subagent log is the prompt the parent already shows
    # on the subagent card (it IS the Agent call's `prompt` argument). Showing it
    # again as the subagent's own opening "user message" says nothing new.
    define_method("test_#{name}_subagent_prompt_echo_is_hidden") do
      doc = ConversationStory::Parser.new(log).to_document
      doc["events"].select { |e| e["kind"] == "subagent" }.each do |e|
        first = e["subagent"]["events"].first
        assert_equal "user_message", first["kind"]
        assert first["hidden"], "#{first["ref"]}: the prompt echo should be hidden"
        assert_equal e.dig("tool", "input", "prompt"), first.dig("detail", "text")
      end
    end

    # Nothing about the subagent's token accounting may leak into the parent's:
    # the parent's total is what the parent's API calls cost, and a subagent's
    # context is its own (the Agent tool_result reports the subagent's totals
    # separately, under tool.subagent_tokens).
    define_method("test_#{name}_nested_tokens_stay_out_of_the_parent_total") do
      doc = ConversationStory::Parser.new(log).to_document
      subagent = doc["events"].find { |e| e["kind"] == "subagent" }
      skip "#{name} spawns no Agent" unless subagent

      nested_total = subagent["subagent"]["meta"]["total_tokens"]

      assert_operator nested_total, :>, 0, "the nested story should have its own total"
      leaders = doc["events"].select { |e| e["turn_leader"] && e["tokens"] }
      assert_equal leaders.sum { |e| e["tokens"]["context"].to_i + e["tokens"]["output"].to_i },
                   doc["meta"]["total_tokens"],
                   "meta.total_tokens must still count only the parent's own turns"
    end
  end

  # ---- assistant turns and token attribution --------------------------------
  #
  # The trap these guard: one API response spans several records, and each one
  # repeats the whole turn's `usage`. Attributing tokens per record instead of
  # per turn silently triples a running total, and the page still looks fine.

  EXAMPLES.each do |log|
    name = File.basename(log, ".jsonl")

    define_method("test_#{name}_elects_exactly_one_leader_per_turn") do
      doc = ConversationStory::Parser.new(log).to_document
      assistant = doc["events"].select { |e| e["role"] == "assistant" }
      by_turn = assistant.group_by { |e| e.dig("links", "message_id") }

      refute_empty by_turn, "expected assistant turns in #{name}"
      by_turn.each do |message_id, group|
        leaders = group.select { |e| e["turn_leader"] }
        assert_equal 1, leaders.size,
                     "turn #{message_id} should have exactly one turn_leader, " \
                     "got #{leaders.size} across #{group.size} records"
      end
    end

    # A turn with no text block still has to show its tokens somewhere, or the
    # running total jumps with no card to explain it. 7 of 33 turns in
    # episode-8-before are bare tool_use, so this path is exercised for real.
    define_method("test_#{name}_leader_prefers_the_message_record_but_always_exists") do
      doc = ConversationStory::Parser.new(log).to_document
      assistant = doc["events"].select { |e| e["role"] == "assistant" }

      assistant.group_by { |e| e.dig("links", "message_id") }.each_value do |group|
        leader = group.find { |e| e["turn_leader"] }
        message = group.find { |e| e["kind"] == "assistant_message" }
        assert_equal message, leader, "a turn with prose should lead with it" if message
        assert_equal group.first, leader, "a turn with no prose should lead with its first record" unless message
      end
    end

    # Recomputed independently from the log, so a change to how the parser
    # groups turns can't quietly agree with itself.
    define_method("test_#{name}_token_totals_match_an_independent_sum") do
      doc = ConversationStory::Parser.new(log).to_document

      seen = {}
      expected_sum = 0
      expected_total = 0
      File.foreach(log) do |line|
        next if line.strip.empty?

        rec = JSON.parse(line)
        usage = rec.dig("message", "usage")
        next unless rec["type"] == "assistant" && usage.is_a?(Hash)

        id = rec.dig("message", "id")
        next if seen[id]

        seen[id] = true
        context = usage["input_tokens"].to_i +
                  usage["cache_creation_input_tokens"].to_i +
                  usage["cache_read_input_tokens"].to_i
        expected_sum += context
        expected_total += context + usage["output_tokens"].to_i
      end

      leaders = doc["events"].select { |e| e["turn_leader"] && e["tokens"] }
      running = leaders.filter_map { |e| e.dig("tokens", "cumulative_context") }.max

      assert_equal expected_sum, running,
                   "cumulative_context should sum each TURN's context exactly once"
      assert_equal expected_total, doc["meta"]["total_tokens"],
                   "meta.total_tokens should sum every turn's context plus its output, " \
                   "counting each turn once"
    end

    # `estimated_input` is our arithmetic, not the API's. The name has to stay
    # distinct from the reported `input` so nothing downstream conflates them.
    define_method("test_#{name}_tool_results_carry_a_clearly_named_estimate") do
      doc = ConversationStory::Parser.new(log).to_document
      results = doc["events"].select { |e| e["kind"] == "tool_result" && e["tokens"] }

      refute_empty results, "expected tool_result events with an estimate in #{name}"
      results.each do |e|
        tokens = e["tokens"]
        assert_operator tokens["result_chars"], :>, 0, "#{e["ref"]}: estimate needs a length"
        assert_equal (tokens["result_chars"] / ConversationStory::Parser::CHARS_PER_TOKEN).round,
                     tokens["estimated_input"], "#{e["ref"]}: estimate should follow CHARS_PER_TOKEN"
        refute tokens.key?("input"),
               "#{e["ref"]}: an estimate must not be named like a reported count"
      end
    end
  end

  # ---- the mode a prompt was sent in ----------------------------------------
  #
  # Every real example log was recorded in one mode start to finish (44 stamps
  # saying `normal`, and not one switch), so the case the feature EXISTS for is
  # unreachable from examples/. These two tests build the log by hand instead.

  # A prompt's mode comes from the stamp written AFTER it — the harness writes
  # {last-prompt, mode, permission-mode} at submission, and `last-prompt` holds
  # that prompt's own text. Reading the stamp before the prompt would credit the
  # switch to the following prompt, one too late.
  def test_a_mode_switch_lands_on_the_prompt_it_applies_to
    doc = parse_records([
                          { "type" => "mode", "mode" => "normal" },
                          { "type" => "permission-mode", "permissionMode" => "auto" },
                          user_record("first, in normal mode"),
                          { "type" => "last-prompt", "lastPrompt" => "first, in normal mode" },
                          { "type" => "mode", "mode" => "normal" },
                          user_record("second — sent after shift-tabbing to plan"),
                          { "type" => "last-prompt", "lastPrompt" => "second" },
                          { "type" => "mode", "mode" => "plan" },
                          user_record("third, still in plan"),
                          { "type" => "mode", "mode" => "plan" },
                        ])
    prompts = doc["events"].select { |e| e["kind"] == "user_message" }
    assert_equal %w[normal plan plan], prompts.map { |e| e["mode"] }
    # only the one that MOVED is flagged — the opening state is not a switch,
    # and neither is staying put.
    assert_equal [nil, true, nil], prompts.map { |e| e["mode_changed"] }
    # permissions never moved, so they ride along on every prompt unflagged
    assert_equal %w[auto auto auto], prompts.map { |e| e["permission_mode"] }
    assert_nil prompts[1]["permission_mode_changed"]
  end

  # Only a change reaches the card face; the value itself lives in the pane.
  def test_only_a_changed_mode_badges_the_card
    doc = parse_records([
                          { "type" => "mode", "mode" => "normal" },
                          user_record("no badge on this one"),
                          { "type" => "mode", "mode" => "normal" },
                          user_record("this one switched"),
                          { "type" => "mode", "mode" => "plan" },
                        ])
    html = ConversationStory::Renderer.new(doc).to_html

    assert_equal 1, html.scan(/badge mode/).size, "exactly one prompt changed mode"
    assert_includes html, %(<span class="badge mode">plan</span>)
    # ...while both prompts report their mode in the detail pane
    assert_equal 2, html.scan(%r{<dt>Mode</dt>}).size
  end

  # Switching into plan mode moves both dimensions at once, and two badges
  # reading PLAN say nothing the one says.
  def test_a_switch_that_moves_both_dimensions_badges_once
    doc = parse_records([
                          { "type" => "mode", "mode" => "normal" },
                          { "type" => "permission-mode", "permissionMode" => "auto" },
                          user_record("normal to start"),
                          { "type" => "mode", "mode" => "normal" },
                          { "type" => "permission-mode", "permissionMode" => "auto" },
                          user_record("into plan, both dimensions"),
                          { "type" => "mode", "mode" => "plan" },
                          { "type" => "permission-mode", "permissionMode" => "plan" },
                        ])
    prompt = doc["events"].select { |e| e["kind"] == "user_message" }.last
    assert prompt["mode_changed"]
    assert prompt["permission_mode_changed"]

    html = ConversationStory::Renderer.new(doc).to_html
    assert_equal 1, html.scan(/badge mode/).size, "one badge, not two saying `plan`"
  end

  # Writes records to a temp log and parses it, so a hand-built conversation goes
  # through the real Parser (and the real renderer) rather than a stub document.
  def parse_records(records)
    Tempfile.create(["mode-test", ".jsonl"]) do |f|
      records.each { |r| f.puts JSON.generate(r) }
      f.flush
      return ConversationStory::Parser.new(f.path).to_document
    end
  end

  def user_record(text)
    @seq = (@seq || 0) + 1
    {
      "type" => "user", "uuid" => "u#{@seq}", "sessionId" => "test-session",
      "timestamp" => "2026-07-28T1#{@seq}:00:00.000Z", "gitBranch" => "main",
      "cwd" => "/tmp", "version" => "2.1.220",
      "message" => { "role" => "user", "content" => text },
    }
  end
end
