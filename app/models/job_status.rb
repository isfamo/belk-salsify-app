class JobStatus < ApplicationRecord
  include ActiveModel::Serializers::JSON

  scope :cma_job, -> { where(title: 'cma').last }
  scope :cfh_job, -> { where(title: 'cfh').last }
  scope :offline_cfh_job, -> { where(title: 'offline').last }
  scope :color_job, -> { where(title: 'color').last }
  scope :inventory, -> { where(title: 'inventory').last }
  scope :dwre_master, -> { where(title: 'dwre_master').last }
  scope :dwre_limited, -> { where(title: 'dwre_limited').last }

  def attributes
    {
      title: title,
      status: status,
      activity: activity,
      formatted_start_time: formatted_start_time,
      formatted_end_time: formatted_end_time,
      run_time: run_time,
      error: error
    }
  end

  def formatted_start_time
    start_time.in_time_zone(CMAEvent::TIMEZONE).strftime('%m/%d %I:%M:%S') if start_time
  end

  def formatted_end_time
    end_time.in_time_zone(CMAEvent::TIMEZONE).strftime('%m/%d %I:%M:%S') if end_time
  end

  def run_time
    end_time ? "#{(end_time.to_i - start_time.to_i) / 60} minutes" :
      "Running for #{(Time.now.to_i - start_time.to_i) / 60} minutes"
  end

end
