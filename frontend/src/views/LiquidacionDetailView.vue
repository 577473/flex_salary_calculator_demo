<script setup>
import { onMounted } from 'vue'
import { usePayrollStore } from '../stores/payroll'
import { formatMoney } from '../utils/money'

const props = defineProps({
  id: { type: [String, Number], required: true }
})

const store = usePayrollStore()

onMounted(() => {
  store.loadDetail(props.id)
})

const groups = [
  { key: 'haber', label: 'Haberes' },
  { key: 'descuento', label: 'Descuentos' },
  { key: 'aporte', label: 'Aportes' }
]
</script>

<template>
  <section v-if="store.detail" data-testid="detail">
    <h2>{{ store.detail.name }} — {{ store.detail.period }}</h2>

    <p v-if="store.detail.pending" class="pending-notice" data-testid="pending-notice">
      Liquidación pendiente de cálculo: los importes aparecen cuando el calculador completa cada ítem.
    </p>

    <dl class="totals">
      <div>
        <dt>Haberes</dt>
        <dd>{{ formatMoney(store.detail.haberes_totales_cents, store.detail.currency) }}</dd>
      </div>
      <div>
        <dt>Descuentos</dt>
        <dd>{{ formatMoney(store.detail.descuentos_totales_cents, store.detail.currency) }}</dd>
      </div>
      <div>
        <dt>Aportes</dt>
        <dd>{{ formatMoney(store.detail.aportes_totales_cents, store.detail.currency) }}</dd>
      </div>
      <div>
        <dt>Salario final</dt>
        <dd>{{ formatMoney(store.detail.final_salary_cents, store.detail.currency) }}</dd>
      </div>
    </dl>

    <div v-for="group in groups" :key="group.key" class="group">
      <h4 data-testid="group-heading">{{ group.label }}</h4>
      <ul>
        <li v-for="item in store.detail.items.filter((item) => item.category === group.key)" :key="item.description">
          {{ item.description }} — {{ formatMoney(item.amount_cents, store.detail.currency) }}
          <small data-testid="item-formula">
            ({{ item.formula }} · versión {{ item.formula_version }})
          </small>
        </li>
      </ul>
    </div>
  </section>

  <p v-else class="missing" data-testid="detail-missing">
    {{ store.error || 'Liquidación no encontrada' }}
  </p>
</template>

<style scoped>
.missing {
  color: #b00020;
}

.pending-notice {
  color: #8a6d3b;
}

.totals {
  display: flex;
  gap: 1rem;
}

.totals div {
  border: 1px solid #ccc;
  padding: 0.5rem 1rem;
}

dd {
  margin: 0;
  font-weight: 600;
}

small {
  color: #666;
}
</style>