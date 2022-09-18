module PropCheck
  class Property
    Configuration = Struct.new(
      :verbose,
      :n_runs,
      :max_generate_attempts,
      :max_shrink_steps,
      :max_consecutive_attempts) do

      def initialize(
            verbose: false,
            n_runs: 100,
            max_generate_attempts: 10000,
            max_shrink_steps: 10000,
            max_consecutive_attempts: 30
          )
        #require 'byebug'; byebug
        super
        self.verbose = verbose
        self.n_runs = n_runs
        self.max_generate_attempts = max_generate_attempts
        self.max_shrink_steps = max_shrink_steps
        self.max_consecutive_attempts = max_consecutive_attempts
      end

      def merge(other)
        Configuration.new(**self.to_h.merge(other.to_h))
      end
    end
  end
end
