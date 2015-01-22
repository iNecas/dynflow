module Dynflow
  module Dispatcher
    class ExecutorDispatcher < Concurrent::Actor::Context
      include Algebrick::Matching

      def initialize(world)
        @world        = Type! world, World
      end

      private

      def on_message(message)
        match message,
            (on ~Envelope.(message: Ping) do |envelope|
               respond(envelope, Pong)
             end),
            (on ~Envelope.(message: ~Execution) do |envelope, execution|
               perform_execution(envelope, execution)
             end),
            (on ~Envelope.(message: ~Event) do |envelope, event|
               perform_event(envelope, event)
             end)
      end

      def perform_execution(envelope, execution)
        future = Concurrent::IVar.new.with_observer do |_, execution_plan, reason|
          allocation = Persistence::ExecutorAllocation[@world.id, execution_plan.id]
          @world.persistence.delete_executor_allocation(allocation)
          if reason
            respond(envelope, Failed[reason.message])
          elsif execution_plan.state == :paused && execution_plan.result == :pending
            # the execution plan was returned without reporting error
            # but marked as paused = the execution was paused due to
            # termination: retry on other executor
            @world.execute()
          else
            respond(envelope, Done)
          end
        end
        allocate_executor(execution.execution_plan_id)
        @world.executor.execute(execution.execution_plan_id, future)
        respond(envelope, Accepted)
      rescue Dynflow::Error => e
        respond(envelope, Failed[e.message])
      end

      def perform_event(envelope, event_job)
        # TODO: handle failure/result resolution
        @world.executor.event(event_job.execution_plan_id, event_job.step_id, event_job.event)
      end

      def allocate_executor(execution_plan_id)
        @world.persistence.save_executor_allocation(Persistence::ExecutorAllocation[@world.id, execution_plan_id])
      end

      def find_executor(execution_plan_id)
        @world.persistence.find_executor_for_plan(execution_plan_id) or
            raise Dynflow::Error, "Could not find an executor for execution plan #{ execution_plan_id }"
      end

      def respond(request_envelope, response)
        response_envelope = request_envelope.build_response_envelope(response, @world)
        @world.connector.send(response_envelope)
      end
    end
  end
end
