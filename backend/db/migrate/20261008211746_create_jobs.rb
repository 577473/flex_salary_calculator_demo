class CreateJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :jobs do |t|
      t.references :employee, null: false, foreign_key: true
      t.string :country, null: false
      t.integer :base_salary_cents, null: false
      t.date :effective_from, null: false
      t.date :effective_to

      t.timestamps
    end
  end
end
