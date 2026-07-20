# frozen_string_literal: true

require "json"

module ConversationStory
  # Reads a Claude conversation log (a .jsonl file, plus its sibling directory
  # of subagent logs) and produces the intermediate "document": a Ruby hash
  # matching the schema in notes/plan.md, ready to serialize as YAML.
  #
  # The schema is the contract: known event kinds store only named fields.
  # Unrecognized records fall back to kind `unknown` with `detail.raw` kept
  # verbatim, so nothing in the log is silently lost.
  class Parser
    # @param log_path [String] path to the top-level conversation .jsonl.
    #   Subagent logs are expected in a sibling directory named after the log
    #   file's basename (without .jsonl).
    def initialize(log_path)
      @log_path = log_path
    end

    # @return [Hash] the intermediate document (YAML-serializable).
    def to_document
      raise NotImplementedError,
            "Parser#to_document: not implemented yet (Mountain 1, step 1 in notes/plan.md). " \
            "Log: #{@log_path}"
    end
  end
end
