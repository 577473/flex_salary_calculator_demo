export const PENDING_PLACEHOLDER = '—'

// `currency` is the ISO 4217 code of the Job contract for the period (display
// only — amounts are raw integer minor units). The ISO code is always shown
// (e.g. "ARS 1.200.000,00", never the locale's bare "$") so every row stays
// unambiguous when employees are paid in different currencies. Falls back to
// ARS when a caller omits it; a null amount is always a dash, never a fake zero.
export function formatMoney(cents, currency) {
  if (cents === null || cents === undefined) return PENDING_PLACEHOLDER

  const amount = Number(cents) / 100
  return new Intl.NumberFormat('es-AR', {
    style: 'currency',
    currency: currency || 'ARS',
    currencyDisplay: 'code'
  }).format(amount)
}

export function formatPeriod(year, month) {
  return `${year}-${String(month).padStart(2, '0')}`
}
