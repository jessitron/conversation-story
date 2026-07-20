# frozen_string_literal: true

require "erb"

module ConversationStory
  # Turns an intermediate document (the hash loaded from a story.yaml) into a
  # static HTML page via ERB. The renderer reads ONLY the schema — never the
  # original log — and reproduces the look of design-prototype.html.
  class Renderer
    # @param document [Hash] the intermediate document (from YAML).
    def initialize(document)
      @document = document
    end

    # @return [String] the complete HTML page.
    def to_html
      raise NotImplementedError,
            "Renderer#to_html: not implemented yet (Mountain 1, step 2 in notes/plan.md)."
    end
  end
end
