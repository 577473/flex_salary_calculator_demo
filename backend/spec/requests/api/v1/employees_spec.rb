require 'rails_helper'

RSpec.describe 'Employees API', type: :request do
  describe 'GET /api/v1/employees' do
    it 'returns the list of employees' do
      create(:employee, name: 'Ana García')
      create(:employee, name: 'Bruno Sosa')

      get '/api/v1/employees'

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['employees']).to contain_exactly(
        { 'id' => an_instance_of(Integer), 'name' => 'Ana García' },
        { 'id' => an_instance_of(Integer), 'name' => 'Bruno Sosa' }
      )
    end

    it 'returns an empty list when there are no employees' do
      get '/api/v1/employees'

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq('employees' => [])
    end
  end

  describe 'GET /api/v1/employees/:id' do
    it 'returns the employee with their jobs' do
      employee = create(:employee, name: 'Ana García')
      create(:job, employee: employee, country: 'AR', base_salary_cents: 1_200_000,
                   effective_from: Date.new(2025, 1, 1), effective_to: nil)

      get "/api/v1/employees/#{employee.id}"

      expect(response).to have_http_status(:ok)
      employee_json = JSON.parse(response.body)['employee']
      expect(employee_json['id']).to eq(employee.id)
      expect(employee_json['name']).to eq('Ana García')
      expect(employee_json['jobs']).to eq([
        {
          'id' => employee.jobs.first.id,
          'country' => 'AR',
          'base_salary_cents' => 1_200_000,
          'effective_from' => '2025-01-01',
          'effective_to' => nil
        }
      ])
    end

    it 'returns 404 problem+json for an unknown employee' do
      get '/api/v1/employees/99999'

      expect(response).to have_http_status(:not_found)
      body = JSON.parse(response.body)
      expect(body['errors']).to be_an(Array)
      expect(body['errors'].first).to include('status' => 404, 'title' => 'Not Found')
    end
  end
end
