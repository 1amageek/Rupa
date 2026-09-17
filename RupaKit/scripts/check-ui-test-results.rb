#!/usr/bin/env ruby
require 'json'

def verify_ui_test_results(tree, requested)
  nodes = []
  visit = lambda do |node|
    nodes << node
    (node['children'] || []).each { |child| visit.call(child) }
  end
  (tree['testNodes'] || []).each { |node| visit.call(node) }
  raise 'Empty or duplicate test selection' if requested.empty? || requested.uniq != requested
  raise 'A test failed or was skipped' if nodes.any? { |n| n['result'] && n['result'] != 'Passed' }
  cases = nodes.select { |n| n['nodeType'] == 'Test Case' }
  raise 'Missing passing outcome' unless cases.all? { |n| n['result'] == 'Passed' }
  actual = cases.map { |n| n.fetch('nodeIdentifier') }.sort
  raise "Executed tests differ from requested tests: #{actual.inspect}" unless actual == requested.sort
  actual.count
end

if $PROGRAM_NAME == __FILE__
  if ARGV == ['--self-test']
    passing = {'testNodes' => [{'nodeType' => 'Test Case', 'nodeIdentifier' => 'sample()', 'result' => 'Passed'}]}
    raise unless verify_ui_test_results(passing, ['sample()']) == 1
    rejected = [{}, passing, {'testNodes' => [passing['testNodes'][0].merge('result' => 'Skipped')]},
                {'testNodes' => [passing['testNodes'][0].reject { |key, _| key == 'result' }]}]
    rejected.each_with_index do |tree, index|
      refused = false
      begin
        verify_ui_test_results(tree, index == 1 ? ['missing()'] : ['sample()'])
      rescue RuntimeError
        refused = true
      end
      raise 'Invalid evidence was accepted' unless refused
    end
    puts 'Result validation rejects empty, missing, skipped and incomplete test evidence.'
  else
    target = ARGV.shift
    requested = ARGV.map { |id| id.delete_prefix("-only-testing:#{target}/") }
    puts "Passed: #{verify_ui_test_results(JSON.parse(STDIN.read), requested)} requested test functions."
  end
end
