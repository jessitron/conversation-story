# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module ConversationStory
  # Answers "what IS this session?" about one Claude session log — the handful of
  # facts needed to judge whether a conversation is worth turning into a story
  # (title, first prompt, recap, turns, subagents, max context, size, date).
  #
  # ONE streaming pass, O(1) memory, and the result is cached by
  # path + mtime + size (see Cache below) so an unchanged log is never reopened.
  #
  # IT DELIBERATELY DOES NOT REUSE `Parser`. Parser accumulates a full event
  # array for the whole log AND recursively parses every subagent sidecar, so a
  # listing of 50 sessions would spend minutes and gigabytes building complete
  # documents just to read five numbers off them. The corpus is ~416 logs /
  # 621 MB; that is the whole reason this class exists. The overlap with Parser
  # is small and stable (a couple of record types and the context formula), and
  # the two agree on what they share — see test/session_scan_test.rb, which
  # checks this scan's `turns` against Parser's own turn-leader count.
  #
  # THE MEMORY HAZARD IS A SINGLE LINE, NOT THE FILE. Measured over the golden
  # fixtures: every line above 100 KB (11 of them, up to 782 KB) is a `user`
  # record carrying a tool result, and none of them carries `usage`. So each
  # line is pre-filtered with a cheap `String#include?` before `JSON.parse` —
  # a line we don't want is read as a String and thrown away, never turned into
  # Ruby objects — and the one filter that CAN match a fat line (the
  # first-prompt hunt) is additionally capped by MAX_PROMPT_BYTES and switched
  # off the moment the prompt is found.
  class SessionScan
    # Where a scan's cached result lives. Gitignored: these are derived from
    # private conversation logs and must never land in this public repo. The
    # importer's generated HTML is this directory's other tenant.
    CACHE_DIR = File.expand_path("../../.importer/scans", __dir__)

    # The recap's harness chrome, stripped so the card body is prose. Not every
    # recap has it (mtg-tabletop-plan's first one doesn't), so it's optional.
    RECAP_TAIL = "(disable recaps in /config)"

    # A prompt Jess typed is never this big. The cap exists so the first-prompt
    # hunt can't be tricked into parsing a multi-megabyte tool_result line,
    # which is the same `type: "user"` shape.
    MAX_PROMPT_BYTES = 64 * 1024

    # Cheap pre-filter substrings. All of them are JSON *keys* or fixed string
    # *values*, so they survive any spacing the serializer might use — matching
    # on `"type":"user"` would not.
    TITLE_HINT    = '"ai-title"'
    RECAP_HINT    = '"away_summary"'
    # Only assistant records carry `usage`, and this key is always inside it —
    # so it's both the assistant filter and one of the numbers being summed.
    USAGE_HINT    = '"cache_read_input_tokens"'
    USER_HINT     = '"user"'
    SESSION_HINT  = '"sessionId"'

    # Scan one log. Always reads the file; use Cache#fetch (or .fetch below) to
    # get the cached-when-unchanged behaviour.
    def self.scan(path) = new(path).to_h

    # Cache-aware entry point: a hit returns the stored result without opening
    # the log at all.
    def self.fetch(path, cache: Cache.new) = cache.fetch(path) { scan(_1) }

    def initialize(path)
      @path = File.expand_path(path)
    end

    attr_reader :path

    # String keys, and JSON-native value types only, because this hash goes
    # straight into the cache and must come back byte-identical. In particular
    # `mtime` is a Float epoch, not a Time: a cache hit and a cache miss have to
    # be indistinguishable to the caller.
    def to_h
      stat = File.stat(@path)
      facts = read_facts

      {
        "session_id"  => facts[:session_id],
        "title"       => facts[:title],
        "first_prompt" => facts[:first_prompt],
        "recap"       => facts[:recap],
        "turns"       => facts[:turn_ids].size,
        "subagents"   => subagent_count,
        "max_context" => facts[:max_context],
        "size"        => stat.size,
        "mtime"       => stat.mtime.to_f,
        "path"        => @path,
        "project"     => project_label(facts[:cwd]),
      }
    end

    private

    # THE one pass. Everything above is derived from what this collects.
    def read_facts
      facts = {
        session_id: nil, title: nil, first_prompt: nil, recap: nil,
        cwd: nil, max_context: 0, turn_ids: {},
      }

      File.foreach(@path) do |line|
        rec = nil

        # `sessionId` rides on the bookkeeping records too, so this is normally
        # settled by line 1 and the check costs one `include?` per line after
        # that. `rec` is reused below so no line is ever parsed twice.
        if facts[:session_id].nil? && line.include?(SESSION_HINT) &&
           line.bytesize <= MAX_PROMPT_BYTES
          rec = parse(line)
          facts[:session_id] = rec["sessionId"] if rec
        end

        # Order matters only for cost: the cheapest, most selective checks
        # first, and `next` before JSON.parse in every branch that can't match.
        if line.include?(USAGE_HINT)
          rec ||= parse(line) or next
          next unless rec["type"] == "assistant"

          # Every record of one API response repeats that response's whole
          # `usage` and shares its `message.id` (the fact Parser's turn-leader
          # election exists for), so counting records inflates turns ~3x —
          # 62 assistant records for 33 turns in episode-8-before. Count
          # distinct ids instead. A Hash is the set; ids are ~40 bytes each.
          facts[:turn_ids][rec.dig("message", "id")] = true if rec.dig("message", "id")

          ctx = context_of(rec.dig("message", "usage"))
          facts[:max_context] = ctx if ctx > facts[:max_context]
          facts[:cwd] ||= rec["cwd"]
        elsif line.include?(TITLE_HINT)
          rec ||= parse(line) or next
          # LAST one wins: the harness regenerates the title as the session
          # runs (5 to 43 of them per fixture), so the last is best informed.
          facts[:title] = rec["aiTitle"] if rec["type"] == "ai-title" && rec["aiTitle"]
        elsif line.include?(RECAP_HINT)
          rec ||= parse(line) or next
          next unless rec["type"] == "system" && rec["subtype"] == "away_summary"

          # Last one wins here too, and for the same reason the title does:
          # the fixtures carry 2 to 9 away_summary records, one per time Jess
          # came back, and the most recent describes the most work. (The ticket
          # says "the record", singular — measurement says otherwise.)
          facts[:recap] = strip_recap_tail(rec["content"]) if rec["content"]
        elsif facts[:first_prompt].nil? && line.include?(USER_HINT) &&
              line.bytesize <= MAX_PROMPT_BYTES
          rec ||= parse(line) or next
          facts[:cwd] ||= rec["cwd"]
          facts[:first_prompt] = first_prompt_of(rec)
        end
      end

      facts
    end

    # A log being written to right now can end mid-line, and old logs have held
    # rarities we've never seen; one bad line is not worth failing a listing over.
    def parse(line)
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end

    # The context actually sent on that turn: fresh tokens, tokens written to
    # cache, and tokens read back from it — the same sum Parser's
    # `tokens["context"]` uses, so the two can't disagree.
    #
    # The TRUE MAX over all assistant records, not the last one. It's free (the
    # pass reads the whole file anyway for turns, title and recap), and it can
    # only be more honest: zero `isCompactSummary` records exist across all 416
    # logs, so nothing has ever been dropped from a context, and on the sample
    # log the last record's total (76,597) was exactly the max.
    def context_of(usage)
      return 0 unless usage

      usage["input_tokens"].to_i +
        usage["cache_creation_input_tokens"].to_i +
        usage["cache_read_input_tokens"].to_i
    end

    # What Jess actually typed. A `type: "user"` record is also how tool
    # results, task notifications and other harness blobs arrive; the ones from
    # Jess have a plain String content that doesn't open with `<`.
    def first_prompt_of(rec)
      return nil unless rec["type"] == "user"

      content = rec.dig("message", "content")
      return nil unless content.is_a?(String)

      text = content.strip
      return nil if text.empty? || text.start_with?("<")

      text
    end

    def strip_recap_tail(text)
      text.sub(/\s*#{Regexp.escape(RECAP_TAIL)}\s*\z/, "").strip
    end

    # Subagent sidecars live in `<log dir>/<session id>/subagents/`, one
    # `agent-<id>.jsonl` plus an `agent-<id>.meta.json` each — so count the
    # logs, not the files, or every number doubles. A directory listing, so free.
    def subagent_count
      dir = File.join(File.dirname(@path), File.basename(@path, ".jsonl"), "subagents")
      Dir.glob(File.join(dir, "*.jsonl")).size
    end

    # Which project this session came from, for grouping the listing.
    #
    # Preferred source is the log's own `cwd` — every conversation record
    # carries it, so it costs nothing and is exact. The directory name is the
    # fallback, and it can only ever be a best-effort label: the harness encodes
    # a path by replacing separators with `-`, which is lossy, and
    # `-Users-jess-code-mtg-deck-shuffler` gives no way to tell a separator from
    # a hyphen in `mtg-deck-shuffler`.
    #
    # Shown relative to home when it's under home, since every one of Jess's is.
    def project_label(cwd)
      raw = cwd || decode_project_dir(File.basename(File.dirname(@path)))
      home = Dir.home
      raw.start_with?("#{home}/") ? raw.delete_prefix("#{home}/") : raw
    end

    def decode_project_dir(dir)
      encoded_home = Dir.home.tr("/", "-")
      dir.delete_prefix(encoded_home).delete_prefix("-")
    end

    # Per-session scan results on disk, keyed by path + mtime + size.
    #
    # An unchanged log is never reopened; a log that was appended to (new size,
    # new mtime) is rescanned. Every result is written THE MOMENT IT COMPLETES,
    # one file per session — never a batch flushed at the end — so a crash
    # halfway through a cold 621 MB scan keeps everything already done, and
    # nothing holds 50 scans in memory at once.
    class Cache
      def initialize(dir = CACHE_DIR)
        @dir = dir
        @hits = 0
        @misses = 0
      end

      attr_reader :dir, :hits, :misses

      # Yields the path on a miss and expects the scan hash back; stores it
      # before returning. On a hit the log is not opened at all — only `stat`ed.
      def fetch(path)
        path = File.expand_path(path)
        if (hit = read(path))
          @hits += 1
          return hit
        end

        @misses += 1
        result = yield path
        write(path, result)
        result
      end

      def read(path)
        file = file_for(path)
        return nil unless File.exist?(file)

        entry = JSON.parse(File.read(file))
        return nil unless fresh?(entry, path)

        entry["scan"]
      rescue JSON::ParserError, Errno::ENOENT
        nil # a truncated cache file is a miss, not a crash
      end

      def write(path, scan)
        FileUtils.mkdir_p(@dir)
        entry = { "path" => path, "mtime" => scan["mtime"],
                  "size" => scan["size"], "scan" => scan }
        # Write-then-rename so a crash mid-write can't leave a half-file that a
        # later run would have to distrust.
        tmp = "#{file_for(path)}.#{Process.pid}.tmp"
        File.write(tmp, JSON.generate(entry))
        File.rename(tmp, file_for(path))
      end

      private

      def fresh?(entry, path)
        stat = File.stat(path)
        entry["path"] == path && entry["size"] == stat.size &&
          entry["mtime"] == stat.mtime.to_f
      rescue Errno::ENOENT
        false
      end

      # The key is the path; the filename is a digest of it because a session
      # path has slashes in it. The path is stored inside the file as well, so a
      # digest collision reads as a miss rather than as another log's numbers.
      def file_for(path)
        File.join(@dir, "#{Digest::SHA256.hexdigest(path)[0, 24]}.json")
      end
    end
  end
end
