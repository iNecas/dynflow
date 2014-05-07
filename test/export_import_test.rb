require_relative 'test_helper'
require 'fileutils'
module Dynflow
  module ExportImportTest
    describe 'export-import' do

      before do 
        @world = Dynflow::SimpleWorld.new
        @exporter = Dynflow::Exporter.new @world
      end

      let :execution_plan do
        @world.plan(Support::CodeWorkflowExample::FastCommit, 'sha' => 'abc123')
      end

      let :path do
        "testlogs"
      end

      let :ref_action do
        @world.persistence.load_action(execution_plan.steps[3]) 
      end

      describe 'execution plan export' do

        before do
          execution_plan.save
          @exporter.export_to_dir(execution_plan.id, path)
        end

        it 'creates a structure like path/execution_plan_id/plan.json' do
          assert Dir.exists?(path)
          assert Dir.exists?("#{path}/#{execution_plan.id}")
          assert File.exists?("#{path}/#{execution_plan.id}/plan.json")
        end

        it 'makes hash from db properly' do
          execution_plan_hash = execution_plan.to_hash
          exported_plan = @exporter.export_execution_plan(execution_plan.id)
          execution_plan_hash[:id].must_equal exported_plan[:id]
          execution_plan_hash[:class].must_equal exported_plan[:class]
          execution_plan_hash[:state].must_equal exported_plan[:state]
          execution_plan_hash[:started_at].must_equal exported_plan[:started_at]
          execution_plan_hash[:ended_at].must_equal exported_plan[:ended_at]
          execution_plan_hash[:execution_time].must_equal exported_plan[:execution_time]
          execution_plan_hash[:real_time].must_equal exported_plan[:real_time]
        end

        it 'plan.json contents equals json generated from execution plan' do
          expected_json = File.read("#{path}/#{execution_plan.id}/plan.json")
          generated_json = MultiJson.dump(@exporter.export_execution_plan(execution_plan.id))
          expected_json.must_equal generated_json
        end

        after do
          Dir.exists?(path) && FileUtils.rm_rf(path)
        end

      end

      describe 'action export' do

        before do
          @exporter.export_to_dir(execution_plan.id, path)
        end

        it 'exports to path/execution_plan_id/action-action_id.json' do
          assert Dir.exists?(path)
          assert Dir.exists?("#{path}/#{execution_plan.id}")
          assert File.exists?("#{path}/#{execution_plan.id}/action-#{ref_action.id}.json")
        end

        it 'makes action-#{ref_action.id}.json contents equal json generated from ref action' do
          expected_json = File.read("#{path}/#{execution_plan.id}/action-#{ref_action.id}.json")
          generated_json = MultiJson.dump(@exporter.export_action(execution_plan.id, ref_action.id))
          expected_json.must_equal generated_json
        end

        after do
          Dir.exists?(path) && FileUtils.rm_rf(path)
        end

      end

      describe 'plan import' do
        include PlanAssertions

        before do
          execution_plan.save
          @exporter.export_to_dir(execution_plan.id, path)
          @dest_world = Dynflow::SimpleWorld.new
          @importer = Dynflow::Importer.new @dest_world
          @importer.import_from_dir("#{path}/#{execution_plan.id}/")
        end

        it 'raises ActionMissing when action file is missing' do
          File.delete("#{path}/#{execution_plan.id}/action-1.json")
          proc { @importer.import_from_dir("#{path}/#{execution_plan.id}/") }.must_raise ActionMissing
        end

        it 'should not fail' do
          action_json = File.read("#{path}/#{execution_plan.id}/action-1.json")
          File.write("#{path}/#{execution_plan.id}/action-42.json", action_json)
          @importer.import_from_dir("#{path}/#{execution_plan.id}").must_be_instance_of Hash
        end

        it 'imports the plan properly' do
          dest_execution_plan = @dest_world.persistence.load_execution_plan(execution_plan.id)
          dest_execution_plan.id.must_equal execution_plan.id

          assert_steps_equal execution_plan.root_plan_step, dest_execution_plan.root_plan_step
          execution_plan.root_plan_step.action_class.must_equal dest_execution_plan.root_plan_step.action_class
          assert_equal execution_plan.steps.keys, dest_execution_plan.steps.keys

          dest_execution_plan.steps.each do |id, step|
            assert_steps_equal(step, execution_plan.steps[id])
          end
        end

        after do
          Dir.exists?(path) && FileUtils.rm_rf(path)
        end
      end
    end
  end
end
