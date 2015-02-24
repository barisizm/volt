require 'volt/reactive/reactive_array'
require 'volt/models/model_wrapper'
require 'volt/models/model_helpers'
require 'volt/models/state_manager'
require 'volt/models/state_helpers'

module Volt
  class ArrayModel < ReactiveArray
    include ModelWrapper
    include ModelHelpers
    include StateManager
    include StateHelpers


    attr_reader :parent, :path, :persistor, :options, :array

    # For many methods, we want to call load data as soon as the model is interacted
    # with, so we proxy the method, then call super.
    def self.proxy_with_root_dep(*method_names)
      method_names.each do |method_name|
        define_method(method_name) do |*args|
          # track on the root dep
          persistor.try(:root_dep).try(:depend)

          super(*args)
        end
      end
    end

    # Some methods get passed down to the persistor.
    def self.proxy_to_persistor(*method_names)
      method_names.each do |method_name|
        define_method(method_name) do |*args, &block|
          if @persistor.respond_to?(method_name)
            @persistor.send(method_name, *args, &block)
          else
            fail "this model's persistance layer does not support #{method_name}, try using store"
          end
        end
      end
    end

    proxy_with_root_dep :[], :size, :first, :last, :state_for#, :limit, :find_one, :find
    proxy_to_persistor :find, :skip, :limit, :then

    def initialize(array = [], options = {})
      @options   = options
      @parent    = options[:parent]
      @path      = options[:path] || []
      @persistor = setup_persistor(options[:persistor])

      array = wrap_values(array)

      super(array)

      @persistor.loaded if @persistor
    end

    def attributes
      self
    end

    # Make sure it gets wrapped
    def <<(model)
      if model.is_a?(Model)
        # Set the new path
        model.options = @options.merge(path: @options[:path] + [:[]])
      else
        model = wrap_values([model]).first
      end

      super(model)

      if @persistor
        @persistor.added(model, @array.size - 1)
      else
        nil
      end
    end

    # Works like << except it returns a promise
    def append(model)
      promise, model = send(:<<, model)

      # Return a promise if one doesn't exist
      promise ||= Promise.new.resolve(model)

      promise
    end

    # Find one does a query, but only returns the first item or
    # nil if there is no match.  Unlike #find, #find_one does not
    # return another cursor that you can call .then on.
    def find_one(*args, &block)
      find(*args, &block).limit(1)[0]
    end

    # Make sure it gets wrapped
    def inject(*args)
      args = wrap_values(args)
      super(*args)
    end

    # Make sure it gets wrapped
    def +(*args)
      args = wrap_values(args)
      super(*args)
    end

    def new_model(*args)
      class_at_path(options[:path]).new(*args)
    end

    def new_array_model(*args)
      ArrayModel.new(*args)
    end

    # Convert the model to an array all of the way down
    def to_a
      array = []
      attributes.each do |value|
        array << deep_unwrap(value)
      end
      array
    end

    def inspect
      Computation.run_without_tracking do
        # Track on size
        @size_dep.depend
        str = "#<#{self.class}:#{object_id} #{loaded_state}"
        str += " path:#{path.join('.')}" if path
        str += " persistor:#{persistor.inspect}" if persistor
        str += " #{@array.inspect}>"

        str
      end
    end

    def buffer
      model_path  = options[:path] + [:[]]
      model_klass = class_at_path(model_path)

      new_options = options.merge(path: model_path, save_to: self, buffer: true).reject { |k, _| k.to_sym == :persistor }
      model       = model_klass.new({}, new_options)

      model
    end

    private

    # Takes the persistor if there is one and
    def setup_persistor(persistor)
      if persistor
        @persistor = persistor.new(self)
      end
    end
  end
end
