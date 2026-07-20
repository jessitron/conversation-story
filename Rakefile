# frozen_string_literal: true

# Phases of the pipeline, as named tasks. Run `rake -T` to list them.
#
#   rake parse   examples/*.jsonl        -> out/<name>/story.yaml
#   rake render  out/*/story.yaml        -> out/<name>/index.html
#   rake build   parse then render
#   rake serve   serve out/ on :8080
#   rake test    golden-fixture tests
#
# Default is ALL examples. Override for one-offs with env vars:
#   LOG=examples/episode-8-before.jsonl rake parse
#   NAME=episode-8-before rake render
#   PORT=9000 rake serve

require "yaml"
require "fileutils"

require_relative "lib/conversation_story"

EXAMPLES_DIR = "examples"
OUT_DIR      = "out"

# The example name (basename without .jsonl) for a given log path.
def name_for(log_path)
  File.basename(log_path, ".jsonl")
end

# Logs to process: LOG=… for one, otherwise every examples/*.jsonl.
def logs_to_parse
  return [ENV["LOG"]] if ENV["LOG"]

  Dir.glob(File.join(EXAMPLES_DIR, "*.jsonl")).sort
end

# story.yaml files to render: NAME=… for one, otherwise every out/*/story.yaml.
def stories_to_render
  return [File.join(OUT_DIR, ENV["NAME"], "story.yaml")] if ENV["NAME"]

  Dir.glob(File.join(OUT_DIR, "*", "story.yaml")).sort
end

desc "Parse conversation logs into intermediate story.yaml (LOG=path for one)"
task :parse do
  logs = logs_to_parse
  abort "No logs found in #{EXAMPLES_DIR}/*.jsonl" if logs.empty?

  logs.each do |log_path|
    name = name_for(log_path)
    dest_dir = File.join(OUT_DIR, name)
    dest = File.join(dest_dir, "story.yaml")
    FileUtils.mkdir_p(dest_dir)

    document = ConversationStory::Parser.new(log_path).to_document
    File.write(dest, YAML.dump(document))
    puts "parsed  #{log_path} -> #{dest}"
  end
end

desc "Render story.yaml into index.html (NAME=example for one)"
task :render do
  stories = stories_to_render
  abort "No story.yaml found. Run `rake parse` first." if stories.empty?

  stories.each do |story_path|
    dest = File.join(File.dirname(story_path), "index.html")

    document = YAML.safe_load_file(story_path)
    html = ConversationStory::Renderer.new(document).to_html
    File.write(dest, html)
    puts "rendered #{story_path} -> #{dest}"
  end
end

desc "Parse then render (LOG=/NAME= to scope to one example)"
task build: %i[parse render]

desc "Serve out/ as a static site (PORT=8080 by default)"
task :serve do
  port = ENV.fetch("PORT", "8080")
  puts "Serving #{OUT_DIR}/ at http://localhost:#{port}  (Ctrl-C to stop)"
  sh "ruby", "-run", "-e", "httpd", OUT_DIR, "-p", port
end

desc "Run the golden-fixture tests"
task :test do
  sh "ruby", "-Ilib", "-Itest", "-e", 'Dir.glob("test/**/*_test.rb").each { |f| require "./#{f}" }'
end

task default: :test
