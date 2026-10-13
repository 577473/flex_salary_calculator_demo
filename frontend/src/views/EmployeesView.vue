<script setup>
import { onMounted } from 'vue'
import { usePayrollStore } from '../stores/payroll'

const store = usePayrollStore()

onMounted(() => {
  if (store.employees.length === 0) store.loadEmployees()
})
</script>

<template>
  <section>
    <h2>Empleados</h2>
    <p v-if="store.error" class="error" data-testid="error">{{ store.error }}</p>
    <ul data-testid="employees">
      <li v-for="employee in store.employees" :key="employee.id">{{ employee.name }}</li>
    </ul>
    <RouterLink to="/payroll" class="cta">Ir a la nómina</RouterLink>
  </section>
</template>

<style scoped>
.error {
  color: #b00020;
}

.cta {
  font-weight: 600;
}
</style>