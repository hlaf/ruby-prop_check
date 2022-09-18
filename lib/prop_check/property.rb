require 'stringio'
require 'awesome_print'

require 'prop_check/property/configuration'
require 'prop_check/property/output_formatter'
require 'prop_check/property/shrinker'
require 'prop_check/hooks'
module PropCheck
  ##
  # Create and run property-checks.
  #
  # For simple usage, see `.forall`.
  #
  # For advanced usage, call `PropCheck::Property.new(...)` and then configure it to your liking
  # using e.g. `#with_config`, `#before`, `#after`, `#around` etc.
  # Each of these methods will return a new `Property`, so earlier properties are not mutated.
  # This allows you to re-use configuration and hooks between multiple tests.
  class Property
    ##
    # Main entry-point to create (and possibly immediately run) a property-test.
    #
    # This method accepts a list of generators and a block.
    # The block will then be executed many times, passing the values generated by the generators
    # as respective arguments:
    #
    # ```
    # include PropCheck::Generators
    # PropCheck.forall(integer(), float()) { |x, y| ... }
    # ```
    #
    # It is also possible (and recommended when having more than a few generators) to use a keyword-list
    # of generators instead:
    #
    # ```
    # include PropCheck::Generators
    # PropCheck.forall(x: integer(), y: float()) { |x:, y:| ... }
    # ```
    #
    #
    # If you do not pass a block right away,
    # a Property object is returned, which you can call the other instance methods
    # of this class on before finally passing a block to it using `#check`.
    # (so `forall(Generators.integer) do |val| ... end` and forall(Generators.integer).check do |val| ... end` are the same)
    def self.forall(*bindings, **kwbindings, &block)
      property = new(*bindings, **kwbindings)

      return property.check(&block) if block_given?

      property
    end

    ##
    # Returns the default configuration of the library as it is configured right now
    # for introspection.
    #
    # For the configuration of a single property, check its `configuration` instance method.
    # See PropCheck::Property::Configuration for more info on available settings.
    def self.configuration
      @configuration ||= Configuration.new
    end

    ##
    # Yields the library's configuration object for you to alter.
    # See PropCheck::Property::Configuration for more info on available settings.
    def self.configure
      yield(configuration)
    end

    def initialize(*bindings, **kwbindings)
      @config = self.class.configuration
      @hooks = PropCheck::Hooks.new

      @gen = gen_from_bindings(bindings, kwbindings) unless bindings.empty? && kwbindings.empty?
      freeze
    end

    # [:condition, :config, :hooks, :gen].each do |symbol|
    #   define_method(symbol) do
    #     self.instance_variable_get("@#{symbol}")
    #   end

    #   protected define_method("#{symbol}=") do |value|
    #     duplicate = self.dup
    #     duplicate.instance_variable_set("@#{symbol}", value)
    #     duplicate
    #   end

    ##
    # Returns the configuration of this property
    # for introspection.
    #
    # See PropCheck::Property::Configuration for more info on available settings.
    def configuration
      @config
    end

    ##
    # Allows you to override the configuration of this property
    # by giving a hash with new settings.
    #
    # If no other changes need to occur before you want to check the property,
    # you can immediately pass a block to this method.
    # (so `forall(a: Generators.integer).with_config(verbose: true) do ... end` is the same as `forall(a: Generators.integer).with_config(verbose: true).check do ... end`)
    def with_config(**config, &block)
      duplicate = self.dup
      duplicate.instance_variable_set(:@config, @config.merge(config))
      duplicate.freeze

      return duplicate.check(&block) if block_given?

      duplicate
    end

    def with_bindings(*bindings, **kwbindings)
      raise ArgumentError, 'No bindings specified!' if bindings.empty? && kwbindings.empty?

      duplicate = self.dup
      duplicate.instance_variable_set(:@gen, gen_from_bindings(bindings, kwbindings))
      duplicate.freeze
      duplicate
    end

    ##
    # filters the generator using the  given `condition`.
    # The final property checking block will only be run if the condition is truthy.
    #
    # If wanted, multiple `where`-conditions can be specified on a property.
    # Be aware that if you filter away too much generated inputs,
    # you might encounter a GeneratorExhaustedError.
    # Only filter if you have few inputs to reject. Otherwise, improve your generators.
    def where(&condition)
      raise ArgumentError, 'No generator bindings specified! #where should be called after `#forall` or `#with_bindings`.' unless @gen

      duplicate = self.dup
      duplicate.instance_variable_set(:@gen, @gen.where(&condition))
      duplicate.freeze
      duplicate
    end


    ##
    # Calls `hook` before each time a check is run with new data.
    #
    # This is useful to add setup logic
    # When called multiple times, earlier-added hooks will be called _before_ `hook` is called.
    def before(&hook)
      duplicate = self.dup
      duplicate.instance_variable_set(:@hooks, @hooks.add_before(&hook))
      duplicate.freeze
      duplicate
    end

    ##
    # Calls `hook` after each time a check is run with new data.
    #
    # This is useful to add teardown logic
    # When called multiple times, earlier-added hooks will be called _after_ `hook` is called.
    def after(&hook)
      duplicate = self.dup
      duplicate.instance_variable_set(:@hooks, @hooks.add_after(&hook))
      duplicate.freeze
      duplicate
    end

    ##
    # Calls `hook` around each time a check is run with new data.
    #
    # `hook` should `yield` to the passed block.
    #
    # When called multiple times, earlier-added hooks will be wrapped _around_ `hook`.
    #
    # Around hooks will be called after all `#before` hooks
    # and before all `#after` hooks.
    #
    # Note that if the block passed to `hook` raises an exception,
    # it is possible for the code after `yield` not to be called.
    # So make sure that cleanup logic is wrapped with the `ensure` keyword.
    def around(&hook)
      duplicate = self.dup
      duplicate.instance_variable_set(:@hooks, @hooks.add_around(&hook))
      duplicate.freeze
      duplicate
    end

    ##
    # Checks the property (after settings have been altered using the other instance methods in this class.)
    def check(&block)
      n_runs = 0
      n_successful = 0

      # Loop stops at first exception
      attempts_enum(@gen).each do |generator_result|
        n_runs += 1
        check_attempt(generator_result, n_successful, &block)
        n_successful += 1
      end

      ensure_not_exhausted!(n_runs)
    end

    def gen_from_bindings(bindings, kwbindings)
      if bindings == [] && kwbindings != {}
        PropCheck::Generators.fixed_hash(**kwbindings)
      elsif bindings != [] && kwbindings == {}
        if bindings.size == 1
          bindings.first
        else
          PropCheck::Generators.tuple(*bindings)
        end
      else
        raise ArgumentError,
              'Attempted to use both normal and keyword bindings at the same time.
