require 'dynflow/executors/active_job/orchestrator_jobs'
require 'dynflow/executors/active_job/worker_jobs'

module Dynflow
  module Executors
    module ActiveJob
      class Core < Abstract::Core
        attr_reader :logger

        def initialize(world, heartbeat_interval, queues_options)
          super(world, heartbeat_interval)
          # TODO AJ: clear
          #@queues_options = queues_options
          #@pools          = {}
          #initialize_queues
        end

        # TODO AJ: clear
        # def initialize_queues
        #   default_pool_size = @queues_options[:default][:pool_size]
        #   @queues_options.each do |(queue_name, queue_options)|
        #     queue_pool_size = queue_options.fetch(:pool_size, default_pool_size)
        #     @pools[queue_name] = Pool.spawn("pool #{queue_name}", @world,
        #                                     reference, queue_name, queue_pool_size,
        #                                     @world.transaction_adapter)
        #   end
        # end

        # TODO AJ: do we need this for active job?
        def start_termination(*args)
          super
        end

        # TODO AJ: do we need this for active job?
        def finish_termination(pool_name)
          super()
        end

        # TODO AJ: needs thoughs on how to implement it
        def execution_status(execution_plan_id = nil)
          {}
        end

        def feed_pool(work_items)
          work_items.each do |new_work|
            begin
            WorkerJobs::PerformWork.perform_later(new_work)
            rescue => e
              # AJ TODO: handle serialization issues
              require 'pry'; binding.pry
            end
          end
        end

        private

        def fallback_queue
          :default
        end
      end
    end
  end
end
