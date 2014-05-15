require 'fileutils'
module Dynflow
  class Exporter

    def initialize(world)
      @world = world
    end

    def export_execution_plan(execution_plan_id)
      execution_plan = @world.persistence.load_execution_plan(execution_plan_id)
      execution_plan_hash = execution_plan.to_hash
      execution_plan_hash.tap do |eph|
        eph[:steps] = execution_plan.steps.map { |_, step| step.to_hash }
      end
    end

    def export_action(execution_plan_id, action_id)
      @world.persistence.adapter.load_action(execution_plan_id, action_id).to_hash
    end

    def export_to_dir(execution_plan_id, dir)
      path = "#{dir}/#{execution_plan_id}"
      execution_plan_hash = export_execution_plan(execution_plan_id)
      FileUtils.mkdir_p(path) unless Dir.exists?(path)
      File.write("#{path}/plan.json", MultiJson.dump(execution_plan_hash))
      execution_plan_hash[:steps].each do |step|
        action_hash = export_action(execution_plan_hash[:id], step[:action_id])
        File.write("#{path}/action-#{action_hash['id']}.json", MultiJson.dump(action_hash))
      end
    end
  end
end
