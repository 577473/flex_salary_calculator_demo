import { createRouter, createWebHistory } from 'vue-router'
import EmployeesView from '../views/EmployeesView.vue'
import PayrollView from '../views/PayrollView.vue'
import LiquidacionDetailView from '../views/LiquidacionDetailView.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'employees', component: EmployeesView },
    { path: '/payroll', name: 'payroll', component: PayrollView },
    { path: '/liquidaciones/:id', name: 'liquidacion-detail', component: LiquidacionDetailView, props: true }
  ]
})

export default router