class FixAsignacionTemplateUniqueness < ActiveRecord::Migration[8.1]
  def change
    remove_index :asignacion_templates, [ :country, :category ]
    add_index :asignacion_templates, [ :country, :category, :description ], unique: true
  end
end
