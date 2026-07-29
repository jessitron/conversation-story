# The `beat` Flag — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make "does narration stop here?" a real `beat` field on each event —
defaulted by the parser to today's behavior, overridable per card in edit mode.

**Architecture:** The parser sets `beat: true` on main-thread `user_message` /
`assistant_message` events; a `nested: true` constructor arg keeps subagents out.
The renderer emits `data-beat="true"`; `story.js` replaces its class-sniffing
`isMessage` with `isBeat` reading that attribute. Overrides live in the existing
`edits/<name>.yaml` sidecar, which grows two named sections (`summaries:`,
`beats:`), written by a new `PUT /api/beat` that reuses the summary write path.

**Tech Stack:** Ruby 4 (stdlib only in `bin/parse`, `bin/render`), minitest, ERB,
vanilla JS/CSS in `assets/`, `ferrum` (headless Chrome) for `bin/check-modes`.

Design doc: `notes/2026-07-28-beat-flag-design.md`.

## Global Constraints

- **Ruby 4**, asdf-pinned in `.tool-versions`. Run tests with `rake test`.
- **`bin/parse` / `bin/render` / `bin/site-index` stay on default gems only.** No
  new requires in those three or in `lib/conversation_story/*`.
- **The schema is the contract.** The renderer reads `story.yaml`, never the log.
  `story.yaml` stays 100% derived — from the log AND the sidecar.
- **`beat` is emitted only when true**, like `hidden`.
- **Field name is `beat`; UI label is "Beat stops here"; detail-pane cue is `🥁`.**
- **No `beat_edited` stamp** — there's no composed card face to beat.
- `out/` **is committed**. A task that changes rendered output runs `rake build`
  and commits the regenerated pages with it.
- Card ids contain a colon. Resolve them with `getElementById`, never
  `querySelector('#' + id)`, and add no id-based CSS selectors.
- Tag every commit message `- claude`.

---

### Task 1: Parser sets the `beat` default; subagents are exempt

**Files:**
- Modify: `lib/conversation_story/parser.rb` — `initialize` (line 111), `build_event` (line 145), `subagent_story` (line 608)
- Test: `test/parser_test.rb`

**Interfaces:**
- Produces: `ConversationStory::Parser.new(log_path, nested: false)` — a nested
  parser sets no `beat` on any event. Events gain `event["beat"] = true` for
  main-thread `user_message` / `assistant_message`; the key is absent otherwise.

- [ ] **Step 1: Write the failing tests**

Add to `test/parser_test.rb`, inside the `EXAMPLES.each do |log|` block (next to
`test_#{name}_every_event_has_a_ref_handle`):

```ruby
    # `beat` is where narration stops (n / p / shift+arrow). The default has to
    # reproduce what story.js used to hard-code from CSS classes: exactly the
    # main log's user and assistant messages.
    define_method("test_#{name}_beats_are_exactly_the_main_thread_messages") do
      doc = ConversationStory::Parser.new(log).to_document
      beats, rest = doc["events"].partition { |e| e["beat"] }

      assert_equal %w[assistant_message user_message],
                   beats.map { |e| e["kind"] }.uniq.sort,
                   "beats should be exactly the two conversation kinds"
      refute_empty beats
      assert(beats.all? { |e| e["beat"] == true }, "beat is only ever true")
      assert(rest.none? { |e| e.key?("beat") }, "a non-beat carries no beat key")
    end

    # A beat never stops inside a subagent: its log is parsed by the same class
    # recursively, so without the `nested:` guard a 70-event agent story would
    # become 70 beats and shatter one beat of Jess's conversation.
    define_method("test_#{name}_no_event_inside_a_subagent_is_a_beat") do
      doc = ConversationStory::Parser.new(log).to_document
      nested = doc["events"].flat_map { |e| e.dig("subagent", "events") || [] }
      assert(nested.none? { |e| e.key?("beat") },
             "subagent events must carry no beat key")
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rake test 2>&1 | tail -20`
Expected: FAIL — `beats.map { ... }.uniq.sort` is `[]`, not the two kinds
("beats should be exactly the two conversation kinds").

- [ ] **Step 3: Add the `nested:` arg and the default**

In `lib/conversation_story/parser.rb`, replace `initialize` (line 111):

```ruby
    # @param log_path [String] path to the top-level conversation .jsonl.
    # @param nested [Boolean] true when this is a SUBAGENT's log, parsed
    #   recursively by subagent_story. A nested parser sets no `beat`: narration
    #   stops in Jess's conversation, and a subagent's own messages are that
    #   agent talking to itself. Riding the constructor means a subagent that
    #   spawns a subagent is correct for free.
    def initialize(log_path, nested: false)
      @log_path = log_path
      @nested   = nested
      @log_file = File.basename(log_path)            # source.file (with .jsonl)
      @log_name = File.basename(log_path, ".jsonl")  # the `ref` prefix (no ext)
    end
```

Add a constant next to `MESSAGE_SUMMARY_LIMIT` (line 108):

