class EmployeeSerializer
  class << self
    def list(employees)
      { employees: employees.map { |employee| list_attributes(employee) } }
    end

    def show(employee)
      { employee: list_attributes(employee).merge(jobs: employee.jobs.map { |job| job_attributes(job) }) }
    end

    private

    def list_attributes(employee)
      { id: employee.id, name: employee.name }
    end

    def job_attributes(job)
      {
        id: job.id,
        country: job.country,
        currency: job.currency,
        base_salary_cents: job.base_salary_cents,
        effective_from: job.effective_from.iso8601,
        effective_to: job.effective_to&.iso8601
      }
    end
  end
end
