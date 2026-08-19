# frozen_string_literal: true

require "fileutils"

module ConversationStory
  # The one door into `examples/`. Two jobs, both of them about files on disk:
  #
  #   DISCOVERY — what session logs does this machine have? (`Import.sessions`)
  #   COPY      — put one of them in examples/ under a name (`Import.copy`)
  #
  # Both `bin/grab-example` (the CLI door) and `bin/importer` (the browser one)
  # call this, so the two can't drift — session 25, decision 9.
  #
  # Copy takes a session log **PATH**, never a session id it re-derives from the
  # current repo. Deriving was the bug: `bin/grab-example` looked only in *this*
  # repo's project dir, so a session from another project (mtg-tabletop-plan) had
  # to be copied in by hand.
  #
  # A fixture is a main log plus, if the session delegated, its subagent
  # sidecars:
  #
  #   examples/<name>.jsonl
  #   examples/<name>/subagents/agent-<id>.jsonl + .meta.json
  #
  # The parser finds the sidecars by that layout (agent ids are in the
  # filenames), so this is a straight copy — no rewriting.
  module Import
    EXAMPLES_DIR = File.expand_path("../../examples", __dir__)

    # Where the harness keeps session logs. NOT `~/.claude/projects`, which is
    # what grab-example used to read and is empty (in fact not even a directory)
    # on this machine — Jess runs two configs, work and personal, and a session
    # can be in either. `CLAUDE_CONFIG_DIR` in the environment names only the one
    # the *current* agent is running under, so it can't stand in for this list.
    CONFIG_DIRS = [
      File.join(Dir.home, ".claude-work"),
      File.join(Dir.home, ".claude-personal"),
    ].freeze

    # A name that can become a filename: the rule grab-example has always
    # enforced, and the one the importer's name field validates against too.
    SLUG = /\A[a-z0-9]+(-[a-z0-9]+)*\z/

    # A log written to this recently is still being appended to, so a fixture
    # taken from it ends wherever the log happened to be. grab-example warns;
    # the importer flags the card "live". Same threshold, one constant.
    LIVE_SECONDS = 120

    # One discovered session log. Path-first: everything a caller needs to copy
    # it, plus the project it came from so a listing can group by that.
    #
    # `project` is a *display* name and `path` is the truth. The project
    # directory encodes the project's path by replacing every "/" with "-", which
    # is lossy — `-Users-jessitron-code-jessitron-conversation-story` could
    # decode back to a dozen paths (every dash is either a real dash or a
    # slash), and the ".claude" in a worktree's path shows up as a doubled dash.
    # So we don't decode: we only trim the boilerplate head (the home directory,
    # then a leading "code"), which leaves
    # "jessitron-conversation-story" — recognisable without pretending to be a
    # path.
    HOME_PREFIX = Dir.home.tr("/", "-")

    Session = Struct.new(:path, :id, :project_dir, :config_dir, keyword_init: true) do
      def project
        File.basename(project_dir).delete_prefix(HOME_PREFIX).delete_prefix("-code").delete_prefix("-")
      end

      # "work" / "personal" — which config the session lived under.
      def config = File.basename(config_dir).delete_prefix(".claude").delete_prefix("-")

      def size  = File.size(path)
      def mtime = File.mtime(path)
      def live? = mtime > Time.now - LIVE_SECONDS

      # The session's subagent sidecar directory, or nil if it delegated nothing.
      def subagents_dir
        dir = File.join(File.dirname(path), id, "subagents")
        dir if Dir.exist?(dir)
      end
    end

    class Error < StandardError; end

    class << self
      # Every session log on this machine, across both config dirs and ALL
      # projects, newest first. Sorting here rather than in the callers means
      # `--list` and the importer's "50 most recent" agree on what recent means.
      def sessions(config_dirs: CONFIG_DIRS)
        config_dirs.flat_map { |config_dir| sessions_in(config_dir) }
                   .sort_by { |session| -session.mtime.to_i }
      end

      # Resolve a bare session id to its log. Discovery is global now, so an id
      # is no longer scoped to one project directory — and the same conversation
      # id could in principle sit under two projects (a session that got
      # relocated), which is worth saying out loud rather than picking one.
      def find(id, config_dirs: CONFIG_DIRS)
        found = sessions(config_dirs: config_dirs).select { |session| session.id == id }
        raise Error, "no session log with id #{id}" if found.empty?

        if found.size > 1
          raise Error, "session id #{id} is ambiguous — #{found.size} logs:\n" +
                       found.map { |s| "  #{s.path}" }.join("\n")
        end

        found.first
      end

      # Copy a session log into examples/ under `name`. The main log is written
      # whole and the sidecars are MERGED into place rather than replacing the
      # directory: a subagent that finished after an earlier snapshot is a new
      # file, and nothing in the old ones changed.
      #
      # @param log [String] path to the session's .jsonl
      # @param name [String] fixture name, a SLUG
      # @return [Hash] what landed: :path, :lines, :size, :subagents
      def copy(log, name, examples_dir: EXAMPLES_DIR)
        raise Error, "name should be a slug like `mode-switches`, got #{name.inspect}" unless name.match?(SLUG)
        raise Error, "no such session log: #{log}" unless File.exist?(log)

        FileUtils.mkdir_p(examples_dir)
        dest = File.join(examples_dir, "#{name}.jsonl")
        FileUtils.cp(log, dest)

        { path: dest,
          lines: File.foreach(dest).count,
          size: File.size(dest),
          subagents: copy_sidecars(log, name, examples_dir) }
      end

      # True when examples/<name>.jsonl is already this log, byte-count for
      # byte-count. Only the caller knows whether that means "nothing to do"
      # (grab-example) or "re-snapshot anyway, the sidecars may have grown"
      # (the importer), so this answers the question and decides nothing.
      def same_snapshot?(log, name, examples_dir: EXAMPLES_DIR)
        dest = File.join(examples_dir, "#{name}.jsonl")
        File.exist?(dest) && File.size(dest) == File.size(log)
      end

      private

      # A config dir holds one directory per project; each holds the project's
      # session logs, plus a same-named directory of sidecars per session.
      def sessions_in(config_dir)
        projects = File.join(config_dir, "projects")
        return [] unless Dir.exist?(projects)

        Dir.glob(File.join(projects, "*", "*.jsonl")).map do |path|
          Session.new(path: path,
                      id: File.basename(path, ".jsonl"),
                      project_dir: File.dirname(path),
                      config_dir: config_dir)
        end
      end

      # Sidecars live next to the main log in a directory named for the session,
      # and the session id is the log's basename — so this works from the path
      # alone, whether the caller had a Session or just a filename.
      def copy_sidecars(log, name, examples_dir)
        source = File.join(File.dirname(log), File.basename(log, ".jsonl"), "subagents")
        return 0 unless Dir.exist?(source)

        target = File.join(examples_dir, name, "subagents")
        FileUtils.mkdir_p(target)
        FileUtils.cp_r(Dir.glob(File.join(source, "*")), target)
        Dir.glob(File.join(target, "*.jsonl")).size
      end
    end
  end
end
