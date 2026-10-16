import { describe, it, expect } from 'vitest'
import { formatMoney, formatPeriod, PENDING_PLACEHOLDER } from '../../src/utils/money'

describe('money formatting', () => {
  it('renders a pending (null) amount as a dash instead of a fake zero', () => {
    expect(formatMoney(null)).toBe(PENDING_PLACEHOLDER)
    expect(formatMoney(undefined)).toBe(PENDING_PLACEHOLDER)
    expect(formatMoney(null, 'UYU')).toBe(PENDING_PLACEHOLDER)
  })

  it('renders a calculated zero as real money, not as pending', () => {
    expect(formatMoney(0)).not.toBe(PENDING_PLACEHOLDER)
    expect(formatMoney(0, 'ARS')).toContain('0,00')
  })

  it('renders integer cents labelled with the contract currency code', () => {
    expect(formatMoney(1_225_000, 'ARS')).toContain('ARS')
    expect(formatMoney(1_225_000, 'ARS')).toContain('12.250,00')
    expect(formatMoney(1_225_000, 'UYU')).toContain('UYU')
    expect(formatMoney(1_225_000, 'UYU')).toContain('12.250,00')
  })

  it('falls back to ARS when no currency is provided', () => {
    expect(formatMoney(1_225_000)).toBe(formatMoney(1_225_000, 'ARS'))
  })

  it('formats a period as YYYY-MM', () => {
    expect(formatPeriod(2026, 9)).toBe('2026-09')
  })
})
