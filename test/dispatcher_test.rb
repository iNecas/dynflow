require_relative 'test_helper'

module Dynflow
  module DispatcherTest
    describe "dispatcher" do

      let(:persistence_adapter) { WorldInstance.persistence_adapter }

      def create_world(with_executor = true)
        WorldInstance.create_world do |config|
          config.connector = connector
          config.persistence_adapter = persistence_adapter
          unless with_executor
            config.executor = false
          end
        end
      end

      def self.dispatcher_works_with_this_connector
        describe 'connector basics' do
          before do
            @executors = [executor_world]
          end

          describe 'execution passing' do
            it 'succeeds when expected' do
              result = client_world.trigger(Support::DummyExample::Dummy)
              assert_equal :success, result.finished.value.result
            end
          end

          describe 'event passing' do
            it 'succeeds when expected' do
              result = client_world.trigger(Support::DummyExample::EventedAction, :timeout => 3)
              step = wait_for do
                client_world.persistence.load_execution_plan(result.id).
                    steps_in_state(:suspended).first
              end
              client_world.event(step.execution_plan_id, step.id, 'finish')
              plan = result.finished.value
              assert_equal('finish', plan.actions.first.output[:event])
            end

            it 'fails the future when the step is not accepting events' do
              result = client_world.trigger(Support::CodeWorkflowExample::Dummy, { :text => "dummy" })
              plan   = result.finished.value
              step   = plan.steps.values.first
              future = client_world.event(plan.id, step.id, 'finish').wait
              assert future.rejected?
            end

            it 'succeeds when executor acts as client' do
              result = client_world.trigger(Support::DummyExample::ComposedAction, :timeout => 3)
              plan = result.finished.value
              assert_equal('finish', plan.actions.first.output[:event])
            end
          end
        end

        def wait_for
          30.times do
            ret = yield
            return ret if ret
            sleep 0.3
          end
          return nil
        end
      end

      def self.supports_dynamic_retry
        before do
          # mention the executors to make sure they are initialized
          @executors = [executor_world, executor_world_2]
        end

        describe 'when some executor is terminated and client is notified about the failure' do
          specify 'client passes the work to another executor' do
            triggered = client_world.trigger(Support::DummyExample::Slow, 0.5)
            sleep 0.2
            executor = wait_for do
              client_world.persistence.find_executor_for_plan(triggered.id)
            end
            first_executor = @executors.find { |e| e.id == executor.id }
            second_executor = @executors.find { |e| e.id != executor.id }
            first_executor.terminate.wait
            plan = triggered.finished.value
            assert_equal :stopped, plan.state
            assert_equal :success, plan.result
            assert_equal plan.execution_history.map { |h| [h.name, h.world_id] },
                [['start execution', first_executor.id],
                 ['terminate execution', first_executor.id],
                 ['start execution', second_executor.id],
                 ['finish execution', second_executor.id]]
          end
        end
      end

      def self.supports_world_invalidation

        describe 'world invalidation' do
          it 'removes the world from the register' do
            client_world.invalidate(executor_world.registered_world)
            worlds = client_world.persistence.find_worlds({})
            refute_includes(worlds, executor_world.registered_world)
          end

          it 'schedules the plans to be run on different executor' do
            triggered = client_world.trigger(Support::DummyExample::EventedAction)
            executor = wait_for do
              client_world.persistence.find_executor_for_plan(triggered.id)
            end
            first_executor = @executors.find { |e| e.id == executor.id }
            simulate_executor_fail(first_executor)
            second_executor = @executors.find { |e| e.id != executor.id }
            client_world.invalidate(first_executor.registered_world)
            executor = wait_for do
              allocations_filters = { world_id: second_executor.id, execution_plan_id: triggered.id }
              client_world.persistence.find_executor_allocations(filters: allocations_filters).first
            end
            client_world.event(triggered.id, 2, 'finish')
            plan = triggered.finished.value
            assert_equal :stopped, plan.state
            assert_equal :success, plan.result
            assert_equal plan.execution_history.map { |h| [h.name, h.world_id] },
                [['start execution', first_executor.id],
                 ['terminate execution', first_executor.id],
                 ['start execution', second_executor.id],
                 ['finish execution', second_executor.id]]
          end

          it 'when no executor is available, marks the plans as paused' do
            triggered = client_world.trigger(Support::DummyExample::EventedAction)
            executor = wait_for do
              client_world.persistence.find_executor_for_plan(triggered.id)
            end
            first_executor = @executors.find { |e| e.id == executor.id }
            simulate_executor_fail(first_executor)
            second_executor = @executors.find { |e| e.id != executor.id }
            second_executor.terminate.wait
            client_world.invalidate(first_executor.registered_world)
            plan = client_world.persistence.load_execution_plan(triggered.id)
            assert_equal :paused, plan.state
            assert_equal :pending, plan.result
            assert_equal plan.execution_history.map { |h| [h.name, h.world_id] },
                [['start execution', first_executor.id],
                 ['terminate execution', first_executor.id]]
          end

          def simulate_executor_fail(world)
            if Connectors::Direct === world.connector
              world.connector.stop_listening(world)
            end
          end
        end
      end

      def self.supports_ping_pong
        describe 'ping/pong' do
          it 'succeeds when the world is available' do
            ping_response = client_world.ping(executor_world.id, 0.1).wait
            assert ping_response.fulfilled?
          end

          it 'time-outs when the world is not responding' do
            executor_world.terminate.wait
            ping_response = client_world.ping(executor_world.id, 0.1).wait
            assert ping_response.rejected?
          end
        end
      end

      describe 'direct connector - all in one' do
        let(:connector) { Proc.new { |world| Connectors::Direct.new(world) } }
        let(:executor_world) { create_world }
        let(:client_world) { executor_world }

        dispatcher_works_with_this_connector
        supports_ping_pong
      end

      describe 'direct connector - multi executor multi client' do
        let(:shared_connector) { Connectors::Direct.new() }
        let(:connector) { Proc.new { |world| shared_connector.start_listening(world); shared_connector } }
        let(:executor_world) { create_world(true) }
        let(:executor_world_2) { create_world(true) }
        let(:client_world) { create_world(false) }
        let(:client_world_2) { create_world(false) }

        dispatcher_works_with_this_connector
        supports_dynamic_retry
        supports_world_invalidation
        supports_ping_pong
      end

      describe 'database connector - all in one' do
        let(:connector) { Proc.new { |world| Connectors::Database.new(world, 0.005) } }
        let(:executor_world) { create_world }
        let(:client_world) { executor_world }

        dispatcher_works_with_this_connector
        supports_ping_pong
      end

      describe 'database connector - multi executor multi client' do
        let(:connector) { Proc.new { |world| Connectors::Database.new(world, 0.005) } }
        let(:executor_world) { create_world(true) }
        let(:executor_world_2) { create_world(true) }
        let(:client_world) { create_world(false) }
        let(:client_world_2) { create_world(false) }

        dispatcher_works_with_this_connector
        supports_dynamic_retry
        supports_world_invalidation
        supports_ping_pong
      end
    end
  end
end
