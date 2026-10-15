import { describe, it, expect } from 'vitest'
import { formatMoney, formatPeriod, PENDING_PLACEHOLDER } from '../../src/utils/money'

describe('money formatting', () => {
  it('renders a pending (null) amount as a dash instead of a fake zero', () => {
    expect(formatMoney(null)).toBe(PENDING_PLACEHOLDER)
    expect(formatMoney(undefined)).toBe(PENDING_PLACEHOLDER)
  })

  it('renders a calculated zero as real money, not as pending', () => {
    expect(formatMoney(0).startsWith('$')).toBe(true)
    expect(formatMoney(0)).not.toBe(PENDING_PLACEHOLDER)
  })

  it('renders integer cents as money', () => {
    expect(formatMoney(1_225_000).startsWith('$')).toBe(true)
    expect(formatMoney(1_225_000)).not.toBe(PENDING_PLACEHOLDER)
  })

  it('formats a period as YYYY-MM', () => {
    expect(formatPeriod(2026, 9)).toBe('2026-09')
  })
})
