module Dynflow
  module ActiveJob
    # TODO - hook into ActiveJob serializers one moving to ActiveJob 6
    class ActiveJobSerializer # < ::ActiveJob::Serializers::ObjectSerializer
      def serialize(value)
        # we need to convert to JSON because the ActiveJob doesn't support symbols
        # See https://github.com/rails/rails/issues/25993. Should be fixed in ActiveJob 6
        Dynflow.serializer.dump(value).to_json
      end

      def deserialize(json)
        val = JSON.parse(json)
        val = Utils::IndifferentHash.new(val) if val.is_a? Hash
        Dynflow.serializer.load(val)
      end
    end

    # we should not need this anymore in ActiveJob 6 thanks to
    # https://github.com/rails/rails/commit/e360ac12315
    module SerializationExtension
      def perform(*args)
        serializer = ActiveJobSerializer.new
        args = args.map { |a| serializer.deserialize(a) }
        super(*args)
      end
    end

    # Common job for all the internal jobs for performing Dynflow actions
    class DynflowInternalJob < ::ActiveJob::Base
      def self.perform_later(*args)
        serializer = ActiveJobSerializer.new
        args = args.map { |a| serializer.serialize(a) }
        super(*args)
      end

      def self.inherited(klass)
        klass.prepend(SerializationExtension)
      end
    end
  end
end