```ruby
    # Where narration stops by default: `beat` is true on these kinds in the
    # MAIN log, and assets/story.js's isBeat steps between them (n / p /
    # shift+arrow). Jess overrides it per card via the edits sidecar — this is
    # only the guess. These two kinds are exactly what CSS_KIND maps to
    # k-user / k-assistant, which is what story.js used to sniff for.
    BEAT_KINDS = %w[user_message assistant_message].freeze
```

In `build_event`, after the `event["hidden"] = true if hidden?(kind, rec)` line
(line 168):

```ruby
      event["beat"] = true if !@nested && BEAT_KINDS.include?(kind)
```

In `subagent_story` (line 617), pass the flag down:

```ruby
      nested = self.class.new(path, nested: true).to_document
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rake test 2>&1 | tail -20`
Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/conversation_story/parser.rb test/parser_test.rb
git commit -m "Parse where narration stops: a beat flag on main-thread messages - claude"
```

---

### Task 2: Renderer emits `data-beat`

**Files:**
- Modify: `lib/conversation_story/renderer.rb:196` (the `render_card` locals), `lib/conversation_story/templates/card.html.erb:19`
- Test: `test/renderer_test.rb`

**Interfaces:**
- Consumes: `event["beat"]` from Task 1.
- Produces: `<a class="card k-…" … data-beat="true">` on beat cards; the
  attribute is absent otherwise. Task 3 (`story.js`, CSS) and Task 6
  (`bin/check-modes`) read it.

- [ ] **Step 1: Write the failing test**

Add to `test/renderer_test.rb`:

```ruby
  # The card carries the beat as an attribute so story.js can read it straight
  # off the DOM (isBeat) instead of re-deriving it from kind and nesting.
  def test_a_beat_card_carries_data_beat_and_others_do_not
    doc = {
      "meta" => { "name" => "demo" },
      "events" => [
        { "ref" => "demo:1", "kind" => "user_message", "summary" => "hi", "beat" => true },
        { "ref" => "demo:2", "kind" => "tool_call", "summary" => "Bash",
          "tool" => { "name" => "Bash", "primary_arg" => "ls" } },
      ],
    }
    html = ConversationStory::Renderer.new(doc).to_html

    assert_includes html, %(id="demo:1")
    assert_match(/id="demo:1"[^>]*data-beat="true"/, html)
    refute_match(/id="demo:2"[^>]*data-beat/, html)
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec ruby -Ilib -Itest test/renderer_test.rb -n /data_beat/ 2>&1 | tail -15`
Expected: FAIL — no `data-beat` in the output.

- [ ] **Step 3: Emit the attribute**

In `lib/conversation_story/renderer.rb`, in the `render_card` locals hash next to
`edited_attr:` (line 196):

```ruby
             beat_attr:    event["beat"] ? %( data-beat="true") : "",
```

In `lib/conversation_story/templates/card.html.erb`, extend the anchor (line 19).
**Keep it on one line** — and note every comment line in that file must end with
a dash before the closing delimiter, or ERB emits a blank line per card:

```erb
      <a class="card k-<%= css_kind %>" id="<%= anchor %>" href="#<%= anchor %>" data-time="<%= data_time %>"<%= link_attr %><%= edited_attr %><%= beat_attr %>>
```

Add `beat_attr` to that file's header comment, after the `edited_attr` sentence:

```erb
<%# marks a summary Jess rewrote by hand, which only the editing UI reacts to;   -%>
<%# beat_attr (optional) marks a card narration stops on — story.js's isBeat.    -%>
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rake test 2>&1 | tail -15`
Expected: PASS, 0 failures (the whole suite — `renderer_test.rb` also asserts no
ERB delimiter ever reaches the output, which the template edit could break).

- [ ] **Step 5: Rebuild and commit**

`out/` is committed, so the regenerated pages belong in this commit.

```bash
bundle exec rake build
git add lib/conversation_story/renderer.rb lib/conversation_story/templates/card.html.erb test/renderer_test.rb out
git commit -m "Carry the beat onto the card as data-beat - claude"
```

---

### Task 3: `story.js` steps by `data-beat`; the cue and the edit-mode marker

**Files:**
- Modify: `assets/story.js` — `isMessage` (lines 360-368), `selectCard` (line 59)
- Modify: `assets/story.css` — a new rule near the `.card` kind rules (~line 303)

**Interfaces:**
- Consumes: `data-beat` from Task 2.
- Produces: `isBeat(card) -> boolean`, replacing `isMessage`. Callers
  `beatForwardTo`, `beatBackTo` and `moveSelection`'s `byMessage` branch keep
  working through the renamed predicate.

- [ ] **Step 1: Replace `isMessage` with `isBeat`**

In `assets/story.js`, replace the `isMessage` const and its comment block
(lines 360-368) with:

```js
/* Does narration stop here? A "beat" is one step of n / p / shift+arrow, and
   which cards count is now the PARSER's call, carried on the card as data-beat
   (see BEAT_KINDS in lib/conversation_story/parser.rb) and overridable per card
   from the edits sidecar. This used to sniff k-user/k-assistant plus "not inside
   .subactions" — the same set, but re-derived here from CSS classes, so Jess had
   no way to say "don't stop on that one". */
