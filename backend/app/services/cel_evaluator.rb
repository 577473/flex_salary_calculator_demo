class CelEvaluator
  class Error < StandardError
    attr_reader :code

    def initialize(message, code)
      super(message)
      @code = code
    end
  end

  class CompilationError < Error
    def initialize(message)
      super(message, :formula_invalid)
    end
  end

  class EvaluationError < Error
    def initialize(message)
      super(message, :formula_error)
    end
  end

  class << self
    def evaluate(formula, bindings)
      result = runner(formula).evaluate(bindings)
      value = result.respond_to?(:value) ? result.value : result

      unless value.is_a?(Integer) && value >= 0
        raise EvaluationError, "formula produced a non-integer money result"
      end

      value
    rescue Cel::ParseError, Cel::CheckError => e
      raise CompilationError, e.message
    rescue Cel::EvaluateError => e
      raise CompilationError, e.message if e.message.include?("no value in context")

      raise EvaluationError, e.message
    rescue Error
      raise
    rescue StandardError => e
      raise EvaluationError, e.message
    end

    private

    def runner(formula)
      @runners ||= {}
      @runners[formula] ||= environment.program(formula)
    end

    def environment
      @environment ||= Cel::Environment.new(
        declarations: {},
        extensions: { salary: Cel::Extensions::SalaryHelpers }
      )
    end
  end
end

module Cel
  module Extensions
    module SalaryHelpers
      module_function

      def implicit?
        true
      end

      def __check(funcall, checker:)
        func = funcall.func
        args = funcall.args

        case func
        when :round
          checker.check_arity(func, args, 2, :>=)
          arg = checker.call(args.first)
          TYPES[:int] if numeric_type?(arg)
        when :min, :max
          checker.check_arity_any(func, args)
          types = args.map(&checker.method(:call))
          TYPES[:int] if types.all? { |type| numeric_type?(type) }
        end
      end

      def round(value, digits = 0, program:)
        num = program.call(value)
        digit_count = digits.is_a?(Integer) ? digits : program.call(digits).value
        factor = 10**digit_count
        Number.new(:int, (num.value * factor).round / factor)
      end

      def min(*args, program:)
        args.map { |arg| program.call(arg) }.min
      end

      def max(*args, program:)
        args.map { |arg| program.call(arg) }.max
      end

      def numeric_type?(type)
        [ :int, :double, :any ].include?(type) ||
          [ TYPES[:int], TYPES[:double], TYPES[:any] ].include?(type)
      end
    end
  end
end
