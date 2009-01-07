module Fixjour
  class << self
    attr_accessor :allow_redundancy
    
    # The list of classes that have builders defined.
    def builders
      @builders ||= Set.new
    end

    # This method should always return a valid instance of
    # a model object.
    def define_builder(klass, options={}, &block)
      add_builder(klass)

      if block_given?
        define_new(klass, &block)
      else
        define_new(klass) do |overrides|
          klass.new(options.merge(overrides))
        end
      end
      
      name = name_for(klass)
      
      define_create(name)
      define_valid_attributes(name)
    end
    
    def evaluate(&block)
      begin
        module_eval(&block)
      rescue NameError => e
        if evaluator.respond_to?(e.name)
          raise NonBlockBuilderReference.new("You must use a builder block in order to reference other Fixjour creation methods.")
        else
          raise e
        end
      end
    end
    
    private
    
    # Registers a class' builder. This allows us to make sure
    # redundant builders aren't defined, which can lead to confusion
    # when trying to figure out where objects are being created.
    def add_builder(klass)
      unless builders.add?(klass) or Fixjour.allow_redundancy
        raise RedundantBuilder.new("You already defined a builder for #{klass.inspect}")
      end
    end
    
    def name_for(klass)
      klass.name.underscore
    end
    
    # Defines the new_* method
    def define_new(klass, &block)
      name = name_for(klass)
      define_method("new_#{name}") do |*args|
        overrides = OverridesHash.new(args.first || { })
        
        args = case block.arity
        when 1 then [overrides]
        when 2 then [Merger.new(klass, overrides), overrides]
        end
        
        result = block.bind(self).call(*args)
        result
      end
    end
    
    # Defines the create_* method
    def define_create(name)
      define_method("create_#{name}") do |*args|
        model = send("new_#{name}", *args)
        model.save!
        model
      end
    end
    
    # Defines the valid_*_attributes method
    def define_valid_attributes(name)
      define_method("valid_#{name}_attributes") do |*args|
        if instance_variable_get("@__valid_#{name}_attrs").nil?
          valid_attributes = send("new_#{name}").attributes
          valid_attributes.delete_if { |key, value| value.nil? }
          instance_variable_set("@__valid_#{name}_attrs", valid_attributes)
        end

        overrides = args.extract_options!
        attrs = instance_variable_get("@__valid_#{name}_attrs").merge(overrides)
        attrs.stringify_keys!
        attrs.make_indifferent!
        attrs
      end
    end
    
    def evaluator
      @evaluator ||= begin
        klass = Class.new
        klass.send :include, self
        klass.new
      end
    end
  end
end
