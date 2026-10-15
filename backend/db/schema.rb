# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_14_010000) do
  create_table "asignacion_templates", force: :cascade do |t|
    t.string "description", null: false
    t.text "formula", null: false
    t.string "category", null: false
    t.date "effective_from", null: false
    t.date "effective_to"
    t.integer "version", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category", "description"], name: "index_asignacion_templates_on_category_and_description", unique: true
    t.index ["effective_from", "effective_to"], name: "index_asignacion_templates_on_effective_from_and_effective_to"
  end

  create_table "asignaciones", force: :cascade do |t|
    t.integer "liquidacion_id", null: false
    t.integer "template_id", null: false
    t.text "description", null: false
    t.string "category", null: false
    t.text "formula", null: false
    t.integer "formula_version", null: false
    t.integer "amount_cents"
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["liquidacion_id", "position"], name: "index_asignaciones_on_liquidacion_id_and_position"
    t.index ["liquidacion_id"], name: "index_asignaciones_on_liquidacion_id"
    t.index ["template_id"], name: "index_asignaciones_on_template_id"
  end

  create_table "employees", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "jobs", force: :cascade do |t|
    t.integer "employee_id", null: false
    t.string "country", null: false
    t.integer "base_salary_cents", null: false
    t.date "effective_from", null: false
    t.date "effective_to"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_jobs_on_employee_id"
  end

  create_table "liquidaciones", force: :cascade do |t|
    t.integer "employee_id", null: false
    t.integer "period_year", null: false
    t.integer "period_month", null: false
    t.integer "haberes_totales_cents"
    t.integer "descuentos_totales_cents"
    t.integer "aportes_totales_cents"
    t.integer "final_salary_cents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id", "period_year", "period_month"], name: "idx_liquidaciones_employee_period", unique: true
    t.index ["employee_id"], name: "index_liquidaciones_on_employee_id"
    t.index ["period_year", "period_month"], name: "index_liquidaciones_on_period_year_and_period_month"
    t.check_constraint "haberes_totales_cents >= 0 AND descuentos_totales_cents >= 0 AND aportes_totales_cents >= 0 AND final_salary_cents >= 0", name: "chk_liquidaciones_non_negative"
    t.check_constraint "period_month BETWEEN 1 AND 12", name: "chk_liquidaciones_period_month"
  end

  add_foreign_key "asignaciones", "asignacion_templates", column: "template_id"
  add_foreign_key "asignaciones", "liquidaciones"
  add_foreign_key "jobs", "employees"
  add_foreign_key "liquidaciones", "employees"
end
