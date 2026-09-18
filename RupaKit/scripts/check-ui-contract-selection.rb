#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks the UI contract manifest against the sources it names, before any
# batch is built. A renamed, moved or deleted test otherwise reaches the runner
# as a result that never arrives, minutes into a run.

SUPPORTED_TARGETS = %w[RupaUIPackageTests RupaRenderingTests].freeze

TYPE_DECLARATION = /\b(?:struct|class|enum|actor|extension)\s+([A-Za-z_][A-Za-z0-9_]*)/.freeze
FUNCTION_START = /\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^>]*>)?\s*\(/.freeze

# Swift Testing names a test by its argument labels, so the manifest carries
# them and a signature split across lines has to be read whole.
def argument_labels(parameters)
  depth = 0
  fields = [+""]
  parameters.each_char do |character|
    case character
    when "(", "[", "<" then depth += 1
    when ")", "]", ">" then depth -= 1
    end
    if character == "," && depth.zero?
      fields << +""
    else
      fields.last << character
    end
  end
  fields.map(&:strip).reject(&:empty?).map do |field|
    field[/\A([A-Za-z_][A-Za-z0-9_]*|_)/, 1]
  end
end

def test_identifier(name, parameters)
  labels = argument_labels(parameters)
  "#{name}(#{labels.map { |label| "#{label}:" }.join})"
end

# Returns every declared test as "<suite>/<identifier>", or "<identifier>" at
# file scope, matching the shape the manifest uses.
def declared_tests(root)
  declarations = []
  Dir.glob(File.join(root, "**", "*.swift")).sort.each do |path|
    suites = []
    depth = 0
    pending_test = false
    signature = nil
    File.foreach(path) do |raw|
      # Braces and parens inside comments or string literals must not move the
      # scope or close a signature.
      line = raw.sub(%r{//.*\z}, "").gsub(/"(?:\\.|[^"\\])*"/, '""').strip

      if signature
        signature[:text] << " " << line
        signature[:depth] += line.count("(") - line.count(")")
        if signature[:depth] <= 0
          parameters = signature[:text][/\((.*)\)/m, 1].to_s
          identifier = test_identifier(signature[:name], parameters)
          declarations << (signature[:suite] ? "#{signature[:suite]}/#{identifier}" : identifier)
          signature = nil
        end
        depth += line.count("{") - line.count("}")
        suites.pop while !suites.empty? && depth <= suites.last[1]
        next
      end

      function_match = FUNCTION_START.match(line)
      is_test = line.include?("@Test")

      if function_match && (is_test || pending_test)
        remainder = line[function_match.end(0) - 1..-1]
        signature = {
          name: function_match[1],
          suite: suites.empty? ? nil : suites.last[0],
          text: +remainder,
          depth: remainder.count("(") - remainder.count(")")
        }
        pending_test = false
        if signature[:depth] <= 0
          parameters = signature[:text][/\((.*)\)/m, 1].to_s
          identifier = test_identifier(signature[:name], parameters)
          declarations << (signature[:suite] ? "#{signature[:suite]}/#{identifier}" : identifier)
          signature = nil
        end
      elsif is_test && !function_match
        pending_test = true
      elsif function_match
        pending_test = false
      end

      opened = line.count("{")
      closed = line.count("}")
      # An attribute may precede the keyword, so the name is read from anywhere
      # on a line that opens a scope.
      type_name = line[TYPE_DECLARATION, 1]
      suites.push([type_name, depth]) if type_name && opened > closed
      depth += opened - closed
      suites.pop while !suites.empty? && depth <= suites.last[1]
    end
  end
  declarations
end

def check(manifest_path, tests_root)
  identifiers = File.readlines(manifest_path).map(&:strip).reject(&:empty?)
  problems = []

  identifiers.group_by { |identifier| identifier }
             .select { |_, entries| entries.length > 1 }
             .keys.sort
             .each { |identifier| problems << "listed more than once: #{identifier}" }

  declared = {}
  identifiers.group_by { |identifier| identifier.split("/").first }.each_key do |target|
    unless SUPPORTED_TARGETS.include?(target)
      problems << "target is not one this entry point runs: #{target}"
      next
    end
    declared[target] = declared_tests(File.join(tests_root, target))
  end

  identifiers.uniq.each do |identifier|
    parts = identifier.split("/")
    target = parts.first
    next unless declared.key?(target)

    selector = parts.drop(1).join("/")
    next if declared[target].include?(selector)

    name = selector.split("/").last.sub(/\(.*\z/, "")
    elsewhere = declared[target].select do |entry|
      entry.split("/").last.sub(/\(.*\z/, "") == name
    end
    problems << if elsewhere.empty?
                  "no test declares #{name} in #{target}: #{identifier}"
                else
                  "#{name} is declared as #{elsewhere.join(", ")}: #{identifier}"
                end
  end

  problems
end

def self_test
  require "tmpdir"
  require "fileutils"

  Dir.mktmpdir do |root|
    target_root = File.join(root, "RupaRenderingTests")
    FileUtils.mkdir_p(target_root)
    File.write(File.join(target_root, "Fixture.swift"), <<~SWIFT)
      import Testing

      @Test func fileScopedContract() throws {
          #expect(Bool(true))
      }

      @Suite struct SuiteFixture {
          @Test(.timeLimit(.minutes(1)))
          func suiteScopedContract() throws {
              let brace = "{"
              #expect(brace == "{")
          }

          @Test(arguments: [true, false])
          func parameterizedContract(
              _ value: Bool,
              labelled second: Bool = true
          ) throws {
              #expect(value || second)
          }
      }

      extension SuiteFixture {
          // A retired name lives on in comments: func retiredContract()
          @Test func extendedContract() throws {
              #expect(Bool(true))
          }
      }
    SWIFT

    accepted = File.join(root, "accepted.txt")
    File.write(accepted, <<~LIST)
      RupaRenderingTests/fileScopedContract()
      RupaRenderingTests/SuiteFixture/suiteScopedContract()
      RupaRenderingTests/SuiteFixture/parameterizedContract(_:labelled:)
      RupaRenderingTests/SuiteFixture/extendedContract()
    LIST
    rejected_consistent = check(accepted, root)
    raise "a consistent manifest was rejected: #{rejected_consistent.join("; ")}" unless rejected_consistent.empty?

    {
      "an unsupported target was accepted" => "RupaCoreTests/fileScopedContract()\n",
      "an undeclared test was accepted" => "RupaRenderingTests/retiredContract()\n",
      "a wrong suite was accepted" => "RupaRenderingTests/OtherSuite/suiteScopedContract()\n",
      "a file-scope claim for a suite test was accepted" =>
        "RupaRenderingTests/suiteScopedContract()\n",
      "wrong argument labels were accepted" =>
        "RupaRenderingTests/SuiteFixture/parameterizedContract(_:)\n",
      "a duplicate was accepted" =>
        "RupaRenderingTests/fileScopedContract()\nRupaRenderingTests/fileScopedContract()\n"
    }.each do |failure, body|
      rejected = File.join(root, "rejected.txt")
      File.write(rejected, body)
      raise failure if check(rejected, root).empty?
    end
  end

  puts "Selection validation rejects unknown targets, undeclared tests, " \
       "misplaced suites, wrong argument labels and duplicates."
end

if ARGV.first == "--self-test"
  self_test
  exit 0
end

Dir.chdir(File.expand_path("..", __dir__))
problems = check("scripts/ui-contract-tests.txt", "Tests")
if problems.empty?
  puts "Every selected identifier names a test the sources declare."
  exit 0
end

warn "The UI contract manifest does not match the sources:"
problems.each { |problem| warn "  #{problem}" }
exit 1
