#!/usr/bin/env ruby

# Demo script showing changelog fragments functionality
# This script demonstrates how changelog fragments are processed

require_relative "../../lib/discharger/task"
require "fileutils"

puts "🚀 Changelog Fragments Demo"
puts "=" * 50

# Setup demo directory
demo_dir = __dir__
changelog_file = File.join(demo_dir, "CHANGELOG.md")
fragments_dir = File.join(demo_dir, "changelog", "unreleased")

# Show current state
puts "\n📋 Current CHANGELOG.md:"
puts "-" * 30
puts File.read(changelog_file)

puts "\n📄 Current fragment files:"
puts "-" * 30
fragment_files = Dir.glob(File.join(fragments_dir, "*.md"))
if fragment_files.empty?
  puts "No fragment files found"
else
  fragment_files.each do |file|
    filename = File.basename(file)
    puts "#{filename}:"
    puts "  #{File.read(file).strip}"
  end
end

puts "\n⚙️  Processing changelog fragments..."
puts "-" * 30

# Create and configure Discharger task
task = Discharger::Task.new
task.changelog_file = changelog_file
task.changelog_fragments_dir = fragments_dir
task.changelog_fragments_enabled = true

# Process the fragments
task.process_changelog_fragments

puts "\n📋 Updated CHANGELOG.md:"
puts "-" * 30
puts File.read(changelog_file)

puts "\n📄 Remaining fragment files:"
puts "-" * 30
remaining_files = Dir.glob(File.join(fragments_dir, "*.md"))
if remaining_files.empty?
  puts "✅ All fragment files were processed and removed"
else
  remaining_files.each do |file|
    puts File.basename(file)
  end
end

puts "\n🎉 Demo completed!"
puts "=" * 50
puts
puts "Key features demonstrated:"
puts "• Fragment files are named: {section}.{summary}.md"
puts "• Content is organized by changelog sections"
puts "• Bullets are automatically added if missing"
puts "• Fragments are inserted into the 'Unreleased' section"
puts "• Fragment files are deleted after processing"
puts
puts "To restore the demo, run:"
puts "  git checkout examples/changelog_fragments_demo/"
