import { defineStore } from 'pinia'
import {
  getEmployees,
  getLiquidaciones,
  getLiquidacion,
  calculatePayroll,
  toErrorMessage
} from '../services/api'

export const usePayrollStore = defineStore('payroll', {
  state: () => ({
    employees: [],
    results: [],
    liquidaciones: [],
    detail: null,
    loading: false,
    error: null,
    calculated: false
  }),

  actions: {
    async loadEmployees() {
      this.error = null
      this.loading = true
      try {
        this.employees = await getEmployees()
      } catch (error) {
        this.error = toErrorMessage(error)
      } finally {
        this.loading = false
      }
    },

    async loadLiquidaciones(period) {
      this.error = null
      this.loading = true
      try {
        this.liquidaciones = await getLiquidaciones(period)
      } catch (error) {
        this.error = toErrorMessage(error)
      } finally {
        this.loading = false
      }
    },

    async calculate(period) {
      if (!period) {
        this.error = 'Seleccioná un período'
        return
      }
      this.error = null
      this.loading = true
      try {
        this.results = await calculatePayroll(
          this.employees.map((employee) => employee.id),
          period
        )
        this.liquidaciones = await getLiquidaciones(period)
        this.calculated = true
      } catch (error) {
        this.error = toErrorMessage(error)
      } finally {
        this.loading = false
      }
    },

    async loadDetail(id) {
      this.error = null
      this.detail = null
      this.loading = true
      try {
        this.detail = await getLiquidacion(id)
      } catch (error) {
        this.error = toErrorMessage(error)
      } finally {
        this.loading = false
      }
    }
  }
})