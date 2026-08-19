# frozen_string_literal: true
#
# The pipeline is two SEPARATE PROGRAMS — bin/parse and bin/render — that share
# nothing at runtime except the intermediate story.yaml on disk. This Rakefile
# is only the task runner: it knows the dependency (a page needs its story.yaml,
# which needs its log) and shells out to each program in its own process.
#
#   rake parse    bin/parse:  examples/<name>.jsonl -> out/<name>/story.yaml
#   rake render   bin/render: out/<name>/story.yaml -> out/<name>/index.html
#   rake site     bin/site-index: out/*/story.yaml -> out/index.html (landing)
#   rake build    parse then render then site, dependency-ordered
#   rake serve    serve out/ on :8080
#   rake test     golden-fixture tests
#
# Default is ALL examples. Scope to one with LOG= :
#   LOG=examples/episode-8-before.jsonl rake build
#   PORT=9000 rake serve

LOGS = ENV["LOG"] ? FileList[ENV["LOG"]] : FileList["examples/*.jsonl"]

# Source files each program is built from. Listing them as prerequisites means
# editing the parser/renderer/templates/assets re-runs the affected phase — the
# output depends on the code, not just the story.yaml on disk.
PARSE_SRC  = FileList["bin/parse", "lib/conversation_story/parser.rb",
                      "lib/conversation_story/edits.rb"]
RENDER_SRC = FileList["bin/render", "lib/conversation_story/renderer.rb",
                      "lib/conversation_story/markdown.rb",
                      "lib/conversation_story/templates/*.erb",
                      "assets/**/*", "images/**/*"]
SITE_SRC   = FileList["bin/site-index", "lib/conversation_story/renderer.rb"]
# The import door — bin/grab-example, and (ticket 04) bin/importer — over the
# shared ConversationStory::Import. Deliberately NOT a prerequisite of parse or
# render: neither program requires import.rb, so making it one would re-parse
# every example whenever the copy logic changed. It's a *_SRC list so the file is
# named here (session 25's follow-through) and so the importer's own task, when
# it arrives, has the list already written.
IMPORT_SRC = FileList["bin/grab-example", "lib/conversation_story/import.rb"]

# DELIBERATELY NOT LISTED: lib/conversation_story/session_scan.rb. These lists
# exist so a page is rebuilt when the code that PRODUCED it changes, and the
# session scanner produces nothing in out/ — it reads Jess's ~/.claude*/projects
# logs for the importer's listing page. Adding it here would re-parse and
# re-render every example (and dirty the committed out/) every time the scanner
# is touched, for no change in output. The importer's own files belong to
# whatever task runs the importer, not to build.

SITE_INDEX = "out/index.html"

def name_for(log)  = File.basename(log, ".jsonl")
def story_for(log) = File.join("out", name_for(log), "story.yaml")
def page_for(log)  = File.join("out", name_for(log), "index.html")

stories = []
pages   = []

LOGS.each do |log|
  story   = story_for(log)
  page    = page_for(log)
  out_dir = File.dirname(story)
  stories << story
  pages   << page

  directory out_dir

  # bin/parse: log -> intermediate YAML. Re-runs when the log, the parser, or
  # the story's hand-written summaries change. The edits file is a prerequisite
  # only when it exists — an absent one has no mtime to compare against, and
  # the first one is written by bin/serve, which re-runs the pipeline itself.
  # A subagent's own log is an input too — bin/parse inlines those events as the
  # nested story under the Agent call that spawned them — so the story is stale
  # if any of them changes, not just the main log.
  edits = File.join("edits", "#{name_for(log)}.yaml")
  subagent_logs = FileList[File.join("examples", name_for(log), "subagents", "*.jsonl")]
  file story => [log, out_dir, *subagent_logs, *PARSE_SRC,
                 *(File.exist?(edits) ? [edits] : [])] do
    sh "ruby", "bin/parse", log, "-o", story
  end

  # bin/render: YAML -> page. Depends on the YAML, so asking for the page runs
  # bin/parse first when the story is missing or stale. That's the dependency
  # the Rakefile owns; the two programs never call each other. Also depends on
  # the renderer/templates/assets so a design edit re-renders.
  file page => [story, *RENDER_SRC] do
    sh "ruby", "bin/render", story, "-o", page
  end
end

desc "Parse logs into intermediate story.yaml (LOG=path to scope to one)"
task parse: stories

desc "Render story.yaml into index.html (runs parse first when needed)"
task render: pages

# The landing page at the SITE ROOT. Unlike the per-story tasks above this one
# isn't scoped by LOG= : it lists every story present in out/, because that's
# what a visitor arriving at the root should see. It depends on the stories'
# YAML (the contract it reads) and on its own source.
file SITE_INDEX => [*stories, *SITE_SRC] do
  sh "ruby", "bin/site-index", "out"
end

desc "Write the site-root landing page listing every built story"
task site: SITE_INDEX

desc "Parse then render then write the landing page"
task build: %i[render site]

desc "Serve out/ locally with summary editing enabled (PORT=8080 by default)"
task :serve do
  # bin/serve, not `ruby -run -e httpd`: it serves the same static out/ AND
  # accepts summary edits from the page, writing them to edits/<name>.yaml and
  # re-running bin/parse + bin/render. Localhost only; the published site has
  # no write path.
  sh "ruby", "bin/serve", "-p", ENV.fetch("PORT", "8080")
end

desc "Run the golden-fixture tests"
task :test do
  sh "ruby", "-Ilib", "-Itest", "-e", 'Dir.glob("test/**/*_test.rb").each { |f| require "./#{f}" }'
end

task default: :test
