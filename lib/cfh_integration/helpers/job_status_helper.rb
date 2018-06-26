module JobStatusHelper
  extend self

  def job_status
    @job_status ||= JobStatus.create(start_time: Time.now)
  end

  def finalize_job_status
    job_status.status = 'Finished Processing'
    job_status.activity = ''
    job_status.end_time = Time.now
    job_status.save!
  end

end
