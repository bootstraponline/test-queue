require 'test_queue/runner'
require 'rspec/core'

case ::RSpec::Core::Version::STRING.to_i
when 2
  require_relative 'rspec2'
when 3
  require_relative 'rspec3'
else
  fail 'requires rspec version 2 or 3'
end

module TestQueue
  class Runner
    class RSpec < Runner
      def initialize
        # Require spec helper immediately
        require File.join(::RSpec::Core::RubyProject.root,  'spec', 'spec_helper')
        super(TestFramework::RSpec.new)
      end

      def run_worker(iterator)
        rspec = ::RSpec::Core::QueueRunner.new
        # Save worker return value so we can exit in cleanup_worker
        @run_worker_exit_code = rspec.run_each(iterator).to_i
      end

      def summarize_worker(worker)
        worker.summary  = worker.lines.grep(/ examples?, /).first
        worker.failure_output = worker.output[/^Failures:\n\n(.*)\n^Finished/m, 1]
      end

      # clean exit to make sure at_exit {} hooks run (used by simplecov)
      # test-queue will invoke exit! by default which doesn't run at_exit
      # https://github.com/instructure/canvas-lms/blob/039207c04faa67503633e4caf554dbc49cc78549/script/rspec-queue#L43
      def summarize
        estatus = @completed.inject(0) { |s, worker| s + (worker.status.exitstatus || 1) }
        estatus = [estatus, 255].min
        exit estatus
      end

      # set env number for simplecov
      def after_fork(num)
        ENV['TEST_ENV_NUMBER'] = num > 1 ? num.to_s : ''
      end

      # clean exit to make sure at_exit {} hooks run (used by simplecov)
      def cleanup_worker
        Kernel.exit @run_worker_exit_code || 0
      end
    end
  end

  class TestFramework
    class RSpec < TestFramework
      def all_suite_files
        options = ::RSpec::Core::ConfigurationOptions.new(ARGV)
        options.parse_options if options.respond_to?(:parse_options)
        options.configure(::RSpec.configuration)

        ::RSpec.configuration.files_to_run.uniq
      end

      def suites_from_file(path)
        ::RSpec.world.example_groups.clear
        load path
        split_groups(::RSpec.world.example_groups).map { |example_or_group|
          name = if example_or_group.respond_to?(:id)
                   example_or_group.id
                 elsif example_or_group.respond_to?(:full_description)
                   example_or_group.full_description
                 elsif example_or_group.metadata.key?(:full_description)
                   example_or_group.metadata[:full_description]
                 else
                   example_or_group.metadata[:example_group][:full_description]
                 end
          [name, example_or_group]
        }
      end

      private

      def split_groups(groups)
        return groups unless split_groups?

        groups_to_split, groups_to_keep = [], []
        groups.each do |group|
          (group.metadata[:no_split] ? groups_to_keep : groups_to_split) << group
        end
        queue = groups_to_split.flat_map(&:descendant_filtered_examples)
        queue.concat groups_to_keep
        queue
      end

      def split_groups?
        return @split_groups if defined?(@split_groups)
        @split_groups = ENV['TEST_QUEUE_SPLIT_GROUPS'] && ENV['TEST_QUEUE_SPLIT_GROUPS'].strip.downcase == 'true'
      end
    end
  end
end
