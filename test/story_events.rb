# frozen_string_literal: true

# Shared test helper: walk a story document's events the way the PAGE does.
#
# A document's top-level `events` list is one event per line of the main log.
# A `subagent` event carries a whole nested story (`subagent.events`, the same
# document shape recursively) and the renderer draws cards for those too, inside
# a `.subactions` block. So any test that counts cards, copy chips, Tokens
# sections or token estimates has to walk the tree, not the list.
#
# Deliberately its own little implementation, not a call into the renderer: a
# test that reuses the code under test can only confirm it agrees with itself.
module StoryEvents
  # Every event that gets a card, in card order (hidden events excluded).
  def visible_cards(document)
    flatten_visible(document["events"] || [])
  end

  private

  def flatten_visible(events)
    events.reject { |e| e["hidden"] }
          .flat_map { |e| [e, *flatten_visible(nested(e))] }
  end

  def nested(event)
    event.dig("subagent", "events") || []
  end
end
