class AllowPendingPayrollState < ActiveRecord::Migration[8.1]
  # An upstream step (out of this app's scope) creates the empty Liquidacion and
  # its Asignacion rows — formula, category, position — before anything is
  # computed. The calculator only fills in amount_cents and the four totals, so
  # both have to tolerate the pending (not-yet-calculated) NULL state.
  def up
    change_column_null :liquidaciones, :haberes_totales_cents, true
    change_column_null :liquidaciones, :descuentos_totales_cents, true
    change_column_null :liquidaciones, :aportes_totales_cents, true
    change_column_null :liquidaciones, :final_salary_cents, true
    change_column_null :asignaciones, :amount_cents, true
  end

  def down
    # Pending rows carry no computable totals/amounts to restore a NOT NULL
    # constraint on, so they are rolled back first (child rows before parents).
    execute <<~SQL
      DELETE FROM asignaciones
      WHERE liquidacion_id IN (
        SELECT id FROM liquidaciones
        WHERE haberes_totales_cents IS NULL OR descuentos_totales_cents IS NULL
           OR aportes_totales_cents IS NULL OR final_salary_cents IS NULL
      )
    SQL
    execute <<~SQL
      DELETE FROM liquidaciones
      WHERE haberes_totales_cents IS NULL OR descuentos_totales_cents IS NULL
         OR aportes_totales_cents IS NULL OR final_salary_cents IS NULL
    SQL
    execute "DELETE FROM asignaciones WHERE amount_cents IS NULL"

    change_column_null :liquidaciones, :haberes_totales_cents, false
    change_column_null :liquidaciones, :descuentos_totales_cents, false
    change_column_null :liquidaciones, :aportes_totales_cents, false
    change_column_null :liquidaciones, :final_salary_cents, false
    change_column_null :asignaciones, :amount_cents, false
  end
end
