class CreateAsignaciones < ActiveRecord::Migration[8.1]
  def change
    create_table :asignaciones do |t|
      t.references :liquidacion, null: false, foreign_key: true
      t.references :template, null: false, foreign_key: { to_table: :asignacion_templates }
      t.text :description, null: false
      t.string :category, null: false
      t.text :formula, null: false
      t.integer :formula_version, null: false
      t.integer :amount_cents, null: false
      t.integer :position, null: false

      t.timestamps
    end
    add_index :asignaciones, [ :liquidacion_id, :position ]
  end
end
