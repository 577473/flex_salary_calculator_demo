class CreateAsignacionTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :asignacion_templates do |t|
      t.string :description, null: false
      t.text :formula, null: false
      t.string :category, null: false
      t.string :country, null: false
      t.date :effective_from, null: false
      t.date :effective_to
      t.integer :version, null: false, default: 1

      t.timestamps
    end
    add_index :asignacion_templates, [ :country, :category ], unique: true
    add_index :asignacion_templates, [ :country, :effective_from, :effective_to ]
  end
end
