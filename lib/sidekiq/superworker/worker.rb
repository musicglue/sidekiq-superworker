module Sidekiq
  module Superworker
    class Worker
      def self.create(*args, &block)
        class_name = args.shift.to_sym
        nested_hash = DSLParser.parse(block)
        create_class(class_name, args, nested_hash)
      end

      protected

      def self.create_class(class_name, arg_keys, nested_hash)
        klass = Class.new do
          @class_name = class_name
          @arg_keys = arg_keys
          @nested_hash = nested_hash
          @dsl_hash = DSLHash.new

          class << self
            attr_reader :nested_hash

            def is_a_superworker?
              true
            end

            def perform_async(*arg_values)
              superjob_options = {}

              # If an additional argument value is given, it's the superjob's options
              if (arg_values.length == @arg_keys.length + 1) && arg_values.last.is_a?(Hash)
                superjob_options = arg_values.last
              elsif @arg_keys.length != arg_values.length
                raise "Wrong number of arguments for #{name}.perform_async (#{arg_values.length} for #{@arg_keys.length})"
              end

              @args = Hash[@arg_keys.zip(arg_values)]
              @superjob_id = SecureRandom.hex(12)
              subjobs = create_subjobs(arg_values)
              SuperjobProcessor.create(@superjob_id, @class_name, arg_values, subjobs, superjob_options)
            end

            protected

            def create_subjobs(arg_values)
              records = @dsl_hash.nested_hash_to_records(@nested_hash, @args)
              subjobs = records.collect do |id, record|
                record[:status] = 'initialized'
                record[:superjob_id] = @superjob_id
                record[:superworker_class] = @class_name
                unless record.key?(:arg_values)
                  record[:arg_values] = record[:arg_keys].collect do |arg_key|
                    # Allow for subjob arg_values to be set within the superworker definition; if a symbol is
                    # used in the DSL, use @args[arg_key], and otherwise use arg_key as the value
                    arg_key.is_a?(Symbol) ? @args[arg_key] : arg_key
                  end
                end
                record
              end
              # Perform the inserts in a single transaction to improve the performance of large mass inserts
              Sidekiq::Superworker::Subjob.transaction do
                Sidekiq::Superworker::Subjob.create(subjobs)
              end
            end
          end
        end

        Object.const_set(class_name, klass)
      end
    end
  end
end
