class CfhExecutionError < ApplicationRecord
  validates :salsify_cfh_execution_id, presence: true
  belongs_to :salsify_cfh_execution
end
