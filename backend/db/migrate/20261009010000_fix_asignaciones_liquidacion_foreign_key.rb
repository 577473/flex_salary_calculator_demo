class FixAsignacionesLiquidacionForeignKey < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :asignaciones, column: :liquidacion_id
    add_foreign_key :asignaciones, :liquidaciones, column: :liquidacion_id
  end
end
