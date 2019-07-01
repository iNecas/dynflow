module Dynflow
  module Executors
    module ActiveJob
      module OrchestratorJobs
        # handles resposnes about finished work form the workers
        # or some event to handle on orchestrator side
        class WorkerDone < Dynflow::ActiveJob::DynflowInternalJob
          queue_as :dynflow_orchestrator

          # @param request_envelope [Dispatcher::Request] - request to handle on orchestrator side
          #   usually to start new execution or to pass some event
          def perform(work_item)
            Dynflow.orchestrator.executor.core.tell([:work_finished, work_item])
          end
        end

        class HandlePersistenceError < Dynflow::ActiveJob::DynflowInternalJob
          queue_as :dynflow_orchestrator

          # @param request_envelope [Dispatcher::Request] - request to handle on orchestrator side
          #   usually to start new execution or to pass some event
          def perform(error, work_item)
            Dynflow.orchestrator.executor.core.tell([:handle_persistence_error, error, work])
          end
        end
      end
    end
  end
end
