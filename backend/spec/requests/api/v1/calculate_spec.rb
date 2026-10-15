require 'rails_helper'

RSpec.describe 'Calculate Liquidaciones API', type: :request do
  let(:period) { '2026-09' }
  let(:json_headers) { { 'CONTENT_TYPE' => 'application/json' } }

  def post_calculate(body)
    post '/api/v1/liquidaciones/calculate', params: body.to_json, headers: json_headers
  end

  describe 'POST /api/v1/liquidaciones/calculate' do
    it 'returns 400 problem+json when employee_ids is missing' do
      post_calculate(period: period)

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)['errors']).to be_an(Array)
    end

    it 'returns 400 problem+json when employee_ids is empty' do
      post_calculate(employee_ids: [], period: period)

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)['errors']).to be_an(Array)
    end

    it 'returns 400 problem+json when period is missing' do
      post_calculate(employee_ids: [ 1 ])

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)['errors']).to be_an(Array)
    end

    it 'returns 400 problem+json when period is not YYYY-MM' do
      post_calculate(employee_ids: [ 1 ], period: '09-2026')

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)['errors']).to be_an(Array)
    end

    it 'returns 400 problem+json when period month is out of range' do
      post_calculate(employee_ids: [ 1 ], period: '2026-13')

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)['errors']).to be_an(Array)
    end

    it 'returns 422 problem+json when every requested employee is unknown' do
      post_calculate(employee_ids: [ 999, 1000 ], period: period)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['errors']).to be_an(Array)
    end

    it 'returns a 200 per-employee envelope with success and failure results' do
      employee = create(:employee, name: 'Ana García')
      create(:job, employee: employee, country: 'AR', base_salary_cents: 1_200_000,
                   effective_from: Date.new(2025, 1, 1), effective_to: nil)
      prepare_pending_run(employee, period,
                          [ { description: 'Salario base', category: 'haber', formula: 'base_salary' } ])
      no_job = create(:employee, name: 'Bruno Sosa')

      post_calculate(employee_ids: [ employee.id, no_job.id ], period: period)

      expect(response).to have_http_status(:ok)
      results = JSON.parse(response.body)['results']
      expect(results.map { |result| result['employee_id'] }).to contain_exactly(employee.id, no_job.id)

      success = results.find { |result| result['employee_id'] == employee.id }
      expect(success['status']).to eq('success')
      expect(success['liquidacion']['url']).to match(%r{\A/api/v1/liquidaciones/\d+\z})

      failure = results.find { |result| result['employee_id'] == no_job.id }
      expect(failure['status']).to eq('failure')
      expect(failure['error']['code']).to eq('no_job_for_period')
      expect(failure['error']['detail']).to eq('No contractual Job found for 2026-09')
    end

    it 'reports a missing prepared run as no_applicable_items' do
      employee = create(:employee, name: 'Ana García')
      create(:job, employee: employee, country: 'AR', base_salary_cents: 1_200_000,
                   effective_from: Date.new(2025, 1, 1), effective_to: nil)

      post_calculate(employee_ids: [ employee.id ], period: period)

      expect(response).to have_http_status(:ok)
      result = JSON.parse(response.body)['results'].first
      expect(result['status']).to eq('failure')
      expect(result['error']['code']).to eq('no_applicable_items')
      expect(result['error']['detail']).to eq('No prepared items found for 2026-09')
    end

    it 'reports formula evaluation failures with their stable code in the envelope' do
      employee = create(:employee, name: 'Ana García')
      create(:job, employee: employee, country: 'AR', base_salary_cents: 1_200_000,
                   effective_from: Date.new(2025, 1, 1), effective_to: nil)
      prepare_pending_run(employee, period,
                          [ { description: 'División', category: 'haber', formula: 'base_salary / 0' } ])

      post_calculate(employee_ids: [ employee.id ], period: period)

      expect(response).to have_http_status(:ok)
      result = JSON.parse(response.body)['results'].first
      expect(result['status']).to eq('failure')
      expect(result['error']['code']).to eq('formula_error')
      expect(result['error']['detail']).to include('División')
    end

    it 'reports unknown employees as per-employee failures in a mixed batch' do
      employee = create(:employee, name: 'Ana García')
      create(:job, employee: employee, country: 'AR', base_salary_cents: 1_200_000,
                   effective_from: Date.new(2025, 1, 1), effective_to: nil)
      prepare_pending_run(employee, period,
                          [ { description: 'Salario base', category: 'haber', formula: 'base_salary' } ])

      post_calculate(employee_ids: [ employee.id, 424_242 ], period: period)

      expect(response).to have_http_status(:ok)
      results = JSON.parse(response.body)['results']

      unknown = results.find { |result| result['employee_id'] == 424_242 }
      expect(unknown['status']).to eq('failure')
      expect(unknown['error']['code']).to eq('unknown_employee')
      expect(results.select { |result| result['status'] == 'success' }.size).to eq(1)
    end
  end
end
