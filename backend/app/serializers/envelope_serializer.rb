class EnvelopeSerializer
  # Stable per-employee failure codes clients can act on. Never rename or
  # re-use an existing code for a different meaning (see docs/API.md).
  FAILURE_CODES = %w[
    no_job_for_period
    no_applicable_items
    formula_invalid
    formula_error
    unknown_employee
  ].freeze

  class << self
    def envelope(service_envelope)
      { results: service_envelope[:results].map { |result| serialize_result(result) } }
    end

    private

    def serialize_result(result)
      result[:status] == "success" ? success(result) : failure(result)
    end

    def success(result)
      {
        employee_id: result[:employee_id],
        status: "success",
        liquidacion: { url: Rails.application.routes.url_helpers.api_v1_liquidacion_path(result[:liquidacion][:id]) }
      }
    end

    def failure(result)
      code = result[:error][:code]
      raise ArgumentError, "unknown failure code: #{code}" unless FAILURE_CODES.include?(code)

      { employee_id: result[:employee_id], status: "failure", error: result[:error] }
    end
  end
end
