export const PENDING_PLACEHOLDER = '—'

export function formatMoney(cents) {
  if (cents === null || cents === undefined) return PENDING_PLACEHOLDER

  const amount = Number(cents) / 100
  return `$${amount.toLocaleString('es-AR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

export function formatPeriod(year, month) {
  return `${year}-${String(month).padStart(2, '0')}`
}
