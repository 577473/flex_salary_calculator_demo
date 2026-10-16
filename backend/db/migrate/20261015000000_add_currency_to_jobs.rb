class AddCurrencyToJobs < ActiveRecord::Migration[8.1]
  # Currency is a contractual condition, exactly like base_salary_cents: it is
  # stored on the Job and is NOT used by the calculator (amounts are raw integer
  # minor units). A run's amounts share the currency of the Job effective for the
  # period; that code is resolved for display only.
  #
  # Existing demo contracts are backfilled from their jurisdiction, then the
  # column is made NOT NULL (a contract always states its currency).
  def up
    add_column :jobs, :currency, :string

    execute <<~SQL
      UPDATE jobs SET currency = CASE country
        WHEN 'AR' THEN 'ARS'
        WHEN 'UY' THEN 'UYU'
      END
      WHERE currency IS NULL
    SQL

    change_column_null :jobs, :currency, false
  end

  def down
    remove_column :jobs, :currency
  end
end
