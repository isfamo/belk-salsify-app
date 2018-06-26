class CreateJobStatuses < ActiveRecord::Migration[5.0]
  def change
    create_table :job_statuses do |t|
      t.string :title
      t.string :status, default: 'In Progress'
      t.string :activity, default: 'Listening to FTP'
      t.time :start_time
      t.time :end_time
    end

    add_index :job_statuses, :id, using: :btree
  end
end
