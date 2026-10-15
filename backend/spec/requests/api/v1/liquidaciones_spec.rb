require 'rails_helper'

RSpec.describe 'Liquidaciones API', type: :request do
  let!(:ana) { create(:employee, name: 'Ana García') }
  let!(:bruno) { create(:employee, name: 'Bruno Sosa') }
  let!(:liquidacion) do
    create(:liquidacion, employee: ana, period_year: 2026, period_month: 9,
                         haberes_totales_cents: 1_225_000, descuentos_totales_cents: 240_750,
                         aportes_totales_cents: 348_000, final_salary_cents: 984_250)
  end
  let!(:template) do
    create(:asignacion_template, description: 'Base salary', category: 'haber')
  end

  before do
    create(:asignacion, liquidacion: liquidacion, template: template, description: 'Base salary',
                        category: 'haber', formula: 'base_salary', formula_version: 1,
                        amount_cents: 1_200_000, position: 1)
  end

  describe 'GET /api/v1/liquidaciones?period=:period' do
    it 'returns liquidaciones for the required period with integer-cent amounts' do
      create(:liquidacion, employee: bruno, period_year: 2026, period_month: 8)

      get '/api/v1/liquidaciones', params: { period: '2026-09' }

      expect(response).to have_http_status(:ok)
      list = JSON.parse(response.body)['liquidaciones']
      expect(list.size).to eq(1)

      first = list.first
      expect(first['id']).to eq(liquidacion.id)
      expect(first['employee_id']).to eq(ana.id)
      expect(first['name']).to eq('Ana García')
      expect(first['period']).to eq('2026-09')
      expect(first['haberes_totales_cents']).to eq(1_225_000)
      expect(first['descuentos_totales_cents']).to eq(240_750)
      expect(first['aportes_totales_cents']).to eq(348_000)
      expect(first['final_salary_cents']).to eq(984_250)
      expect(first['pending']).to be(false)
      expect(first['items_url']).to eq("/api/v1/liquidaciones/#{liquidacion.id}")
    end

    it 'exposes a not-yet-calculated run with null totals and pending true' do
      create(:liquidacion, :pending, employee: bruno, period_year: 2026, period_month: 9)

      get '/api/v1/liquidaciones', params: { period: '2026-09' }

      expect(response).to have_http_status(:ok)
      entry = JSON.parse(response.body)['liquidaciones'].find { |row| row['employee_id'] == bruno.id }
      expect(entry['pending']).to be(true)
      expect(entry['haberes_totales_cents']).to be_nil
      expect(entry['final_salary_cents']).to be_nil
    end

    it 'filters by employee_id when provided' do
      get '/api/v1/liquidaciones', params: { period: '2026-09', employee_id: bruno.id }
      expect(JSON.parse(response.body)['liquidaciones']).to eq([])

      get '/api/v1/liquidaciones', params: { period: '2026-09', employee_id: ana.id }
      expect(JSON.parse(response.body)['liquidaciones'].size).to eq(1)
    end

    it 'returns 400 problem+json when period is missing' do
      get '/api/v1/liquidaciones'

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)['errors']).to be_an(Array)
    end

    it 'returns 400 problem+json when period is not YYYY-MM' do
      get '/api/v1/liquidaciones', params: { period: '2026/09' }

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)['errors']).to be_an(Array)
    end
  end

  describe 'GET /api/v1/liquidaciones/:id' do
    it 'returns detail with integer-cent totals and the per-item breakdown' do
      get "/api/v1/liquidaciones/#{liquidacion.id}"

      expect(response).to have_http_status(:ok)
      detail = JSON.parse(response.body)['liquidacion']
      expect(detail['id']).to eq(liquidacion.id)
      expect(detail['employee_id']).to eq(ana.id)
      expect(detail['name']).to eq('Ana García')
      expect(detail['period']).to eq('2026-09')
      expect(detail['haberes_totales_cents']).to eq(1_225_000)
      expect(detail['descuentos_totales_cents']).to eq(240_750)
      expect(detail['aportes_totales_cents']).to eq(348_000)
      expect(detail['final_salary_cents']).to eq(984_250)
      expect(detail['pending']).to be(false)
      expect(detail['items']).to eq([
        {
          'description' => 'Base salary',
          'category' => 'haber',
          'amount_cents' => 1_200_000,
          'formula' => 'base_salary',
          'formula_version' => 1
        }
      ])
    end

    it 'orders items by category haber, descuento, aporte then position' do
      descuento_template = create(:asignacion_template, description: 'Descuento',
                                                        category: 'descuento')
      aporte_template = create(:asignacion_template, description: 'Aporte',
                                                     category: 'aporte')
      create(:asignacion, liquidacion: liquidacion, template: aporte_template, category: 'aporte',
                          description: 'Aporte', formula: 'base_salary', formula_version: 1,
                          amount_cents: 100, position: 3)
      create(:asignacion, liquidacion: liquidacion, template: descuento_template, category: 'descuento',
                          description: 'Descuento', formula: 'base_salary', formula_version: 1,
                          amount_cents: 200, position: 2)

      get "/api/v1/liquidaciones/#{liquidacion.id}"

      categories = JSON.parse(response.body)['liquidacion']['items'].map { |item| item['category'] }
      expect(categories).to eq(%w[haber descuento aporte])
    end

    it 'exposes pending items with a null amount until they are calculated' do
      pending_run = create(:liquidacion, :pending, employee: bruno, period_year: 2026, period_month: 9)
      create(:asignacion, :pending, liquidacion: pending_run, template: template,
                                    description: 'Base salary', category: 'haber',
                                    formula: 'base_salary', formula_version: 1, position: 1)

      get "/api/v1/liquidaciones/#{pending_run.id}"

      expect(response).to have_http_status(:ok)
      item = JSON.parse(response.body)['liquidacion']['items'].first
      expect(item['amount_cents']).to be_nil
    end

    it 'returns 404 problem+json for an unknown liquidacion' do
      get '/api/v1/liquidaciones/99999'

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['errors']).to be_an(Array)
    end
  end
end