const isBeat = c => c.dataset.beat === 'true';
```

- [ ] **Step 2: Update the three callers**

`beatForwardTo` (line 267): `if (isMessage(nav[i]))` → `if (isBeat(nav[i]))`
`beatBackTo` (line 275): `if (isMessage(nav[i]))` → `if (isBeat(nav[i]))`
`moveSelection` (line 407): `!isMessage(list[next])` → `!isBeat(list[next])`

Run: `grep -n isMessage assets/story.js`
Expected: no output.

- [ ] **Step 3: Add the detail-pane cue, every mode**

In `selectCard`, replace line 59:

```js
  /* The beat cue rides along in every mode — it's for Jess's eye, on the
     published site too, like the ✎ marker. Read-only; the checkbox that CHANGES
     it is edit-mode only (see showBeatEditor). */
  dTime.textContent = card.dataset.time + ' UTC' + (card.dataset.beat ? ' · 🥁' : '');
```

- [ ] **Step 4: Add the edit-mode gutter marker**

In `assets/story.css`, after the `.card.k-user { --kind: var(--blue); }` block
of kind colors (~line 303):

```css
/* Where narration stops. Only in edit mode — that's where Jess can change it,
   and it's where seeing the rhythm of stops across the whole board pays for the
   ink. Explore and narrate stay clean; in narrate the board IS the story. */
body.mode-edit .card[data-beat] .gutter::before {
  content: '\25B8';                /* ▸ */
  position: absolute;
  left: calc(var(--card-inset) * -1);
  color: var(--kind);
  font-size: 0.8em;
  line-height: 1.6;
}
body.mode-edit .card[data-beat] .gutter { position: relative; }
```

- [ ] **Step 5: Rebuild and see it**

```bash
bundle exec rake build
bin/screenshot episode-8-before '#episode-8-before:15' /tmp/beat-cue.png
```

Expected: the detail pane header reads `Assistant · … UTC · 🥁`. Read the PNG.
(The region above the target card screenshots blank — a headless repaint
artifact, not a page bug.)

- [ ] **Step 6: Verify navigation still works**

Run: `bundle exec bin/check-modes 2>&1 | tail -20`
Expected: all scenarios OK. The existing "shift+right jumps to the next
user/assistant card" scenario computes its expectation with its own `message?`
helper (CSS classes), which still agrees with `data-beat` because Task 1's
default reproduces it exactly. Task 6 switches that helper over.

- [ ] **Step 7: Commit**

```bash
git add assets/story.js assets/story.css out
git commit -m "Step by the beat flag, not by CSS class; cue it in the detail pane - claude"
```

---

### Task 4: The sidecar grows a `beats:` section

**Files:**
- Modify: `lib/conversation_story/edits.rb`
- Modify: `edits/episode-8-before.yaml` (convert to the two-section shape)
- Test: `test/edits_test.rb`

**Interfaces:**
- Produces:
  - `Edits#beat(ref) -> true | false | nil` (nil = no override)
  - `Edits#set_beat(ref, value) -> self` — `nil` removes the override; anything
    else is stored as `!!value`
  - `Edits#apply(document)` also writes `event["beat"]`: `true` sets it, `false`
    **deletes the key** (so "not a beat" is the absent-key shape Task 1 emits)
  - File shape: `{"summaries" => {ref => text}, "beats" => {ref => bool}}`; a
    section is omitted when empty, and the file is deleted when both are.
- Consumed by: Task 5 (`bin/serve`).

- [ ] **Step 1: Write the failing tests**

Add to `test/edits_test.rb`:

