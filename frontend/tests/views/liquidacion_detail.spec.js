import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import LiquidacionDetailView from '../../src/views/LiquidacionDetailView.vue'
import { formatMoney, PENDING_PLACEHOLDER } from '../../src/utils/money'

vi.mock('../../src/services/api', () => ({
  getEmployees: vi.fn(),
  getLiquidaciones: vi.fn(),
  getLiquidacion: vi.fn(),
  calculatePayroll: vi.fn(),
  toErrorMessage: (error) => {
    if (error && error.response && error.response.status === 404) return 'Liquidación no encontrada'
    return (error && error.message) || 'Error de red'
  }
}))

import { getLiquidacion } from '../../src/services/api'

const flush = () => new Promise((resolve) => setTimeout(resolve))

const pinia = createPinia()
setActivePinia(pinia)

const detail = {
  id: 10,
  employee_id: 1,
  name: 'Ana García',
  period: '2026-09',
  currency: 'ARS',
  haberes_totales_cents: 1_225_000,
  descuentos_totales_cents: 240_750,
  aportes_totales_cents: 348_000,
  final_salary_cents: 984_250,
  items: [
    { description: 'Salario base', category: 'haber', amount_cents: 1_200_000, formula: 'base_salary', formula_version: 1 },
    { description: 'Bono fijo', category: 'haber', amount_cents: 25_000, formula: '25000', formula_version: 1 },
    { description: 'Descuento legal', category: 'descuento', amount_cents: 204_000, formula: 'round(base_salary * 0.17)', formula_version: 1 },
    { description: 'Descuento previsional', category: 'descuento', amount_cents: 36_750, formula: 'round(haberes_totales * 0.03)', formula_version: 1 },
    { description: 'Aporte empleador', category: 'aporte', amount_cents: 348_000, formula: 'round(base_salary * 0.29)', formula_version: 1 }
  ]
}

function mountView() {
  return mount(LiquidacionDetailView, { props: { id: '10' } })
}

const pendingDetail = {
  id: 11,
  employee_id: 2,
  name: 'Bruno Sosa',
  period: '2026-09',
  currency: 'UYU',
  pending: true,
  haberes_totales_cents: null,
  descuentos_totales_cents: null,
  aportes_totales_cents: null,
  final_salary_cents: null,
  items: [
    { description: 'Salario base', category: 'haber', amount_cents: null, formula: 'base_salary', formula_version: 1 }
  ]
}

describe('LiquidacionDetailView', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('renders the totals in integer cents formatted as money', async () => {
    getLiquidacion.mockResolvedValue(detail)

    const wrapper = mountView()
    await flush()

    const text = wrapper.text()
    expect(text).toContain('Ana García')
    expect(text).toContain('2026-09')
    expect(text).toContain(formatMoney(1_225_000, 'ARS'))
    expect(text).toContain(formatMoney(240_750, 'ARS'))
    expect(text).toContain(formatMoney(348_000, 'ARS'))
    expect(text).toContain(formatMoney(984_250, 'ARS'))
  })

  it('groups items by category in haber, descuento, aporte order', async () => {
    getLiquidacion.mockResolvedValue(detail)

    const wrapper = mountView()
    await flush()

    const headings = wrapper.findAll('[data-testid="group-heading"]').map((node) => node.text())
    expect(headings).toEqual([ 'Haberes', 'Descuentos', 'Aportes' ])

    const text = wrapper.text()
    expect(text).toContain('Salario base')
    expect(text).toContain('Descuento legal')
    expect(text).toContain('Aporte empleador')
    expect(text).toContain('round(haberes_totales * 0.03)')
  })

  it('renders a pending liquidacion with dashes for totals and items', async () => {
    getLiquidacion.mockResolvedValue(pendingDetail)

    const wrapper = mountView()
    await flush()

    expect(wrapper.find('[data-testid="pending-notice"]').exists()).toBe(true)
    expect(wrapper.text()).toContain(PENDING_PLACEHOLDER)
    expect(wrapper.text()).toContain('Salario base')
    expect(wrapper.text()).not.toContain('$0,00')
    expect(wrapper.text()).not.toContain('$0.00')
  })

  it('shows a missing-result state with no fake zeros when the liquidacion is not found', async () => {
    getLiquidacion.mockRejectedValue({ response: { status: 404 } })

    const wrapper = mountView()
    await flush()

    expect(wrapper.find('[data-testid="detail-missing"]').exists()).toBe(true)
    expect(wrapper.text()).toContain('Liquidación no encontrada')
    expect(wrapper.text()).not.toContain('$')
  })
})