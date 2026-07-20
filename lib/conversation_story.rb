# frozen_string_literal: true

# Conversation Story: turn a Claude agent conversation log into an
# explorable, pretty static web page.
#
# Pipeline: Input Logs -> Intermediate YAML -> Output HTML
#   - Parser:   jsonl (+ subagent dir) -> document (Ruby hash)
#   - Renderer: document -> static HTML via ERB
#
# See README.md for how to run, and notes/plan.md for the schema + design.
module ConversationStory
  VERSION = "0.0.1"
end

require_relative "conversation_story/parser"
require_relative "conversation_story/renderer"