```ruby
  def test_apply_turns_a_beat_off_by_removing_the_key
    in_tmp_dir do |dir|
      doc = document
      doc["events"][0]["beat"] = true          # the parser's default
      edits = Edits.for_story("demo", dir: dir).set_beat("demo:1", false)

      assert_empty edits.apply(doc)
      refute doc["events"][0].key?("beat"),
             "beat off means the key is gone, same shape the parser emits"
    end
  end

  def test_apply_turns_a_beat_on_for_a_card_the_parser_would_not_stop_at
    in_tmp_dir do |dir|
      doc = document
      edits = Edits.for_story("demo", dir: dir).set_beat("demo:2", true)

      assert_empty edits.apply(doc)
      assert_equal true, doc["events"][1]["beat"]
    end
  end

  # Beats reach nested subagent events too, so Jess can stop on one deliberately.
  def test_apply_sets_a_beat_inside_a_nested_subagent_story
    in_tmp_dir do |dir|
      doc = document
      edits = Edits.for_story("demo", dir: dir).set_beat("agent-abc:2", true)

      assert_empty edits.apply(doc)
      assert_equal true, doc["events"][2]["subagent"]["events"][0]["beat"]
    end
  end

  def test_a_beat_override_for_a_ref_that_no_longer_exists_is_reported_stale
    in_tmp_dir do |dir|
      edits = Edits.for_story("demo", dir: dir).set_beat("demo:999", false)
      assert_equal ["demo:999"], edits.apply(document)
    end
  end

  def test_round_trip_keeps_summaries_and_beats_in_named_sections
    in_tmp_dir do |dir|
      Edits.for_story("demo", dir: dir)
           .set("demo:1", "Jess's line")
           .set_beat("demo:2", true)
           .set_beat("demo:1", false)
           .save

      raw = YAML.safe_load_file(File.join(dir, "demo.yaml"))
      assert_equal({ "demo:1" => "Jess's line" }, raw["summaries"])
      assert_equal({ "demo:1" => false, "demo:2" => true }, raw["beats"])

      reloaded = Edits.for_story("demo", dir: dir)
      assert_equal "Jess's line", reloaded["demo:1"]
      assert_equal false, reloaded.beat("demo:1")
      assert_equal true,  reloaded.beat("demo:2")
      assert_nil reloaded.beat("demo:3")
    end
  end

  def test_set_beat_nil_clears_the_override_and_an_empty_file_is_removed
    in_tmp_dir do |dir|
      path = File.join(dir, "demo.yaml")
      Edits.for_story("demo", dir: dir).set_beat("demo:1", false).save
      assert File.exist?(path)

      Edits.for_story("demo", dir: dir).set_beat("demo:1", nil).save
      refute File.exist?(path), "no husk left behind when nothing is overridden"
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -Ilib -Itest test/edits_test.rb 2>&1 | tail -15`
Expected: FAIL — `NoMethodError: undefined method 'set_beat'`.

- [ ] **Step 3: Implement the two sections**

In `lib/conversation_story/edits.rb`:

Update the class comment's file-shape example to the sectioned form and say what
a beat is (insert after the existing `episode-8-after:97: The moment it clicks`
example block):

```ruby
    #     summaries:
    #       episode-8-after:42: Jess asks for the timeline back
    #     beats:
    #       episode-8-after:97: false
    #
    # Two kinds of hand edit, two named sections. `beats` overrides where
    # narration stops (n / p / shift+arrow): false exempts a message the parser
    # defaulted to a beat, true adds a stop the parser wouldn't guess — a tool
    # call, or an event inside a subagent. There is no `beat_edited` stamp:
    # unlike a summary it has no composed card face to beat and nothing to mark.
```

Replace `HEADER`:

```ruby
    HEADER = <<~YAML
      # Hand edits — Jess's, not the parser's. Keyed by event ref (<example>:<line>).
      # bin/parse overlays these onto the freshly parsed story.yaml.
      #   summaries: the one-line card face, rewritten
      #   beats:     where narration stops (n / p / shift+arrow); true or false
      # Edit here or on the page (rake serve).
    YAML
```

Replace `initialize` and add the accessors:

```ruby
    def initialize(path)
      @path = path
      loaded = load_file
      @summaries = loaded["summaries"]
      @beats     = loaded["beats"]
    end

    def empty?  = @summaries.empty? && @beats.empty?
    def refs    = (@summaries.keys + @beats.keys).uniq
    def [](ref) = @summaries[ref]

    # nil means "no override" — the parser's default stands.
    def beat(ref) = @beats[ref]

    # nil clears the override; anything else is coerced to a real boolean, so a
    # JSON "false" string can't sneak in as truthy.
    def set_beat(ref, value)
      value.nil? ? @beats.delete(ref) : @beats[ref] = !!value
      self
    end
```

Replace `apply`:

```ruby
    # Overlay onto a freshly parsed document, in place.
    # @return [Array<String>] refs that matched no event (stale — the log moved).
    def apply(document)
      by_ref = events_by_ref(document["events"])
      stale = []

      @summaries.each do |ref, text|
        event = by_ref[ref]
        next stale << ref unless event

        event["summary"] = text
        event["summary_edited"] = true
      end

      @beats.each do |ref, on|
        event = by_ref[ref]
        next stale << ref unless event

        # `false` DELETES the key rather than storing false: "not a beat" is the
        # absent-key shape the parser emits, and story.js reads
        # dataset.beat === 'true'. One shape, one truth.
        on ? event["beat"] = true : event.delete("beat")
      end

      stale.uniq
    end
```

Replace `save`, `sorted` and `load_file`:

