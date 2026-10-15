class CreateLiquidaciones < ActiveRecord::Migration[8.1]
  def change
    create_table :liquidaciones do |t|
      t.references :employee, null: false, foreign_key: true
      t.integer :period_year, null: false
      t.integer :period_month, null: false
      t.integer :haberes_totales_cents, null: false
      t.integer :descuentos_totales_cents, null: false
      t.integer :aportes_totales_cents, null: false
      t.integer :final_salary_cents, null: false

      t.timestamps
    end
    add_index :liquidaciones, [ :employee_id, :period_year, :period_month ], unique: true, name: :idx_liquidaciones_employee_period
    add_index :liquidaciones, [ :period_year, :period_month ]
    add_check_constraint :liquidaciones, 'period_month BETWEEN 1 AND 12', name: :chk_liquidaciones_period_month
    add_check_constraint :liquidaciones, 'haberes_totales_cents >= 0 AND descuentos_totales_cents >= 0 AND aportes_totales_cents >= 0 AND final_salary_cents >= 0', name: :chk_liquidaciones_non_negative
  end
end
