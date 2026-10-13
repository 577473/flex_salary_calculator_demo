import axios from 'axios'
import { toErrorMessage } from './error'

export { toErrorMessage }

const client = axios.create({
  baseURL: import.meta.env.VITE_API_URL || ''
})

export async function getEmployees() {
  const { data } = await client.get('/api/v1/employees')
  return data.employees
}

export async function getLiquidaciones(period) {
  const { data } = await client.get('/api/v1/liquidaciones', { params: { period } })
  return data.liquidaciones
}

export async function getLiquidacion(id) {
  const { data } = await client.get(`/api/v1/liquidaciones/${id}`)
  return data.liquidacion
}

export async function calculatePayroll(employeeIds, period) {
  const { data } = await client.post('/api/v1/liquidaciones/calculate', {
    employee_ids: employeeIds,
    period
  })
  return data.results
}