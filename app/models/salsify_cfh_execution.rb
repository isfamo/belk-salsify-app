class SalsifyCfhExecution < ApplicationRecord
  # CFH - Category Facing Hierarchy
  has_many :salsify_sql_nodes
  has_many :cfh_execution_errors

  scope :auto_today, -> {
    where(created_at: Time.zone.now.beginning_of_day..Time.zone.now.end_of_day, exec_type: 'auto')
  }

  scope :auto_yesterday, -> {
    where(created_at: Time.zone.yesterday.beginning_of_day..Time.zone.yesterday.end_of_day, exec_type: 'auto')
  }

  scope :last_auto, -> {
    where(exec_type: 'auto').last
  }

  scope :manual_today, -> {
    where(created_at: Time.zone.now.beginning_of_day..Time.zone.now.end_of_day, exec_type: 'manual')
  }

  scope :older_than, -> (number_of) {
    where("created_at < ? ", number_of.days.ago)
  }

  # this likely shouldn't be located here, vs... not sure where else - but for now testing to see if this solves
  #   my problem
  def execute_sql_statement(sql)
    results = ActiveRecord::Base.connection.exec_query(sql)
    #results = ActiveRecord::Base.connection.execute(sql)
    if results.present?
        return results
    else
        return nil
    end
  end

  def destroy_w_children
    # the originals of these worked at the rails object level and never seemed to work correctly
    salsify_sql_nodes.delete_all
    cfh_execution_errors.delete_all
    destroy
  end
end
