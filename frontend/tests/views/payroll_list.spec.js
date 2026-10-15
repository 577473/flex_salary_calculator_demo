import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createWebHistory } from 'vue-router'
import { nextTick } from 'vue'
import PayrollView from '../../src/views/PayrollView.vue'
import { usePayrollStore } from '../../src/stores/payroll'
import { formatMoney, PENDING_PLACEHOLDER } from '../../src/utils/money'

vi.mock('../../src/services/api', () => ({
  getEmployees: vi.fn(),
  getLiquidaciones: vi.fn(),
  getLiquidacion: vi.fn(),
  calculatePayroll: vi.fn(),
  toErrorMessage: (error) => (error && error.message) || 'Error de red'
}))

import { getEmployees, getLiquidaciones, calculatePayroll } from '../../src/services/api'

const flush = () => new Promise((resolve) => setTimeout(resolve))

function router() {
  return createRouter({
    history: createWebHistory(),
    routes: [{ path: '/', component: { template: '<div />' } }]
  })
}

function mountView() {
  const pinia = createPinia()
  setActivePinia(pinia)
  return mount(PayrollView, { global: { plugins: [pinia, router()] } })
}

describe('PayrollView (list)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('loads and renders employees', async () => {
    getEmployees.mockResolvedValue([
      { id: 1, name: 'Ana García' },
      { id: 2, name: 'Bruno Sosa' }
    ])
    getLiquidaciones.mockResolvedValue([])

    const wrapper = mountView()
    await flush()

    expect(wrapper.text()).toContain('Ana García')
    expect(wrapper.text()).toContain('Bruno Sosa')
  })

  it('shows final totals after calculation and reports failures without fake zeros', async () => {
    getEmployees.mockResolvedValue([
      { id: 1, name: 'Ana García' },
      { id: 2, name: 'Bruno Sosa' }
    ])
    calculatePayroll.mockResolvedValue([
      { employee_id: 1, status: 'success', liquidacion: { url: '/api/v1/liquidaciones/10' } },
      {
        employee_id: 2,
        status: 'failure',
        error: { code: 'no_job_for_period', detail: 'No contractual Job found for 2026-09' }
      }
    ])
    getLiquidaciones.mockResolvedValue([
      {
        id: 10,
        employee_id: 1,
        name: 'Ana García',
        period: '2026-09',
        haberes_totales_cents: 1_225_000,
        descuentos_totales_cents: 240_750,
        aportes_totales_cents: 348_000,
        final_salary_cents: 984_250
      }
    ])

    const wrapper = mountView()
    await flush()

    await wrapper.get('input').setValue('2026-09')
    await wrapper.get('form').trigger('submit')
    await flush()

    expect(calculatePayroll).toHaveBeenCalledWith([1, 2], '2026-09')
    expect(wrapper.text()).toContain(formatMoney(984_250))
    expect(wrapper.text()).toContain('no_job_for_period')
    expect(wrapper.text()).toContain('No contractual Job found for 2026-09')

    const stock = usePayrollStore()
    const failedRow = wrapper.findAll('[data-testid="result-row"]')
    expect(failedRow.length).toBeGreaterThan(0)
    const failureLis = stock.results.filter((result) => result.status === 'failure')
    expect(failureLis.length).toBe(1)
  })

  it('shows an empty state with no fake zeros when the period has no results', async () => {
    getEmployees.mockResolvedValue([])
    calculatePayroll.mockResolvedValue([])
    getLiquidaciones.mockResolvedValue([])

    const wrapper = mountView()
    await flush()

    await wrapper.get('input').setValue('2026-09')
    await wrapper.get('form').trigger('submit')
    await flush()

    expect(wrapper.find('[data-testid="empty-state"]').exists()).toBe(true)
    expect(wrapper.find('[data-testid="results"]').exists()).toBe(false)
    expect(wrapper.text()).not.toContain('$')
  })

  it('marks a not-yet-calculated run as pending and renders dashes instead of fake zeros', async () => {
    getEmployees.mockResolvedValue([{ id: 1, name: 'Ana García' }])
    calculatePayroll.mockResolvedValue([
      { employee_id: 1, status: 'success', liquidacion: { url: '/api/v1/liquidaciones/10' } }
    ])
    getLiquidaciones.mockResolvedValue([
      {
        id: 10,
        employee_id: 1,
        name: 'Ana García',
        period: '2026-09',
        pending: true,
        haberes_totales_cents: null,
        descuentos_totales_cents: null,
        aportes_totales_cents: null,
        final_salary_cents: null
      }
    ])

    const wrapper = mountView()
    await flush()

    await wrapper.get('input').setValue('2026-09')
    await wrapper.get('form').trigger('submit')
    await flush()

    expect(wrapper.find('[data-testid="pending-badge"]').exists()).toBe(true)
    expect(wrapper.text()).toContain(PENDING_PLACEHOLDER)
    expect(wrapper.text()).not.toContain('$0,00')
    expect(wrapper.text()).not.toContain('$0.00')
  })

  it('blocks calculation when no period is selected', async () => {
    getEmployees.mockResolvedValue([{ id: 1, name: 'Ana García' }])
    getLiquidaciones.mockResolvedValue([])

    const wrapper = mountView()
    await flush()

    await wrapper.get('form').trigger('submit')
    await nextTick()

    expect(calculatePayroll).not.toHaveBeenCalled()
    expect(wrapper.text()).toContain('Seleccioná un período')
  })
})