```ruby
    # Writing an empty set removes the file, so "reverted everything" leaves no
    # confusing husk behind in git. An empty section is omitted for the same
    # reason.
    def save
      if empty?
        File.delete(@path) if File.exist?(@path)
        return self
      end

      sections = {}
      sections["summaries"] = sorted(@summaries) unless @summaries.empty?
      sections["beats"]     = sorted(@beats)     unless @beats.empty?

      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, HEADER + YAML.dump(sections).delete_prefix("---\n"))
      self
    end

    private

    # Grouped by log, then by line number, so a section reads in story order
    # rather than edit order (and a subagent's edits stay together).
    def sorted(map)
      map.sort_by { |ref, _| [ref.to_s.sub(/:\d+\z/, ""), ref.to_s[/:(\d+)\z/, 1].to_i] }.to_h
    end

    # Two sections, both optional. Only this shape is read: the sidecars live in
    # this repo and nothing else has ever consumed one, so a flat-file
    # compatibility branch would be dead code the day it shipped.
    def load_file
      empty = { "summaries" => {}, "beats" => {} }
      return empty unless File.exist?(@path)

      loaded = YAML.safe_load_file(@path)
      return empty unless loaded.is_a?(Hash)

      {
        "summaries" => string_map(loaded["summaries"]) { |v| v.to_s },
        "beats"     => string_map(loaded["beats"])     { |v| !!v },
      }
    end

    def string_map(raw, &coerce)
      return {} unless raw.is_a?(Hash)

      raw.transform_keys(&:to_s).transform_values(&coerce)
    end
```

Leave `events_by_ref` where it is, below these (it's already `private`; make sure
the file has exactly one `private` keyword after the edit).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -Ilib -Itest test/edits_test.rb 2>&1 | tail -15`
Expected: PASS. (`rake test` will still fail until Step 5 — the real sidecar is
flat, so `episode-8-before`'s hand-written summaries have silently vanished.)

- [ ] **Step 5: Convert the real sidecar**

Rewrite `edits/episode-8-before.yaml` with the new `HEADER`, every existing
`ref: text` pair moved verbatim under a `summaries:` key, and **no `beats:`
section** (there are no beat overrides yet). Preserve the text exactly,
curly apostrophes included.

Verify nothing was lost:

```bash
bundle exec rake build
grep -c 'data-edited' out/episode-8-before/index.html
```

Expected: `8` — the same eight hand-written summaries that were there before.

- [ ] **Step 6: Run the whole suite**

Run: `bundle exec rake test 2>&1 | tail -15`
Expected: PASS, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add lib/conversation_story/edits.rb test/edits_test.rb edits/episode-8-before.yaml out
git commit -m "Sidecar holds two kinds of hand edit: summaries and beats - claude"
```

---

### Task 5: `PUT /api/beat` and the edit-mode checkbox

**Files:**
- Modify: `bin/serve` — `save_summary` (line 114) and the mount procs (line 161)
- Modify: `assets/story.js` — `showSummaryEditor` (line 493) and `selectCard` (line 65)
- Modify: `assets/story.css` — a rule beside the `.summary-edit` styles

**Interfaces:**
- Consumes: `Edits#set_beat` / `#beat` (Task 4), `data-beat` (Task 2).
- Produces: `PUT /api/beat` with `{story, ref, beat}` → `200 {ref, beat}` where
  `beat` is what landed in the rebuilt `story.yaml`. Task 6 calls it.

- [ ] **Step 1: Extract the shared write path in `bin/serve`**

`save_summary` and the new `save_beat` differ only in which override they set and
what they report. Replace `save_summary` (line 114) with:

```ruby
# Write the override, then rebuild this one story through the ordinary programs.
# Returns what actually landed on disk — never what the client asked for.
def save_edit(name:, ref:)
  paths = story_paths(name)
  raise EditError.new("story not built yet: #{name}", status: 409) unless File.exist?(paths[:story])
  raise EditError, "unknown event: #{ref.inspect}" unless event_for(paths[:story], ref)

  edits = ConversationStory::Edits.for_story(name, dir: EDITS_DIR[0])
  yield edits
  edits.save

  run!(RUBY, File.join(REPO_ROOT, "bin", "parse"), paths[:log], "-o", paths[:story],
       "--edits", EDITS_DIR[0])
  run!(RUBY, File.join(REPO_ROOT, "bin", "render"), paths[:story], "-o", paths[:page])

  event_for(paths[:story], ref)
end

def save_summary(name:, ref:, summary:)
  event = save_edit(name: name, ref: ref) { |edits| edits.set(ref, summary) }
  { ref: ref, summary: event["summary"], edited: !!event["summary_edited"] }
end

# `beat` arrives as a real JSON boolean; nil means "drop the override and let the
# parser's default stand". The answer reports the flag as the rebuilt story.yaml
# has it, which is the only thing the page should believe.
def save_beat(name:, ref:, beat:)
  unless [true, false, nil].include?(beat)
    raise EditError, "beat must be true, false or null: #{beat.inspect}"
  end

  event = save_edit(name: name, ref: ref) { |edits| edits.set_beat(ref, beat) }
  { ref: ref, beat: !!event["beat"] }
end
```

- [ ] **Step 2: Mount the endpoint**

After the `/api/summary` mount proc (ends line 179), add:

```ruby
server.mount_proc("/api/beat") do |req, res|
  unless %w[PUT POST].include?(req.request_method)
    next json_response(res, 405, error: "use PUT")
  end

  begin
    body = JSON.parse(req.body.to_s)
    result = save_beat(name: body["story"], ref: body["ref"], beat: body["beat"])
    puts "  beat #{result[:beat] ? "on " : "off"} #{result[:ref]}"
    json_response(res, 200, result)
  rescue EditError => e
    json_response(res, e.status, error: e.message)
  rescue JSON::ParserError => e
    json_response(res, 400, error: "bad JSON: #{e.message}")
  rescue StandardError => e
    warn "#{e.class}: #{e.message}"
    json_response(res, 500, error: "#{e.class}: #{e.message}")
  end
end
```

