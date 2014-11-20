require 'tmpdir'
require 'zlib'
require 'archive/tar/minitar'

module Dynflow
  module Web
    class Api < Sinatra::Base

      helpers Web::FilteringHelpers
      helpers Web::WorldHelpers

      get('/execution_plans') do
        # TODO: this is just quick hack to get us the API quickly
        options = HashWithIndifferentAccess.new
        options.merge!(filtering_options)
        options.merge!(pagination_options)
        options.merge!(ordering_options)

        execution_plans = world.persistence.find_execution_plans(options)

        exporter = Dynflow::Exporter.new(world)
        MultiJson.dump(execution_plans.map do |execution_plan|
                         exporter.export_execution_plan(execution_plan.id)
                       end)
      end

      get('/execution_plans/:id') do |id|
        begin
          exporter = Dynflow::Exporter.new(world)
          MultiJson.dump(exporter.export_execution_plan(id))
        rescue
          status 404
          body "Execution plan with id '#{id}' not found."
        end
      end

      get('/execution_plans/:id/actions/:action_id') do |id, action_id|
        begin
          exporter = Dynflow::Exporter.new(world)
          MultiJson.dump(exporter.export_action(id, action_id))
        rescue
          status 404
          body "Action with ID '#{action_id}' was not found in plan '#{id}'."
        end
      end

      post('/execution_plans') do
        plans = world.persistence.find_execution_plans(params).map { |plan| plan.id }
        MultiJson.dump(plans)
      end

      post('/execution_plans/add') do
        Dir.mktmpdir do |tmp|
          Dir.chdir(tmp) do
            tgz = Zlib::GzipReader.new(File.open(params['upload'][:tempfile], 'rb'))
            Archive::Tar::Minitar.unpack(tgz, '.')
            importer = Dynflow::Importer.new(world)
            begin
              importer.import_from_dir(params['upload'][:filename].gsub(/\.tar\.gz$/,''))
              status 200
            rescue Exception => e
              status 406
              body "Action files are missing"
            end
          end
        end
      end

      get('/worlds') do
        MultiJson.dump(world.persistence.find_worlds({}).map(&:to_hash))
      end

    end
  end
end
