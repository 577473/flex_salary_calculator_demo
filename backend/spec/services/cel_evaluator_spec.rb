require 'rails_helper'

RSpec.describe CelEvaluator do
  let(:bindings) do
    {
      name: 'Juana Perez',
      country: 'AR',
      base_salary: 1_000_000,
      period_year: 2026,
      period_month: 12
    }
  end

  describe '.evaluate' do
    it 'evaluates an integer literal without bindings' do
      expect(described_class.evaluate('25000', {})).to eq(25_000)
    end

    it 'evaluates a bare binding reference' do
      expect(described_class.evaluate('base_salary', bindings)).to eq(1_000_000)
    end

    it 'evaluates integer arithmetic' do
      expect(described_class.evaluate('base_salary + 1000', bindings)).to eq(1_001_000)
      expect(described_class.evaluate('base_salary - 25000', bindings)).to eq(975_000)
      expect(described_class.evaluate('base_salary * 2', bindings)).to eq(2_000_000)
      expect(described_class.evaluate('base_salary % 7', bindings)).to eq(1)
    end

    it 'performs integer division deterministically' do
      expect(described_class.evaluate('base_salary / 12', bindings)).to eq(83_333)
    end

    it 'applies double arithmetic only through round' do
      expect(described_class.evaluate('round(base_salary * 0.17)', bindings)).to eq(170_000)
    end

    it 'evaluates string comparisons inside ternaries' do
      expect(described_class.evaluate('country == "AR" ? base_salary : 500', bindings)).to eq(1_000_000)
      expect(described_class.evaluate('country == "UY" ? base_salary : 500', bindings)).to eq(500)
      expect(described_class.evaluate('name == "Juan" ? 1 : 0', bindings)).to eq(0)
    end

    it 'evaluates numeric comparisons' do
      expect(described_class.evaluate('period_month > 6 ? 100 : 0', bindings)).to eq(100)
      expect(described_class.evaluate('period_month <= 6 ? 100 : 0', bindings)).to eq(0)
    end

    it 'evaluates boolean logic' do
      expect(described_class.evaluate('country == "AR" && period_month == 12 ? 7 : 0', bindings))
        .to eq(7)
      expect(described_class.evaluate('country == "AR" && !(period_month == 12) ? 7 : 0', bindings))
        .to eq(0)
    end

    it 'evaluates ternary conditionals' do
      expect(described_class.evaluate('period_month == 12 ? round(base_salary / 2) : 0', bindings))
        .to eq(500_000)
    end

    it 'rounds half-up' do
      expect(described_class.evaluate('round(2.5)', bindings)).to eq(3)
      expect(described_class.evaluate('round(3.5)', bindings)).to eq(4)
    end

    it 'rounds to an optional number of digits, returning an int' do
      expect(described_class.evaluate('round(123.456, 2)', bindings)).to eq(123)
    end

    it 'supports min and max with any number of numeric args' do
      expect(described_class.evaluate('min(base_salary, 900000)', bindings)).to eq(900_000)
      expect(described_class.evaluate('max(base_salary, 2000000)', bindings)).to eq(2_000_000)
      expect(described_class.evaluate('min(1, 2, 3)', bindings)).to eq(1)
    end

    it 'binds running subtotals made available by the caller' do
      with_subtotals = bindings.merge(haberes_totales: 1_225_000)
      expect(described_class.evaluate('round(haberes_totales * 0.03)', with_subtotals)).to eq(36_750)
    end

    it 'is deterministic for the same formula and bindings' do
      first = described_class.evaluate('round(base_salary * 0.17)', bindings)
      second = described_class.evaluate('round(base_salary * 0.17)', bindings)
      expect(first).to eq(second)
    end
  end

  describe 'failure semantics' do
    it 'reports an unknown variable as formula_invalid' do
      expect { described_class.evaluate('mystery + 1', bindings) }
        .to raise_error(described_class::CompilationError) do |error|
          expect(error.code).to eq(:formula_invalid)
        end
    end

    it 'reports an unavailable subtotal variable as formula_invalid' do
      expect { described_class.evaluate('round(haberes_totales * 0.03)', bindings) }
        .to raise_error(described_class::CompilationError)
    end

    it 'reports bad syntax as formula_invalid' do
      [ '(1 + 2', '1 *' ].each do |formula|
        expect { described_class.evaluate(formula, bindings) }
          .to raise_error(described_class::CompilationError)
      end
    end

    it 'reports a non-boolean condition as formula_invalid' do
      expect { described_class.evaluate('base_salary ? 1 : 0', bindings) }
        .to raise_error(described_class::CompilationError)
    end

    it 'reports a helper called with a wrong type as formula_invalid' do
      expect { described_class.evaluate('round("AR")', bindings) }
        .to raise_error(described_class::CompilationError)
      expect { described_class.evaluate('min()', bindings) }
        .to raise_error(described_class::CompilationError)
    end

    it 'reports division by zero as formula_error' do
      expect { described_class.evaluate('base_salary / 0', bindings) }
        .to raise_error(described_class::EvaluationError) do |error|
          expect(error.code).to eq(:formula_error)
        end
    end

    it 'rejects a non-integer money result as formula_error' do
      expect { described_class.evaluate('base_salary * 0.1', bindings) }
        .to raise_error(described_class::EvaluationError)
      expect { described_class.evaluate('0.17', bindings) }
        .to raise_error(described_class::EvaluationError)
    end
  end

  describe 'error hierarchy' do
    it 'exposes stable failure codes' do
      expect(described_class::CompilationError.ancestors).to include(described_class::Error)
      expect(described_class::EvaluationError.ancestors).to include(described_class::Error)
      expect(described_class::CompilationError.new('x').code).to eq(:formula_invalid)
      expect(described_class::EvaluationError.new('x').code).to eq(:formula_error)
    end
  end
end
