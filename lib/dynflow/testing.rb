module Dynflow
  module Testing

    def self.logger_adapter
      LoggerAdapters::Simple.new $stdout, 0
    end

    def self.get_id
      @last_id ||= 0
      @last_id += 1
    end

    require 'dynflow/testing/mimic'
    require 'dynflow/testing/managed_clock'
    require 'dynflow/testing/dummy_world'
    require 'dynflow/testing/dummy_executor'
    require 'dynflow/testing/dummy_execution_plan'
    require 'dynflow/testing/dummy_step'
    require 'dynflow/testing/dummy_planned_action'
    require 'dynflow/testing/assertions'
    require 'dynflow/testing/factories'

    include Assertions
    include Factories
  end
end