This is not supported because of the separation of positional and keyword arguments
(the old behaviour is deprecated in Ruby 2.7 and will be removed in 3.0)
c.f. https://www.ruby-lang.org/en/news/2019/12/12/separation-of-positional-and-keyword-arguments-in-ruby-3-0/
     '
      end
    end

    def ensure_not_exhausted!(n_runs)
      return if n_runs >= @config.n_runs

      raise_generator_exhausted!
    end

    def raise_generator_exhausted!()
      raise Errors::GeneratorExhaustedError, """
        Could not perform `n_runs = #{@config.n_runs}` runs,
        (exhausted #{@config.max_generate_attempts} tries)
        because too few generator results were adhering to
        the `where` condition.

        Try refining your generators instead.
        """
    end

    def check_attempt(generator_result, n_successful, &block)
      PropCheck::Helper.call_splatted(generator_result.root, &block)

    # immediately stop (without shrinnking) for when the app is asked
    # to close by outside intervention
    rescue SignalException, SystemExit
      raise

    # We want to capture _all_ exceptions (even low-level ones) here,
    # so we can shrink to find their cause.
    # don't worry: they all get reraised
    rescue Exception => e
      output, shrunken_result, shrunken_exception, n_shrink_steps = show_problem_output(e, generator_result, n_successful, &block)
      output_string = output.is_a?(StringIO) ? output.string : e.message

      e.define_singleton_method :prop_check_info do
        {
          original_input: generator_result.root,
          original_exception_message: e.message,
          shrunken_input: shrunken_result,
          shrunken_exception: shrunken_exception,
          n_successful: n_successful,
          n_shrink_steps: n_shrink_steps
        }
      end

      raise e, output_string, e.backtrace
    end

    def attempts_enum(binding_generator)
        @hooks
        .wrap_enum(raw_attempts_enum(binding_generator))
        .lazy
        .take(@config.n_runs)
    end

    def raw_attempts_enum(binding_generator)
      rng = Random::DEFAULT
      size = 1
      (0...@config.max_generate_attempts)
        .lazy
        .map { binding_generator.generate(size: size, rng: rng, max_consecutive_attempts: @config.max_consecutive_attempts) }
        .map do |result|
          size += 1

          result
        end
    end

    def show_problem_output(problem, generator_results, n_successful, &block)
      output = @config.verbose ? STDOUT : StringIO.new
      output = PropCheck::Property::OutputFormatter.pre_output(output, n_successful, generator_results.root, problem)
      shrunken_result, shrunken_exception, n_shrink_steps = shrink(generator_results, output, &block)
      output = PropCheck::Property::OutputFormatter.post_output(output, n_shrink_steps, shrunken_result, shrunken_exception)

      [output, shrunken_result, shrunken_exception, n_shrink_steps]
    end

    def shrink(bindings_tree, io, &block)
      PropCheck::Property::Shrinker.call(bindings_tree, io, @hooks, @config, &block)
    end
  end
end