- [ ] **Step 3: Check the server by hand**

```bash
bundle exec rake build
bundle exec bin/serve -p 8123 &
sleep 3
curl -s -X PUT http://localhost:8123/api/beat -H 'Content-Type: application/json' \
  -d '{"story":"episode-8-before","ref":"episode-8-before:15","beat":false}'
grep -c 'id="episode-8-before:15"[^>]*data-beat' out/episode-8-before/index.html
curl -s -X PUT http://localhost:8123/api/beat -H 'Content-Type: application/json' \
  -d '{"story":"episode-8-before","ref":"episode-8-before:15","beat":null}'
kill %1
```

Expected: first curl answers `{"ref":"episode-8-before:15","beat":false}`, the
grep prints `0`, and the second curl answers `beat":true`. **This writes the real
`edits/` dir** — the `beat":null` call clears it again; confirm with
`git diff --stat edits` (empty) before moving on.

- [ ] **Step 4: Add the checkbox to the detail pane**

In `assets/story.js`, add after `showSummaryEditor`'s closing brace (line 571):

```js
/* The beat toggle: is this where narration stops? Same gate as the summary box —
   the authoring server must be answering AND the page must be in edit mode — so
   the published site shows the 🥁 cue (see selectCard) with no way to change it.
   It SUBMITS ON TOGGLE, with no Save button: a boolean has no draft state to
   protect the way half-typed prose does, and unchecking it is the undo. */
function showBeatEditor(card) {
  if (!editingAvailable || mode !== 'edit') return;

  const sec = document.createElement('div');
  sec.className = 'd-section beat-edit';
  sec.innerHTML =
    '<label class="beat-toggle"><input type="checkbox">' +
    '<span>Beat stops here</span></label>' +
    '<span class="summary-status"></span>';

  const box    = sec.querySelector('input');
  const status = sec.querySelector('.summary-status');
  box.checked = card.dataset.beat === 'true';

  box.addEventListener('change', () => {
    const wanted = box.checked;
    status.className = 'summary-status';
    status.textContent = 'saving…';
    fetch('/api/beat', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ story: STORY, ref: card.id, beat: wanted }),
    })
      .then(r => r.json().then(j => (r.ok ? j : Promise.reject(new Error(j.error || ('HTTP ' + r.status))))))
      .then(result => {
        // Believe the server, not the checkbox: the flag on the page comes from
        // the rebuilt story.yaml, exactly like a saved summary does.
        if (result.beat) card.dataset.beat = 'true'; else delete card.dataset.beat;
        box.checked = result.beat;
        status.textContent = result.beat ? 'beat on' : 'beat off';
        status.classList.add('ok');
      })
      .catch(err => {
        box.checked = card.dataset.beat === 'true';
        status.textContent = err.message;
        status.classList.add('bad');
      });
  });

  dBody.prepend(sec);
}
```

In `selectCard`, after the `showSummaryEditor(card);` line (line 65):

```js
  showBeatEditor(card);      // prepended after, so it sits above the Summary box
```

- [ ] **Step 5: Style it**

In `assets/story.css`, after the `.summary-actions` / `.summary-status` rules:

```css
/* The beat toggle sits above the Summary box, quieter than it: one line, no
   heading — the label IS the question. */
.d-section.beat-edit {
  display: flex;
  align-items: center;
  gap: 0.6rem;
}
.beat-toggle {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  cursor: pointer;
  font-family: var(--font-deco);
  font-size: 0.78rem;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--ink-soft);
}
.beat-toggle input { accent-color: var(--kind); cursor: pointer; }
```

Check those three custom properties exist with the names used here:

```bash
grep -n 'font-deco\|ink-soft' assets/story.css | head -3
```

If a name differs, use the one the file actually defines.

- [ ] **Step 6: See it**

```bash
bundle exec rake build
bundle exec bin/serve -p 8123 &
sleep 3
bin/screenshot 'http://localhost:8123/episode-8-before/?mode=edit#episode-8-before:15' /tmp/beat-edit.png
kill %1
```

Expected: the detail pane shows `☑ BEAT STOPS HERE` above the Summary box, and
the header reads `… UTC · 🥁`. Read the PNG.

- [ ] **Step 7: Commit**

```bash
git add bin/serve assets/story.js assets/story.css out
git commit -m "Toggle a card's beat in edit mode, through PUT /api/beat - claude"
```

---

### Task 6: Extend both checkers

**Files:**
- Modify: `bin/check-edit-api`
- Modify: `bin/check-modes` — the `message?` helper (line 98) and the
  "shift+right jumps to the next user/assistant card" scenario (line 278)

