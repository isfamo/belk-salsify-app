# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20171206210756) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "cfh_execution_errors", force: :cascade do |t|
    t.integer  "salsify_cfh_execution_id"
    t.string   "product_id",               default: ""
    t.string   "category_id",              default: ""
    t.string   "message",                  default: ""
    t.datetime "created_at",                            null: false
    t.datetime "updated_at",                            null: false
    t.index ["salsify_cfh_execution_id"], name: "index_cfh_execution_errors_on_salsify_cfh_execution_id", using: :btree
  end

  create_table "cma_events", force: :cascade do |t|
    t.string   "sku_code"
    t.string   "vendor_upc"
    t.integer  "record_type"
    t.string   "event_id"
    t.datetime "start_date",    null: false
    t.datetime "end_date"
    t.string   "adevent"
    t.string   "parent_id"
    t.string   "regular_price"
    t.index ["sku_code", "adevent", "event_id"], name: "index_cma_events_on_sku_code_and_adevent_and_event_id", unique: true, using: :btree
  end

  create_table "delayed_jobs", force: :cascade do |t|
    t.integer  "priority",   default: 0, null: false
    t.integer  "attempts",   default: 0, null: false
    t.text     "handler",                null: false
    t.text     "last_error"
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string   "locked_by"
    t.string   "queue"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["priority", "run_at"], name: "delayed_jobs_priority", using: :btree
  end

  create_table "grouping_ids", force: :cascade do |t|
    t.integer "sequence"
  end

  create_table "job_statuses", force: :cascade do |t|
    t.string   "title"
    t.string   "status",     default: "In Progress"
    t.string   "activity",   default: "Listening to FTP"
    t.datetime "start_time"
    t.datetime "end_time"
    t.string   "error",      default: "None"
    t.index ["id"], name: "index_job_statuses_on_id", using: :btree
  end

  create_table "parent_products", force: :cascade do |t|
    t.string   "product_id"
    t.date     "first_inventory_date"
    t.datetime "created_at",           null: false
    t.datetime "updated_at",           null: false
    t.index ["product_id"], name: "index_parent_products_on_product_id", using: :btree
  end

  create_table "rrd_car_ids", force: :cascade do |t|
    t.string   "product_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "rrd_deleted_images", force: :cascade do |t|
    t.string   "file_name"
    t.string   "rrd_image_id"
    t.datetime "created_at",   null: false
    t.datetime "updated_at",   null: false
  end

  create_table "rrd_image_histories", force: :cascade do |t|
    t.string   "image_id"
    t.string   "name"
    t.date     "date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "rrd_image_ids", force: :cascade do |t|
    t.string   "salsify_asset_id"
    t.boolean  "approved"
    t.datetime "created_at",       null: false
    t.datetime "updated_at",       null: false
    t.string   "product_id"
    t.string   "color_code"
    t.string   "shot_type"
    t.string   "image_name"
  end

  create_table "rrd_requested_samples", force: :cascade do |t|
    t.string   "product_id"
    t.string   "color_id"
    t.date     "completed_at"
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
    t.boolean  "sent_to_rrd"
    t.string   "of_or_sl"
    t.date     "turn_in_date"
    t.boolean  "silhouette_required"
    t.string   "instructions"
    t.string   "sample_type"
    t.string   "on_hand_or_from_vendor"
    t.string   "color_name"
    t.string   "return_to"
    t.string   "return_notes"
    t.boolean  "must_be_returned"
  end

  create_table "rrd_task_ids", force: :cascade do |t|
    t.string   "product_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "salsify_cfh_executions", force: :cascade do |t|
    t.string   "exec_type",   default: "auto"
    t.datetime "created_at",                   null: false
    t.datetime "updated_at",                   null: false
    t.boolean  "in_progress", default: false
    t.index ["id"], name: "index_salsify_cfh_executions_on_id", using: :btree
  end

  create_table "salsify_sql_nodes", force: :cascade do |t|
    t.string   "sid"
    t.json     "data",                     default: {}
    t.string   "parent_sid"
    t.string   "node_type",                default: "category"
    t.datetime "created_at",                                    null: false
    t.datetime "updated_at",                                    null: false
    t.integer  "salsify_cfh_execution_id"
    t.index ["node_type", "parent_sid", "sid"], name: "index_salsify_sql_nodes_on_node_type_and_parent_sid_and_sid", using: :btree
    t.index ["salsify_cfh_execution_id"], name: "index_salsify_sql_nodes_on_salsify_cfh_execution_id", using: :btree
  end

  create_table "salsify_to_pim_logs", force: :cascade do |t|
    t.text     "product_id"
    t.text     "car_id"
    t.text     "status"
    t.text     "push_type"
    t.datetime "dtstamp"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer  "org_id"
  end

  create_table "skus", force: :cascade do |t|
    t.string   "product_id"
    t.string   "parent_id"
    t.integer  "parent_product_id"
    t.datetime "created_at",           null: false
    t.datetime "updated_at",           null: false
    t.date     "inventory_reset_date"
    t.index ["product_id"], name: "index_skus_on_product_id", unique: true, using: :btree
  end

  add_foreign_key "cfh_execution_errors", "salsify_cfh_executions"
  add_foreign_key "salsify_sql_nodes", "salsify_cfh_executions"
  add_foreign_key "skus", "parent_products"
end
