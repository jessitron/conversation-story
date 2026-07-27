# frozen_string_literal: true

# Why this file exists at all, in a project that prides itself on stdlib-only:
# Ruby 4.0 dropped webrick from the bundled gems, so `rake serve` stopped
# working until someone ran `gem install webrick` by hand. That put a
# prerequisite in Jess's home directory, reproduced only by a README sentence —
# the same portability bug as an unpinned Ruby, one level up. Declaring it makes
# a fresh machine one `bundle install` away from a working `rake serve`.
#
# The Ruby version deliberately is NOT pinned here. `.tool-versions` is the one
# pin (asdf reads it); a `ruby` directive would be a second source of truth that
# could disagree with it.

source "https://rubygems.org"

# The only true runtime dependency, and only for `rake serve` / `bin/serve`.
# bin/parse, bin/render and bin/site-index remain stdlib-only (json, psych, erb
# are real default gems), which is why CI never needs to bundle install.
gem "webrick", "~> 1.9"

# rake and minitest ship WITH Ruby, but as *bundled* gems rather than default
# gems — ordinary gems that a future release could evict exactly the way 4.0
# evicted webrick. Declared so that day is a `bundle install` and not a
# debugging session.
gem "rake", "~> 13.3"

group :test do
  gem "minitest", "~> 6.0"

  # Drives a real Chrome over the DevTools Protocol, for the check scripts that
  # have to answer "what does the PAGE do" rather than "what did Ruby write":
  # bin/check-modes types at it. Pure Ruby — no Node, no Selenium server, no
  # driver binary; it talks to the Chrome that's already installed.
  gem "ferrum", "~> 0.17"
end
