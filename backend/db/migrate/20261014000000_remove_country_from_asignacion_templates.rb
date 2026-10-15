class RemoveCountryFromAsignacionTemplates < ActiveRecord::Migration[8.1]
  def up
    # An item's behavior (including any country dependence) lives entirely in its
    # formula, so templates are no longer scoped by a country relationship. The
    # old seed duplicated every item once per country with identical
    # country-branching formulas; collapse those duplicates first so the
    # per-description uniqueness holds and no Asignacion loses its template.
    execute <<~SQL
      UPDATE asignaciones
      SET template_id = (
        SELECT MIN(g.id)
        FROM asignacion_templates g
        JOIN asignacion_templates a
          ON a.category = g.category AND a.description = g.description
        WHERE a.id = asignaciones.template_id
      )
      WHERE template_id NOT IN (
        SELECT MIN(id) FROM asignacion_templates GROUP BY category, description
      )
    SQL

    execute <<~SQL
      DELETE FROM asignacion_templates
      WHERE id NOT IN (
        SELECT MIN(id) FROM asignacion_templates GROUP BY category, description
      )
    SQL

    remove_index :asignacion_templates, column: [ :country, :category, :description ]
    remove_index :asignacion_templates, column: [ :country, :effective_from, :effective_to ]
    remove_column :asignacion_templates, :country
    add_index :asignacion_templates, [ :category, :description ], unique: true
    add_index :asignacion_templates, [ :effective_from, :effective_to ]
  end

  def down
    add_column :asignacion_templates, :country, :string, null: false, default: "AR"
    remove_index :asignacion_templates, column: [ :category, :description ]
    remove_index :asignacion_templates, column: [ :effective_from, :effective_to ]
    add_index :asignacion_templates, [ :country, :category, :description ], unique: true
    add_index :asignacion_templates, [ :country, :effective_from, :effective_to ]
    change_column_default :asignacion_templates, :country, from: "AR", to: nil
  end
end
