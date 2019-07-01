module Dynflow
  module Executors
    module ActiveJob
      module WorkerJobs
        class PerformWork < Dynflow::ActiveJob::DynflowInternalJob
          queue_as :dynflow_worker

          def perform(work_item)
            Executors.run_user_code do
              work_item.execute
            end
          rescue Errors::PersistenceError => e
            ActiveJob::OrchestratorJobs::HandlePersistenceError.perform_later(e, work_item)
          ensure
            # TODO AJ: get telemetry back
            # Dynflow::Telemetry.with_instance { |t| t.increment_counter(:dynflow_worker_events, 1, @telemetry_options) }
            ActiveJob::OrchestratorJobs::WorkerDone.perform_later(work_item)
          end
        end
      end
    end
  end
end
