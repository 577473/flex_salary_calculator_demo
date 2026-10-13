export function formatMoney(cents) {
  const amount = (Number(cents) || 0) / 100
  return `$${amount.toLocaleString('es-AR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

export function formatPeriod(year, month) {
  return `${year}-${String(month).padStart(2, '0')}`
}