<template>
  <main style="font-family: system-ui, sans-serif; max-width: 60rem; margin: 0 auto; padding: 2rem">
    <h1>Calculadora de Salario Flexible</h1>
    <nav>
      <RouterLink to="/">Empleados</RouterLink>
      <span> · </span>
      <RouterLink to="/payroll">Nómina</RouterLink>
    </nav>
    <RouterView />
  </main>
</template>