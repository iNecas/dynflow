require 'get_process_mem'

module Dynflow
  module Watchers
    class MemoryConsumptionWatcher

      attr_reader :memory_limit, :world

      def initialize(world, memory_limit, options)
        @memory_limit = memory_limit
        @world = world
        @polling_interval = options[:polling_interval] || 10
        @memory_watcher = options[:memory_watcher] || GetProcessMem.new
        set_timer options[:initial_wait] || @polling_interval
      end

      def check_memory_state
        if @memory_watcher.bytes > @memory_limit
          # terminate the world and stop polling
          world.terminate
        else
          # memory is under the limit - keep waiting
          set_timer
        end
      end

      def set_timer(interval = @polling_interval)
        @world.clock.ping(self, interval, :check_memory_state)
      end
    end
  end
end
