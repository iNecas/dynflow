module Dynflow
  class Importer

    def initialize(world)
      @world = world
    end

    def import_from_dir(path)
      execution_plan_hash = MultiJson.load(File.read("#{path}/plan.json"), :symbolize_names => true)
      execution_plan = Dynflow::ExecutionPlan.new_from_hash(execution_plan_hash, @world, false)
      raise ActionMissing, "Action files are missing" unless all_action_files_present?(execution_plan, path)
      execution_plan.save
      each_action_file(path) do |action_file|
        action = MultiJson.load(File.read(action_file), :symbolize_names => true)
        @world.persistence.adapter.save_action(execution_plan.id, action[:id], action)
      end
      execution_plan.steps.each { |step_id, step| @world.persistence.save_step(step) }
    end

    private

    def all_action_files_present?(execution_plan, path)
      action_ids = []
      each_action_file(path) { |file| action_ids << /action-(\d+).json$/.match(file)[1].to_i }
      (execution_plan.steps.map { |_, step| step.action_id } - action_ids).count == 0
    end

    def each_action_file(path, &block)
      Dir.glob("#{path}/action-*.json", &block)
    end
  end

  class ActionMissing < StandardError
  end

end