**Interfaces:**
- Consumes: `PUT /api/beat` (Task 5), `data-beat` (Task 2), `isBeat` (Task 3).

- [ ] **Step 1: Add the beat round-trip to `bin/check-edit-api`**

Add next to `put_summary` (line 39):

```ruby
def put_beat(story:, ref:, beat:)
  uri = URI("http://localhost:#{PORT}/api/beat")
  req = Net::HTTP::Put.new(uri, "Content-Type" => "application/json")
  req.body = JSON.generate(story: story, ref: ref, beat: beat)
  res = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) }
  [res.code.to_i, JSON.parse(res.body)]
end

def beat_on_page?(ref)
  html = File.read(File.join(REPO, "out", STORY, "index.html"))
  html.match?(/id="#{Regexp.escape(ref)}"[^>]*data-beat="true"/)
end
```

Then, inside the `Dir.mktmpdir` block after the existing summary save/revert
checks and before the refusal checks, add a beat round-trip. It targets the
story's first **beat** event, which is not necessarily `REF`:

```ruby
    # ---- beats -------------------------------------------------------------
    # A beat override is the other kind of hand edit in the same sidecar, and it
    # has to reach all three places a summary does: the file, story.yaml and the
    # page. Turning one OFF is the interesting direction — that's the TODO this
    # feature came from.
    beat_ref = story_events.find { |e| e["beat"] }&.fetch("ref")
    if beat_ref
      code, body = put_beat(story: STORY, ref: beat_ref, beat: false)
      failures << "beat off" unless check("PUT /api/beat turns off the beat at #{beat_ref}",
                                          code == 200 && body["beat"] == false,
                                          "#{code} #{body}")
      failures << "beat off story" unless check("story.yaml drops the beat key",
                                                !find_ref(story_events, beat_ref).key?("beat"))
      failures << "beat off page" unless check("the page drops data-beat",
                                               !beat_on_page?(beat_ref))
      failures << "beat off sidecar" unless check("the sidecar records beats: false",
                                                  YAML.safe_load_file(File.join(edits_dir, "#{STORY}.yaml"))
                                                      .dig("beats", beat_ref) == false)

      code, body = put_beat(story: STORY, ref: beat_ref, beat: nil)
      failures << "beat cleared" unless check("PUT beat:null restores the parser's default",
                                              code == 200 && body["beat"] == true,
                                              "#{code} #{body}")
      failures << "beat cleared page" unless check("the page has data-beat back",
                                                   beat_on_page?(beat_ref))
    else
      puts "SKIP  #{STORY} has no beats to toggle"
    end

    code, body = put_beat(story: STORY, ref: beat_ref || REF, beat: "yes")
    failures << "beat type" unless check("PUT /api/beat refuses a non-boolean",
                                          code == 400, "#{code} #{body}")
```

Extend the script's header comment (line 4-8) to say it exercises **both** kinds
of hand edit now, summaries and beats.

- [ ] **Step 2: Run it**

Run: `bundle exec rake build && bundle exec bin/check-edit-api episode-8-after 2>&1 | tail -25`
Expected: every line `OK`, exit 0. Then confirm the real sidecar is untouched:
`git diff --stat edits` — empty (the checker uses a temp edits dir).

- [ ] **Step 3: Point `bin/check-modes` at `data-beat`**

Replace the `message?` helper (lines 96-103) with:

```ruby
  # Does narration stop here? The parser decides and the card carries the answer
  # as data-beat, so this reads the attribute rather than re-deriving the rule
  # from CSS classes the way it used to (k-user/k-assistant and not inside
  # .subactions). The set is the same by default; that the DEFAULT is right is
  # test/parser_test.rb's job, not this script's.
  def beat?(id)
    js("(() => { const c = document.getElementById(#{id.inspect}); " \
       "return !!c && c.dataset.beat === 'true'; })()")
  end

  # Turn a card's beat off/on in the live DOM. isBeat reads dataset.beat on every
  # call, so this exercises the real navigation rule without writing a sidecar
  # file — no temp edits dir, no rebuild, nothing of Jess's touched.
  def set_beat(id, on)
    js("(() => { const c = document.getElementById(#{id.inspect}); " \
       "if (#{on}) c.dataset.beat = 'true'; else delete c.dataset.beat; })()")
  end
```

Then update every `message?` call site:

```bash
grep -n 'message?' bin/check-modes
```

