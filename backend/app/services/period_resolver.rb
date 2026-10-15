class PeriodResolver
  def self.call(employee, year:, month:)
    month_date = Date.new(year, month, -1)
    employee.jobs.find { |job| job.covers?(month_date) }
  end
end
