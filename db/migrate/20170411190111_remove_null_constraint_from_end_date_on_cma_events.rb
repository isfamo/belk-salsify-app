class RemoveNullConstraintFromEndDateOnCMAEvents < ActiveRecord::Migration[5.0]
  def change
    change_column :cma_events, :end_date, :datetime, null: true
  end
end