Rename each to `beat?`, and reword the two scenario names that say
"user/assistant card" to say "beat" (line 278's `"shift+right jumps to the next
user/assistant card"` becomes `"shift+right jumps to the next beat"`).

- [ ] **Step 4: Add the skip scenario**

Add after the (renamed) shift+right scenario:

```ruby
# The whole point of the beat flag: a message Jess exempted is stepped straight
# past. Flipping data-beat in the DOM is the same switch the edits sidecar
# throws, minus the file.
scenario "shift+right skips a message whose beat is turned off" do |s|
  ids = s.card_ids
  start = ids.find { |id| id != s.active_id }
  rest = ids.drop(ids.index(start) + 1)
  skipped = rest.find { |id| s.beat?(id) }
  next "no beat after #{start} to skip" unless skipped
  landing = rest.drop(rest.index(skipped) + 1).find { |id| s.beat?(id) }
  next "only one beat after #{start}" unless landing

  s.click_id(start)
  s.set_beat(skipped, false)
  s.key([:Shift, :Right])
  next "stopped on #{skipped}, whose beat is off" if s.active_id == skipped
  next "expected #{landing}, landed on #{s.active_id.inspect}" unless s.active_id == landing
  nil
end
```

- [ ] **Step 5: Run both checkers and the suite**

```bash
bundle exec rake test 2>&1 | tail -5
bundle exec bin/check-modes 2>&1 | tail -25
bundle exec bin/check-anchors 2>&1 | tail -5
```

Expected: all pass. Read the trap list at the top of `bin/check-modes` if the new
scenario misbehaves — `[:Shift, 'n']` is not `"N"`, a click needs a center-scroll
first, and the page always loads with a card already selected.

- [ ] **Step 6: Commit**

```bash
git add bin/check-edit-api bin/check-modes
git commit -m "Check the beat: write path round-trip, and shift+arrow skipping one - claude"
```

---

### Task 7: Document it and close the TODO

**Files:**
- Modify: `CLAUDE.md`, `TODO.md`, `notes/intermediate-schema.md`
- Create: `notes/2026-07-28-session-20-beat-flag.md`

- [ ] **Step 1: Add the schema field to `notes/intermediate-schema.md`**

Document `beat` next to `hidden`: true only on main-thread `user_message` /
`assistant_message`, absent otherwise; never set inside a subagent (the
`Parser.new(path, nested: true)` guard); overridable from `edits/<name>.yaml`'s
`beats:` section, where `false` deletes the key rather than storing false. Update
whatever description of the sidecar file shape appears there to the two-section
form.

- [ ] **Step 2: Add a `CLAUDE.md` bullet**

In the Status list, after the prompt-mode bullet:

```markdown
- **`beat` says where narration stops** — `n` / `p` / shift+arrow step between
  beats. The parser sets `beat: true` on main-thread `user_message` /
  `assistant_message` (`Parser::BEAT_KINDS`) and **never inside a subagent**:
  the recursive parse is `Parser.new(path, nested: true)`, which suppresses it,
  because a beat never stops inside a subagent. The renderer emits
  `data-beat="true"` and `story.js`'s `isBeat` reads that attribute — it used to
  sniff `k-user`/`k-assistant` plus "not in `.subactions`", the same set with no
  way to override it. Jess overrides per card in edit mode (a checkbox that
  saves on toggle, `PUT /api/beat`), stored in `edits/<name>.yaml`'s `beats:`
  section; `false` **deletes** the key, so "not a beat" has one shape. The
  detail pane shows a 🥁 cue in every mode; the ▸ gutter marker paints only in
  edit mode. See `notes/2026-07-28-beat-flag-design.md`.
```

Also update the two `edits/` bullets further down: the sidecar is no longer "maps
event `ref` → summary" but two sections, `summaries:` and `beats:`.

- [ ] **Step 3: Close the TODO item**

Remove the `- **modify when it stops** …` bullet from `TODO.md` (line 106). Leave
the neighboring **change narrate shortcut** item alone — it's a separate ask.

- [ ] **Step 4: Write the session note**

Create `notes/2026-07-28-session-20-beat-flag.md`: what shipped, and the two
things a future session would otherwise rediscover the hard way —

1. The recursive-parse trap. `subagent_story` calls `self.class.new(path)`, so
   any kind-based default the parser adds lands on every subagent event too. The
   `nested:` arg is the fix; `test_*_no_event_inside_a_subagent_is_a_beat` is the
   tripwire.
2. `beat: false` in the sidecar **deletes** the key instead of storing `false`,
   so the parser's output and an override converge on one shape and
   `dataset.beat === 'true'` is the only test anywhere.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md TODO.md notes
git commit -m "Session 17 notes: the beat flag, and the recursive-parse trap - claude"
```

---

## Self-Review

**Spec coverage:** §1 parser default + `nested:` → Task 1. §2 `data-beat` +
edit-mode marker → Tasks 2, 3. §3 `isBeat` + every-mode detail cue → Task 3. §4
two-section sidecar, `beat`/`set_beat`, no `beat_edited`, file conversion →
Task 4. §5 `PUT /api/beat`, submit-on-toggle, health+mode gate → Task 5. §6 all
three test surfaces → Tasks 1 (golden), 6 (`check-edit-api`, `check-modes`).
Out-of-scope items (header stat, bulk editing) have no tasks, as intended.

**Naming consistency:** `beat` (schema), `BEAT_KINDS`, `data-beat`, `isBeat`,
`Edits#beat` / `#set_beat`, `save_beat`, `PUT /api/beat`, `beat?` / `set_beat`
in `check-modes`, `showBeatEditor`. `save_summary` keeps its name and signature,
so nothing else in `bin/serve` or `story.js` moves.
