# frozen_string_literal: true
#
# The pipeline is two SEPARATE PROGRAMS — bin/parse and bin/render — that share
# nothing at runtime except the intermediate story.yaml on disk. This Rakefile
# is only the task runner: it knows the dependency (a page needs its story.yaml,
# which needs its log) and shells out to each program in its own process.
#
#   rake parse    bin/parse:  examples/<name>.jsonl -> out/<name>/story.yaml
#   rake render   bin/render: out/<name>/story.yaml -> out/<name>/index.html
#   rake build    parse then render, dependency-ordered
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
PARSE_SRC  = FileList["bin/parse", "lib/conversation_story/parser.rb"]
RENDER_SRC = FileList["bin/render", "lib/conversation_story/renderer.rb",
                      "lib/conversation_story/markdown.rb",
                      "lib/conversation_story/templates/*.erb",
                      "assets/**/*", "images/**/*"]

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

  # bin/parse: log -> intermediate YAML. Re-runs when the log or parser changes.
  file story => [log, out_dir, *PARSE_SRC] do
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

desc "Parse then render"
task build: :render

desc "Serve out/ as a static site (PORT=8080 by default)"
task :serve do
  port = ENV.fetch("PORT", "8080")
  puts "Serving out/ at http://localhost:#{port}  (Ctrl-C to stop)"
  sh "ruby", "-run", "-e", "httpd", "out", "-p", port
end

desc "Run the golden-fixture tests"
task :test do
  sh "ruby", "-Ilib", "-Itest", "-e", 'Dir.glob("test/**/*_test.rb").each { |f| require "./#{f}" }'
end

task default: :test
