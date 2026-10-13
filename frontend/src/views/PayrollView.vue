<script setup>
import { ref, onMounted } from 'vue'
import { usePayrollStore } from '../stores/payroll'
import { formatMoney } from '../utils/money'

const store = usePayrollStore()
const period = ref('')

onMounted(() => {
  if (store.employees.length === 0) store.loadEmployees()
})

async function calculate() {
  await store.calculate(period.value)
}
</script>

<template>
  <section>
    <h2>Nómina</h2>

    <form data-testid="calculate-form" @submit.prevent="calculate">
      <label>
        Período (AAAA-MM)
        <input v-model="period" placeholder="2026-09" />
      </label>
      <button type="submit" :disabled="store.loading || !period">Calcular</button>
    </form>

    <p v-if="store.error" class="error" data-testid="calculate-error">{{ store.error }}</p>

    <h3>Empleados</h3>
    <ul data-testid="employees">
      <li v-for="employee in store.employees" :key="employee.id">{{ employee.name }}</li>
    </ul>

    <h3>Resultados por empleado</h3>
    <ul data-testid="results-per-employee">
      <li
        v-for="result in store.results"
        :key="result.employee_id"
        :data-testid="`result-${result.employee_id}`"
      >
        <template v-if="result.status === 'success'">
          Empleado {{ result.employee_id }}: correcto —
          <RouterLink :to="result.liquidacion.url">ver liquidación</RouterLink>
        </template>
        <template v-else>
          Empleado {{ result.employee_id }}: {{ result.error.code }} — {{ result.error.detail }}
        </template>
      </li>
    </ul>

    <p
      v-if="store.calculated && store.liquidaciones.length === 0"
      class="empty"
      data-testid="empty-state"
    >
      Sin liquidaciones para el período seleccionado.
    </p>

    <table v-if="store.liquidaciones.length" data-testid="results">
      <thead>
        <tr>
          <th>Empleado</th>
          <th>Haberes</th>
          <th>Descuentos</th>
          <th>Aportes</th>
          <th>Salario final</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="liquidacion in store.liquidaciones" :key="liquidacion.id" data-testid="result-row">
          <td>
            <RouterLink :to="`/liquidaciones/${liquidacion.id}`">{{ liquidacion.name }}</RouterLink>
          </td>
          <td>{{ formatMoney(liquidacion.haberes_totales_cents) }}</td>
          <td>{{ formatMoney(liquidacion.descuentos_totales_cents) }}</td>
          <td>{{ formatMoney(liquidacion.aportes_totales_cents) }}</td>
          <td>{{ formatMoney(liquidacion.final_salary_cents) }}</td>
        </tr>
      </tbody>
    </table>
  </section>
</template>

<style scoped>
.error {
  color: #b00020;
}

.empty {
  color: #555;
}

table {
  border-collapse: collapse;
}

th,
td {
  border: 1px solid #ccc;
  padding: 0.4rem 0.8rem;
  text-align: right;
}

th:first-child,
td:first-child {
  text-align: left;
}
</style>